--[[
  Tests for core/focus.lua.

  The one that matters is the two-car case: focusing on the mix point between
  two cars would put the plane in empty space and leave both soft, so the legacy
  focuses on the nearer of the two.
]]

local runner = require('tests/runner')
local focus = require('core/focus')

local test, eq, near = runner.test, runner.eq, runner.near

test('distance is plain euclidean', function()
  near(focus.distance(0, 0, 0, 3, 4, 0), 5, 1e-12, '3-4-5')
  near(focus.distance(0, 0, 0, 0, 0, 0), 0, 1e-12)
  near(focus.distance(1, 2, 3, 1, 2, 3), 0, 1e-12)
  -- Direction must not matter.
  near(focus.distance(10, 0, 0, 0, 0, 0), focus.distance(0, 0, 0, 10, 0, 0), 1e-12)
end)

test('autofocus without a mix uses the tracked car', function()
  local cam = { x = 0, y = 0, z = 0 }
  local carA = { x = 30, y = 40, z = 0 }
  local carB = { x = 5, y = 0, z = 0 }

  near(focus.auto(cam, carA, carB, 0), 50, 1e-12, 'mix 0 ignores the second car')
  near(focus.auto(cam, carA, carB, nil), 50, 1e-12, 'no mix either')
  near(focus.auto(cam, carA, nil, 0.5), 50, 1e-12, 'no second car to use')
end)

test('with a mix it focuses on the NEARER car', function()
  local cam = { x = 0, y = 0, z = 0 }
  local far = { x = 100, y = 0, z = 0 }
  local near_ = { x = 20, y = 0, z = 0 }

  near(focus.auto(cam, far, near_, 0.5), 20, 1e-12, 'B is nearer')
  near(focus.auto(cam, near_, far, 0.5), 20, 1e-12, 'A is nearer')

  -- Not the mid point, which would leave both cars soft.
  local midpoint = focus.auto(cam, far, near_, 0.5)
  if math.abs(midpoint - 60) < 1e-9 then
    error('focused on the mix point instead of the nearer car', 2)
  end
end)

test('the vertical axis counts', function()
  local cam = { x = 0, y = 0, z = 0 }
  local above = { x = 0, y = 0, z = 25 }
  near(focus.auto(cam, above, nil, 0), 25, 1e-12)
end)

test('refocus is held when the camera looks away', function()
  -- Beyond a quarter turn from the tracked car, the legacy keeps the previous
  -- focus rather than chasing something off screen.
  eq(focus.shouldRefocus(0, 0), true)
  eq(focus.shouldRefocus(0, math.pi / 4), true)
  eq(focus.shouldRefocus(0, math.pi / 2), true, 'exactly a quarter turn still refocuses')
  eq(focus.shouldRefocus(0, math.pi / 2 + 0.01), false)
  eq(focus.shouldRefocus(0, math.pi), false, 'car directly behind')
  eq(focus.shouldRefocus(1.0, -1.0), false, 'the test is on the raw difference')
end)

test('DOF switches off for a very near focus', function()
  eq(focus.MIN_DISTANCE, 0.1)
  eq(focus.dofFactor(0), 0)
  eq(focus.dofFactor(0.09), 0)
  eq(focus.dofFactor(0.1), 1, 'the threshold itself is on')
  eq(focus.dofFactor(500), 1)
  eq(focus.dofFactor(nil), 0)
end)
