--[[
  Tests for core/cars.lua: walking from one car to the next along the track.
]]

local runner = require('tests/runner')
local cars = require('core/cars')

local test, eq = runner.test, runner.eq

-- Indices deliberately out of track order: the arrows follow the track.
local PACK = {
  { index = 0, pos = 0.50 },
  { index = 1, pos = 0.10 },
  { index = 2, pos = 0.95 },
  { index = 3, pos = 0.55 },
}

test('next is the nearest car ahead on the track, not the next index', function()
  eq(cars.step(PACK, 0, 0.50, 1), 3)
  eq(cars.step(PACK, 3, 0.55, 1), 2)
end)

test('previous is the nearest car behind', function()
  eq(cars.step(PACK, 0, 0.50, -1), 1)
  eq(cars.step(PACK, 3, 0.55, -1), 0)
end)

test('stepping wraps across the start line both ways', function()
  eq(cars.step(PACK, 2, 0.95, 1), 1, 'ahead of the last car is the first')
  eq(cars.step(PACK, 1, 0.10, -1), 2, 'behind the first car is the last')
end)

test('a lone car steps to itself', function()
  eq(cars.step({ { index = 4, pos = 0.3 } }, 4, 0.3, 1), 4)
  eq(cars.step({}, 4, 0.3, -1), 4)
end)

test('a car exactly level is never the next one', function()
  -- The legacy measures a whole lap to a car alongside.
  local level = { { index = 0, pos = 0.5 }, { index = 1, pos = 0.5 },
    { index = 2, pos = 0.7 } }
  eq(cars.step(level, 0, 0.5, 1), 2)
end)

test('the extra car starts as none and steps off the followed car', function()
  eq(cars.stepExtra(PACK, 0, nil, 1), 3, 'ahead of the followed car')
  eq(cars.stepExtra(PACK, 0, nil, -1), 1, 'behind it')
end)

test('the extra car walks on from where it is', function()
  eq(cars.stepExtra(PACK, 0, 3, 1), 2)
  eq(cars.stepExtra(PACK, 0, 1, -1), 2)
end)

test('stepping back onto the followed car means none again', function()
  eq(cars.stepExtra(PACK, 0, 3, -1), nil)
  eq(cars.stepExtra(PACK, 0, 1, 1), nil)
end)

test('no extra car when there is nobody else', function()
  local alone = { { index = 0, pos = 0.5 } }
  eq(cars.stepExtra(alone, 0, nil, 1), nil)
  eq(cars.stepExtra(alone, 0, nil, -1), nil)
end)

test('an extra car that left is stepped from the followed one', function()
  eq(cars.stepExtra(PACK, 0, 7, 1), 3)
end)

test('nothing followed, nothing to step', function()
  eq(cars.stepExtra(PACK, nil, nil, 1), nil)
end)
