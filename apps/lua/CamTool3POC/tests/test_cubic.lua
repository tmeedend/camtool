--[[
  Golden-master tests for the cubic solver behind the bezier interpolation.

  Expected values come from running the real SolveCubic, via tools/gen_golden.py.
  Two of the cases record an exception rather than a value: the legacy raises,
  and every caller turns that into None, so nil is the behaviour to match.
]]

local runner = require('tests.runner')
local interpolation = require('core.interpolation')
local golden = require('tests.fixtures.cubic_golden')

local test, eq, near = runner.test, runner.eq, runner.near

local NAME, A, B, C, D, EXPECTED = 1, 2, 3, 4, 5, 6

test('cubic fixture covers every branch of the solver', function()
  eq(type(golden), 'table')
  eq(#golden, 10)
end)

test('solveCubic matches the legacy, including where it raises', function()
  for i = 1, #golden do
    local case = golden[i]
    local expected = case[EXPECTED]
    local actual = interpolation._solveCubic(case[A], case[B], case[C], case[D])
    local where = 'solveCubic[' .. case[NAME] .. ']'

    if expected == false then
      eq(actual, nil, where .. ' should return nil')
    elseif type(expected) == 'string' then
      -- The legacy raised expected (NameError, TypeError...). Callers swallow
      -- it into None, so the port has to land on nil by whatever route.
      eq(actual, nil, where .. ' legacy raised ' .. expected .. ', so expect nil')
    else
      near(actual, expected, math.max(1e-12, math.abs(expected) * 1e-12), where)
    end
  end
end)

test('the disc == 0 NameError is pinned, not accidentally fixed', function()
  -- Guards the specific input that trips `return result` in the Python.
  -- If someone fixes the legacy, this test fails and forces the decision to be
  -- made on purpose rather than drifting in.
  eq(interpolation._solveCubic(1.0, 0.0, -0.1875, -0.03125), nil,
    'exact double root with the single root at 0.5')
end)

test('negative discriminant falls through to nil via nan', function()
  -- Python gets a complex root and raises TypeError; Lua gets nan and every
  -- comparison is false. Different route, same answer.
  eq(interpolation._solveCubic(0.0, 1.0, 0.0, 1.0), nil)
end)
