--[[
  Tests for ui/band.lua, the lap laid out as a ribbon.

  Same bargain as the map's tests: these cannot say it looks right, only what
  reached the screen and what a click on it means. The geometry is arithmetic
  -- a lap is a line of known length -- so where things land can be checked
  exactly rather than by eye.
]]

local runner = require('tests/runner')
local fakes = require('tests/fakes/csp')
local band = require('ui/band')
local theme = require('ui/theme')

local test, eq, near = runner.test, runner.eq, runner.near

local WIDTH = 400
local ORIGIN_X, ORIGIN_Y = 17, 23

local function cameras(starts)
  local out = {}
  for i = 1, #starts do out[i] = { camera_in = starts[i], camera_pit = false } end
  return out
end

local function keyframesAt(positions)
  local out = {}
  for i = 1, #positions do out[i] = { keyframe = positions[i] } end
  return out
end

---Draw one frame, optionally with the mouse somewhere on the band.
local function draw(state, mouseX, clickedIt)
  local handle = fakes.install({
    clicks = clickedIt and { ['##trackBand'] = true } or {},
    itemHovered = mouseX ~= nil,
    mouseX = mouseX ~= nil and (ORIGIN_X + mouseX) or -1,
    mouseY = ORIGIN_Y + 10,
  })
  local camera, keyframe = band.draw(state, WIDTH)
  handle.restoreIo()
  return camera, keyframe, handle.drawn
end

