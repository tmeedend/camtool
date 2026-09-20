--[[
  Tests for core/edit.lua, the one way a camera changes.

  Two things are being pinned down. That an arrow moves a value by what
  CamTool 2 moves it by -- these numbers came off its source and changing one
  changes the feel of files people already made. And that every change comes
  back as a record that can be put back, because that is what undo will be.
]]

local runner = require('tests/runner')
local edit = require('core/edit')

local test, eq, near = runner.test, runner.eq, runner.near

---A camera with one keyframe that carries loc_x, and camera-level values.
local function camera()
  return {
    camera_in = 0.25,
    tracking_mix = 0.5,
    transform_rot_strength = 1,
    spline_affect_loc_xy = 0.5,
    keyframes = {
      { keyframe = 0.30, interpolation = { loc_x = 10 } },
      { keyframe = 0.60, interpolation = {} },
    },
  }
end

--------------------------------------------------------------------------------
-- Where a value lives
--------------------------------------------------------------------------------

test('a value is found on the keyframe first, then on the camera', function()
  local c = camera()

  local _, where = edit.holderOf(c, 1, 'loc_x')
  eq(where, 'keyframe')

  -- The second keyframe does not carry loc_x, and the camera has nowhere to
  -- keep it either: loc_x only exists as a keyframe.
  local holder, where2 = edit.holderOf(c, 2, 'loc_x')
  eq(holder, nil)
  eq(where2, 'nowhere')

  -- tracking_mix does live on the camera.
  local _, where3 = edit.holderOf(c, 2, 'tracking_mix')
  eq(where3, 'camera')
end)

--------------------------------------------------------------------------------
-- Nudging
--------------------------------------------------------------------------------

test('an arrow moves a camera-level value by the full step', function()
  local c = camera()
  local change = edit.apply({
    camera = c, keyframeIndex = 2, key = 'tracking_mix',
    op = 'nudge', direction = 1,
  })

  near(c.tracking_mix, 0.75, 1e-12, 'the step is 0.25')
  eq(change.before, 0.5)
  near(change.after, 0.75, 1e-12)
end)

test('an arrow moves a keyframed value by a fifth of the step', function()
  -- CamTool 2 divides by 5 once a keyframe is what is being edited, so the
  -- same arrow tunes finely on a keyframe and coarsely on the camera.
  local c = camera()
  edit.apply({
    camera = c, keyframeIndex = 1, key = 'loc_x', op = 'nudge', direction = 1,
  })
  near(c.keyframes[1].interpolation.loc_x, 10 + 0.5 / 5, 1e-12)
end)

test('the Spline tab divides by ten instead of five', function()
  -- Two divisors for the same idea, in two functions. Reproduced because
  -- changing it changes how existing cameras respond, not because it is right.
  local c = camera()
  c.keyframes[1].interpolation.spline_affect_loc_xy = 0.5
  edit.apply({
    camera = c, keyframeIndex = 1, key = 'spline_affect_loc_xy',
    op = 'nudge', direction = 1,
  })
  near(c.keyframes[1].interpolation.spline_affect_loc_xy, 0.5 + 0.1 / 10, 1e-12)
end)

test('Ctrl quarters the step and Shift quadruples it', function()
  local c = camera()
  edit.apply({ camera = c, keyframeIndex = 2, key = 'tracking_mix',
    op = 'nudge', direction = 1, ctrl = true })
  near(c.tracking_mix, 0.5 + 0.25 / 4, 1e-12)

  c = camera()
  edit.apply({ camera = c, keyframeIndex = 2, key = 'tracking_mix',
    op = 'nudge', direction = -1, shift = true })
  -- 0.5 - 1.0, clamped at zero.
  near(c.tracking_mix, 0, 1e-12)
end)

test('strengths are held inside 0..1 and positions are not', function()
  local c = camera()
  for _ = 1, 10 do
    edit.apply({ camera = c, keyframeIndex = 2, key = 'tracking_mix',
      op = 'nudge', direction = 1 })
  end
  eq(c.tracking_mix, 1, 'a strength cannot go past one')

  for _ = 1, 10 do
    edit.apply({ camera = c, keyframeIndex = 1, key = 'loc_x',
      op = 'nudge', direction = -1 })
  end
  eq(c.keyframes[1].interpolation.loc_x < 10, true, 'a position is free')
end)

