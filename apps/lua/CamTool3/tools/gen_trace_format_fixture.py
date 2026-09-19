"""Write a small trace with CamTool 2's own recorder, out of the game.

The recording end lives in CamTool 2 and the reading end lives here, and
nothing else checks that they agree. Without this, the first real recording
could fail on a mismatched field name, and finding that out costs a game
session -- the very cost this whole arrangement exists to avoid.

So the real Trace and Spy classes are driven here against a stand-in camera,
with stand-in globals for the ones only Assetto Corsa provides. The numbers are
invented; the format is not. The result is converted with trace_to_lua.py and
both files are kept as fixtures, so the Lua side reads something the recorder
actually wrote.

Usage, from apps/lua/CamTool3:
    python tools/gen_trace_format_fixture.py
"""
import math
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
LUA_APP = os.path.dirname(HERE)
CAMTOOL2 = os.path.abspath(
    os.path.join(LUA_APP, '..', '..', 'python', 'CamTool_2'))

FIXTURES = os.path.join(LUA_APP, 'tests', 'fixtures')
JSONL = os.path.join(FIXTURES, 'trace_format.jsonl')
LUA = os.path.join(FIXTURES, 'trace_format.lua')


def install_fake_ac():
    """The three modules only the game provides."""
    ac = types.ModuleType('ac')
    ac.getTrackName = lambda i: 'fake_track'
    ac.getTrackConfiguration = lambda i: 'layout'
    ac.getTrackLength = lambda: 4321.0
    ac.getFocusedCar = lambda: 0
    ac.isConnected = lambda i: 1
    ac.console = lambda message: None
    ac.log = lambda message: None

    def car_state(car_id, what):
        # A car going round a circle, in AC's order: x, y up, z.
        angle = car_state.frame * 0.05 + car_id
        car_state.frame += 1
        return (math.cos(angle) * 300, 1.2, math.sin(angle) * 300)

    car_state.frame = 0
    ac.getCarState = car_state

    acsys = types.ModuleType('acsys')

    class CS(object):
        WorldPosition = 1
        NormalizedSplinePosition = 2

    acsys.CS = CS

    sys.modules['ac'] = ac
    sys.modules['acsys'] = acsys
    return ac


class FakeCtt(object):
    """Just enough camera for Spy to stand in front of."""

    def __init__(self):
        self.position = [0.0, 0.0, 0.0]
        self.rotation = (0.0, 0.0, 0.0)
        self.fov = 30.0
        self.focus = 40.0

    def set_position(self, axis, value):
        self.position[axis] = value

    def set_rotation(self, pitch, roll, heading):
        self.rotation = (pitch, roll, heading)

    def set_fov(self, fov):
        self.fov = fov

    def set_focus_point(self, value):
        self.focus = value


class FakeCam(object):
    def get_tracked_car(self, car=0):
        return car


class FakeData(object):
    def __init__(self):
        self.active_mode = 'pos'
        self.active_cam = 0


class FakeInfo(object):
    class graphics(object):
        replayTimeMultiplier = 1.0
        status = 1


class FakeReplay(object):
    def __init__(self):
        self.frame = 0

    def get_interpolated_replay_pos(self):
        self.frame += 1
        return 1000.0 + self.frame * 1.0

    def get_refresh_rate(self):
        return 16.666666666666668


FRAMES = 24


def main():
    install_fake_ac()
    sys.path.insert(0, CAMTOOL2)

    from classes import trace as trace_module
    from files.settings import settings

    # The recorder asks settings for the file name to put in the header, and
    # reads its own flag from there too.
    settings.settings = {
        'last_used_data': {'fake_track_layout': 'cameras'},
        'dev_record_trace': True,
    }

    if os.path.exists(JSONL):
        os.remove(JSONL)

    recorder = trace_module.Trace()
    recorder.configure(settings)
    # Write where the fixtures live, not into CamTool 2's traces folder.
    trace_module.G_TRACE_PATH = FIXTURES + os.sep
    original_open = recorder._Trace__open

    def open_at_fixture_path():
        original_open()
        os.rename(recorder.path, JSONL)
        recorder.path = JSONL

    recorder._Trace__open = open_at_fixture_path

    ctt = FakeCtt()
    cam = FakeCam()
    data = FakeData()
    info = FakeInfo()
    replay = FakeReplay()

    for frame in range(FRAMES):
        the_x = frame / float(FRAMES)
        data.active_cam = frame // 8

        # One stretch under mouse look, which a reader has to skip.
        strength_inv = 0.5 if 8 <= frame < 12 else 0.0

        spy = recorder.begin(ctt, data, cam, 1.0 / 60, info, replay,
                             strength_inv, the_x)
        if spy is None:
            raise SystemExit('the recorder refused to record')

        # Frame 5 sets nothing at all, the way a frame with no camera
        # selected would not.
        if frame != 5:
            spy.set_position(0, -600.0 + frame * 3.5)
            spy.set_position(1, 40.0 + math.sin(frame * 0.3) * 8)
            spy.set_position(2, 12.5)
            spy.set_rotation(-0.12 + frame * 0.001, 0.0, 1.9 - frame * 0.01)
            # Not every frame keyframes a lens or a focus.
            if frame % 3 != 0:
                spy.set_fov(28.0 + math.sin(frame * 0.4) * 4)
            if frame % 4 != 0:
                spy.set_focus_point(95.0 + frame)

        recorder.end(spy)

    recorder.flush()
    print('wrote %s (%d frames)' % (JSONL, recorder.frame))

    # Convert it the way a real recording would be converted.
    sys.path.insert(0, HERE)
    import trace_to_lua
    sys.argv = ['trace_to_lua.py', JSONL, LUA]
    return trace_to_lua.main()


if __name__ == '__main__':
    sys.exit(main())
