--[[
  Turning a camera plus a track position into concrete parameter values.
  Pure logic, no ac/CSP dependency.

  Ported from classes/InterpolateFrame.py and classes/data.py. The mapping of
  parameter to interpolator below was extracted from the legacy source rather
  than guessed, because the summary in CLAUDE.md is not quite right: it groups
  "tracking offsets" under sine easing, but tracking_offset actually goes
  through the bezier while tracking_offset_heading and tracking_offset_pitch go
  through the sine.
]]

local interpolation = require('core/interpolation')

local evaluate = {}

---Sine easing. Comes to a visible stop at every keyframe -- issue #37.
local SIN = 'sin'
---Cubic bezier. Everything you actually see move.
local BEZIER = 'bezier'
---Stored in keyframes, but read from the camera instead of being interpolated.
local CAMERA_LEVEL = 'camera_level'

local INTERPOLATOR = {
  -- Position and rotation.
  loc_x = BEZIER, loc_y = BEZIER, loc_z = BEZIER,
  rot_x = BEZIER, rot_y = BEZIER, rot_z = BEZIER,

  -- Lens.
  camera_fov = SIN,
  camera_focus_point = BEZIER,
  camera_shake_strength = SIN,

  -- Tracking. Note the split: the plain offset eases differently from the
  -- heading and pitch offsets. That asymmetry is in the legacy, not a slip.
  tracking_mix = BEZIER,
  tracking_offset = BEZIER,
  tracking_offset_heading = SIN,
  tracking_offset_pitch = SIN,
  tracking_strength_heading = SIN,
  tracking_strength_pitch = SIN,

  -- Transform strengths.
  transform_loc_strength = BEZIER,
  transform_rot_strength = BEZIER,

  -- Recorded spline.
  spline_speed = BEZIER,
  spline_affect_loc_xy = BEZIER,
  spline_affect_loc_z = BEZIER,
  spline_offset_loc_x = BEZIER,
  spline_offset_loc_z = BEZIER,
  spline_offset_pitch = BEZIER,
  spline_offset_heading = BEZIER,
  spline_offset_spline = BEZIER,

  -- These four have a slot in every keyframe and are saved into files, but the
  -- legacy reads them off the camera and never interpolates them.
  -- camera_offset_shake_strength is concrete evidence for issue #25, "shake not
  -- keyframable": the plain shake IS keyframed, the offset shake is not.
  camera_offset_shake_strength = CAMERA_LEVEL,
  spline_affect_pitch = CAMERA_LEVEL,
  spline_affect_roll = CAMERA_LEVEL,
  spline_affect_heading = CAMERA_LEVEL,
}

evaluate.SIN = SIN
evaluate.BEZIER = BEZIER
evaluate.CAMERA_LEVEL = CAMERA_LEVEL
evaluate.INTERPOLATOR = INTERPOLATOR

---Which interpolator a parameter uses, or nil if it is not a known parameter.
function evaluate.interpolatorFor(param)
  return INTERPOLATOR[param]
end

---Build the (positions, values) pair for one parameter of one camera.
---
---Only keyframes that carry the parameter contribute. That matches the legacy
---exactly, though by a shorter route: there, every keyframe holds all 29 keys
---with nil in the gaps, and __sanitize drops the nil pairs. Saving filters the
---nils out, which is why files look sparse. Same result, no placeholder rows.
---@return number[] positions, number[] values
function evaluate.seriesFor(camera, param)
  local positions, values = {}, {}
  local keyframes = camera and camera.keyframes
  if type(keyframes) ~= 'table' then return positions, values end

  for i = 1, #keyframes do
    local kf = keyframes[i]
    local interp = type(kf) == 'table' and kf.interpolation or nil
    local value = interp and interp[param]
    if type(value) == 'number' and type(kf.keyframe) == 'number' then
      positions[#positions + 1] = kf.keyframe
      values[#values + 1] = value
    end
  end

  return positions, values
end

---Evaluate one parameter at a track position.
---Returns nil when the camera does not keyframe it at all, which is the signal
---to fall back to the camera-level value.
---@param camera table
---@param param string
---@param position number @normalised track position, 0..1
---@return number|nil
function evaluate.parameter(camera, param, position)
  local kind = INTERPOLATOR[param]
  if kind == nil or kind == CAMERA_LEVEL then return nil end

  local positions, values = evaluate.seriesFor(camera, param)
  if #values == 0 then return nil end

  if kind == SIN then
    return interpolation.interpolate_sin(position, positions, values)
  end
  return interpolation.interpolate(position, positions, values)
end

---Evaluate every keyframed parameter of a camera at a track position.
---@return table @param -> value, only for parameters this camera keyframes
function evaluate.all(camera, position)
  local out = {}
  for param, kind in pairs(INTERPOLATOR) do
    if kind ~= CAMERA_LEVEL then
      local value = evaluate.parameter(camera, param, position)
      if value ~= nil then out[param] = value end
    end
  end
  return out
end

---Index of the camera active at a track position.
---
---Ported from Data.refresh plus get_prev_camera and get_last_camera. The legacy
---compares x * trackLength against camera_in * trackLength, so the track length
---cancels and this works directly on the normalised position.
---
---Cameras flagged camera_pit are skipped unless wantPit is true; the legacy
---runs the same walk twice, once per flag.
---@param cameras table[] @one of the two camera lists
---@param position number @normalised track position, 0..1
---@param wantPit boolean|nil
---@return number|nil @1-based index, or nil when the list has no such camera
function evaluate.activeCameraIndex(cameras, position, wantPit)
  if type(cameras) ~= 'table' or #cameras == 0 then return nil end
  wantPit = wantPit and true or false

  local function matches(camera)
    local isPit = camera.camera_pit and true or false
    return isPit == wantPit
  end

  -- Last matching camera in the list, the legacy's fallback.
  local lastMatching = nil
  for i = 1, #cameras do
    if matches(cameras[i]) then lastMatching = i end
  end
  if lastMatching == nil then return nil end

  for i = 1, #cameras do
    if matches(cameras[i]) then
      if position < (cameras[i].camera_in or 0) then
        -- Before this camera starts, so the previous one is still running.
        -- Walking backwards wraps around, which is how the camera from the end
        -- of the lap stays live across the start line.
        for step = 1, #cameras do
          local j = i - step
          while j < 1 do j = j + #cameras end
          if matches(cameras[j]) then return j end
        end
        return lastMatching
      end
    end
  end

  return lastMatching
end

return evaluate
