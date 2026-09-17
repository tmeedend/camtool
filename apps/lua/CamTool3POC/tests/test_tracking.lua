--[[
  Tests for core/tracking.lua.

  The aim point is a blend of the car's current position with a lagging or
  leading one, and getting the sign of tracking_offset backwards would make the
  camera trail the car when it should anticipate it -- visible, but easy to
  misread as "tracking is just late".
]]

local runner = require('tests/runner')
local tracking = require('core/tracking')

local test, eq, near = runner.test, runner.eq, runner.near

---Push a straight run of positions along +x, one metre apart.
local function straightRun(buffer, steps)
  for i = 1, steps do
    tracking.push(buffer, i, 0, 0)
  end
end

test('the buffer defaults to the legacy smoothness', function()
  eq(tracking.DEFAULT_SMOOTHNESS, 50, 'Camera.py uses 50 frames')
  eq(tracking.new().size, 50)
end)

test('a fresh buffer primes itself with the first sample', function()
  -- The divergence from the legacy: without this, the average drags the aim
  -- toward the world origin for the first 50 frames.
  local buffer = tracking.new(10)
  tracking.push(buffer, 100, 200, 300)

  local lx, ly, lz = tracking.latest(buffer)
  eq(lx, 100); eq(ly, 200); eq(lz, 300)

  local ax, ay, az = tracking.average(buffer)
  near(ax, 100, 1e-12, 'average must equal the only sample seen')
  near(ay, 200, 1e-12)
  near(az, 300, 1e-12)

  local px, py, pz = tracking.predicted(buffer)
  near(px, 100, 1e-12, 'a car that has not moved is predicted where it is')
  near(py, 200, 1e-12)
  near(pz, 300, 1e-12)
end)

test('legacy zero fill reproduces the startup transient', function()
  -- Kept available so the transient can be compared in game: it is a candidate
  -- explanation for issue #16.
  local buffer = tracking.new(10, true)
  tracking.push(buffer, 100, 0, 0)

  local ax = tracking.average(buffer)
  near(ax, 10, 1e-12, 'nine zeros and one real sample')

  local px = tracking.predicted(buffer)
  near(px, 190, 1e-12, 'prediction overshoots hard away from the origin')
end)

test('the average lags a moving car', function()
  local buffer = tracking.new(10)
  straightRun(buffer, 10)   -- positions 1..10, latest is 10

  local lx = tracking.latest(buffer)
  eq(lx, 10)

  local ax = tracking.average(buffer)
  near(ax, 5.5, 1e-12, 'mean of 1..10')
end)

test('the prediction leads by as much as the average lags', function()
  local buffer = tracking.new(10)
  straightRun(buffer, 10)

  local px = tracking.predicted(buffer)
  near(px, 10 + (10 - 5.5), 1e-12, 'mirror the lag into a lead')
end)

test('the ring keeps only the most recent samples', function()
  local buffer = tracking.new(5)
  straightRun(buffer, 100)  -- positions 1..100

  eq(tracking.latest(buffer), 100)
  near(tracking.average(buffer), (96 + 97 + 98 + 99 + 100) / 5, 1e-12)
end)

test('a zero offset aims exactly at the car', function()
  local buffer = tracking.new(10)
  straightRun(buffer, 10)

  local tx, ty, tz = tracking.target(buffer, 0, 1, 0)
  near(tx, 10, 1e-12, 'no lead, no lag')
  near(ty, 0, 1e-12)
  near(tz, 0, 1e-12)
end)

test('a negative offset leads the car, a positive one trails it', function()
  local buffer = tracking.new(10)
  straightRun(buffer, 10)   -- latest 10, average 5.5, predicted 14.5

  local lead = tracking.target(buffer, -0.5, 1, 0)
  near(lead, 14.5 * 0.5 + 10 * 0.5, 1e-12)
  if lead <= 10 then error('a negative offset must aim ahead of the car', 2) end

  local lag = tracking.target(buffer, 0.5, 1, 0)
  near(lag, 5.5 * 0.5 + 10 * 0.5, 1e-12)
  if lag >= 10 then error('a positive offset must aim behind the car', 2) end
end)

test('slowing the replay stretches the lead', function()
  -- The legacy divides the weight by the replay speed, so a lead measured in
  -- frames stays constant in wall-clock terms when the replay is slowed.
  local buffer = tracking.new(10)
  straightRun(buffer, 10)

  local atFull = tracking.target(buffer, -0.25, 1, 0)
  local atHalf = tracking.target(buffer, -0.25, 0.5, 0)

  if atHalf <= atFull then
    error('half speed must lead further ahead, got ' .. atHalf, 2)
  end
  near(atHalf, 14.5 * 0.5 + 10 * 0.5, 1e-12, 'weight 0.25 / 0.5 = 0.5')
end)

test('a replay speed of zero is treated as one', function()
  local buffer = tracking.new(10)
  straightRun(buffer, 10)
  near(tracking.target(buffer, -0.5, 0, 0), tracking.target(buffer, -0.5, 1, 0), 1e-12)
  near(tracking.target(buffer, -0.5, nil, 0), tracking.target(buffer, -0.5, 1, 0), 1e-12)
end)

test('the weight is not clamped', function()
  -- tracking_offset beyond 1 overshoots on purpose, and the legacy does not
  -- clamp, so neither do we.
  local buffer = tracking.new(10)
  straightRun(buffer, 10)

  local far = tracking.target(buffer, -2, 1, 0)
  near(far, 14.5 * 2 + 10 * (1 - 2), 1e-12)
  if far <= 14.5 then error('an offset past 1 must overshoot the prediction', 2) end
end)