test('a drag is a nudge with a fractional amount', function()
  -- The same entry point, so a drag and an arrow can never drift apart.
  local c = camera()
  edit.apply({ camera = c, keyframeIndex = 2, key = 'tracking_mix',
    op = 'nudge', direction = 1, amount = 0.4 })
  near(c.tracking_mix, 0.5 + 0.25 * 0.4, 1e-12)
end)

test('an arrow on a parameter with no keyframe does nothing, and says why', function()
  -- loc_x exists only as a keyframe. CamTool 2 has no slot for it on the
  -- camera, so inventing one would be dropped at the next save.
  local c = camera()
  local change, why = edit.apply({
    camera = c, keyframeIndex = 2, key = 'loc_x', op = 'nudge', direction = 1,
  })
  eq(change, nil)
  eq(type(why), 'string')
  eq(c.keyframes[2].interpolation.loc_x, nil)
end)

test('the focus step is multiplicative, and zero is a trap', function()
  local c = camera()
  c.keyframes[1].interpolation.camera_focus_point = 100

  -- Keyframed: plus or minus half a metre.
  edit.apply({ camera = c, keyframeIndex = 1, key = 'camera_focus_point',
    op = 'nudge', direction = 1 })
  near(c.keyframes[1].interpolation.camera_focus_point, 100.5, 1e-12)

  -- And it never goes below zero.
  c.keyframes[1].interpolation.camera_focus_point = 0.2
  for _ = 1, 5 do
    edit.apply({ camera = c, keyframeIndex = 1, key = 'camera_focus_point',
      op = 'nudge', direction = -1 })
  end
  eq(c.keyframes[1].interpolation.camera_focus_point >= 0, true)
end)

test('focus and FOV ignore Ctrl and Shift, alone in the panel', function()
  local c = camera()
  c.keyframes[1].interpolation.camera_fov = 30

  edit.apply({ camera = c, keyframeIndex = 1, key = 'camera_fov',
    op = 'nudge', direction = 1, shift = true })
  near(c.keyframes[1].interpolation.camera_fov, 30.5, 1e-12,
    'Shift must not multiply this one')
end)

--------------------------------------------------------------------------------
-- Typing a value
--------------------------------------------------------------------------------

test('a typed value lands where the arrows would have', function()
  local c = camera()
  edit.apply({ camera = c, keyframeIndex = 1, key = 'loc_x',
    op = 'set', value = -42.5 })
  near(c.keyframes[1].interpolation.loc_x, -42.5, 1e-12)

  edit.apply({ camera = c, keyframeIndex = 2, key = 'tracking_mix',
    op = 'set', value = 0.3 })
  near(c.tracking_mix, 0.3, 1e-12)
end)

test('a typed value is clamped like a nudged one', function()
  local c = camera()
  edit.apply({ camera = c, keyframeIndex = 2, key = 'tracking_mix',
    op = 'set', value = 5 })
  eq(c.tracking_mix, 1)
end)

--------------------------------------------------------------------------------
-- The diamond
--------------------------------------------------------------------------------

test('the diamond adds the parameter to the selected keyframe', function()
  local c = camera()
  local change = edit.apply({
    camera = c, keyframeIndex = 2, key = 'loc_x',
    op = 'toggleKeyframe', live = 77,
  })

  eq(c.keyframes[2].interpolation.loc_x, 77, 'seeded from the live camera')
  eq(change.before, nil)
  eq(change.after, 77)
end)

test('the diamond takes it off again', function()
  local c = camera()
  local change = edit.apply({
    camera = c, keyframeIndex = 1, key = 'loc_x', op = 'toggleKeyframe',
  })

  eq(c.keyframes[1].interpolation.loc_x, nil)
  eq(change.before, 10)
  eq(change.after, nil)
end)

test('a parameter that is not aimed is seeded from the camera', function()
  -- tracking_mix has a camera-level value, and that is what the new keyframe
  -- takes. Only the things you point -- position, rotation, focus, FOV --
  -- come from the live camera.
  local c = camera()
  edit.apply({ camera = c, keyframeIndex = 2, key = 'tracking_mix',
    op = 'toggleKeyframe', live = 999 })
  eq(c.keyframes[2].interpolation.tracking_mix, 0.5)
end)

