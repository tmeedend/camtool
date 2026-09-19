"""Record, frame by frame, what CamTool 2 was told and what it asked of the camera.

Why this exists: the CamTool 3 port can be checked against its own past (a
golden master) and against common sense (no infinities, no teleports), but not
against CamTool 2 itself. Only CamTool 2 can say what CamTool 2 does. One
recording session buys that answer permanently, replayable without anyone
launching the game again.

What is recorded, once per frame, as one JSON object per line:

    inputs    dt, the track position driving the interpolation, the replay
              speed and position, which camera the file selected, and the world
              position of the cars being tracked
    outputs   exactly what was asked of the camera -- position, pitch, roll,
              heading, field of view, focus distance

The outputs are taken from the setter calls, not read back afterwards. Reading
back would lie: ctt caches heading and roll for the frame and set_rotation does
not clear that cache, so a getter called after the fact returns the value from
before. Standing in front of the setters also means nothing here can change the
result -- Spy passes every call straight through.

Off unless settings.json says otherwise:

    "dev_record_trace": true

and it stops on its own after MAX_FRAMES. Note that Settings.load_settings
replaces the whole dictionary with the file's contents, so a default added in
Settings.__init__ never reaches a settings.json that already exists; the flag
is therefore read with an explicit fallback below.

Out of the hot path as much as a per-frame recorder can be: the rows are built
in memory and written every FLUSH_EVERY frames, never once per frame.

The file is JSON Lines, in ./apps/python/CamTool_2/traces/. The Lua tests have
no JSON parser -- parsing is CSP's job in game -- so a trace is converted for
them by apps/lua/CamTool3/tools/trace_to_lua.py, the same way real camera files
already are.
"""

running_in_ac = True

try:
    import ac
    import acsys
except:
    running_in_ac = False

import json
import os
import time

from classes.general import debug, cout

G_TRACE_PATH = "./apps/python/CamTool_2/traces/"

# Bumped when the meaning of a field changes, so an old trace cannot be read as
# a new one without anyone noticing.
FORMAT_VERSION = 1

# Rows buffered before they are written. Five seconds at 60 fps.
FLUSH_EVERY = 300

# Two minutes at 60 fps, then the recorder stops on its own. Long enough for
# any scenario worth recording, short enough that a forgotten flag costs a
# handful of megabytes rather than a disk.
MAX_FRAMES = 7200


class Spy(object):
    """Stands in for ctt for the length of one interpolate call.

    Every attribute not named below is the real one, so this changes nothing
    about what the camera is told -- it only remembers what that was.
    """

    def __init__(self, ctt):
        # First, or __getattr__ would recurse looking for it.
        self._ctt = ctt
        self.position = {}
        self.rotation = None
        self.fov = None
        self.focus = None

    def __getattr__(self, name):
        return getattr(self._ctt, name)

    def set_position(self, axis, value):
        self.position[axis] = value
        return self._ctt.set_position(axis, value)

    def set_rotation(self, pitch, roll, heading):
        self.rotation = (pitch, roll, heading)
        return self._ctt.set_rotation(pitch, roll, heading)

    def set_fov(self, fov):
        self.fov = fov
        return self._ctt.set_fov(fov)

    def set_focus_point(self, value):
        self.focus = value
        return self._ctt.set_focus_point(value)


