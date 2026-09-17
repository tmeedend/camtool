--[[
  Tests for core/angles.lua.

  The round-trip test is the one that matters: aimAt and lookVector have to be
  exact inverses, because that is what says the heading convention taken from
  Camera.calculate_cam_rot_to_tracking_car was read correctly. Getting it wrong
  points the camera somewhere plausible but wrong, which is easy to miss and
  costs a session to diagnose in game.
]]

local runner = require('tests/runner')
local angles = require('core/angles')

local test, eq, near = runner.test, runner.eq, runner.near

test('aiming along +y in CamTool space gives heading pi/2', function()
  -- atan2(0, 1) + pi/2 = pi/2
  local h, p = angles.aimAt(0, 0, 0, 0, 10, 0)
  near(h, math.pi / 2, 1e-12)
  near(p, 0, 1e-12)
end)

test('aiming along +x gives heading pi', function()
  -- atan2(1, 0) + pi/2 = pi/2 + pi/2 = pi
  local h = angles.aimAt(0, 0, 0, 10, 0, 0)
  near(h, math.pi, 1e-12)
end)

test('pitch is positive when the target is above', function()
  local _, up = angles.aimAt(0, 0, 0, 10, 0, 10)
  near(up, math.pi / 4, 1e-12, 'a 45 degree climb')

  local _, down = angles.aimAt(0, 0, 0, 10, 0, -10)
  near(down, -math.pi / 4, 1e-12)

  local _, level = angles.aimAt(0, 0, 5, 10, 0, 5)
  near(level, 0, 1e-12)
end)

test('lookVector is a unit vector', function()
  for _, h in ipairs({ -3, -1, 0, 0.7, 2, 3.1 }) do
    for _, p in ipairs({ -1.4, -0.3, 0, 0.5, 1.4 }) do
      local x, y, z = angles.lookVector(h, p)
      near(math.sqrt(x * x + y * y + z * z), 1, 1e-12,
        string.format('heading %g pitch %g', h, p))
    end
  end
end)

test('lookVector undoes aimAt for any direction', function()
  -- Camera at an arbitrary spot, targets all around it. Aim at each, turn the
  -- angles back into a direction, and check it points at the target again.
  local cx, cy, cz = 12.5, -30.25, 8.0
  local targets = {
    { 20, -30.25, 8 }, { 12.5, 10, 8 }, { -40, -80, 25 },
    { 0, 0, 0 }, { 12.5, -30.25, 40 }, { 100, 100, -10 },
  }

  for i = 1, #targets do
    local t = targets[i]
    local h, p = angles.aimAt(cx, cy, cz, t[1], t[2], t[3])
    local lx, ly, lz = angles.lookVector(h, p)

    -- Back to CamTool space: AC y is CamTool z, AC z is CamTool y.
    local dx, dy, dz = t[1] - cx, t[2] - cy, t[3] - cz
    local length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length > 1e-9 then
      near(lx, dx / length, 1e-12, 'x of target ' .. i)
      near(lz, dy / length, 1e-12, 'y of target ' .. i)
      near(ly, dz / length, 1e-12, 'z of target ' .. i)
    end
  end
end)

test('normalize brings a value to the nearest revolution', function()
  local TAU = math.pi * 2
  near(angles.normalize(0, 0.5), 0.5, 1e-12, 'already nearest')
  near(angles.normalize(3.0, -3.0), -3.0 + TAU, 1e-12, 'wrap up across pi')
  near(angles.normalize(-3.0, 3.0), 3.0 - TAU, 1e-12, 'wrap down across -pi')
  near(angles.normalize(0, TAU), 0, 1e-12, 'a full turn is the same angle')
end)

test('blend takes the short way round', function()
  local TAU = math.pi * 2
  -- Half way from 3.0 to -3.0 must cross pi, not run back through zero.
  local mid = angles.blend(3.0, -3.0, 0.5)
  near(mid, (3.0 + (-3.0 + TAU)) / 2, 1e-12)
  if mid > -3.0 and mid < 3.0 then
    error('blend went the long way round, through ' .. mid, 2)
  end
end)

test('blend endpoints are exact', function()
  near(angles.blend(1.0, 2.0, 0), 1.0, 1e-12)
  near(angles.blend(1.0, 2.0, 1), 2.0, 1e-12)
end)

test('fromLook inverts lookVector', function()
  -- Needed to seed the "hold the current heading" fallback: when a camera does
  -- not keyframe rot_z, the legacy keeps the camera's present heading rather
  -- than snapping to zero.
  for _, h in ipairs({ -3.0, -1.2, 0, 0.9, 2.5 }) do
    for _, p in ipairs({ -1.2, -0.4, 0, 0.6, 1.2 }) do
      local x, y, z = angles.lookVector(h, p)
      local h2, p2 = angles.fromLook(x, y, z)
      near(angles.normalize(h, h2), h, 1e-12, string.format('heading %g', h))
      near(p2, p, 1e-12, string.format('pitch %g', p))
    end
  end
end)
