--[[
  Characterisation tests for core/fov.lua.

  These pin down what the Python original does today, not what it arguably
  should do. Existing user camera files were written by that code, so any
  change here silently changes their videos.
]]

local runner = require('tests.runner')
local fov = require('core.fov')

local test, eq, near = runner.test, runner.eq, runner.near

test('encode matches 1/(fov+15)', function()
  near(fov.encode(60), 1 / 75)
  near(fov.encode(40), 1 / 55)
  near(fov.encode(10), 1 / 25)
end)

test('decode matches (1-15v)/v', function()
  near(fov.decode(1 / 75), 60)
  near(fov.decode(1 / 55), 40)
  near(fov.decode(1 / 25), 10)
end)

test('decode undoes encode across the usable range', function()
  local degrees = { 1, 5, 10, 20, 35, 40, 60, 75, 90, 120 }
  for i = 1, #degrees do
    local d = degrees[i]
    near(fov.decode(fov.encode(d)), d, 1e-9, 'round trip at ' .. d .. ' deg')
  end
end)

test('zero returns the legacy sentinel in BOTH directions', function()
  -- Straight out of the Python: `if val != 0: ... ; return 0.00001`.
  eq(fov.encode(0), 0.00001)
  eq(fov.decode(0), 0.00001)
end)

test('zero does not round trip -- legacy asymmetry, kept on purpose', function()
  -- encode(0) is a sentinel, not a real stored value, so feeding it back gives
  -- nonsense rather than 0. Documented so nobody "fixes" it by accident.
  near(fov.decode(fov.encode(0)), 99985, 1e-6)
end)

test('fov of -15 diverges from Python: inf here, ZeroDivisionError there', function()
  -- Python raises, the exception is swallowed by debug(e), and the caller keeps
  -- its previous value. Lua divides by zero happily and returns inf, which then
  -- propagates into the camera. A real portability trap for the port: anything
  -- reading user input or files has to reject this before it reaches here.
  local result = fov.encode(-15)
  eq(result, math.huge)
end)

test('negative stored values decode without error', function()
  -- Not meaningful as a field of view, but the legacy does not guard it, so
  -- neither do we. Recorded so a future guard is a deliberate decision.
  near(fov.decode(-1 / 55), -70)
end)
