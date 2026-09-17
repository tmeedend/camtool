--[[
  Tests for core/spline.lua, run against the real spline set in
  ks_silverstone_gp-seb.json (trimmed to three cameras).

  That file is worth using precisely because it is messy: pos[0] holds 22
  ascending samples followed by one stray point at 0.0015, left over from
  recording, and it shares camera_in = 0 with pos[1] so it is never selected.
  Real user data has scars and the port has to survive them.
]]

local runner = require('tests/runner')
local spline = require('core/spline')
local data = require('core/data')
local rawFile = require('tests/fixtures/camera_file_splines')

local test, eq, near = runner.test, runner.eq, runner.near

test('the fixture really carries recorded splines', function()
  eq(type(rawFile.pos), 'table')
  local withSpline = 0
  for i = 1, #rawFile.pos do
    if spline.exists(rawFile.pos[i]) then withSpline = withSpline + 1 end
  end
  if withSpline < 2 then
    error('expected at least 2 cameras with splines, got ' .. withSpline, 2)
  end
end)

test('exists says no for a camera without one', function()
  eq(spline.exists({}), false)
  eq(spline.exists(nil), false)
  eq(spline.exists({ spline = {} }), false)
  eq(spline.exists({ spline = { the_x = {} } }), false)
end)

test('at speed 1 with no offset the query is the track position', function()
  local positions = { 0.2, 0.3, 0.4 }
  near(spline.queryPosition(0.25, positions, 1, 0, 'pos'), 0.25, 1e-12)
  near(spline.queryPosition(0.35, positions, 1, 0, 'pos'), 0.35, 1e-12)
end)

test('speed scales distance along the path, anchored on its start', function()
  local positions = { 0.2, 0.3, 0.4 }
  -- Twice the speed covers twice the path for the same track travel, and the
  -- anchor means the start does not move.
  near(spline.queryPosition(0.2, positions, 2, 0, 'pos'), 0.2, 1e-12, 'start is fixed')
  near(spline.queryPosition(0.3, positions, 2, 0, 'pos'), 0.4, 1e-12, 'twice as far along')
  near(spline.queryPosition(0.3, positions, 0.5, 0, 'pos'), 0.25, 1e-12, 'half as far')
end)

test('offset shifts the query', function()
  local positions = { 0.2, 0.3, 0.4 }
  near(spline.queryPosition(0.3, positions, 1, 0.05, 'pos'), 0.25, 1e-12)
  near(spline.queryPosition(0.3, positions, 1, -0.05, 'pos'), 0.35, 1e-12)
end)

test('a spline crossing the line wraps in pos mode only', function()
  -- Recorded past the end of the lap, so its last sample is above 1.
  local positions = { 0.9, 1.0, 1.05 }
  -- A car just past the line reads at 0.02, which is really 1.02 on this path.
  near(spline.queryPosition(0.02, positions, 1, 0, 'pos'), 1.02, 1e-12)
  -- Above 0.5 there is nothing to fix.
  near(spline.queryPosition(0.95, positions, 1, 0, 'pos'), 0.95, 1e-12)
  -- Time mode does not wrap.
  near(spline.queryPosition(0.02, positions, 1, 0, 'time'), 0.02, 1e-12)
end)

test('a spline that stays under 1 never wraps', function()
  local positions = { 0.2, 0.3, 0.4 }
  near(spline.queryPosition(0.02, positions, 1, 0, 'pos'), 0.02, 1e-12)
end)

