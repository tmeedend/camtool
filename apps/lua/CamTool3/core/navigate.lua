--[[
  Stepping from one camera or keyframe to the next -- pure logic, no ac/CSP
  dependency.

  What the arrow keys do, and the whole of what they decide. Small enough to
  read in one go, which is the point: the interesting part is not the
  arithmetic but the two rules it obeys.

  IT STOPS AT THE ENDS. Past the last camera there is nothing, not the first
  one. Wrapping is tempting -- it is one more line and it means an arrow never
  does nothing -- and it is wrong here: a held arrow would carry the shot
  silently back round the lap, and the one thing a camera set is arranged in
  is order.

  NOTHING IS NOT AN ERROR. A camera with no keyframes answers nil to both
  directions, and the caller says so in the status line rather than beeping
  or moving something else instead.
]]

local navigate = {}

---How many keyframes a camera has, counting nothing as none.
local function keyframeCount(camera)
  if type(camera) ~= 'table' then return 0 end
  local keyframes = camera.keyframes
  if type(keyframes) ~= 'table' then return 0 end
  return #keyframes
end

---The keyframe after this one.
---@param camera table|nil
---@param current number|nil @1-based, nil meaning none selected
---@return number|nil @the next one, or nil at the end and when there are none
function navigate.nextKeyframe(camera, current)
  local count = keyframeCount(camera)
  if count == 0 then return nil end
  if type(current) ~= 'number' then return 1 end
  if current >= count then return nil end
  return current + 1
end

---The keyframe before this one.
---@return number|nil
function navigate.previousKeyframe(camera, current)
  local count = keyframeCount(camera)
  if count == 0 then return nil end
  if type(current) ~= 'number' then return count end
  if current <= 1 then return nil end
  return current - 1
end

---The camera after this one.
---
---Cameras are in lap order, so "next" is the next stretch of track and not
---merely the next entry in a list. The two happen to be the same thing
---because core/edit keeps the list sorted, which is worth knowing when
---reading this.
---@param cameras table[]|nil
---@param current number|nil
---@return number|nil
function navigate.nextCamera(cameras, current)
  if type(cameras) ~= 'table' or #cameras == 0 then return nil end
  if type(current) ~= 'number' then return 1 end
  if current >= #cameras then return nil end
  return current + 1
end

---The camera before this one.
---@return number|nil
function navigate.previousCamera(cameras, current)
  if type(cameras) ~= 'table' or #cameras == 0 then return nil end
  if type(current) ~= 'number' then return #cameras end
  if current <= 1 then return nil end
  return current - 1
end

---Where a camera or keyframe sits on the track, for bringing the car there.
---
---A keyframe's own position when it has one, and the camera's starting point
---otherwise. Both are lap positions, which is what the seek wants.
---@param camera table|nil
---@param keyframeIndex number|nil @nil to ask about the camera itself
---@return number|nil
function navigate.positionOf(camera, keyframeIndex)
  if type(camera) ~= 'table' then return nil end

  if keyframeIndex ~= nil then
    local keyframes = camera.keyframes
    local keyframe = type(keyframes) == 'table' and keyframes[keyframeIndex]
      or nil
    local at = type(keyframe) == 'table' and keyframe.keyframe or nil
    if type(at) == 'number' and at == at then return at end
    return nil
  end

  local at = camera.camera_in
  if type(at) == 'number' and at == at then return at end
  return nil
end

return navigate
