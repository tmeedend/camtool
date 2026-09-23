--[[
  Stepping from one car to the next along the track -- pure logic, no ac/CSP
  dependency.

  Ported from Camera.get_next_car and get_prev_car, which the arrows of Car 1
  and Extra car call in CamTool 2. "Next" is the nearest car AHEAD on the
  track, "previous" the nearest one behind, both measured along the lap with
  the wrap across the start line. Not the next car index: indices say nothing
  about where the cars are, and the arrows are for walking along a pack.

  Cars are given as a list of { index = <0-based car index>, pos = <0..1> },
  only the connected ones; the caller decides what connected means.
]]

local cars = {}

---How far ahead of `from` a car at `to` is, going forward round the lap.
---
---The legacy's own measure, kept as it is: for a car exactly level it gives a
---whole lap rather than zero, so a car alongside is never "the next one".
---@return number @in (0, 1]
local function ahead(from, to)
  if from < to then return to - from end
  return 1 - math.abs(from - to)
end

---The nearest car ahead of (direction 1) or behind (direction -1) a car.
---@param list table[] @{ index = , pos = }, the connected cars
---@param fromIndex number @the car to step from
---@param fromPos number @its track position, 0..1
---@param direction number @1 for ahead, -1 for behind
---@return number @a car index; fromIndex itself when there is no other car
function cars.step(list, fromIndex, fromPos, direction)
  local best, bestDistance = fromIndex, 1
  if type(list) ~= 'table' or type(fromPos) ~= 'number' then return best end

  for i = 1, #list do
    local car = list[i]
    if car.index ~= fromIndex and type(car.pos) == 'number' then
      local distance
      if direction < 0 then
        distance = ahead(car.pos, fromPos)
      else
        distance = ahead(fromPos, car.pos)
      end
      if distance < bestDistance then
        best, bestDistance = car.index, distance
      end
    end
  end

  return best
end

---Where a car is in the list, or nil when it is not connected.
---@return number|nil
function cars.positionOf(list, index)
  if type(list) ~= 'table' or index == nil then return nil end
  for i = 1, #list do
    if list[i].index == index then return list[i].pos end
  end
  return nil
end

---Step the extra car, the one MIX blends the aim towards.
---
---It starts as none, and the first step goes to the car ahead of or behind
---the followed one. Stepping back onto the followed car makes it none again:
---blending a car with itself does nothing, so that is the one way back to "no
---extra car" and it is where the walk naturally lands.
---@param list table[] @the connected cars
---@param followed number|nil @the car the replay is following
---@param extra number|nil @the current extra car, nil for none
---@param direction number @1 or -1
---@return number|nil @the new extra car, nil for none
function cars.stepExtra(list, followed, extra, direction)
  if followed == nil then return nil end

  local from = extra
  if from == nil or cars.positionOf(list, from) == nil then from = followed end

  local fromPos = cars.positionOf(list, from)
  if fromPos == nil then return nil end

  local nextCar = cars.step(list, from, fromPos, direction)
  if nextCar == followed then return nil end
  -- Nowhere to go: a single car, or none other connected.
  if nextCar == from and from == followed then return nil end
  return nextCar
end

return cars