class Trace(object):

    def __init__(self):
        self.enabled = False
        self.stopped = False
        self.frame = 0
        self.rows = []
        self.path = None
        self.inputs = None

    #---------------------------------------------------------------------------

    def configure(self, settings):
        """Read the flag once, at startup."""
        try:
            value = settings.settings.get("dev_record_trace", False)
            self.enabled = (value == True)
            if self.enabled:
                cout("trace recording is ON, up to {} frames".format(MAX_FRAMES))
        except Exception as e:
            debug(e)
            self.enabled = False

    def is_recording(self):
        return self.enabled and not self.stopped

    #---------------------------------------------------------------------------

    def begin(self, ctt, data, cam, dt, info, replay, strength_inv, the_x):
        """Collect this frame's inputs and return a stand-in for ctt.

        Returns None when nothing is being recorded, which is the signal to
        use the real ctt and skip end().
        """
        if not self.is_recording():
            return None

        try:
            self.inputs = {
                "f": self.frame,
                "dt": dt,
                "x": the_x,
                "mode": data.active_mode,
                "cam": data.active_cam,
                "si": strength_inv,
                "rtm": info.graphics.replayTimeMultiplier,
                "status": info.graphics.status,
                "rpos": replay.get_interpolated_replay_pos(),
                "rrate": replay.get_refresh_rate(),
                "focused": ac.getFocusedCar(),
                # The focus distance the camera already has. Safe to read here,
                # unlike heading and roll: ext_getCameraDofFocus goes straight
                # to CSP and fills no cache, so asking changes nothing. Worth
                # having because the legacy holds this value whenever it
                # decides not to refocus, and a reader cannot guess it.
                "focus0": ctt.get_focus_point(),
            }

            # The two cars a camera can track, and where they are. Raw AC order
            # (x, y, z) with y up; converting to CamTool's Z-up order is the
            # reader's job, and doing it in one place keeps it honest.
            for index in (0, 1):
                car_id = cam.get_tracked_car(index)
                position = ac.getCarState(car_id, acsys.CS.WorldPosition)
                self.inputs["car" + str(index)] = car_id
                self.inputs["carpos" + str(index)] = [
                    position[0], position[1], position[2]]

            return Spy(ctt)

        except Exception as e:
            debug(e)
            self.stopped = True
            return None

    def end(self, spy):
        """Add what the camera was asked for, and buffer the row."""
        if self.inputs == None:
            return

        try:
            row = self.inputs
            self.inputs = None

            # A key is absent when the frame did not set that value at all,
            # which is a fact about the frame and not a missing measurement.
            if len(spy.position) == 3:
                row["pos"] = [spy.position[0], spy.position[1], spy.position[2]]
            if spy.rotation != None:
                row["rot"] = [spy.rotation[0], spy.rotation[1], spy.rotation[2]]
            if spy.fov != None:
                row["fov"] = spy.fov
            if spy.focus != None:
                row["focus"] = spy.focus

            self.rows.append(json.dumps(row, sort_keys=True))
            self.frame += 1

            if len(self.rows) >= FLUSH_EVERY:
                self.flush()

            if self.frame >= MAX_FRAMES:
                self.flush()
                self.stopped = True
                cout("trace recording stopped at {} frames: {}".format(
                    self.frame, self.path))

        except Exception as e:
            debug(e)
            self.stopped = True

    #---------------------------------------------------------------------------

    def flush(self):
        """Write what is buffered, every FLUSH_EVERY frames rather than every frame."""
        if len(self.rows) == 0:
            return

        try:
            if self.path == None:
                self.__open()

            output = open(self.path, "a")
            try:
                for row in self.rows:
                    output.write(row)
                    output.write("\n")
            finally:
                output.close()

            self.rows = []

        except Exception as e:
            debug(e)
            self.stopped = True

    def __open(self):
        """Create the file and write the header line."""
        # Imported here rather than at the top: files.settings imports ac
        # unconditionally, and this module is also loaded outside the game to
        # check that what it writes can be read back.
        from files.settings import settings

        if not os.path.exists(G_TRACE_PATH):
            os.makedirs(G_TRACE_PATH)

        track = ac.getTrackName(0)
        layout = ac.getTrackConfiguration(0)
        name = settings.get_last_used_data()
        if name == None:
            name = "unknown"

        stamp = time.strftime("%Y%m%d-%H%M%S")
        self.path = "{}{}_{}-{}-{}.jsonl".format(
            G_TRACE_PATH, track, layout, name, stamp)

        header = {
            "type": "header",
            "version": FORMAT_VERSION,
            "track": track,
            "layout": layout,
            "data": name,
            "track_length": ac.getTrackLength(),
            "recorded": stamp,
        }

        output = open(self.path, "w")
        try:
            output.write(json.dumps(header, sort_keys=True))
            output.write("\n")
        finally:
            output.close()

        cout("recording a trace to " + self.path)


trace = Trace()