test('the diamond needs a keyframe to act on', function()
  local c = camera()
  local change, why = edit.apply({
    camera = c, keyframeIndex = nil, key = 'loc_x', op = 'toggleKeyframe',
  })
  eq(change, nil)
  eq(type(why), 'string')
end)

--------------------------------------------------------------------------------
-- Undo
--------------------------------------------------------------------------------

test('every change can be put back and done again', function()
  -- This is the whole reason the entry point exists. If it works for a nudge,
  -- a typed value and a keyframe toggle, undo is a stack and nothing more.
  local c = camera()
  local stack = {}

  stack[#stack + 1] = edit.apply({ camera = c, keyframeIndex = 2,
    key = 'tracking_mix', op = 'nudge', direction = 1 })
  stack[#stack + 1] = edit.apply({ camera = c, keyframeIndex = 1,
    key = 'loc_x', op = 'set', value = 3 })
  stack[#stack + 1] = edit.apply({ camera = c, keyframeIndex = 2,
    key = 'loc_x', op = 'toggleKeyframe', live = 50 })

  eq(c.tracking_mix, 0.75)
  eq(c.keyframes[1].interpolation.loc_x, 3)
  eq(c.keyframes[2].interpolation.loc_x, 50)

  for i = #stack, 1, -1 do edit.revert(stack[i]) end

  eq(c.tracking_mix, 0.5, 'back to where it started')
  eq(c.keyframes[1].interpolation.loc_x, 10)
  eq(c.keyframes[2].interpolation.loc_x, nil)

  for i = 1, #stack do edit.reapply(stack[i]) end

  eq(c.tracking_mix, 0.75)
  eq(c.keyframes[1].interpolation.loc_x, 3)
  eq(c.keyframes[2].interpolation.loc_x, 50)
end)

test('a change that changes nothing is not a change', function()
  -- Otherwise a held arrow at a clamp would fill the undo stack with nothing.
  local c = camera()
  c.tracking_mix = 1
  local change, why = edit.apply({ camera = c, keyframeIndex = 2,
    key = 'tracking_mix', op = 'nudge', direction = 1 })
  eq(change, nil)
  eq(why, 'unchanged')
end)

test('an unknown parameter is refused rather than guessed at', function()
  local c = camera()
  local change, why = edit.apply({ camera = c, keyframeIndex = 1,
    key = 'not_a_parameter', op = 'nudge', direction = 1 })
  eq(change, nil)
  eq(type(why), 'string')
end)

test('every parameter the panel shows has a rule', function()
  -- The panel and the edit rules have to agree, or a row exists that no arrow
  -- can move.
  local atr = require('ui/atr')
  for _, column in ipairs(atr.COLUMNS) do
    for _, spec in ipairs(column.rows) do
      -- Skipping the ones that are not numbers to nudge: the starting point
      -- is metres and converted by the panel, and the two plain fields are a
      -- flag and a cycle with their own operations.
      if not spec.runtime and not spec.plain and spec.key ~= 'camera_in' then
        eq(type(edit.RULES[spec.key]), 'table',
          spec.key .. ' (' .. spec.label .. ') has no step')
      end
    end
  end
end)

--------------------------------------------------------------------------------
-- Cameras and keyframes, added and removed
--------------------------------------------------------------------------------

