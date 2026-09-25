--[[
  CamTool 2's session keys (F10, Y to P) as unbound shortcuts, and letting go
  of the camera when Assetto Corsa's own camera keys are pressed.
]]

local runner = require('tests/runner')
local fakes = require('tests/fakes/csp')

local test, eq = runner.test, runner.eq

local function camera(id, at, extra)
  local c = { id = id, camera_in = at, camera_pit = false, camera_use_tracking_point = 0,
    tracking_strength_heading = 1, tracking_strength_pitch = 1, tracking_offset = 0,
    keyframes = { { keyframe = at, interpolation = { loc_x = 0, loc_y = 0, loc_z = 5 } } } }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

local function start(opts)
  opts.cameraFile = opts.cameraFile or { interpolation_mode = 'fixed', version = 2,
    time = {}, pos = { camera(1, 0) } }
  opts.splinePosition = opts.splinePosition or 0.2
  local handle = fakes.install(opts)
  require('adapters/shortcuts').reset()
  require('ui/band').reset()
  assert(loadfile('CamTool3.lua'))()
  handle.tick(0.016)
  return handle
end

---One press of a shortcut, by a piece of its label.
local function press(handle, opts, piece)
  opts.pressedShortcut = piece
  handle.tick(0.016)
  opts.pressedShortcut = nil
  handle.tick(0.016)
end

local function loads(handle)
  local n = 0
  for i = 1, #handle.logs do
    if handle.logs[i]:find('] loaded ', 1, true) then n = n + 1 end
  end
  return n
end

test('the take-camera shortcut loads a file and takes the camera', function()
  local opts = {}
  local handle = start(opts)
  eq(handle.grabbed ~= true, true, 'nothing held yet')
  press(handle, opts, 'Take the camera')
  eq(handle.grabbed, true)
  eq(loads(handle), 1, 'with a file to play, even with the window never opened')
  handle.restoreIo()
  require('adapters/shortcuts').reset()
end)

test('pressed again while held, it loads the next file', function()
  local opts = { ownFiles = { 'fake_track_-mine.json' } }
  local handle = start(opts)
  press(handle, opts, 'Take the camera')
  local before = loads(handle)
  press(handle, opts, 'Take the camera')
  eq(loads(handle), before + 1)
  eq(handle.disposed ~= true, true, 'and keeps the camera')
  handle.restoreIo()
  require('adapters/shortcuts').reset()
end)

test('the release shortcut lets go', function()
  local opts = {}
  local handle = start(opts)
  press(handle, opts, 'Take the camera')
  press(handle, opts, 'Release the camera')
  eq(handle.disposed, true)
  handle.restoreIo()
  require('adapters/shortcuts').reset()
end)

test('load file N loads the N-th file of the track', function()
  local opts = { ownFiles = { 'fake_track_-mine.json' } }
  local handle = start(opts)
  press(handle, opts, 'Load file 2')
  local found = false
  for i = 1, #handle.logs do
    if handle.logs[i]:find('] loaded fake_track_-cameras.json', 1, true) then found = true end
  end
  eq(found, true, 'the second in the list: ours first, then CamTool 2 ones')
  press(handle, opts, 'Load file 5')
  eq(loads(handle), 1, 'there is no fifth file, so nothing more was loaded')
  handle.restoreIo()
  require('adapters/shortcuts').reset()
end)

test("Assetto Corsa's camera keys let go of the camera", function()
  local opts = { cameraMode = 6 }
  local handle = start(opts)
  press(handle, opts, 'Take the camera')
  eq(handle.grabbed, true)
  handle.tick(0.016)
  eq(handle.disposed ~= true, true, 'held while nothing changes')

  handle.sim.cameraMode = 2 -- F1
  handle.tick(0.016)
  eq(handle.disposed, true, 'let go')
  handle.restoreIo()
  require('adapters/shortcuts').reset()
end)

test('a hand-over CamTool asks for itself does not let go', function()
  -- camera_use_specific_cam 13 is the cockpit view: CamTool asks the game for
  -- its drivable camera, which is a change of mode it caused, not the user.
  local opts = { cameraMode = 6, cameraFile = { interpolation_mode = 'fixed',
    version = 2, time = {}, pos = { camera(1, 0, { camera_use_specific_cam = 13 }) } } }
  local handle = start(opts)
  press(handle, opts, 'Take the camera')
  eq(handle.cameraMode, 2, 'CamTool handed the view to the drivable camera')
  handle.tick(0.016)
  eq(handle.disposed ~= true, true, 'before the game applies it')
  handle.sim.cameraMode = 2
  handle.tick(0.016)
  eq(handle.disposed ~= true, true, 'and after')
  handle.restoreIo()
  require('adapters/shortcuts').reset()
end)
