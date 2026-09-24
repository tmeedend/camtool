--[[
  Tests for core/mouselook.lua.

  The oracle is a line-for-line transcription of MouseLook.refresh and
  rotate_camera below: at 60 fps the port has to turn the camera exactly as
  CamTool 2 does, and at any other frame rate by the same amount in the same
  time.
]]

local runner = require('tests/runner')
local mouselook = require('core/mouselook')

local test, eq, near = runner.test, runner.eq, runner.near

local SCREEN_W, SCREEN_H = 1920, 1080

---CamTool 2, per frame, in drag mode. Absolute pointer positions.
local function legacy()
  local self = { positions = {}, avgX = 0, avgY = 0 }
  for i = 1, 60 do self.positions[i] = { x = 0, y = 0 } end

  ---refresh(False, lock) then the turn, in acUpdate's order.
  function self.frame(pointerX, pointerY, lmb, fovDeg)
    local sens = fovDeg / 50
    local heading = math.rad(self.avgX * sens)
    local pitch = math.rad(self.avgY * sens)

    if lmb then
      self.avgX, self.avgY = 0, 0
      for i = 60, 1, -1 do
        if i ~= 1 then
          self.positions[i].x = self.positions[i - 1].x
          self.positions[i].y = self.positions[i - 1].y
        else
          self.positions[1].x, self.positions[1].y = pointerX, pointerY
        end
        self.avgX = self.avgX + self.positions[i].x
        self.avgY = self.avgY + self.positions[i].y
      end
      self.avgX = (self.avgX / 60 - pointerX) / (SCREEN_W / 10)
      self.avgY = (self.avgY / 60 - pointerY) / (SCREEN_H / 10)
    else
      self.avgX, self.avgY = self.avgX * 0.95, self.avgY * 0.95
      for i = 1, 60 do self.positions[i].x, self.positions[i].y = pointerX, pointerY end
    end
    return heading, pitch
  end

  return self
end

---A gesture: the pointer as a function of time, and the button.
local function flick(t)
  -- 200 px right and 50 px down over a tenth of a second, then still.
  local k = math.min(1, t / 0.1)
  return 200 * k, 50 * k, t < 1.5
end

---Total turn over `seconds` at a frame rate, through the port.
local function turnAt(fps, seconds, gesture)
  local state = mouselook.new()
  local dt = 1 / fps
  local heading, pitch = 0, 0
  local lastX, lastY = 0, 0
  for i = 1, math.floor(seconds * fps + 0.5) do
    local x, y, lmb = gesture((i - 1) * dt)
    local out = mouselook.update(state, {
      dt = dt, held = true, steering = lmb,
      dx = x - lastX, dy = y - lastY,
      screenW = SCREEN_W, screenH = SCREEN_H, fov = 50,
    })
    lastX, lastY = x, y
    heading, pitch = heading + out.heading, pitch + out.pitch
  end
  return heading, pitch
end

test('at 60 fps it turns exactly as CamTool 2 does', function()
  local old = legacy()
  local state = mouselook.new()
  local lastX, lastY = 0, 0
  for i = 1, 180 do
    local x, y, lmb = flick((i - 1) / 60)
    local h0, p0 = old.frame(x, y, lmb, 50)
    local out = mouselook.update(state, {
      dt = 1 / 60, held = true, steering = lmb, dx = x - lastX, dy = y - lastY,
      screenW = SCREEN_W, screenH = SCREEN_H, fov = 50,
    })
    lastX, lastY = x, y
    near(out.heading, h0, 1e-9, 'heading, frame ' .. i)
    near(out.pitch, p0, 1e-9, 'pitch, frame ' .. i)
  end
end)

test('the same gesture turns the same amount at any frame rate', function()
  local h60, p60 = turnAt(60, 3, flick)
  local h144, p144 = turnAt(144, 3, flick)
  local h30, p30 = turnAt(30, 3, flick)
  eq(math.abs(h60) > 0.1, true, 'the flick turns the camera')
  near(h144, h60, math.abs(h60) * 0.03, '144 fps')
  near(p144, p60, math.abs(p60) * 0.03, '144 fps pitch')
  near(h30, h60, math.abs(h60) * 0.05, '30 fps')
  near(p30, p60, math.abs(p60) * 0.05, '30 fps pitch')
end)

test('moving right turns the heading down, moving down tilts the view down', function()
  -- CamTool 2's signs, which match its heading convention (and so ours).
  local h, p = turnAt(60, 0.5, flick)
  eq(h < 0, true)
  eq(p < 0, true)
end)

