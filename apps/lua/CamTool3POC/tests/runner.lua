--[[
  Minimal test runner. Pure Lua 5.1 (what LuaJIT, and therefore CSP, speaks),
  with no dependencies.

  Why not busted: it needs luarocks, which on Windows drags in a C toolchain.
  The project already runs on embedded interpreters where installing anything is
  impossible, so the test tooling stays in the same spirit -- one binary,
  luajit.exe, and files checked into the repo.
]]

local runner = {}

local cases = {}

---Register a test case.
---@param name string
---@param fn function
function runner.test(name, fn)
  cases[#cases + 1] = { name = name, fn = fn }
end

---Assert exact equality.
function runner.eq(actual, expected, note)
  if actual ~= expected then
    error(string.format('expected %s, got %s%s',
      tostring(expected), tostring(actual),
      note and (' -- ' .. note) or ''), 2)
  end
end

---Assert equality within epsilon. Use this for anything that went through
---floating point, which is most of what this project computes.
function runner.near(actual, expected, epsilon, note)
  epsilon = epsilon or 1e-9
  if type(actual) ~= 'number' then
    error(string.format('expected a number, got %s (%s)%s',
      type(actual), tostring(actual),
      note and (' -- ' .. note) or ''), 2)
  end
  local diff = math.abs(actual - expected)
  if diff > epsilon then
    error(string.format('expected %.17g +/- %g, got %.17g (off by %g)%s',
      expected, epsilon, actual, diff,
      note and (' -- ' .. note) or ''), 2)
  end
end

---Run every registered case. Returns true when all of them passed.
---@return boolean
function runner.run()
  local passed, failed = 0, 0
  for i = 1, #cases do
    local case = cases[i]
    local ok, err = pcall(case.fn)
    if ok then
      passed = passed + 1
      print('  ok   ' .. case.name)
    else
      failed = failed + 1
      print('  FAIL ' .. case.name)
      print('       ' .. tostring(err))
    end
  end
  print('')
  print(string.format('%d passed, %d failed', passed, failed))
  return failed == 0
end

return runner
