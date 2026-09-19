--[[
  The one way a camera ever changes.

  Every edit the panel can make goes through edit.apply, and comes back as a
  record of what changed. Two reasons, and the second is the one that decides
  whether this is written now or never.

  CamTool 2 wired each field by hand: a hundred and fifty click handlers, each
  reaching into the data and nudging it. Adding a gesture there means touching
  all of them, which is why it never got one.

  And undo. A change record carries what the value was and what it became, so
  undo is edit.revert on a stack, and redo is edit.apply again. Retrofitting
  that onto scattered mutations means finding every one of them; building it
  in costs almost nothing today.

  Pure: no ac, no CSP, no globals. Given a document and a request it returns a
  change, and the caller decides what to do with it.

  THE NUMBERS BELOW ARE CAMTOOL 2'S. They were read off its source and are
  written down in docs/ui-inventory.md. They are not tidy -- the fine-tuning
  divisor is 5 for most parameters and 10 for the Spline tab, which looks far
  more like an accident than a decision -- and they are reproduced as they
  are, because changing how a camera responds to an arrow changes the feel of
  files people already made. Unifying them is Theo's call, not a tidy-up.
]]

local edit = {}

--------------------------------------------------------------------------------
-- What one press of an arrow does
--------------------------------------------------------------------------------

---@param step number @the change at the camera level
---@param clamp boolean @whether the result is held inside 0..1
---@param fine number @what the step is divided by when editing a keyframe
local function rule(step, clamp, fine)
  return { step = step, clamp = clamp, fine = fine }
end

local DEG = math.pi / 180

---From set_data and set_camera_data in CamTool_2.py. The divisor is 5 for
---everything the main panel touches and 10 for the Spline tab.
edit.RULES = {
  loc_x = rule(0.5, false, 5),
  loc_y = rule(0.5, false, 5),
  loc_z = rule(0.5, false, 5),
  rot_x = rule(2.5 * DEG, false, 5),
  rot_y = rule(2.5 * DEG, false, 5),
  rot_z = rule(2.5 * DEG, false, 5),

  transform_loc_strength = rule(0.25, true, 5),
  transform_rot_strength = rule(0.25, true, 5),

  tracking_strength_pitch = rule(0.25, true, 5),
  tracking_strength_heading = rule(0.25, true, 5),
  tracking_offset = rule(0.1, false, 5),
  tracking_offset_pitch = rule(0.5 * DEG, false, 5),
  tracking_offset_heading = rule(1 * DEG, false, 5),
  tracking_mix = rule(0.25, true, 5),

  camera_shake_strength = rule(0.1, false, 5),
  camera_offset_shake_strength = rule(0.1, false, 5),

  spline_speed = rule(0.05, false, 10),
  spline_affect_loc_xy = rule(0.1, true, 10),
  spline_affect_loc_z = rule(0.1, true, 10),
  spline_affect_pitch = rule(0.1, true, 10),
  spline_affect_roll = rule(0.1, true, 10),
  spline_affect_heading = rule(0.1, true, 10),
  spline_offset_pitch = rule(1 * DEG, false, 10),
  spline_offset_heading = rule(5 * DEG, false, 10),
  spline_offset_loc_x = rule(0.25, false, 10),
  spline_offset_loc_z = rule(0.25, false, 10),
  spline_offset_spline = rule(0.25, false, 10),

  -- These two do not follow the rule at all: CamTool 2 gives them their own
  -- branch, with a different step depending on whether a keyframe is being
  -- edited, no Ctrl or Shift, and a multiplicative step for the focus. See
  -- the Camera tab in docs/ui-inventory.md.
  camera_focus_point = rule(0.5, false, 1),
  camera_fov = rule(0.5, false, 1),
}

---Parameters that exist only as keyframes. There is nowhere on the camera to
---put them, so with no keyframe there is nothing for an arrow to move -- the
---diamond is how you bring one into being.
edit.KEYFRAME_ONLY = {
  camera_focus_point = true,
  camera_fov = true,
  loc_x = true, loc_y = true, loc_z = true,
  rot_x = true, rot_y = true, rot_z = true,
}

---Parameters whose first keyframe takes the camera's live value rather than a
---stored one, because that is the gesture: put the view where you want it,
---then pin it.
edit.SEEDS_FROM_LIVE = {
  loc_x = true, loc_y = true, loc_z = true,
  rot_x = true, rot_y = true, rot_z = true,
  camera_focus_point = true, camera_fov = true,
}

--------------------------------------------------------------------------------
-- Reading and writing one value
--------------------------------------------------------------------------------

---Where a parameter lives right now: on the selected keyframe, or on the
---camera itself.
---@return table|nil holder, string where @'keyframe', 'camera' or 'nowhere'
function edit.holderOf(camera, keyframeIndex, key)
  if camera == nil then return nil, 'nowhere' end

  local keyframes = camera.keyframes
  if type(keyframes) == 'table' and keyframeIndex ~= nil then
    local kf = keyframes[keyframeIndex]
    local interp = type(kf) == 'table' and kf.interpolation or nil
    if interp ~= nil and type(interp[key]) == 'number' then
      return interp, 'keyframe'
    end
  end

  if type(camera[key]) == 'number' then return camera, 'camera' end
  if edit.KEYFRAME_ONLY[key] then return nil, 'nowhere' end
  return camera, 'camera'