test('the camera keeps turning after the pointer stops', function()
  -- The whole point of the average: the flick is over in a tenth of a second
  -- and the turn goes on while the average catches up.
  local state = mouselook.new()
  local out
  for i = 1, 30 do
    local x, y = flick((i - 1) / 60)
    local px, py = flick((i - 2) / 60)
    if i == 1 then px, py = 0, 0 end
    out = mouselook.update(state, { dt = 1 / 60, held = true, steering = true,
      dx = x - px, dy = y - py, screenW = SCREEN_W, screenH = SCREEN_H, fov = 50 })
  end
  eq(out.heading ~= 0, true, 'still turning half a second in')
end)

test('releasing the button coasts, and slows by 5% a tick', function()
  local state = mouselook.new()
  mouselook.update(state, { dt = 1 / 60, held = true, steering = true, dx = 300,
    screenW = SCREEN_W, screenH = SCREEN_H, fov = 50 })
  mouselook.update(state, { dt = 1 / 60, held = true, steering = false,
    screenW = SCREEN_W, screenH = SCREEN_H, fov = 50 })
  local a = mouselook.update(state, { dt = 1 / 60, held = true, steering = false,
    screenW = SCREEN_W, screenH = SCREEN_H, fov = 50 }).heading
  local b = mouselook.update(state, { dt = 1 / 60, held = true, steering = false,
    screenW = SCREEN_W, screenH = SCREEN_H, fov = 50 }).heading
  eq(a ~= 0, true, 'coasting')
  near(b / a, 0.95, 1e-9)
end)

test('letting go of the key stops the turn at once', function()
  local state = mouselook.new()
  mouselook.update(state, { dt = 1 / 60, held = true, steering = true, dx = 300, fov = 50 })
  mouselook.update(state, { dt = 1 / 60, held = false, fov = 50 })
  local out = mouselook.update(state, { dt = 1 / 60, held = true, steering = true, fov = 50 })
  eq(out.heading, 0)
end)

test('the camera file lets go over a second and takes back over two', function()
  local state = mouselook.new()
  local out
  for _ = 1, 30 do out = mouselook.update(state, { dt = 1 / 60, held = true, fov = 50, camera = 3 }) end
  near(out.weight, math.sin(0.5 * math.pi / 2), 1e-9, 'halfway through the second')
  for _ = 1, 30 do out = mouselook.update(state, { dt = 1 / 60, held = true, fov = 50, camera = 3 }) end
  near(out.weight, 1, 1e-9, 'all the mouse after a second')

  for _ = 1, 60 do out = mouselook.update(state, { dt = 1 / 60, held = false, fov = 50, camera = 3 }) end
  near(out.weight, math.sin(0.5 * math.pi / 2), 1e-9, 'half way back after a second')
  for _ = 1, 60 do out = mouselook.update(state, { dt = 1 / 60, held = false, fov = 50, camera = 3 }) end
  near(out.weight, 0, 1e-9, 'all the file after two')
end)

test('a cut during the hand-back snaps to the new shot', function()
  local state = mouselook.new()
  for _ = 1, 60 do mouselook.update(state, { dt = 1 / 60, held = true, fov = 50, camera = 3 }) end
  mouselook.update(state, { dt = 1 / 60, held = false, fov = 50, camera = 3 })
  local out = mouselook.update(state, { dt = 1 / 60, held = false, fov = 50, camera = 4 })
  eq(out.weight, 0)
end)

test('the zoom keys ease into a steady zoom, and only with the key held', function()
  local state = mouselook.new()
  local lens = 50
  local steps = {}
  for i = 1, 30 do
    local out = mouselook.update(state, { dt = 1 / 60, held = true, zoomIn = true, fov = lens })
    steps[i] = lens - out.fov
    lens = out.fov
  end
  eq(lens < 50, true, 'zoom in narrows the field of view')
  eq(steps[1] < steps[10], true, 'easing in')
  near(steps[29], steps[30], steps[30] * 0.05, 'steady once eased in')

  local wider = mouselook.update(mouselook.new(),
    { dt = 1 / 60, held = true, zoomOut = true, fov = 50 }).fov
  eq(wider > 50, true, 'zoom out widens it')

  local idle = mouselook.update(mouselook.new(),
    { dt = 1 / 60, held = false, zoomIn = true, fov = 50 }).fov
  eq(idle, 50, 'no zoom without the mouse look key')
end)

test('the zoom eases out after the key is released', function()
  local state = mouselook.new()
  local lens = 50
  for _ = 1, 30 do
    lens = mouselook.update(state, { dt = 1 / 60, held = true, zoomIn = true, fov = lens }).fov
  end
  local after = mouselook.update(state, { dt = 1 / 60, held = true, fov = lens }).fov
  eq(after < lens, true, 'still zooming just after')
  for _ = 1, 30 do
    lens = mouselook.update(state, { dt = 1 / 60, held = true, fov = lens }).fov
  end
  eq(mouselook.update(state, { dt = 1 / 60, held = true, fov = lens }).fov, lens,
    'at rest a quarter second later')
end)