test('sampling a real spline gives a point on the track', function()
  local doc = data.load(rawFile)
  -- pos[2] is a clean ascending recording, unlike pos[1].
  local camera = doc.pos[2]
  if not spline.exists(camera) then error('fixture camera has no spline', 2) end

  local positions = camera.spline.the_x
  local mid = (positions[1] + positions[#positions]) / 2
  local point = spline.sample(camera, mid, 0, 0)

  eq(type(point), 'table')
  eq(type(point.x), 'number')
  eq(type(point.y), 'number')
  eq(type(point.z), 'number')

  -- Silverstone sits within a couple of kilometres of its origin, and the
  -- vertical axis is loc_z, so a sane sample is not off in the weeds.
  if math.abs(point.x) > 5000 or math.abs(point.y) > 5000 then
    error(string.format('sample is off the map: %g %g', point.x, point.y), 2)
  end
  if math.abs(point.z) > 500 then
    error('implausible elevation: ' .. point.z, 2)
  end
end)

test('sampling at the ends returns the end points', function()
  local doc = data.load(rawFile)
  local camera = doc.pos[2]
  local s = camera.spline
  local last = #s.the_x

  local atStart = spline.sample(camera, s.the_x[1], 0, 0)
  near(atStart.x, s.loc_x[1], 1e-6, 'first sample')
  near(atStart.y, s.loc_y[1], 1e-6)

  local atEnd = spline.sample(camera, s.the_x[last], 0, 0)
  near(atEnd.x, s.loc_x[last], 1e-6, 'last sample')
  near(atEnd.y, s.loc_y[last], 1e-6)
end)

test('the lateral offset moves sideways, not along the view', function()
  -- look direction is (-cos h, sin h); the offset is (sin h, cos h).
  for _, h in ipairs({ 0, 0.7, 1.9, -2.4 }) do
    local ox, oy = spline.lateralOffset(h, 1)
    local lx, ly = -math.cos(h), math.sin(h)
    near(ox * lx + oy * ly, 0, 1e-12, 'must be perpendicular at heading ' .. h)
    near(math.sqrt(ox * ox + oy * oy), 1, 1e-12, 'unit length for amount 1')
  end
end)

test('the lateral offset scales and reverses with its amount', function()
  local ax, ay = spline.lateralOffset(0.5, 3)
  local bx, by = spline.lateralOffset(0.5, -3)
  near(ax, -bx, 1e-12)
  near(ay, -by, 1e-12)

  local zx, zy = spline.lateralOffset(0.5, 0)
  near(zx, 0, 1e-12)
  near(zy, 0, 1e-12)
end)

test('the vertical offset is added straight to z', function()
  local doc = data.load(rawFile)
  local camera = doc.pos[2]
  local mid = camera.spline.the_x[2]

  local plain = spline.sample(camera, mid, 0, 0)
  local lifted = spline.sample(camera, mid, 0, 12.5)
  near(lifted.z - plain.z, 12.5, 1e-9)
  near(lifted.x, plain.x, 1e-12, 'only z moves')
end)

test('mix blends the keyframed value with the spline', function()
  near(spline.mix(10, 20, 0), 10, 1e-12, 'affect 0 keeps the keyframes')
  near(spline.mix(10, 20, 1), 20, 1e-12, 'affect 1 takes the spline')
  near(spline.mix(10, 20, 0.25), 12.5, 1e-12)
end)

test('mix copes with either side missing', function()
  near(spline.mix(nil, 20, 0.5), 20, 1e-12, 'no keyframed value')
  near(spline.mix(10, nil, 0.5), 10, 1e-12, 'no spline value')
end)

test('a spline with a stray out-of-order sample does not blow up', function()
  -- pos[1] in the fixture: 22 ascending samples then one at 0.0015. The legacy
  -- never sorts, so the port must simply not crash on it.
  local doc = data.load(rawFile)
  local camera = doc.pos[1]
  if not spline.exists(camera) then error('expected pos[1] to have a spline', 2) end

  for _, query in ipairs({ 0.0, 0.2, 0.3346, 0.35, 0.3691, 0.9, 1.2 }) do
    local ok, point = pcall(spline.sample, camera, query, 0, 0)
    eq(ok, true, 'sampling at ' .. query .. ' must not raise')
    if point ~= nil then
      eq(type(point.x), 'number')
    end
  end
end)
