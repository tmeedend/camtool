--[[
  Replaying a CamTool 2 recording against core/playback.

  Two kinds of test live here.

  The first kind proves the machinery. A trace of the core's own output,
  replayed against the core, must come back with a gap of zero -- and a trace
  with one frame nudged must not. Until a real recording exists, this is what
  says the comparison means anything, and it keeps saying it afterwards.

  The second kind is the real measurement, and it needs a recording. Add one to
  RECORDINGS below with the camera file it was made against, and it becomes a
  standing check that the port has not drifted further from CamTool 2 than it
  had drifted the day the numbers were written down. See the head of
  tests/trace.lua for what is compared and what is deliberately not.

  How to make one, from the game:
    1. add  "dev_record_trace": true  to apps/python/CamTool_2/settings.json
    2. play the replay you care about; recording stops after two minutes
    3. python tools/trace_to_lua.py <the .jsonl> tests/fixtures/trace_<name>.lua
    4. convert the camera file too, if it is not already a fixture:
       python tools/json_to_lua.py <the camera .json> tests/fixtures/<name>.lua
    5. add both to RECORDINGS, run, and write the measured gaps into the
       tolerances with a word on why each is what it is
]]

local runner = require('tests/runner')
local lap = require('tests/lap')
local trace = require('tests/trace')

local test, eq = runner.test, runner.eq

---Recordings made in game.
---
---  fixture     the converted trace
---  cameraFile  the camera document it was recorded against
---  options     how the port has to be set for the comparison to be fair
---  tolerance   the worst gap each measure is allowed, with the reason
---
---A tolerance is not a target. Three of the ones below are the size of a known
---defect, named as such; shrinking them is the point of fixing it.
local RECORDINGS = {
  {
    name = 'silverstone seb, 45 seconds of a real lap',
    fixture = 'tests/fixtures/trace_seb',
    cameraFile = 'tests/fixtures/camera_file_seb',
    -- CamTool 2 has the issue #16 startup transient, so the port has to be
    -- asked for it too. Recorded with it off, the aim was out by 1.56 rad for
    -- the first frames and by nothing afterwards -- which is the diagnosis of
    -- #16 confirmed on a real session rather than argued from the source.
    options = { legacyZeroFill = true },
    tolerance = {
      -- Exact, to the last bits of a double, over 2700 frames: keyframes,
      -- beziers, recorded paths and the mixing between them all agree with
      -- CamTool 2. The bound is far above the 1.3e-13 measured and still far
      -- below anything a real change could produce.
      position = 1e-9,

      -- The shake phase, and only that. CamTool 2's fallback clock is a
      -- running total of dt since the app started, so a recording that begins
      -- mid-session cannot say what phase the shake was in; the cameras that
      -- shake are exactly the ones that miss. Every camera with no shake
      -- agrees to the last bit. Recording the clock itself would close this,
      -- and is the obvious version 2 of the trace format.
      heading = 0.14,
      pitch = 0.02,
      roll = 1e-5,

      -- Exact, since evaluate started interpolating camera_fov in the form
      -- the file stores it in. It was 2.3 deg over this window before that,
      -- and 3.6 over the whole recording.
      fov = 1e-9,

      -- DEFECT, not a tolerance, and a smaller one than it was: reading the
      -- autofocus flag correctly took this from 500 m to 277. What is left is
      -- the gate that decides when to refocus. CamTool 2 holds the focus when
      -- the camera is aimed more than a right angle away from the car, and it
      -- measures that against the heading of the PREVIOUS frame, because ctt
      -- caches the heading and set_rotation does not clear it. The port
      -- measures it against the heading it has just worked out, so the two
      -- stop refocusing at different moments and one of them holds a stale
      -- distance. Every camera that is refocusing agrees exactly.
      focus = 277,
    },
  },
}

--------------------------------------------------------------------------------
-- The machinery
--------------------------------------------------------------------------------

local SELFTEST_FRAMES = 600

---A lap of the core, turned into a recording of itself.
local function selfRecording(options)
  local result = lap.runCore({
    cameraFile = require('tests/fixtures/camera_file_lap'),
    frames = SELFTEST_FRAMES,
    options = options,
  })
  return trace.fromLap(result.frames), result
end

test('a trace of the core replays against the core with no gap', function()
  -- Zero, not nearly zero: same code, same inputs, same order. Anything here
  -- is a bug in the replay -- a mixed-up axis, a clock rebuilt wrong, an angle
  -- compared without wrapping.
  local recording = selfRecording()
  local report = trace.replay(recording, require('tests/fixtures/camera_file_lap'))

  eq(report.compared > 500, true, 'almost every frame should be comparable, got '
    .. report.compared)
  eq(report.skippedMouseLook, 0)

  for _, field in ipairs({ 'position', 'heading', 'pitch', 'roll', 'fov', 'focus' }) do
    eq(report.worst[field], 0, field .. ' -- \n       ' .. trace.summary(report))
  end
end)