end

---@return number|nil
function edit.valueOf(camera, keyframeIndex, key)
  local holder = edit.holderOf(camera, keyframeIndex, key)
  return holder ~= nil and holder[key] or nil
end

--------------------------------------------------------------------------------
-- The single entry point
--------------------------------------------------------------------------------

---@class EditChange
---@field holder table @the table that was written to
---@field key string
---@field before number|nil
---@field after number|nil

local function clamped(value, rule_)
  if not rule_.clamp then return value end
  return math.max(0, math.min(1, value))
end

---Apply one edit.
---
---@param request table
---  camera        the camera being edited
---  keyframeIndex the selected keyframe, or nil
---  key           the parameter
---  op            'nudge', 'set' or 'toggleKeyframe'
---  direction     -1 or 1, for nudge
---  amount        how many steps, for nudge; defaults to 1 and may be
---                fractional, which is what a drag produces
---  value         the new value, for set
---  ctrl, shift   the modifiers: a quarter of the step, or four times it
---  live          the camera's current value, for seeding a new keyframe
---@return EditChange|nil change, string|nil why @nil when nothing changed
function edit.apply(request)
  local camera = request.camera
  local key = request.key
  if camera == nil or key == nil then return nil, 'nothing to edit' end

  local rule_ = edit.RULES[key]
  if rule_ == nil then return nil, 'no rule for ' .. tostring(key) end

  if request.op == 'toggleKeyframe' then
    return edit.toggleKeyframe(camera, request.keyframeIndex, key, request.live)
  end

  local holder, where = edit.holderOf(camera, request.keyframeIndex, key)
  if holder == nil then
    -- A keyframe-only parameter with no keyframe: the arrows have nothing to
    -- move. Say so rather than inventing a camera-level value that CamTool 2
    -- has no slot for and would drop on the next save.
    return nil, key .. ' has no value until it is keyframed'
  end

  local before = holder[key]

  if request.op == 'set' then
    if type(request.value) ~= 'number' then return nil, 'no value given' end
    local after = clamped(request.value, rule_)
    if after == before then return nil, 'unchanged' end
    holder[key] = after
    return { holder = holder, key = key, before = before, after = after }
  end

  if request.op ~= 'nudge' then return nil, 'unknown operation' end

  local step = rule_.step
  -- Focus and FOV take neither modifier in CamTool 2; everything else does.
  if key ~= 'camera_focus_point' and key ~= 'camera_fov' then
    if request.ctrl then step = step / 4 end
    if request.shift then step = step * 4 end
  end
  if where == 'keyframe' then step = step / rule_.fine end

  local direction = request.direction or 1
  local amount = request.amount or 1
  local after

  if key == 'camera_focus_point' and where ~= 'keyframe' then
    -- Multiplicative, and so a focus at zero can never be raised again. That
    -- is CamTool 2's behaviour and it is a trap; reproduced here, flagged in
    -- docs/ui-inventory.md, and worth fixing once Theo says so.
    after = (before or 0) * (direction > 0 and 1.1 or 0.9)
  else
    after = (before or 0) + direction * step * amount
  end

  if key == 'camera_focus_point' or key == 'camera_fov' then
    after = math.max(0, after)
  end
  after = clamped(after, rule_)

  if after == before then return nil, 'unchanged' end
  holder[key] = after
  return { holder = holder, key = key, before = before, after = after }
end

---Add this parameter to the selected keyframe, or take it off.
---@return EditChange|nil change, string|nil why
function edit.toggleKeyframe(camera, keyframeIndex, key, live)
  if camera == nil or keyframeIndex == nil then
    return nil, 'no keyframe selected'
  end

  local keyframes = camera.keyframes
  local kf = type(keyframes) == 'table' and keyframes[keyframeIndex] or nil
  if type(kf) ~= 'table' then return nil, 'no such keyframe' end
  if type(kf.interpolation) ~= 'table' then kf.interpolation = {} end

  local interp = kf.interpolation
  local before = interp[key]

  if type(before) == 'number' then
    interp[key] = nil
    return { holder = interp, key = key, before = before, after = nil }
  end

  -- Creating one: the live camera for the things you aim, the camera's own
  -- value for the rest. CamTool 2 makes the same split, and it is what makes
  -- the gesture work -- put the view where you want it, then pin it.
  local seed
  if edit.SEEDS_FROM_LIVE[key] and type(live) == 'number' then
    seed = live
  elseif type(camera[key]) == 'number' then
    seed = camera[key]
  elseif type(live) == 'number' then
    seed = live
  else
    return nil, 'nothing to seed ' .. key .. ' from'
  end

  interp[key] = seed
  return { holder = interp, key = key, before = nil, after = seed }
end

---Put back what a change changed. Undo is a stack of these.
---@param change EditChange
function edit.revert(change)
  if type(change) ~= 'table' or change.holder == nil then return false end
  change.holder[change.key] = change.before
  return true
end

---Do it again, after a revert.
---@param change EditChange
function edit.reapply(change)
  if type(change) ~= 'table' or change.holder == nil then return false end
  change.holder[change.key] = change.after
  return true
end

return edit
