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

local cameramode = require('core/cameramode')

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

  -- Where the camera takes over, as a fraction of a lap. CamTool 2 has no
  -- field for it -- a camera's start was wherever you happened to create it,
  -- and the red bar was the only way to move one -- so the step is ours:
  -- a thousandth of a lap is about five metres on a normal circuit, and it
  -- scales with the track rather than being five metres everywhere.
  --
  -- Clamped, because a lap position outside 0..1 is not a place.
  camera_in = rule(0.001, true, 5),
}

---How close two cameras may start to one another, as a fraction of a lap.
---Half a metre on a five kilometre circuit: enough that a camera always has
---some lap to call its own.
edit.MIN_CAMERA_GAP = 0.0001

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
---
---A structural change -- a camera or a keyframe added or removed -- carries
---the list and a copy of it instead, because the lists are kept sorted and
---an insertion shifts every index after it. Restoring the copy puts the
---order back as well as the contents.
---@class EditStructuralChange
---@field list table
---@field before table @a copy of the list as it was
---@field after table @a copy of the list as it became

local function clamped(value, rule_)
  if not rule_.clamp then return value end
  return math.max(0, math.min(1, value))
end

---Keep a camera's start between its neighbours'.
---
---The camera list is sorted by camera_in and everything downstream leans on
---it: evaluate walks it in order to find the live camera, and both
---projections in core/trackmap cut their segments from consecutive starts.
---Dragging one camera past another would break that quietly -- no error, just
---a set that selects the wrong camera on part of the lap.
---
---So a start stops at its neighbours rather than swapping with them. Crossing
---would mean renumbering mid-gesture, which is worse: the camera being
---dragged would change index under the hand doing it.
---@param cameras table[]|nil @the list the camera belongs to
---@param index number|nil @its position in that list
---@param position number
---@return number
function edit.betweenNeighbours(cameras, index, position)
  if type(cameras) ~= 'table' or type(index) ~= 'number' then return position end

  local previous = cameras[index - 1]
  local next_ = cameras[index + 1]

  if type(previous) == 'table' and type(previous.camera_in) == 'number' then
    local floor_ = previous.camera_in + edit.MIN_CAMERA_GAP
    if position < floor_ then position = floor_ end
  end

  if type(next_) == 'table' and type(next_.camera_in) == 'number' then
    local ceiling = next_.camera_in - edit.MIN_CAMERA_GAP
    if position > ceiling then position = ceiling end
  end

  return position
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

  if request.op == 'toggleKeyframe' then
    return edit.toggleKeyframe(camera, request.keyframeIndex, key, request.live)
  end

  -- A caller that already knows where the value lives says so. The keyframe's
  -- own position is the case: it is not a parameter, it sits on the keyframe
  -- record itself, and it has no step of its own because a step in metres
  -- depends on how long the track is.
  if request.holder ~= nil then
    if request.op ~= 'set' then return nil, 'an explicit holder only takes set' end
    local holderBefore = request.holder[key]
    local holderAfter = request.value
    -- A string gets through here too: interpolation_mode is set this way, so
    -- that switching a file's maths lands on the undo stack like everything
    -- else rather than being a change nothing remembers.
    if type(holderAfter) ~= 'number' and type(holderAfter) ~= 'string' then
      return nil, 'no value given'
    end
    if holderAfter == holderBefore then return nil, 'unchanged' end
    request.holder[key] = holderAfter
    return {
      holder = request.holder, key = key,
      before = holderBefore, after = holderAfter,
    }
  end

  local rule_ = edit.RULES[key]
  if rule_ == nil then return nil, 'no rule for ' .. tostring(key) end

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
    if key == 'camera_in' then
      after = edit.betweenNeighbours(request.cameras, request.cameraIndex, after)
    end
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
  if key == 'camera_in' then
    after = edit.betweenNeighbours(request.cameras, request.cameraIndex, after)
  end

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

--------------------------------------------------------------------------------
-- The two fields that are not numbers
--------------------------------------------------------------------------------

---Pit only. A real boolean in every reference file, unlike the autofocus
---flag beside it, which is a 0 or a 1 -- CamTool 2 is not consistent about
---this and both have to be read the way they are written.
---@return EditChange|nil
function edit.toggleFlag(camera, key)
  if camera == nil or key == nil then return nil, 'nothing to toggle' end
  local before = camera[key]
  local after = not (before == true)
  camera[key] = after
  return { holder = camera, key = key, before = before, after = after }
end

---Step camera_use_specific_cam through the list in core/cameramode, which is
---where the values and their names live.
edit.SPECIFIC_CAM_MIN = cameramode.MIN
edit.SPECIFIC_CAM_MAX = cameramode.MAX

---@return EditChange|nil
function edit.cycleSpecificCam(camera, direction)
  if camera == nil then return nil, 'no camera' end
  local key = 'camera_use_specific_cam'
  local before = camera[key]
  local after = cameramode.cycle(before, direction)

  camera[key] = after
  return { holder = camera, key = key, before = before, after = after }
end

--------------------------------------------------------------------------------
-- Cameras and keyframes, added and removed
--------------------------------------------------------------------------------

local function copyList(list)
  local out = {}
  for i = 1, #list do out[i] = list[i] end
  return out
end

local function replaceList(list, contents)
  for i = #list, 1, -1 do list[i] = nil end
  for i = 1, #contents do list[i] = contents[i] end
end

---@return EditStructuralChange
local function structural(list, before)
  return { list = list, before = before, after = copyList(list) }
end