local function rects(drawn)
  local out = {}
  for i = 1, #drawn do
    if drawn[i].op == 'drawRectFilled' then out[#out + 1] = drawn[i] end
  end
  return out
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

test('each camera gets a stretch of the ribbon, in lap order', function()
  local _, _, drawn = draw({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 })
  local bars = rects(drawn)

  -- One background plus two cameras.
  eq(#bars, 3)
  near(bars[2].x, ORIGIN_X, 1, 'the first camera starts at the line')
  near(bars[3].x, ORIGIN_X + WIDTH / 2, 1, 'the second at half a lap')
end)

test('the ribbon fills the width exactly, whatever the cameras', function()
  local _, _, drawn = draw({ cameras = cameras({ 0.2, 0.7, 0.75 }), cameraIndex = 1 })
  local bars = rects(drawn)

  local left, right = nil, nil
  for i = 2, #bars do
    if left == nil or bars[i].x < left then left = bars[i].x end
    if right == nil or bars[i].x2 > right then right = bars[i].x2 end
  end
  near(left, ORIGIN_X, 0.001, 'no gap at the start line')
  near(right, ORIGIN_X + WIDTH, 1.001, 'and none at the finish')
end)

test('nothing is drawn outside the band', function()
  local _, _, drawn = draw({
    cameras = cameras({ 0, 0.3, 0.9 }), cameraIndex = 2,
    camera = { keyframes = keyframesAt({ 0, 0.5, 1 }) }, keyframeIndex = 1,
    trackPos = 0.42,
  })
  for i = 1, #drawn do
    local call = drawn[i]
    if call.x ~= nil then
      eq(call.x >= ORIGIN_X - theme.bandDiamond
        and call.x <= ORIGIN_X + WIDTH + theme.bandDiamond, true,
        call.op .. ' at x=' .. tostring(call.x))
      eq(call.y >= ORIGIN_Y and call.y <= ORIGIN_Y + theme.bandHeight, true,
        call.op .. ' at y=' .. tostring(call.y))
    end
  end
end)

test('the camera being edited is red, the live one pale', function()
  local _, _, drawn = draw({
    cameras = cameras({ 0, 0.33, 0.66 }), cameraIndex = 2, liveCameraIndex = 3,
  })
  local reds, pales = 0, 0
  for _, bar in ipairs(rects(drawn)) do
    if bar.colour == theme.stripActive then reds = reds + 1 end
    if bar.colour == theme.stripLive then pales = pales + 1 end
  end
  eq(reds, 1)
  eq(pales, 1)
end)

test('the camera holding the start line is drawn at both ends', function()
  local _, _, drawn = draw({
    cameras = cameras({ 0.25, 0.5 }), cameraIndex = 2,
  })
  local reds = {}
  for _, bar in ipairs(rects(drawn)) do
    if bar.colour == theme.stripActive then reds[#reds + 1] = bar end
  end
  eq(#reds, 2, 'camera 2 runs to the finish and carries on past the line')
  near(reds[1].x, ORIGIN_X, 1, 'one piece at the very start')
end)

test('the car is a line across the whole band', function()
  local _, _, drawn = draw({
    cameras = cameras({ 0 }), cameraIndex = 1, trackPos = 0.25,
  })
  local line = nil
  for i = 1, #drawn do
    if drawn[i].op == 'drawLine' then line = drawn[i] end
  end
  eq(line ~= nil, true)
  near(line.x, ORIGIN_X + WIDTH * 0.25, 1)
  near(line.y, ORIGIN_Y, 0.001, 'from the top')
  near(line.y2, ORIGIN_Y + theme.bandHeight, 0.001, 'to the bottom')
end)

test('only the selected camera shows its keyframes', function()
  local _, _, drawn = draw({
    cameras = cameras({ 0, 0.5 }), cameraIndex = 1,
    camera = { keyframes = keyframesAt({ 0.1, 0.2, 0.3 }) }, keyframeIndex = 2,
  })
  local diamonds = 0
  for i = 1, #drawn do
    if drawn[i].op == 'drawQuadFilled' then diamonds = diamonds + 1 end
  end
  eq(diamonds, 3, 'three keyframes, three markers')
end)

test('a keyframe outside the lap is not drawn at the edge', function()
  -- A keyframe that has not been placed yet, or a file with something odd in
  -- it. Clamping would put a marker on the start line that is not there.
  local _, _, drawn = draw({
    cameras = cameras({ 0 }), cameraIndex = 1,
    camera = { keyframes = keyframesAt({ 0.5, 1.4, 0 / 0 }) }, keyframeIndex = 1,
  })
  local diamonds = 0
  for i = 1, #drawn do
    if drawn[i].op == 'drawQuadFilled' then diamonds = diamonds + 1 end
  end
  eq(diamonds, 1)
end)

test('a band with no cameras draws without raising', function()
  local _, _, drawn = draw({ cameras = nil, trackPos = 0.5 })
  eq(#drawn > 0, true, 'the background at least')
end)

--------------------------------------------------------------------------
-- Clicking
--------------------------------------------------------------------------

test('clicking a stretch selects the camera that covers it', function()
  local state = { cameras = cameras({ 0, 0.25, 0.5, 0.75 }), cameraIndex = 1 }
  eq(draw(state, WIDTH * 0.1, true), 1)
  eq(draw(state, WIDTH * 0.3, true), 2)
  eq(draw(state, WIDTH * 0.6, true), 3)
  eq(draw(state, WIDTH * 0.9, true), 4)
end)

test('clicking before the first camera selects the one holding the line', function()
  local state = { cameras = cameras({ 0.4, 0.6 }), cameraIndex = 1 }
  eq(draw(state, WIDTH * 0.1, true), 2)
end)

test('clicking a keyframe selects the keyframe, not the camera', function()
  -- Diamonds are small and sit on the ribbon: anything else would make them
  -- unclickable.
  local state = {
    cameras = cameras({ 0, 0.5 }), cameraIndex = 1,
    camera = { keyframes = keyframesAt({ 0.2, 0.8 }) }, keyframeIndex = 1,
  }
  local camera, keyframe = draw(state, WIDTH * 0.2, true)
  eq(keyframe, 1)
  eq(camera, nil, 'one or the other, never both')
end)

test('clicking beside a keyframe still selects the camera', function()
  local state = {
    cameras = cameras({ 0, 0.5 }), cameraIndex = 1,
    camera = { keyframes = keyframesAt({ 0.2 }) }, keyframeIndex = 1,
  }
  local camera, keyframe = draw(state, WIDTH * 0.35, true)
  eq(keyframe, nil)
  eq(camera, 1)
end)

test('hovering without clicking selects nothing', function()
  local state = { cameras = cameras({ 0, 0.5 }), cameraIndex = 1 }
  local camera, keyframe = draw(state, WIDTH * 0.6, false)
  eq(camera, nil)
  eq(keyframe, nil)
end)
