--[[
  Depth of field focus -- pure logic, no ac/CSP dependency.

  The UI offers two ways to set the focus distance, under Camera:

    Autofocus: True   the distance to the tracked car, recomputed each frame
    Focus point:      a keyframed distance in metres, greyed out while
                      Autofocus is on

  Autofocus is plain euclidean distance from the camera to the car. With two
  cars mixed, it focuses on whichever is NEARER -- not on the mix point, which
  would sit in empty space between them and leave both soft.
]]

local focus = {}

---Below this, the legacy switches DOF off entirely rather than focusing.
focus.MIN_DISTANCE = 0.1

---Straight-line distance between two points, in CamTool space (Z-up).
---@return number
function focus.distance(camX, camY, camZ, targetX, targetY, targetZ)
  local dx = targetX - camX
  local dy = targetY - camY
  local dz = targetZ - camZ
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Autofocus distance, from Camera.calculate_focus_point.
---
---`carB` is only consulted when `mix` is set: with a single tracked car the
---legacy skips the comparison entirely rather than comparing a car against
---itself.
---@param cam table @{x, y, z} camera position, CamTool space
---@param carA table @{x, y, z}
---@param carB table|nil
---@param mix number|nil @tracking_mix; 0 or nil means car A only
---@return number
function focus.auto(cam, carA, carB, mix)
  local a = focus.distance(cam.x, cam.y, cam.z, carA.x, carA.y, carA.z)

  if mix == nil or mix == 0 or carB == nil then
    return a
  end

  local b = focus.distance(cam.x, cam.y, cam.z, carB.x, carB.y, carB.z)
  -- The nearer car, so one of them is sharp. Focusing on the mix point would
  -- put the plane between them and leave both soft.
  return math.min(a, b)
end

---Should autofocus recompute this frame?
---
---The legacy holds the previous focus when the camera is aimed more than a
---quarter turn away from the tracked car: refocusing on something off screen
---would pump the depth of field for no reason.
---@param cameraHeading number @radians
---@param trackedHeading number @radians
---@return boolean
function focus.shouldRefocus(cameraHeading, trackedHeading)
  return math.abs(cameraHeading - trackedHeading) <= math.pi / 2
end

---DOF strength for a focus distance, from CamToolTool.set_focus_point:
---below 0.1 the effect is switched off rather than focused very near.
---@param distance number
---@return number @0 or 1
function focus.dofFactor(distance)
  if (distance or 0) < focus.MIN_DISTANCE then return 0 end
  return 1
end

return focus
