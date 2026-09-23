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