test('a trace the port disagrees with is reported', function()
  -- The same lap, with one frame moved a metre sideways and its lens opened by
  -- five degrees. A comparison that cannot see this cannot see a real
  -- divergence either.
  local recording = selfRecording()
  local target = recording.frames[200]
  target.pos[1] = target.pos[1] + 1
  target.fov = (target.fov or 30) + 5

  local report = trace.replay(recording, require('tests/fixtures/camera_file_lap'))

  runner.near(report.worst.position, 1, 1e-9, trace.summary(report))
  eq(report.worstFrame.position, target.f)
  runner.near(report.worst.fov, 5, 1e-9, trace.summary(report))
end)

test('an aim that drifts is reported as an angle', function()
  local recording = selfRecording()
  local target = recording.frames[300]
  target.rot[3] = target.rot[3] + 0.25

  local report = trace.replay(recording, require('tests/fixtures/camera_file_lap'))

  runner.near(report.worst.heading, 0.25, 1e-9, trace.summary(report))
  eq(report.worstFrame.heading, target.f)
end)

test('an angle that wrapped past pi is still a small gap', function()
  -- CamTool 2 and the port can hold the same aim and write it a full turn
  -- apart. Subtracting those two numbers gives 2 pi; the aim is identical.
  local recording = selfRecording()
  for i = 1, #recording.frames do
    local row = recording.frames[i]
    row.rot[3] = row.rot[3] + 2 * math.pi
  end

  local report = trace.replay(recording, require('tests/fixtures/camera_file_lap'))
  eq(report.worst.heading < 1e-9, true, trace.summary(report))
end)

test('frames recorded under mouse look are left out', function()
  -- CamTool 2 blends its result with wherever the camera already was; the port
  -- does not model that, so those frames cannot say anything about it.
  local recording = selfRecording()
  for i = 100, 199 do
    recording.frames[i].si = 0.5
    -- Wrong on purpose: if these frames were compared, this would show.
    recording.frames[i].pos[1] = recording.frames[i].pos[1] + 500
  end

  local report = trace.replay(recording, require('tests/fixtures/camera_file_lap'))

  eq(report.skippedMouseLook, 100)
  eq(report.worst.position, 0, trace.summary(report))
end)

test('a frame with no camera output is counted, not compared', function()
  -- CamTool 2 writes a row every frame, including the frames where it set
  -- nothing at all -- no camera selected, or the app between two files.
  local recording = selfRecording()
  for i = 1, 50 do
    recording.frames[i].pos = nil
    recording.frames[i].rot = nil
  end

  local report = trace.replay(recording, require('tests/fixtures/camera_file_lap'))
  eq(report.skippedNoOutput, 50)
  eq(report.worst.position, 0, trace.summary(report))
end)

--------------------------------------------------------------------------------
-- The measurement
--------------------------------------------------------------------------------

for _, recording in ipairs(RECORDINGS) do
  test('the port keeps up with CamTool 2: ' .. recording.name, function()
    local report = trace.replay(
      require(recording.fixture),
      require(recording.cameraFile),
      recording.options)

    eq(report.compared > 0, true, 'nothing was comparable in this recording')

    for field, allowed in pairs(recording.tolerance) do
      if report.worst[field] > allowed then
        error(string.format('%s is off by %.6g, more than the %.6g allowed'
          .. '\n       %s', field, report.worst[field], allowed,
          trace.summary(report)), 2)
      end
    end
  end)
end

if #RECORDINGS == 0 then
  test('no recording to measure against yet', function()
    -- Not a failure: the machinery above is tested, and this is the reminder
    -- that the question it answers has not been asked of the game yet. It
    -- goes away the moment a recording is added to RECORDINGS.
    eq(#RECORDINGS, 0)
  end)
end

--------------------------------------------------------------------------------
-- The format
--------------------------------------------------------------------------------

test('a trace written by the real recorder reads back', function()
  -- tests/fixtures/trace_format.jsonl was written by CamTool 2's own Trace and
  -- Spy classes, driven out of the game against a stand-in camera, and
  -- converted the way a real recording is converted. See
  -- tools/gen_trace_format_fixture.py. The numbers in it are invented; the
  -- format is not, and nothing else checks that the end that writes and the
  -- end that reads agree on it.
  local recording = require('tests/fixtures/trace_format')

  eq(recording.header.version, 1)
  eq(recording.header.type, 'header')
  eq(#recording.frames, 24)

  local first = recording.frames[1]
  eq(first.f, 0, 'frames are numbered from zero, as the recorder numbers them')
  eq(#first.pos, 3)
  eq(#first.rot, 3)
  eq(#first.carpos0, 3)

  -- Frame five set nothing, the way a frame with no camera selected would
  -- not; frames eight to eleven were recorded under mouse look.
  eq(recording.frames[6].pos, nil)
  eq(recording.frames[9].si, 0.5)

  local report = trace.replay(recording,
    require('tests/fixtures/camera_file_lap'))

  eq(report.skippedNoOutput, 1, 'the frame that set nothing')
  eq(report.skippedMouseLook, 4, 'the frames under mouse look')
  eq(report.compared, 19, 'everything else')
end)
