--[[
  Golden-master tests for core/interpolation.lua.

  Expected values come from running the real legacy module, via
  tools/gen_golden.py. Regenerate the fixture whenever the Python changes; never
  edit it to make a test pass.
]]

local runner = require('tests.runner')
local interpolation = require('core.interpolation')
local golden = require('tests.fixtures.interpolation_golden')

local test, eq, near = runner.test, runner.eq, runner.near

-- Column order in a fixture row.
local TIME = 1
local COL_SIN = 3

-- Values here span 1e-6 to a few hundred metres, so scale the tolerance with
-- the magnitude rather than trusting one absolute epsilon everywhere.
local function tolerance(expected)
  return math.max(1e-12, math.abs(expected) * 1e-12)
end

---Run one column of the fixture against one ported function.
local function checkColumn(column, fn, label)
  local checked = 0
  for c = 1, #golden do
    local case = golden[c]
    for r = 1, #case.rows do
      local row = case.rows[r]
      local time = row[TIME]
      local expected = row[column]
      local actual = fn(time, case.x, case.y)
      local where = string.format('%s[%s] at time %.17g', label, case.name, time)

      if expected == false then
        eq(actual, nil, where .. ' should return nil')
      else
        near(actual, expected, tolerance(expected), where)
      end
      checked = checked + 1
    end
  end
  return checked
end

test('fixture is present and non-trivial', function()
  eq(type(golden), 'table')
  local rows = 0
  for c = 1, #golden do rows = rows + #golden[c].rows end
  if rows < 100 then
    error('expected at least 100 sampled points, got ' .. rows, 2)
  end
end)

test('interpolate_sin matches the legacy on every sampled point', function()
  local checked = checkColumn(COL_SIN, interpolation.interpolate_sin, 'interpolate_sin')
  if checked == 0 then error('no points were checked', 2) end
end)

test('interpolate_sin does not leak state between calls', function()
  -- The legacy singleton stores its working variables on self, so a second call
  -- can see leftovers from the first. CLAUDE.md wants this gone: same inputs
  -- must give the same answer no matter what ran in between.
  local x, y = { 0.0, 0.25, 0.5, 1.0 }, { 0.0, 10.0, -5.0, 3.0 }
  local first = interpolation.interpolate_sin(0.4, x, y)

  interpolation.interpolate_sin(0.9, { 0.0, 1.0 }, { 100.0, 200.0 })
  interpolation.interpolate_sin(0.1, { 0.5 }, { 7.0 })
  interpolation.interpolate_sin(0.0, {}, {})

  near(interpolation.interpolate_sin(0.4, x, y), first, 0,
    'same inputs must give a bit-identical result after other calls')
end)

test('interpolate_sin does not modify its inputs', function()
  local x, y = { 0.0, 0.5, 1.0 }, { 1.0, 2.0, 3.0 }
  interpolation.interpolate_sin(0.3, x, y)
  eq(#x, 3)
  eq(#y, 3)
  eq(x[2], 0.5)
  eq(y[2], 2.0)
end)