test('a new keyframe is born at the playhead, in order', function()
  -- CamTool 2 creates one with no position and makes you place it afterwards
  -- with the position bar. Same file either way; one step fewer to get there.
  local c = camera()
  local change = edit.addKeyframe(c, 0.45)

  eq(#c.keyframes, 3)
  eq(c.keyframes[2].keyframe, 0.45, 'sorted between 0.30 and 0.60')
  eq(next(c.keyframes[2].interpolation), nil, 'and carrying nothing yet')
  eq(change ~= nil, true)
end)

test('removing a keyframe leaves at least one', function()
  local c = camera()
  eq(edit.removeKeyframe(c, 1) ~= nil, true)
  eq(#c.keyframes, 1)

  local change, why = edit.removeKeyframe(c, 1)
  eq(change, nil)
  eq(type(why), 'string')
  eq(#c.keyframes, 1, 'the last one stays')
end)

test('adding and removing a keyframe can be undone, order included', function()
  -- The lists are kept sorted, so an insertion shifts every index after it.
  -- Undo has to put the order back, not just the contents.
  local c = camera()
  local first, second = c.keyframes[1], c.keyframes[2]

  local added = edit.addKeyframe(c, 0.45)
  eq(#c.keyframes, 3)

  edit.revert(added)
  eq(#c.keyframes, 2)
  eq(c.keyframes[1], first, 'the same tables, in the same order')
  eq(c.keyframes[2], second)

  edit.reapply(added)
  eq(#c.keyframes, 3)
  eq(c.keyframes[2].keyframe, 0.45)
end)

test('a new camera arrives usable and in position order', function()
  local cameras = { { camera_in = 0.1 }, { camera_in = 0.8 } }
  local change = edit.addCamera(cameras, 0.5)

  eq(#cameras, 3)
  eq(cameras[2].camera_in, 0.5)
  eq(#cameras[2].keyframes, 1, 'with a keyframe, or it could never animate')
  eq(cameras[2].camera_pit, false)
  eq(cameras[2].tracking_strength_heading, 1, 'tracking on, like CamTool 2')

  edit.revert(change)
  eq(#cameras, 2)
end)

test('removing a camera leaves at least one', function()
  local cameras = { { camera_in = 0.1 } }
  local change, why = edit.removeCamera(cameras, 1)
  eq(change, nil)
  eq(type(why), 'string')
end)

--------------------------------------------------------------------------------
-- The keyframe's own position
--------------------------------------------------------------------------------

test('a keyframe can be moved along the track, and moved back', function()
  -- Not a parameter: it lives on the keyframe record, and a step in metres
  -- depends on the track, so the caller works out the number and says where
  -- to put it.
  local c = camera()
  local kf = c.keyframes[1]

  local change = edit.apply({
    camera = c, holder = kf, key = 'keyframe', op = 'set', value = 0.42,
  })
  eq(kf.keyframe, 0.42)

  edit.revert(change)
  eq(kf.keyframe, 0.30)
end)

test('an explicit holder refuses anything but a plain set', function()
  local c = camera()
  local change, why = edit.apply({
    camera = c, holder = c.keyframes[1], key = 'keyframe',
    op = 'nudge', direction = 1,
  })
  eq(change, nil)
  eq(type(why), 'string')
end)

--------------------------------------------------------------------------------
-- The two fields that are not numbers
--------------------------------------------------------------------------------

test('Pit only flips either way, and can be put back', function()
  local c = camera()
  c.camera_pit = false

  local change = edit.toggleFlag(c, 'camera_pit')
  eq(c.camera_pit, true)
  edit.revert(change)
  eq(c.camera_pit, false)
end)

test('Specific cam cycles between CamTool and the AC cameras', function()
  -- Minus one is CamTool driving; 0 to 13 hand the view to Assetto Corsa and
  -- CamTool 2 then skips interpolating altogether. It wraps at both ends.
  local c = camera()
  c.camera_use_specific_cam = -1

  edit.cycleSpecificCam(c, 1)
  eq(c.camera_use_specific_cam, 0)

  c.camera_use_specific_cam = edit.SPECIFIC_CAM_MAX
  edit.cycleSpecificCam(c, 1)
  eq(c.camera_use_specific_cam, edit.SPECIFIC_CAM_MIN, 'wraps at the top')

  edit.cycleSpecificCam(c, -1)
  eq(c.camera_use_specific_cam, edit.SPECIFIC_CAM_MAX, 'and at the bottom')
end)

test('a camera with no Specific cam set starts from CamTool', function()
  local c = camera()
  eq(c.camera_use_specific_cam, nil)
  edit.cycleSpecificCam(c, 1)
  eq(c.camera_use_specific_cam, 0, 'nil reads as -1, so one step is 0')
end)

test('Reset clears a list but leaves one camera, and can be undone', function()
  -- CamTool 2 wipes both lists and both track splines with no confirmation
  -- and no way back. This clears one list, keeps a camera to work from, and
  -- goes on the undo stack like everything else.
  local cameras = { { camera_in = 0.1 }, { camera_in = 0.5 }, { camera_in = 0.9 } }
  local change = edit.clearCameras(cameras)

  eq(#cameras, 1, 'a list with no cameras at all is not usable')
  eq(#cameras[1].keyframes, 1)

  edit.revert(change)
  eq(#cameras, 3)
  eq(cameras[2].camera_in, 0.5, 'the same cameras, in the same order')
end)

test('undo and redo walk the same path in both directions', function()
  local c = camera()
  local one = edit.apply({ camera = c, keyframeIndex = 2,
    key = 'tracking_mix', op = 'nudge', direction = 1 })
  local two = edit.apply({ camera = c, keyframeIndex = 1,
    key = 'loc_x', op = 'set', value = 3 })

  edit.revert(two)
  edit.revert(one)
  eq(c.tracking_mix, 0.5)
  eq(c.keyframes[1].interpolation.loc_x, 10)

  edit.reapply(one)
  edit.reapply(two)
  eq(c.tracking_mix, 0.75)
  eq(c.keyframes[1].interpolation.loc_x, 3)
end)

test('the legacy switches come from the file, not from a preference', function()
  -- The one thing the two-axis design in core/data exists to prevent: a
  -- CamTool 2 file played with the corrected curves without anyone meaning
  -- it, which would change footage already cut.
  local playback = require('core/playback')

  local state = playback.new()
  playback.applyMode(state, 'legacy')
  eq(state.options.legacyLastCamera, true)
  eq(state.options.legacyZeroFill, true)

  playback.applyMode(state, 'fixed')
  eq(state.options.legacyLastCamera, false)
  eq(state.options.legacyZeroFill, false)

  -- A file with no mode at all is treated as legacy, which is what an
  -- unknown file most likely is.
  playback.applyMode(state, nil)
  eq(state.options.legacyLastCamera, true)
end)

test('a migrated CamTool 2 file asks for legacy maths', function()
  local dataModule = require('core/data')
  local doc = dataModule.load(require('tests/fixtures/camera_file_lap'))
  eq(doc.version, dataModule.CURRENT_VERSION, 'the encoding is migrated')
  eq(doc.interpolation_mode, 'legacy', 'but the maths is not')
end)

test('a CamTool 3 file that says nothing gets the corrected maths', function()
  local dataModule = require('core/data')
  local doc = dataModule.load({ version = 1, pos = {}, time = {} })
  eq(doc.interpolation_mode, 'fixed')
end)

test('switching the maths is an edit, and undoes', function()
  local doc = require('core/data').load(require('tests/fixtures/camera_file_lap'))
  local change = edit.apply({
    camera = doc, holder = doc, key = 'interpolation_mode',
    op = 'set', value = 'fixed',
  })
  eq(doc.interpolation_mode, 'fixed')
  edit.revert(change)
  eq(doc.interpolation_mode, 'legacy')
end)

--------------------------------------------------------------------------
-- One drag, one undo
--------------------------------------------------------------------------

local function change(holder, key, before, after)
  return { holder = holder, key = key, before = before, after = after }
end

test('the same gesture on the same value stretches one entry', function()
  local holder = {}
  local open = { gesture = 7, change = change(holder, 'camera_fov', 40, 41) }
  eq(edit.continues(open, change(holder, 'camera_fov', 41, 42), 7), true)
end)

test('a second drag of the same parameter is a second entry', function()
  -- The one that makes the gesture a counter rather than the row's name: let
  -- go, drag the same field again, and that has to be undoable on its own.
  local holder = {}
  local open = { gesture = 7, change = change(holder, 'camera_fov', 40, 41) }
  eq(edit.continues(open, change(holder, 'camera_fov', 41, 42), 8), false)
end)

test('a drag that wanders onto another parameter starts a new entry', function()
  local holder = {}
  local open = { gesture = 7, change = change(holder, 'camera_fov', 40, 41) }
  eq(edit.continues(open, change(holder, 'tracking_mix', 0, 0.1), 7), false)
end)

test('the same parameter on another keyframe is another entry', function()
  -- Same key, different holder: the keyframe under the playhead moved on.
  local open = { gesture = 7, change = change({}, 'camera_fov', 40, 41) }
  eq(edit.continues(open, change({}, 'camera_fov', 41, 42), 7), false)
end)

test('an arrow or a typed value never continues a drag', function()
  local holder = {}
  local open = { gesture = 7, change = change(holder, 'camera_fov', 40, 41) }
  eq(edit.continues(open, change(holder, 'camera_fov', 41, 42), nil), false,
    'no gesture in progress, so nothing to stretch')
end)

test('with nothing open there is nothing to continue', function()
  eq(edit.continues(nil, change({}, 'camera_fov', 40, 41), 7), false)
  eq(edit.continues({ gesture = 7 }, change({}, 'camera_fov', 40, 41), 7), false)
end)

--------------------------------------------------------------------------
-- Moving where a camera takes over
--------------------------------------------------------------------------

local function threeCameras()
  return {
    { camera_in = 0.10, keyframes = {} },
    { camera_in = 0.50, keyframes = {} },
    { camera_in = 0.90, keyframes = {} },
  }
end

test('a camera start moves where it is asked to', function()
  local cameras = threeCameras()
  local change = edit.apply({
    camera = cameras[2], cameras = cameras, cameraIndex = 2,
    key = 'camera_in', op = 'set', value = 0.6,
  })
  runner.near(cameras[2].camera_in, 0.6)
  runner.near(change.before, 0.5)
end)

test('a camera start stops at its neighbour rather than crossing it', function()
  -- The list is sorted by camera_in and everything downstream leans on it:
  -- selection walks it in order, and both projections cut their segments from
  -- consecutive starts. Crossing would break all three quietly.
  local cameras = threeCameras()
  edit.apply({
    camera = cameras[2], cameras = cameras, cameraIndex = 2,
    key = 'camera_in', op = 'set', value = 0.99,
  })
  runner.near(cameras[2].camera_in, 0.9 - edit.MIN_CAMERA_GAP)
  eq(cameras[2].camera_in < cameras[3].camera_in, true, 'still in order')
end)

test('and stops at the one before it too', function()
  local cameras = threeCameras()
  edit.apply({
    camera = cameras[2], cameras = cameras, cameraIndex = 2,
    key = 'camera_in', op = 'set', value = 0,
  })
  runner.near(cameras[2].camera_in, 0.1 + edit.MIN_CAMERA_GAP)
  eq(cameras[1].camera_in < cameras[2].camera_in, true)
end)

test('the first and last cameras still reach the start and finish lines', function()
  local cameras = threeCameras()
  edit.apply({
    camera = cameras[1], cameras = cameras, cameraIndex = 1,
    key = 'camera_in', op = 'set', value = -1,
  })
  runner.near(cameras[1].camera_in, 0, 1e-12, 'clamped to the lap, not to a neighbour')

  edit.apply({
    camera = cameras[3], cameras = cameras, cameraIndex = 3,
    key = 'camera_in', op = 'set', value = 2,
  })
  runner.near(cameras[3].camera_in, 1, 1e-12)
end)

test('the arrows move a start too, and stop at the same fences', function()
  -- Same rule whichever gesture asks: the STARTING POINT row had no edit path
  -- at all before this, so its arrows did nothing.
  local cameras = threeCameras()
  for _ = 1, 1000 do
    edit.apply({
      camera = cameras[2], cameras = cameras, cameraIndex = 2,
      key = 'camera_in', op = 'nudge', direction = 1, amount = 1,
    })
  end
  eq(cameras[2].camera_in <= cameras[3].camera_in - edit.MIN_CAMERA_GAP, true,
    'a thousand steps up still cannot pass the next camera')
end)

test('a start with no list to compare against just clamps to the lap', function()
  -- The map hands the neighbours over; a caller that does not should still
  -- get a sane answer rather than an error.
  local camera = { camera_in = 0.5, keyframes = {} }
  edit.apply({ camera = camera, key = 'camera_in', op = 'set', value = 0.7 })
  runner.near(camera.camera_in, 0.7)
end)

test('two cameras cannot be squeezed onto the same point', function()
  local cameras = {
    { camera_in = 0.5, keyframes = {} },
    { camera_in = 0.5 + edit.MIN_CAMERA_GAP, keyframes = {} },
  }
  edit.apply({
    camera = cameras[1], cameras = cameras, cameraIndex = 1,
    key = 'camera_in', op = 'set', value = 0.9,
  })
  eq(cameras[1].camera_in < cameras[2].camera_in, true)
end)

--------------------------------------------------------------------------
-- Naming a camera
--------------------------------------------------------------------------

test('a camera can be named, and the change can be undone', function()
  local camera = { camera_in = 0, keyframes = {} }
  local change = edit.renameCamera(camera, 'Eau Rouge')
  eq(camera.name, 'Eau Rouge')

  edit.revert(change)
  eq(camera.name, nil, 'back to having no name at all, not an empty one')
end)

test('a name is trimmed, and its whitespace flattened', function()
  -- A name with a space on the end looks identical to one without and sorts
  -- differently everywhere; a newline breaks the line it is drawn on.
  local camera = {}
  edit.renameCamera(camera, '  Bus Stop  ')
  eq(camera.name, 'Bus Stop')

  edit.renameCamera(camera, 'Bus\tStop')
  eq(camera.name, 'Bus Stop')
end)

test('a name that is only spaces is no name', function()
  local camera = { name = 'something' }
  edit.renameCamera(camera, '   ')
  eq(camera.name, nil)
end)

test('clearing a name is an edit like any other', function()
  local camera = { name = 'Tamburello' }
  local change = edit.renameCamera(camera, nil)
  eq(camera.name, nil)
  edit.revert(change)
  eq(camera.name, 'Tamburello')
end)

test('a very long name is cut to something that fits a segment', function()
  local camera = {}
  edit.renameCamera(camera, string.rep('x', 200))
  eq(#camera.name, edit.MAX_NAME)
end)

test('renaming to the same name changes nothing', function()
  local camera = { name = 'Eau Rouge' }
  eq(edit.renameCamera(camera, 'Eau Rouge'), nil)
  eq(edit.renameCamera(camera, ' Eau Rouge '), nil, 'trimmed first, then compared')
end)

test('a name has to be text', function()
  local camera = {}
  eq(edit.renameCamera(camera, 42), nil)
  eq(camera.name, nil)
end)

--------------------------------------------------------------------------
-- Identity on creation
--------------------------------------------------------------------------

test('a new camera is born with an id', function()
  local cameras = { { id = 4, camera_in = 0, keyframes = {} } }
  edit.addCamera(cameras, 0.5, 12)

  local added = nil
  for _, camera in ipairs(cameras) do
    if camera.camera_in == 0.5 then added = camera end
  end
  eq(added.id, 12)
end)

test('with no id given it takes one past the highest in the list', function()
  -- The fallback for callers with no document, which is the tests.
  local cameras = { { id = 4, camera_in = 0, keyframes = {} } }
  edit.addCamera(cameras, 0.5)
  for _, camera in ipairs(cameras) do
    if camera.camera_in == 0.5 then eq(camera.id, 5) end
  end
end)

test('an id is never shared, whatever order cameras are added in', function()
  local cameras = {}
  for i = 1, 10 do
    edit.addCamera(cameras, (11 - i) / 20)
  end

  local seen = {}
  for _, camera in ipairs(cameras) do
    eq(seen[camera.id], nil, 'id ' .. tostring(camera.id) .. ' twice')
    seen[camera.id] = true
  end
end)

test('inserting a camera shifts every rank after it, and no id at all', function()
  -- The reason any of this exists. The list is sorted by camera_in, so a
  -- camera added between two others pushes everything after it down a place:
  -- what the panel called 3 is now 4, and so is every note and every mental
  -- landmark. The id underneath does not move, and neither does the name
  -- hanging off it.
  local cameras = {}
  edit.addCamera(cameras, 0.1, 1)
  edit.addCamera(cameras, 0.4, 2)
  edit.addCamera(cameras, 0.7, 3)
  edit.renameCamera(cameras[3], 'Eau Rouge')

  eq(cameras[3].id, 3)
  eq(cameras[3].name, 'Eau Rouge')

  edit.addCamera(cameras, 0.2, 4)

  eq(#cameras, 4)
  eq(cameras[4].id, 3, 'it is the fourth camera now, and still id 3')
  eq(cameras[4].name, 'Eau Rouge', 'and still called what it was called')
  eq(cameras[2].id, 4, 'the new one took the place, not the identity')
end)
