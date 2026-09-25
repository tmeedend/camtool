--[[
  Tests for core/recorder.lua: recording a path, as Camera.record_spline does.
]]

local runner = require('tests/runner')
local recorder = require('core/recorder')
local angles = require('core/angles')
local playback = require('core/playback')

local test, eq, near = runner.test, runner.eq, runner.near

local function sample(trackPos, heading)
  return { trackPos = trackPos, x = trackPos * 100, y = 2, z = 5,
    pitch = 0.1, roll = 0, heading = heading or 0 }
end

---Feed a sample every frame for `seconds` of replay time.
local function run(state, spline, seconds, at, fps)
  fps = fps or 60
  local done = false
  for i = 1, math.floor(seconds * fps + 0.5) do
    local s = at((i - 1) / fps)
    done = recorder.feed(state, spline, s, 1 / fps) or done
  end
  return done
end

test('one sample per second of replay time, whatever the frame rate', function()
  local a, b = recorder.emptySpline(), recorder.emptySpline()
  run(recorder.new('camera'), a, 10.5, function(t) return sample(t / 100) end, 60)
  run(recorder.new('camera'), b, 10.5, function(t) return sample(t / 100) end, 144)
  eq(recorder.count(a), 10)
  eq(recorder.count(b), 10)
end)

test('a paused replay records nothing', function()
  local spline = recorder.emptySpline()
  local state = recorder.new('camera')
  for _ = 1, 600 do recorder.feed(state, spline, sample(0.2), 0) end
  eq(recorder.count(spline), 0)
end)

test('crossing the line, the_x runs on past 1', function()
  local spline = recorder.emptySpline()
  local state = recorder.new('camera')
  local positions = { 0.97, 0.99, 0.01, 0.03 }
  for _, p in ipairs(positions) do recorder.feed(state, spline, sample(p), 1.01) end
  near(spline.the_x[3], 1.01, 1e-12)
  near(spline.the_x[4], 1.03, 1e-12)
end)

test('the heading is unwound, so it never jumps a full turn', function()
  local spline = recorder.emptySpline()
  local state = recorder.new('camera')
  recorder.feed(state, spline, sample(0.1, math.pi - 0.05), 1.01)
  recorder.feed(state, spline, sample(0.2, -math.pi + 0.05), 1.01)
  near(spline.rot_z[2], math.pi + 0.05, 1e-12)
end)

test('the track path records one lap from the first half and stops at the line', function()
  local spline = recorder.emptySpline()
  local state = recorder.new('track')
  local done = false
  -- Starting in the second half: nothing until the car is past the line.
  for _, p in ipairs({ 0.8, 0.9, 0.1, 0.3, 0.6, 0.9, 0.05 }) do
    done = recorder.feed(state, spline, sample(p), 1.01)
  end
  eq(done, true, 'finished by itself back at the line')
  eq(recorder.count(spline), 4, '0.1, 0.3, 0.6 and 0.9')
  eq(spline.the_x[1], 0.1)
  eq(spline.the_x[4], 0.9, 'no wrap for the track path')
end)

test('the pit path runs on across the line like a camera one', function()
  local spline = recorder.emptySpline()
  local state = recorder.new('pit')
  for _, p in ipairs({ 0.95, 0.99, 0.02 }) do recorder.feed(state, spline, sample(p), 1.01) end
  near(spline.the_x[3], 1.02, 1e-12)
end)

test('the roll read back from an up vector is the roll that built it', function()
  -- Build the up vector the way core/playback does, and read it back.
  for _, roll in ipairs({ 0, 0.3, -0.7, 1.2 }) do
    local state = playback.new({ applyShake = false, applySpline = false })
    local doc = { interpolation_mode = 'fixed', time = {}, pos = { {
      camera_in = 0, tracking_strength_heading = 0, tracking_strength_pitch = 0,
      keyframes = { { keyframe = 0, interpolation = { loc_x = 0, loc_y = 0, loc_z = 5,
        rot_x = 0.2, rot_z = 1.1, rot_y = roll } } } } } }
    local out = playback.frame(state, doc, { trackPos = 0.5, replayRate = 1, clock = 0 })
    near(angles.rollFromUp(out.lookX, out.lookY, out.lookZ, out.upX, out.upY, out.upZ),
      roll, 1e-9, 'roll ' .. roll)
  end
end)

--------------------------------------------------------------------------------
-- Through the app
--------------------------------------------------------------------------------

local fakes = require('tests/fakes/csp')

local function start()
  local opts = {
    clicks = {}, splinePosition = 0.1, cameraMode = 6,
    cameraFile = { interpolation_mode = 'fixed', version = 2, time = {}, pos = { {
      id = 1, camera_in = 0, camera_pit = false, camera_use_tracking_point = 0,
      tracking_strength_heading = 0, tracking_strength_pitch = 0,
      keyframes = { { keyframe = 0, interpolation = { loc_x = 0, loc_y = 0, loc_z = 5 } } } } } },
  }
  local handle = fakes.install(opts)
  require('ui/atr').cancelEditing()
  require('ui/band').reset()
  assert(loadfile('CamTool3.lua'))()
  pcall(_G.script.windowAtr, 0.016)

  local app = { handle = handle }
  function app.click(label)
    opts.clicks[label] = true
    pcall(_G.script.windowAtr, 0.016)
    opts.clicks[label] = nil
  end
  function app.seconds(n)
    for _ = 1, math.floor(n / 0.016 + 0.5) do handle.tick(0.016) end
  end
  function app.drawn(piece)
    handle.drawn, handle.buttons = {}, {}
    pcall(_G.script.windowAtr, 0.016)
    for i = 1, #handle.drawn do
      if (handle.drawn[i].text or ''):find(piece, 1, true) then return true end
    end
    for i = 1, #handle.buttons do
      if tostring(handle.buttons[i]):find(piece, 1, true) then return true end
    end
    return false
  end
  return app
end

test('Record path records the camera on screen, and Stop is one undo', function()
  local app = start()
  -- Select the camera: the pit view and back picks the first track camera.
  app.click(' pit ###pitView')
  app.click('[pit]###pitView')

  app.click('Record path###recordCameraPath')
  eq(app.drawn('Stop recording###recordCameraPath'), true, 'the button says Stop')
  app.handle.cameraPosition = vec3(10, 3, 20)
  app.seconds(3.2)
  app.click('Stop recording###recordCameraPath')

  eq(app.drawn('SPLINE -- 3 points recorded'), true)
  eq(app.drawn('Remove path###recordCameraPath'), true, 'and then offers to remove it')
  eq(app.drawn('Undo (1)###undo'), true, 'the whole recording is one undo')

  app.click('Undo (1)###undo')
  eq(app.drawn('SPLINE -- nothing recorded'), true, 'undo takes it all back')
  app.handle.restoreIo()
end)

test('the track path records a lap from the keys panel and stops by itself', function()
  local app = start()
  app.click(' keys ###showKeys')
  app.click('Record###recordTrackPath')
  eq(app.drawn('Track path -- recording'), true)

  app.handle.car.splinePosition = 0.2
  app.seconds(1.1)
  app.handle.car.splinePosition = 0.7
  app.seconds(1.1)
  app.handle.car.splinePosition = 0.02
  app.seconds(1.1)

  eq(app.drawn('Track path -- 2 points'), true, 'back at the line, it stopped')
  eq(app.drawn('Undo (1)###undo'), true, 'with its undo entry')
  app.handle.restoreIo()
end)
