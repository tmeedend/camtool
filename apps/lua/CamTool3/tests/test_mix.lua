--[[
  Tests for MIX: the aim blended from the followed car towards the extra one,
  in core/playback, as InterpolateFrame.py does it outside smart tracking.
]]

local runner = require('tests/runner')
local playback = require('core/playback')
local angles = require('core/angles')

local test, eq, near = runner.test, runner.eq, runner.near

local TWO_PI = 2 * math.pi

---The same angle, whichever turn it is written on.
local function sameAngle(a, b, eps, message)
  local d = (a - b) % TWO_PI
  if d > math.pi then d = d - TWO_PI end
  near(d, 0, eps or 1e-9, message)
end

---A camera at the origin that tracks fully, with no lead unless asked.
local function docWith(fields)
  local camera = {
    camera_in = 0,
    keyframes = { { keyframe = 0,
      interpolation = { loc_x = 0, loc_y = 0, loc_z = 0 } } },
    tracking_strength_heading = 1,
    tracking_strength_pitch = 1,
    tracking_offset = 0,
    tracking_mix = 0,
    camera_use_tracking_point = 0,
  }
  for k, v in pairs(fields or {}) do camera[k] = v end
  return { pos = { camera }, time = {}, interpolation_mode = 'fixed' }
end

local function newState()
  return playback.new({ applyShake = false, applySpline = false })
end

---Where a target has to be, seen from the origin, for the aim to be `heading`.
local function towards(heading, distance)
  local a = heading - math.pi / 2
  return math.sin(a) * distance, math.cos(a) * distance, 0
end

local function frame(state, doc, a, b, extraCar)
  return playback.frame(state, doc, {
    trackPos = 0.5, replayRate = 1, clock = 0,
    -- Facing the followed car to begin with, as a camera taken on a shot
    -- does. Facing away, the autofocus holds rather than refocuses.
    seedHeading = angles.aimAt(0, 0, 0, a[1], a[2], a[3]),
    carX = a[1], carY = a[2], carZ = a[3],
    extraCar = extraCar or (b and 7) or nil,
    extraX = b and b[1], extraY = b and b[2], extraZ = b and b[3],
  })
end

local A = { 100, 0, 0 }
local B = { 0, 100, 20 }

local function aimAt(p)
  return angles.aimAt(0, 0, 0, p[1], p[2], p[3])
end

test('MIX at 0 aims at the followed car, at 100% at the extra one', function()
  local headingA, pitchA = aimAt(A)
  local headingB, pitchB = aimAt(B)

  local out = frame(newState(), docWith({ tracking_mix = 0 }), A, B)
  sameAngle(out.heading, headingA, nil, 'MIX 0')
  near(out.pitch, pitchA, 1e-9)
  eq(out.aimMix, 0)

  out = frame(newState(), docWith({ tracking_mix = 1 }), A, B)
  sameAngle(out.heading, headingB, nil, 'MIX 100%')
  near(out.pitch, pitchB, 1e-9)
  eq(out.aimMix, 1)
end)

test('MIX at 50% aims halfway, by angle', function()
  local headingA, pitchA = aimAt(A)
  local headingB, pitchB = aimAt(B)
  local out = frame(newState(), docWith({ tracking_mix = 0.5 }), A, B)
  sameAngle(out.heading, angles.blend(headingA, headingB, 0.5))
  near(out.pitch, (pitchA + pitchB) / 2, 1e-9)
end)

test('the blend takes the short way round', function()
  -- Two aims 0.2 rad apart across the seam of atan2: halfway between them is
  -- next to both, not on the far side of the circle.
  local seam = -math.pi / 2
  local a = { towards(seam + 0.1, 100) }
  local b = { towards(seam - 0.1, 100) }
  local out = frame(newState(), docWith({ tracking_mix = 0.5 }), a, b)
  sameAngle(out.heading, seam, 1e-9)
end)

test('without an extra car MIX does nothing', function()
  local headingA = aimAt(A)
  local out = frame(newState(), docWith({ tracking_mix = 1 }), A, nil)
  sameAngle(out.heading, headingA)
  eq(out.aimMix, 0)
end)

test('the extra car is recorded while MIX is at 0', function()
  -- CamTool 2 only records it while MIX is above zero, so the lead is worked
  -- out from a stale history when MIX rises. Here the switch from 0 to 1
  -- lands exactly where a camera that had MIX at 1 all along is.
  local zeroThenOne = newState()
  local alwaysOne = newState()
  local off = docWith({ tracking_offset = -0.1, tracking_mix = 0 })
  local on = docWith({ tracking_offset = -0.1, tracking_mix = 1 })

  local last
  for i = 1, 60 do
    local b = { 3 * i, 100 + 2 * i, 20 }
    frame(zeroThenOne, i < 60 and off or on, A, b)
    last = frame(alwaysOne, on, A, b).heading
  end
  sameAngle(zeroThenOne.heading, last, 1e-9)
end)

test('another extra car starts a history of its own', function()
  -- With a lead, a history still about the previous car would aim ahead of
  -- the new one along a path it never drove.
  local state = newState()
  local doc = docWith({ tracking_offset = -0.1, tracking_mix = 1 })
  for i = 1, 30 do frame(state, doc, A, { 3 * i, 100, 20 }, 7) end

  local elsewhere = { -200, 50, 0 }
  local out = frame(state, doc, A, elsewhere, 8)
  sameAngle(out.heading, aimAt(elsewhere), 1e-9)
end)

test('the autofocus picks the nearer car once MIX is set', function()
  local near_ = { 0, 30, 0 }
  local out = frame(newState(),
    docWith({ tracking_mix = 0.2, camera_use_tracking_point = 1 }), A, near_)
  near(out.dofDistance, 30, 1e-9, 'the extra car is nearer')

  out = frame(newState(),
    docWith({ tracking_mix = 0, camera_use_tracking_point = 1 }), A, near_)
  near(out.dofDistance, 100, 1e-9, 'MIX at 0 ignores it')
end)

