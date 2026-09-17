--[[
  Recorded camera splines -- pure logic, no ac/CSP dependency.

  A spline is a path the user flew and recorded, stored per camera as parallel
  arrays (the_x, loc_x, loc_y, loc_z, rot_x, rot_y, rot_z). Instead of
  interpolating between a handful of keyframes, the camera follows that path.

  Two things worth knowing, both contradicting the summary in CLAUDE.md:

  1. Recorded camera splines are sampled with the CUBIC BEZIER interpolator, not
     the linear one. interpolate_spline is for the track and pit splines at the
     top of the file, which are a different thing.

  2. The camera does not read the spline at the car's track position. It reads
     it at a position of its own, scaled by spline_speed and shifted by
     spline_offset_spline, anchored on the spline's first sample. That is what
     lets a recorded path play back faster, slower or offset from the car.
]]

local interpolation = require('core/interpolation')

local spline = {}

---Does this camera have a recorded path?
---@param camera table
---@return boolean
function spline.exists(camera)
  if type(camera) ~= 'table' or type(camera.spline) ~= 'table' then return false end
  local positions = camera.spline.the_x
  return type(positions) == 'table' and #positions > 0
end

---Where along the recorded path to read, given the car's track position.
---
---    query = (theX - first) * speed - offset + first
---
---Anchored on the spline's first sample so that speed scales the distance
---travelled along the path rather than moving its start.
---
---The wrap: a spline recorded across the start line stores positions past 1.
---In `pos` mode a query that has fallen below 0.5 is really on the far side of
---the line, so a lap is added back.
---@param theX number @car track position, 0..1
---@param positions number[] @the spline's the_x array
---@param speed number|nil @spline_speed, default 1
---@param offset number|nil @spline_offset_spline, default 0
---@param mode string|nil @'pos' or 'time'
---@return number
function spline.queryPosition(theX, positions, speed, offset, mode)
  if type(positions) ~= 'table' or #positions == 0 then return theX end

  local first = positions[1]
  local query = (theX - first) * (speed or 1) - (offset or 0) + first

  if positions[#positions] > 1 and mode ~= 'time' and query < 0.5 then
    query = query + 1
  end

  return query
end

---Read one channel of the spline at a query position.
---@return number|nil
function spline.channel(camera, name, query)
  if not spline.exists(camera) then return nil end
  local values = camera.spline[name]
  if type(values) ~= 'table' or #values == 0 then return nil end
  return interpolation.interpolate(query, camera.spline.the_x, values)
end

---Sideways shift off the recorded path, from spline_offset_loc_x.
---
---The legacy builds it as (sin h, cos h) against a look direction of
---(-cos h, sin h), and those are perpendicular, so this offset moves the camera
---sideways rather than along its view. In CamTool space (Z-up), so x and y are
---the horizontal pair.
---@param heading number @the spline's own heading at this point
---@param amount number
---@return number x, number y
function spline.lateralOffset(heading, amount)
  amount = amount or 0
  return math.sin(heading) * amount, math.cos(heading) * amount
end

---Sample the recorded path: position, heading, and the offsets applied.
---Returns nil when the camera has no spline.
---@param camera table
---@param query number @from queryPosition
---@param offsetLateral number|nil @spline_offset_loc_x
---@param offsetVertical number|nil @spline_offset_loc_z
---@return table|nil @{ x, y, z, heading, pitch, roll } in CamTool space
function spline.sample(camera, query, offsetLateral, offsetVertical)
  if not spline.exists(camera) then return nil end

  local heading = spline.channel(camera, 'rot_z', query)
  local x = spline.channel(camera, 'loc_x', query)
  local y = spline.channel(camera, 'loc_y', query)
  local z = spline.channel(camera, 'loc_z', query)

  if x == nil or y == nil or z == nil then return nil end

  if heading ~= nil then
    local dx, dy = spline.lateralOffset(heading, offsetLateral)
    x = x + dx
    y = y + dy
  end

  z = z + (offsetVertical or 0)

  return {
    x = x, y = y, z = z,
    heading = heading,
    pitch = spline.channel(camera, 'rot_x', query),
    roll = spline.channel(camera, 'rot_y', query),
  }
end

---Mix a keyframed value with the spline's, by spline_affect_*.
---0 keeps the keyframed value, 1 takes the spline's.
---@return number
function spline.mix(fromKeyframes, fromSpline, affect)
  if fromSpline == nil then return fromKeyframes end
  if fromKeyframes == nil then return fromSpline end
  affect = affect or 0
  return fromKeyframes * (1 - affect) + fromSpline * affect
end

return spline
