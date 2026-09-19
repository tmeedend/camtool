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
      if not spec.runtime and spec.key ~= 'camera_in' then
        eq(type(edit.RULES[spec.key]), 'table',
          spec.key .. ' (' .. spec.label .. ') has no step')
      end
    end
  end
end)