---Keep keyframes in order of position, as CamTool 2 does after every change.
---One with no position sorts to the end of the lap, which is where the legacy
---puts it too.
function edit.sortKeyframes(camera)
  local keyframes = camera ~= nil and camera.keyframes or nil
  if type(keyframes) ~= 'table' then return end
  table.sort(keyframes, function(a, b)
    local pa = type(a.keyframe) == 'number' and a.keyframe or 1
    local pb = type(b.keyframe) == 'number' and b.keyframe or 1
    return pa < pb
  end)
end

---Where a new keyframe goes.
---
---CamTool 2 creates one with no position at all and makes you place it
---afterwards with the position bar; the two locals it computes for the job
---are dead code. A keyframe with nowhere to be is no use to anybody, so this
---one is born at the playhead -- the same file either way, one step fewer to
---get there, and moving it afterwards still works.
---@param camera table
---@param position number @the playhead, 0..1
---@return EditStructuralChange|nil change, string|nil why
function edit.addKeyframe(camera, position)
  if camera == nil then return nil, 'no camera' end
  if type(position) ~= 'number' then return nil, 'no position to put it at' end
  if type(camera.keyframes) ~= 'table' then camera.keyframes = {} end

  local before = copyList(camera.keyframes)
  camera.keyframes[#camera.keyframes + 1] = {
    keyframe = position,
    interpolation = {},
  }
  edit.sortKeyframes(camera)

  return structural(camera.keyframes, before)
end

---Remove one, unless it is the last. CamTool 2 refuses to leave a camera with
---no keyframes at all, and so does this.
---@return EditStructuralChange|nil change, string|nil why
function edit.removeKeyframe(camera, index)
  local keyframes = camera ~= nil and camera.keyframes or nil
  if type(keyframes) ~= 'table' then return nil, 'no keyframes' end
  if index == nil or keyframes[index] == nil then return nil, 'no such keyframe' end
  if #keyframes <= 1 then return nil, 'a camera keeps at least one keyframe' end

  local before = copyList(keyframes)
  table.remove(keyframes, index)
  return structural(keyframes, before)
end

---@return EditStructuralChange|nil change, string|nil why
function edit.addCamera(cameras, position)
  if type(cameras) ~= 'table' then return nil, 'no camera list' end
  if type(position) ~= 'number' then return nil, 'no position to put it at' end

  local before = copyList(cameras)
  cameras[#cameras + 1] = {
    camera_in = position,
    camera_pit = false,
    camera_use_tracking_point = 1,
    tracking_strength_heading = 1,
    tracking_strength_pitch = 1,
    tracking_offset = -0.1,
    tracking_mix = 0,
    transform_loc_strength = 1,
    transform_rot_strength = 1,
    camera_shake_strength = 0,
    camera_offset_shake_strength = 0,
    keyframes = { { keyframe = position, interpolation = {} } },
  }
  table.sort(cameras, function(a, b)
    return (a.camera_in or 0) < (b.camera_in or 0)
  end)

  return structural(cameras, before)
end

---Empty a camera list, leaving one blank camera behind -- CamTool 2's Reset,
---which does the same to both lists and both track splines with no
---confirmation and no way back. Here it is one list, it is undoable, and the
---panel asks first.
---@return EditStructuralChange|nil change, string|nil why
function edit.clearCameras(cameras)
  if type(cameras) ~= 'table' or #cameras == 0 then
    return nil, 'nothing to clear'
  end

  local before = copyList(cameras)
  for i = #cameras, 1, -1 do cameras[i] = nil end
  edit.addCamera(cameras, 0)

  return structural(cameras, before)
end

---@return EditStructuralChange|nil change, string|nil why
function edit.removeCamera(cameras, index)
  if type(cameras) ~= 'table' then return nil, 'no camera list' end
  if index == nil or cameras[index] == nil then return nil, 'no such camera' end
  if #cameras <= 1 then return nil, 'a file keeps at least one camera' end

  local before = copyList(cameras)
  table.remove(cameras, index)
  return structural(cameras, before)
end

--------------------------------------------------------------------------------
-- Undo
--------------------------------------------------------------------------------

---Put back what a change changed. Undo is a stack of these.
---@param change EditChange|EditStructuralChange
---Does this change continue an entry a drag has already opened?
---
---A drag is one gesture and should cost one undo, however many frames it
---takes. Recording every frame would bury the rest of the stack under a
---two-second drag and make undoing it a walk back pixel by pixel. So the
---entry already on the stack keeps the value from before the gesture started
---and grows a new end -- but only while all three of these hold.
---
---The gesture is a COUNTER, not the name of the row. Two drags of the same
---parameter are two entries, and only a counter can tell them apart: the row
---is called the same thing both times.
---@param open table|nil @{ gesture = , change = } or nil when none is open
---@param change table @what edit.apply just returned
---@param gesture number|nil @the drag in progress, nil when none is
---@return boolean
function edit.continues(open, change, gesture)
  if gesture == nil or open == nil or change == nil then return false end
  return open.gesture == gesture
    and open.change ~= nil
    and open.change.holder == change.holder
    and open.change.key == change.key
end

function edit.revert(change)
  if type(change) ~= 'table' then return false end
  if change.list ~= nil then
    replaceList(change.list, change.before)
    return true
  end
  if change.holder == nil then return false end
  change.holder[change.key] = change.before
  return true
end

---Do it again, after a revert.
---@param change EditChange|EditStructuralChange
function edit.reapply(change)
  if type(change) ~= 'table' then return false end
  if change.list ~= nil then
    replaceList(change.list, change.after)
    return true
  end
  if change.holder == nil then return false end
  change.holder[change.key] = change.after
  return true
end

return edit
