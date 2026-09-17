--[[
  Angle conventions -- pure logic, no ac/CSP dependency.

  These were the last thing still being guessed at, and they did not need to be:
  the legacy states them outright in Camera.calculate_cam_rot_to_tracking_car.

      heading = atan2(dx, dy) + pi/2
      pitch   = atan2(dz, sqrt(dx*dx + dy*dy))

  where the deltas are in CamTool space, which is Z-up: dx and dy are the two
  horizontal axes and dz is the vertical one. AC is Y-up, so its z is CamTool's
  y and its y is CamTool's z.
]]

local angles = {}

---Aim angles from a camera position to a target, both in CamTool space (Z-up).
---@return number heading, number pitch @radians
function angles.aimAt(camX, camY, camZ, targetX, targetY, targetZ)
  local dx = targetX - camX
  local dy = targetY - camY
  local dz = targetZ - camZ
  local horizontal = math.sqrt(dx * dx + dy * dy)
  return math.atan2(dx, dy) + math.pi / 2, math.atan2(dz, horizontal)
end

---Turn a CamTool heading and pitch into an AC look vector (Y-up, unit length).
---
---Inverse of the formula above. With heading h, atan2(dx, dy) = h - pi/2, so
---the horizontal direction is (-cos h, sin h) in CamTool x and y, which is AC
---x and z. Pitch tilts it: horizontal scales by cos(p), vertical is sin(p).
---@return number x, number y, number z
function angles.lookVector(heading, pitch)
  local cp = math.cos(pitch)
  return -math.cos(heading) * cp, math.sin(pitch), math.sin(heading) * cp
end

---Heading and pitch of an AC look vector (Y-up), in CamTool convention.
---The inverse of lookVector, and the same formula as aimAt from the origin.
---@return number heading, number pitch
function angles.fromLook(x, y, z)
  -- AC z is CamTool y, AC y is CamTool z.
  ---Combine the three sources of aim, exactly as InterpolateFrame assembles them:
---
---    ((transform * (1 - track) + tracking * track) * (1 - spline)
---      + splineAngle * spline)
---
---Note the nesting. Transform and tracking are blended first, and the spline is
---then mixed over the result, so a spline strength of 1 overrides both.
---
---Any source that is nil falls back to `current`, which is what makes an
---unkeyframed camera hold its aim rather than snap somewhere.
---
---Every candidate is brought to the revolution nearest `current` before the
---arithmetic, as the legacy does, so a blend near the +/-pi seam takes the short
---way round instead of unwinding a full turn.
---@param current number @the camera's present angle
---@param transform number|nil @from the keyframes
---@param tracking number|nil @aim at the tracked car
---@param trackStrength number|nil
---@param splineAngle number|nil @from the recorded path
---@param splineStrength number|nil
---@return number
function angles.combine(current, transform, tracking, trackStrength, splineAngle, splineStrength)
  local t = transform ~= nil and angles.normalize(current, transform) or current
  local k = tracking ~= nil and angles.normalize(current, tracking) or current
  local s = splineAngle ~= nil and angles.normalize(current, splineAngle) or current

  local kw = trackStrength or 0
  local sw = splineStrength or 0

  return (t * (1 - kw) + k * kw) * (1 - sw) + s * sw
end

return angles.aimAt(0, 0, 0, x, z, y)
end

---Bring `value` to the revolution nearest `current`, so a blend between two
---angles takes the short way round instead of unwinding through a full turn.
---Ported from general.normalize_angle.
---@return number
function angles.normalize(current, value)
  local result = value
  if value < current then
    if math.abs(value - current) > math.abs(value + math.pi * 2 - current) then
      result = result + math.pi * 2
    end
  else
    if math.abs(value - current) > math.abs(value - math.pi * 2 - current) then
      result = result - math.pi * 2
    end
  end
  return result
end

---Blend two angles by weight, taking the short way round.
---@param from number @the angle `weight` = 0 gives
---@param to number @the angle `weight` = 1 gives
---@param weight number
---@return number
function angles.blend(from, to, weight)
  local target = angles.normalize(from, to)
  return from * (1 - weight) + target * weight
end

---Combine the three sources of aim, exactly as InterpolateFrame assembles them:
---
---    ((transform * (1 - track) + tracking * track) * (1 - spline)
---      + splineAngle * spline)
---
---Note the nesting. Transform and tracking are blended first, and the spline is
---then mixed over the result, so a spline strength of 1 overrides both.
---
---Any source that is nil falls back to `current`, which is what makes an
---unkeyframed camera hold its aim rather than snap somewhere.
---
---Every candidate is brought to the revolution nearest `current` before the
---arithmetic, as the legacy does, so a blend near the +/-pi seam takes the short
---way round instead of unwinding a full turn.
---@param current number @the camera's present angle
---@param transform number|nil @from the keyframes
---@param tracking number|nil @aim at the tracked car
---@param trackStrength number|nil
---@param splineAngle number|nil @from the recorded path
---@param splineStrength number|nil
---@return number
function angles.combine(current, transform, tracking, trackStrength, splineAngle, splineStrength)
  local t = transform ~= nil and angles.normalize(current, transform) or current
  local k = tracking ~= nil and angles.normalize(current, tracking) or current
  local s = splineAngle ~= nil and angles.normalize(current, splineAngle) or current

  local kw = trackStrength or 0
  local sw = splineStrength or 0

  return (t * (1 - kw) + k * kw) * (1 - sw) + s * sw
end

return angles