--------------------------------------------------------------------------------
-- Through the app: the arrows, the names, and the aim they lead to
--------------------------------------------------------------------------------

local fakes = require('tests/fakes/csp')

---One tracking camera at a fixed spot, MIX at 100%, no lead.
local function appDoc()
  return {
    pos = {
      { camera_in = 0, camera_pit = false, camera_use_tracking_point = 0,
        tracking_strength_heading = 1, tracking_strength_pitch = 1,
        tracking_offset = 0, tracking_mix = 1,
        transform_loc_strength = 1, transform_rot_strength = 1,
        camera_shake_strength = 0, camera_offset_shake_strength = 0,
        keyframes = { { keyframe = 0,
          interpolation = { loc_x = 60, loc_y = 0, loc_z = 5 } } } },
    },
    time = {},
    version = 2,
    interpolation_mode = 'fixed',
  }
end

-- AC world, Y up. The camera sits at (60, 5, 0).
local CAMERA = { 60, 5, 0 }
local FOLLOWED = { 160, 5, 0 }
local AHEAD = { 60, 5, 100 }
local BEHIND = { -40, 5, 0 }

local function startApp()
  local opts = {
    cameraFile = appDoc(),
    splinePosition = 0.20,
    carPosition = vec3(FOLLOWED[1], FOLLOWED[2], FOLLOWED[3]),
    driverName = 'Followed',
    otherCars = {
      [1] = { splinePosition = 0.25, isConnected = true, driverName = 'Rival Ahead',
        position = vec3(AHEAD[1], AHEAD[2], AHEAD[3]) },
      [2] = { splinePosition = 0.10, isConnected = true,
        driverName = 'A Driver With A Long Name',
        position = vec3(BEHIND[1], BEHIND[2], BEHIND[3]) },
    },
    clicks = {
      ['no file###fileName'] = true,
      ['cameras   [CamTool 2]###fileName'] = true,
      ['Take camera###hold'] = true,
    },
  }
  local handle = fakes.install(opts)
  require('ui/band').reset()
  assert(loadfile('CamTool3.lua'))()

  for _ = 1, 6 do
    pcall(_G.script.windowAtr, 0.016)
    handle.tick(0.016)
  end
  for label in pairs(opts.clicks) do opts.clicks[label] = nil end
  eq(handle.grabbed, true, 'the camera was taken')

  local app = { handle = handle }

  function app.click(label)
    opts.clicks[label] = true
    pcall(_G.script.windowAtr, 0.016)
    opts.clicks[label] = nil
    handle.tick(0.016)
  end

  ---What the panel shows for a row.
  function app.shown(key)
    handle.buttons = {}
    pcall(_G.script.windowAtr, 0.016)
    for i = 1, #handle.buttons do
      local text = tostring(handle.buttons[i]):match('^(.-)###.*' .. key .. 'val$')
      if text ~= nil then return text end
    end
    return nil
  end

  ---Is the camera looking at this point, AC world?
  function app.lookingAt(p)
    local l = handle.transform.look
    local dx, dy, dz = p[1] - CAMERA[1], p[2] - CAMERA[2], p[3] - CAMERA[3]
    local n = math.sqrt(dx * dx + dy * dy + dz * dz)
    return (l.x * dx + l.y * dy + l.z * dz) / n > 0.9999
  end

  return app
end

test('with no extra car, MIX at 100% still frames the followed car', function()
  local app = startApp()
  eq(app.shown('trackedCarB'), '--', 'none to begin with')
  eq(app.lookingAt(FOLLOWED), true)
  app.handle.restoreIo()
end)

test('the extra car arrow steps to the car ahead, and MIX aims at it', function()
  local app = startApp()
  app.click('##trackingtrackedCarBinc')
  for _ = 1, 3 do app.handle.tick(0.016) end

  eq(app.shown('trackedCarB'), 'Rival Ahead', 'named as its driver')
  eq(app.lookingAt(AHEAD), true, 'MIX at 100% frames the extra car')
  app.handle.restoreIo()
end)

test('stepping the extra car back onto the followed one means none', function()
  local app = startApp()
  app.click('##trackingtrackedCarBinc')
  app.click('##trackingtrackedCarBdec')
  for _ = 1, 3 do app.handle.tick(0.016) end

  eq(app.shown('trackedCarB'), '--')
  eq(app.lookingAt(FOLLOWED), true)
  app.handle.restoreIo()
end)

test('a long driver name is cut as CamTool 2 cuts it', function()
  local app = startApp()
  app.click('##trackingtrackedCarBdec')
  eq(app.shown('trackedCarB'), 'A Driver With.')
  app.handle.restoreIo()
end)

test('the active car arrows move the replay to the next car on track', function()
  local app = startApp()
  eq(app.shown('trackedCarA'), 'Followed')
  app.click('##trackingtrackedCarAinc')
  eq(app.handle.focusCalls[1], 1, 'the car ahead, not the next number')
  app.click('##trackingtrackedCarAdec')
  eq(app.handle.focusCalls[2], 0, 'and back')
  app.handle.restoreIo()
end)

test('the extra car is forgotten when it becomes the followed one', function()
  local app = startApp()
  app.click('##trackingtrackedCarBinc')
  app.click('##trackingtrackedCarAinc')
  -- The replay now follows car 1, which was the extra car.
  eq(app.shown('trackedCarB'), '--')
  app.click('##trackingtrackedCarAdec')
  eq(app.shown('trackedCarB'), '--', 'and it does not come back')
  app.handle.restoreIo()
end)
