--[[
  Tests for core/navigate.lua and core/playstate.lua: what the arrow keys do,
  and whether the replay is running.

  Both are small, and both have one rule that is easy to get comfortably wrong
  -- stepping past the end should stop rather than wrap, and an icon should not
  blink.
]]

local runner = require('tests/runner')
local navigate = require('core/navigate')
local playstate = require('core/playstate')

local test, eq, near = runner.test, runner.eq, runner.near

local function cameraWith(positions)
  local keyframes = {}
  for i, at in ipairs(positions) do keyframes[i] = { keyframe = at } end
  return { camera_in = positions[1] or 0, keyframes = keyframes }
end

--------------------------------------------------------------------------
-- Keyframes
--------------------------------------------------------------------------

test('the arrows walk the keyframes of a camera', function()
  local camera = cameraWith({ 0.1, 0.2, 0.3 })
  eq(navigate.nextKeyframe(camera, 1), 2)
  eq(navigate.nextKeyframe(camera, 2), 3)
  eq(navigate.previousKeyframe(camera, 3), 2)
  eq(navigate.previousKeyframe(camera, 2), 1)
end)

test('they stop at the ends rather than wrapping round', function()
  -- Wrapping is one line shorter and means an arrow never does nothing. It is
  -- also wrong: a held arrow would carry the shot silently back round the lap,
  -- and order is the one thing a camera set has.
  local camera = cameraWith({ 0.1, 0.2, 0.3 })
  eq(navigate.nextKeyframe(camera, 3), nil)
  eq(navigate.previousKeyframe(camera, 1), nil)
end)

test('a camera with no keyframes answers nothing, both ways', function()
  -- Not an error, and not a reason to move something else instead. The caller
  -- says so in the status line.
  local camera = { camera_in = 0.5, keyframes = {} }
  eq(navigate.nextKeyframe(camera, 1), nil)
  eq(navigate.previousKeyframe(camera, 1), nil)
  eq(navigate.nextKeyframe(camera, nil), nil)
end)

test('with none selected, an arrow picks the end it came from', function()
  local camera = cameraWith({ 0.1, 0.2, 0.3 })
  eq(navigate.nextKeyframe(camera, nil), 1)
  eq(navigate.previousKeyframe(camera, nil), 3)
end)

test('no camera at all is not a crash', function()
  eq(navigate.nextKeyframe(nil, 1), nil)
  eq(navigate.previousKeyframe(nil, 1), nil)
end)

--------------------------------------------------------------------------
-- Cameras
--------------------------------------------------------------------------

test('the arrows walk the cameras in lap order', function()
  local cameras = { {}, {}, {} }
  eq(navigate.nextCamera(cameras, 1), 2)
  eq(navigate.previousCamera(cameras, 3), 2)
end)

test('they stop at the first and the last', function()
  local cameras = { {}, {}, {} }
  eq(navigate.nextCamera(cameras, 3), nil)
  eq(navigate.previousCamera(cameras, 1), nil)
end)

test('an empty file has nowhere to go', function()
  eq(navigate.nextCamera({}, 1), nil)
  eq(navigate.previousCamera({}, 1), nil)
  eq(navigate.nextCamera(nil, 1), nil)
end)

test('with none selected, an arrow picks the end it came from', function()
  local cameras = { {}, {}, {} }
  eq(navigate.nextCamera(cameras, nil), 1)
  eq(navigate.previousCamera(cameras, nil), 3)
end)

--------------------------------------------------------------------------
-- Where a step lands on the track
--------------------------------------------------------------------------

test('a keyframe has its own place on the lap', function()
  local camera = cameraWith({ 0.1, 0.55, 0.9 })
  near(navigate.positionOf(camera, 2), 0.55)
end)

test('a camera without a keyframe in mind means where it takes over', function()
  local camera = cameraWith({ 0.1, 0.55 })
  camera.camera_in = 0.42
  near(navigate.positionOf(camera, nil), 0.42)
end)

test('a keyframe with no position of its own has none to give', function()
  local camera = { camera_in = 0.3, keyframes = { { keyframe = 0 / 0 }, {} } }
  eq(navigate.positionOf(camera, 1), nil)
  eq(navigate.positionOf(camera, 2), nil)
  eq(navigate.positionOf(camera, 9), nil)
end)

--------------------------------------------------------------------------
-- Is the replay running?
--------------------------------------------------------------------------

test('a running replay reads as running', function()
  local state = playstate.new()
  for _ = 1, 10 do playstate.update(state, 0.016) end
  eq(state.paused, false)
end)

test('a paused one reads as paused, after a moment', function()
  -- Assetto Corsa says so itself: getGameDeltaT is zero when the sim or the
  -- replay is paused, whoever paused it.
  local state = playstate.new()
  for _ = 1, 10 do playstate.update(state, 0.016) end
  for _ = 1, 10 do playstate.update(state, 0) end
  eq(state.paused, true)
end)

test('one odd frame does not flip the icon', function()
  -- A stutter, a load, a frame the game skipped. An icon that blinks is the
  -- same lie told faster.
  local state = playstate.new()
  for _ = 1, 10 do playstate.update(state, 0.016) end

  eq(playstate.update(state, 0), false, 'one zero frame changes nothing')
  eq(playstate.update(state, 0.016), false)
  eq(state.paused, false)
end)

test('it takes a run of agreeing frames to change the answer', function()
  local state = playstate.new()
  for _ = 1, 10 do playstate.update(state, 0.016) end

  for i = 1, playstate.STEADY_FRAMES - 1 do
    eq(playstate.update(state, 0), false, 'still playing after ' .. i)
  end
  eq(playstate.update(state, 0), true, 'and now it is paused')
end)

test('no reading at all leaves the answer where it was', function()
  -- A build without the call, or a frame that answered nothing. Better to
  -- hold the last honest reading than announce one never taken.
  local state = playstate.new()
  for _ = 1, 10 do playstate.update(state, 0.016) end

  eq(playstate.update(state, nil), false)
  eq(playstate.update(state, 0 / 0), false)
  eq(state.paused, false)
end)

test('a pause that flickers back does not leave it stuck', function()
  local state = playstate.new()
  for _ = 1, 10 do playstate.update(state, 0) end
  eq(state.paused, true)

  for _ = 1, 10 do playstate.update(state, 0.016) end
  eq(state.paused, false)
end)