test('nothing zooms when the app starts', function()
  -- CamTool 2 starts its easing at "just released", so the free camera
  -- zooms in by several degrees in the first quarter second.
  local state = mouselook.new()
  for _ = 1, 20 do
    eq(mouselook.update(state, { dt = 1 / 60, held = false, fov = 50 }).fov, 50)
  end
end)

test('the field of view stays between 1 and 90 degrees', function()
  local state = mouselook.new()
  local lens = 2
  for _ = 1, 600 do
    lens = mouselook.update(state, { dt = 1 / 60, held = true, zoomIn = true, fov = lens }).fov
  end
  eq(lens >= 1, true)
  state = mouselook.new()
  lens = 89
  for _ = 1, 600 do
    lens = mouselook.update(state, { dt = 1 / 60, held = true, zoomOut = true, fov = lens }).fov
  end
  eq(lens <= 90, true)
end)

--------------------------------------------------------------------------------
-- The playback hands the camera over by the weight
--------------------------------------------------------------------------------

local playback = require('core/playback')
local angles = require('core/angles')

---A camera sliding from x = 0 to x = 100 over the lap, tracking the car,
---with a keyframed lens and a set focus.
local function slidingDoc()
  return { interpolation_mode = 'fixed', time = {}, pos = { {
    camera_in = 0, tracking_strength_heading = 1, tracking_strength_pitch = 1,
    tracking_offset = 0, camera_use_tracking_point = 0,
    keyframes = {
      { keyframe = 0, interpolation = { loc_x = 0, loc_y = 0, loc_z = 5,
        camera_fov = 40, camera_focus_point = 20 } },
      { keyframe = 1, interpolation = { loc_x = 100, loc_y = 0, loc_z = 5,
        camera_fov = 40, camera_focus_point = 20 } },
    } } } }
end

local function run(state, doc, pos, manual)
  manual = manual or {}
  return playback.frame(state, doc, {
    trackPos = pos, replayRate = 1, clock = 0,
    carX = 50, carY = 80, carZ = 0,
    seedHeading = 0, seedPitch = 0,
    manualWeight = manual.weight, manualHeading = manual.heading,
    manualPitch = manual.pitch, manualFov = manual.fov,
  })
end

local function fresh()
  return playback.new({ applyShake = false, applySpline = false })
end

test('at full weight the mouse has the camera', function()
  local state, doc = fresh(), slidingDoc()
  local before = run(state, doc, 0.2)
  local x, heading = before.x, before.heading

  local out = run(state, doc, 0.6, { weight = 1, heading = 0.1, pitch = -0.05, fov = 25 })
  near(out.x, x, 1e-9, 'the camera stays where it was')
  near(out.heading, heading + 0.1, 1e-9, 'and turns by what the mouse gave it')
  near(out.fov, 25, 1e-9, 'with the lens the zoom left')
  near(out.dofDistance, mouselook.FOCUS_DISTANCE, 1e-9, 'focused long')
end)

test('at half weight the two cameras are blended', function()
  local ref = run(fresh(), slidingDoc(), 0.2)
  local file = run(fresh(), slidingDoc(), 0.6)

  local state = fresh()
  run(state, slidingDoc(), 0.2)
  local out = run(state, slidingDoc(), 0.6, { weight = 0.5, heading = 0, pitch = 0, fov = 60 })
  near(out.x, (file.x + ref.x) / 2, 1e-9, 'halfway between moving and held')
  near(out.fov, (40 + 60) / 2, 1e-9, 'halfway between the lenses')
  near(out.dofDistance, (20 + mouselook.FOCUS_DISTANCE) / 2, 1e-9)
end)

test('at zero weight nothing changes', function()
  local a = run(fresh(), slidingDoc(), 0.6)
  local b = run(fresh(), slidingDoc(), 0.6, { weight = 0, heading = 1, pitch = 1, fov = 10 })
  for _, key in ipairs({ 'x', 'y', 'z', 'heading', 'pitch', 'fov', 'dofDistance' }) do
    eq(b[key], a[key], key)
  end
end)

test('the mouse cannot tip the camera over the top', function()
  local state, doc = fresh(), slidingDoc()
  run(state, doc, 0.2)
  local out
  for _ = 1, 50 do out = run(state, doc, 0.2, { weight = 1, pitch = 0.2 }) end
  eq(out.pitch <= 1.5 + 1e-9, true)
  local _, ly = angles.lookVector(out.heading, out.pitch)
  eq(ly > 0, true, 'still looking up, not over and behind')
end)
