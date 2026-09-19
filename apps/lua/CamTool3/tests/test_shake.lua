--[[
  Tests for core/shake.lua.

  Shake is the one effect where "looks about right" is not good enough: it is
  driven by the replay position so that re-rendering the same footage gives the
  same shake. A shake that is merely plausible would differ between renders and
  ruin a cut.
]]

local runner = require('tests/runner')
local shake = require('core/shake')

local test, eq, near = runner.test, runner.eq, runner.near

test('the momentum window matches the legacy', function()
  eq(shake.DEFAULT_MOMENTUM_WINDOW, 50, 'Camera.py keeps 50 headings')
end)

test('a still camera has no momentum', function()
  local still = {}
  for i = 1, 50 do still[i] = 1.25 end
  near(shake.momentum(still), 0, 1e-12)
end)

test('momentum grows with how fast the camera turns', function()
  local slow = { 1.001 }
  local fast = { 1.02 }
  for i = 2, 50 do
    slow[i] = 1.0
    fast[i] = 1.0
  end

  local slowM = shake.momentum(slow)
  local fastM = shake.momentum(fast)

  if slowM <= 0 then error('a moving camera must have some momentum', 2) end
  if fastM <= slowM then error('turning faster must give more momentum', 2) end
end)

test('momentum is clamped to 1', function()
  local wild = { 10.0 }
  for i = 2, 50 do wild[i] = 0.0 end
  eq(shake.momentum(wild), 1)
end)

test('momentum copes with too little history', function()
  eq(shake.momentum({}), 0)
  eq(shake.momentum({ 1.0 }), 0)
  eq(shake.momentum(nil), 0)
end)

test('zero strength means no shake at all', function()
  local pitch, heading = shake.rotation(0, 12.34, 0.5, 1)
  eq(pitch, 0)
  eq(heading, 0)
end)

test('rotation shake is deterministic for a given clock', function()
  -- The whole point: same replay position, same shake, every render.
  local p1, h1 = shake.rotation(1, 7.5, 0.3, 1)
  local p2, h2 = shake.rotation(1, 7.5, 0.3, 1)
  eq(p1, p2)
  eq(h1, h2)
end)

test('rotation shake matches the legacy formula', function()
  local t, momentum = 3.2, 0.4
  local strength = 0.5 * (momentum * 0.2 + 0.8) * 0.001

  local expectedHeading = (math.sin(t * 8) + math.sin(t * 5) + math.sin(t)) * strength
  local expectedPitch = (math.sin(t * 7) + math.sin(t * 2) + math.sin(t * 8)) * strength

  local pitch, heading = shake.rotation(0.5, t, momentum, 1)
  near(pitch, expectedPitch, 1e-15)
  near(heading, expectedHeading, 1e-15)
end)

test('rotation shake scales with replay speed', function()
  local p1 = shake.rotation(1, 3.2, 0.4, 1)
  local p2 = shake.rotation(1, 3.2, 0.4, 2)
  near(p2, p1 * 2, 1e-15)

  -- No speed given behaves as 1.
  local p3 = shake.rotation(1, 3.2, 0.4, nil)
  near(p3, p1, 1e-15)
end)

test('panning makes the shake stronger', function()
  local still = select(2, shake.rotation(1, 3.2, 0, 1))
  local panning = select(2, shake.rotation(1, 3.2, 1, 1))
  -- The factor is (momentum * 0.2 + 0.8), so 0.8 against 1.0.
  near(panning, still * (1.0 / 0.8), 1e-12)
end)

test('the tracking shake crossfades between two sine terms', function()
  local t = 2.7

  -- At rest it is the beating term only.
  local atRest = shake.trackingOffset(1, t, 0)
  near(atRest, math.sin(t * 3) * math.sin(t * 4) * 0.8 * 0.25, 1e-15)

  -- At full momentum it is the plain term only.
  local moving = shake.trackingOffset(1, t, 1)
  near(moving, math.sin(t * 9) * 1.0 * 0.25, 1e-15)
end)

test('the tracking shake scales with strength and is zero without it', function()
  eq(shake.trackingOffset(0, 2.7, 0.5), 0)
  near(shake.trackingOffset(2, 2.7, 0.5),
    shake.trackingOffset(1, 2.7, 0.5) * 2, 1e-15)
end)

test('the tracking shake is NOT scaled by replay speed', function()
  -- Legacy bug, reproduced deliberately: Camera.py computes
  -- `self.__shake_offset / replayTimeMultiplier` and discards the result, so
  -- the division never happens. The signature takes no speed at all, which is
  -- the honest way to say so.
  near(shake.trackingOffset(1, 2.7, 0.5), shake.trackingOffset(1, 2.7, 0.5), 0)
end)
