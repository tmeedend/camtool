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

---Only the pieces of the ribbon itself: the background and the drag handle
---are rectangles too, and they run the full height.
local function ribbon(drawn)
  local out = {}
  local top = ORIGIN_Y + theme.bandHeight - theme.bandRibbon
  for _, bar in ipairs(rects(drawn)) do
    if math.abs(bar.y - top) < 0.001 then out[#out + 1] = bar end
  end
  return out
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

test('each camera gets a stretch of the ribbon, in lap order', function()
  local _, _, drawn = draw({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 })
  local bars = ribbon(drawn)

  eq(#bars, 2)
  near(bars[1].x, ORIGIN_X, 1, 'the first camera starts at the line')
  near(bars[2].x, ORIGIN_X + WIDTH / 2, 1, 'the second at half a lap')
end)

test('the ribbon fills the width exactly, whatever the cameras', function()
  local _, _, drawn = draw({ cameras = cameras({ 0.2, 0.7, 0.75 }), cameraIndex = 1 })
  local bars = ribbon(drawn)

  local left, right = nil, nil
  for i = 1, #bars do
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
  for _, bar in ipairs(ribbon(drawn)) do
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
  for _, bar in ipairs(ribbon(drawn)) do
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

--------------------------------------------------------------------------
-- Dragging where a camera takes over
--------------------------------------------------------------------------

---Press somewhere on the band and report what came back.
local function press(state, mouseX)
  local handle = fakes.install({
    itemActive = true, itemHovered = true,
    mouseX = ORIGIN_X + mouseX, mouseY = ORIGIN_Y + 10,
  })
  local camera, keyframe, move = band.draw(state, WIDTH)
  handle.restoreIo()
  return move, camera, keyframe
end

test('the selected camera shows a handle where it takes over', function()
  local _, _, drawn = draw({ cameras = cameras({ 0.25, 0.75 }), cameraIndex = 1 })
  local handle = nil
  for _, bar in ipairs(rects(drawn)) do
    if bar.colour == theme.stripActive
      and math.abs(bar.y - ORIGIN_Y) < 0.001 then handle = bar end
  end
  eq(handle ~= nil, true)
  near((handle.x + handle.x2) / 2, ORIGIN_X + WIDTH * 0.25, 1)
end)

test('pressing the handle and moving reports a new start', function()
  band.reset()
  local state = { cameras = cameras({ 0.25, 0.75 }), cameraIndex = 1 }

  local move = press(state, WIDTH * 0.25)
  eq(move ~= nil, true, 'the press landed on the handle')

  move = press(state, WIDTH * 0.4)
  near(move.position, 0.4, 0.01, 'and it follows the pointer')
  band.reset()
end)

test('a drag is one gesture from beginning to end', function()
  -- What keeps a drag across the whole ribbon to a single undo entry.
  band.reset()
  local state = { cameras = cameras({ 0.25, 0.75 }), cameraIndex = 1 }

  local first = press(state, WIDTH * 0.25)
  local later = press(state, WIDTH * 0.45)
  eq(first.gesture, later.gesture)

  -- Let go, press again: a new gesture, so a second undo entry.
  local released = fakes.install({ itemActive = false })
  band.draw(state, WIDTH)
  released.restoreIo()

  local again = press(state, WIDTH * 0.25)
  eq(again.gesture ~= first.gesture, true)
  band.reset()
end)

test('a press away from the handle does not grab it', function()
  -- Otherwise clicking a camera to select it would move the selected one.
  band.reset()
  local state = { cameras = cameras({ 0.25, 0.75 }), cameraIndex = 1 }
  eq(press(state, WIDTH * 0.6), nil)
  band.reset()
end)

test('a drag that merely passes over the handle cannot grab it', function()
  -- The press has to start on it. Dragging across the ribbon from elsewhere
  -- crosses the handle on the way, and would otherwise pick it up mid-flight.
  band.reset()
  local state = { cameras = cameras({ 0.5, 0.9 }), cameraIndex = 1 }

  eq(press(state, WIDTH * 0.1), nil, 'pressed well away from it')
  eq(press(state, WIDTH * 0.5), nil, 'and passing over it changes nothing')
  band.reset()
end)

test('with no camera selected there is nothing to drag', function()
  band.reset()
  eq(press({ cameras = cameras({ 0.25 }), cameraIndex = nil }, WIDTH * 0.25), nil)
  band.reset()
end)

--------------------------------------------------------------------------
-- What each segment says it is
--------------------------------------------------------------------------

local function labels(drawn)
  local out = {}
  for i = 1, #drawn do
    if drawn[i].op == 'label' then out[#out + 1] = drawn[i] end
  end
  return out
end

local function named(list)
  local out = cameras({})
  for i, entry in ipairs(list) do
    out[i] = { id = i, camera_in = entry[1], name = entry[2], camera_pit = false }
  end
  return out
end

test('a segment wide enough shows the camera number', function()
  local _, _, drawn = draw({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 })
  local written = labels(drawn)
  eq(#written, 2)
  eq(written[1].text, '1')
  eq(written[2].text, '2')
end)

test('a named camera shows its name instead', function()
  -- The whole point of names: "Eau Rouge" says where the shot is, 14 does not.
  local _, _, drawn = draw({
    cameras = named({ { 0, 'Eau Rouge' }, { 0.5, nil } }), cameraIndex = 1,
  })
  local written = labels(drawn)
  eq(written[1].text, 'Eau Rouge')
  eq(written[2].text, '2', 'and an unnamed one still shows its rank')
end)

test('a name too long for its segment falls back to the number', function()
  -- Twenty cameras on a 400 pixel band is 20 pixels each: room for a digit,
  -- not for a name.
  local starts, names = {}, {}
  for i = 1, 20 do
    starts[i] = (i - 1) / 20
    names[i] = { starts[i], 'Some Long Corner Name' }
  end

  local _, _, drawn = draw({ cameras = named(names), cameraIndex = nil })
  for _, label in ipairs(labels(drawn)) do
    eq(#label.text <= 2, true, 'got "' .. label.text .. '" in a 20px segment')
  end
end)

test('a segment too thin for anything stays blank', function()
  local starts = {}
  for i = 1, 60 do starts[i] = (i - 1) / 60 end

  local _, _, drawn = draw({ cameras = cameras(starts), cameraIndex = nil })
  eq(#labels(drawn), 0, 'sixty cameras on 400 pixels: nothing legible to write')
end)

test('the selected camera says who it is however thin it gets', function()
  -- What keeps a hundred cameras readable rather than a row of clipped stubs.
  local starts = {}
  for i = 1, 60 do starts[i] = (i - 1) / 60 end

  local _, _, drawn = draw({ cameras = cameras(starts), cameraIndex = 30 })
  local written = labels(drawn)
  eq(#written, 1)
  eq(written[1].text, '30')
end)

test('a label is drawn inside its own segment, not across its neighbour', function()
  local _, _, drawn = draw({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 })
  local written = labels(drawn)
  eq(written[1].x >= ORIGIN_X, true)
  eq(written[1].x2 <= ORIGIN_X + WIDTH / 2, true, 'the first stays in its half')
  eq(written[2].x >= ORIGIN_X + WIDTH / 2, true)
end)

--------------------------------------------------------------------------
-- Renaming in place
--------------------------------------------------------------------------

---Double click a segment, then hand back the fake so the field can be driven.
local function openRename(state, mouseX)
  local handle = fakes.install({
    itemHovered = true, mouseDoubleClicked = true,
    mouseX = ORIGIN_X + mouseX, mouseY = ORIGIN_Y + 10,
  })
  band.draw(state, WIDTH)
  handle.restoreIo()
end

test('double clicking a segment opens a field over it', function()
  band.reset()
  local state = { cameras = cameras({ 0, 0.5 }), cameraIndex = 1 }
  openRename(state, WIDTH * 0.75)

  -- The field is drawn on the next frame, with nothing typed yet.
  local handle = fakes.install({})
  band.draw(state, WIDTH)
  handle.restoreIo()
  band.reset()
end)

test('typing a name and pressing enter reports it', function()
  band.reset()
  local state = { cameras = named({ { 0, nil }, { 0.5, nil } }), cameraIndex = 1 }
  openRename(state, WIDTH * 0.75)

  local handle = fakes.install({ typed = 'Bus Stop', enterPressed = true })
  local _, _, _, rename = band.draw(state, WIDTH)
  handle.restoreIo()

  eq(rename ~= nil, true)
  eq(rename.index, 2, 'the segment that was double clicked')
  eq(rename.name, 'Bus Stop')
  band.reset()
end)

test('escape drops the rename', function()
  band.reset()
  local state = { cameras = named({ { 0, nil } }), cameraIndex = 1 }
  openRename(state, WIDTH * 0.5)

  local handle = fakes.install({ typed = 'nope', keyPressed = 27 })
  local _, _, _, rename = band.draw(state, WIDTH)
  handle.restoreIo()
  eq(rename, nil)

  -- And the field is gone: nothing comes back on the next frame either.
  handle = fakes.install({ typed = 'nope', enterPressed = true })
  local _, _, _, after = band.draw(state, WIDTH)
  handle.restoreIo()
  eq(after, nil, 'the field closed rather than staying open')
  band.reset()
end)

test('renaming follows the camera, not the place it was in', function()
  -- The rename is held by id. Insert a camera ahead of the one being renamed
  -- and its rank changes underneath the field; the name must still land on
  -- the camera that was double clicked.
  band.reset()
  local cameraList = named({ { 0.1, nil }, { 0.6, nil } })
  local state = { cameras = cameraList, cameraIndex = 1 }
  openRename(state, WIDTH * 0.8)

  -- A camera appears in front of it, as adding one at the playhead would.
  table.insert(cameraList, 2, { id = 99, camera_in = 0.3, camera_pit = false })

  local handle = fakes.install({ typed = 'Eau Rouge', enterPressed = true })
  local _, _, _, rename = band.draw(state, WIDTH)
  handle.restoreIo()

  eq(rename.index, 3, 'it is the third camera now, and still the right one')
  eq(cameraList[rename.index].id, 2, 'the camera that was double clicked')
  band.reset()
end)

test('a camera deleted while being renamed closes the field', function()
  band.reset()
  local cameraList = named({ { 0.1, nil }, { 0.6, nil } })
  local state = { cameras = cameraList, cameraIndex = 1 }
  openRename(state, WIDTH * 0.8)

  table.remove(cameraList, 2)

  local handle = fakes.install({ typed = 'gone', enterPressed = true })
  local _, _, _, rename = band.draw(state, WIDTH)
  handle.restoreIo()
  eq(rename, nil)
  band.reset()
end)

--------------------------------------------------------------------------
-- Dragging a keyframe
--------------------------------------------------------------------------

test('pressing a diamond and moving reports a new position', function()
  band.reset()
  local state = {
    cameras = cameras({ 0, 0.5 }), cameraIndex = 1,
    camera = { keyframes = keyframesAt({ 0.2, 0.8 }) }, keyframeIndex = 1,
  }

  local _, _, _, _, move = select(1, (function()
    local handle = fakes.install({
      itemActive = true, itemHovered = true,
      mouseX = ORIGIN_X + WIDTH * 0.2, mouseY = ORIGIN_Y + 10,
    })
    local a, b, c, d, e = band.draw(state, WIDTH)
    handle.restoreIo()
    return a, b, c, d, e
  end)())

  eq(move ~= nil, true, 'the press landed on a diamond')
  eq(rawequal(move.keyframe, state.camera.keyframes[1]), true,
    'and it is holding the keyframe itself, not its place in the list')
  band.reset()
end)

---Press somewhere and hand back the keyframe move, if any.
local function pressKeyframe(state, mouseX)
  local handle = fakes.install({
    itemActive = true, itemHovered = true,
    mouseX = ORIGIN_X + mouseX, mouseY = ORIGIN_Y + 10,
  })
  local _, _, _, _, move = band.draw(state, WIDTH)
  handle.restoreIo()
  return move
end

test('the drag follows the pointer along the lap', function()
  band.reset()
  local state = {
    cameras = cameras({ 0 }), cameraIndex = 1,
    camera = { keyframes = keyframesAt({ 0.2 }) }, keyframeIndex = 1,
  }

  eq(pressKeyframe(state, WIDTH * 0.2) ~= nil, true)
  local move = pressKeyframe(state, WIDTH * 0.65)
  near(move.position, 0.65, 0.01)
  band.reset()
end)

test('a whole keyframe drag is one gesture', function()
  band.reset()
  local state = {
    cameras = cameras({ 0 }), cameraIndex = 1,
    camera = { keyframes = keyframesAt({ 0.2 }) }, keyframeIndex = 1,
  }

  local first = pressKeyframe(state, WIDTH * 0.2)
  local later = pressKeyframe(state, WIDTH * 0.5)
  eq(first.gesture, later.gesture)

  local released = fakes.install({ itemActive = false })
  band.draw(state, WIDTH)
  released.restoreIo()

  eq(pressKeyframe(state, WIDTH * 0.2).gesture ~= first.gesture, true)
  band.reset()
end)

test('a diamond wins over the camera handle underneath it', function()
  -- Four pixels wide and drawn on top: anything else would make it
  -- impossible to grab, since the handle spans the full height of the band.
  band.reset()
  local state = {
    cameras = cameras({ 0.3, 0.8 }), cameraIndex = 1,
    camera = { keyframes = keyframesAt({ 0.3 }) }, keyframeIndex = 1,
  }

  local move = pressKeyframe(state, WIDTH * 0.3)
  eq(move ~= nil, true, 'the keyframe, not the camera start')
  band.reset()
end)

test('a press away from any diamond drags no keyframe', function()
  band.reset()
  local state = {
    cameras = cameras({ 0 }), cameraIndex = 1,
    camera = { keyframes = keyframesAt({ 0.2 }) }, keyframeIndex = 1,
  }
  eq(pressKeyframe(state, WIDTH * 0.7), nil)
  band.reset()
end)

test('a drag passing over a diamond does not pick it up', function()
  band.reset()
  local state = {
    cameras = cameras({ 0 }), cameraIndex = 1,
    camera = { keyframes = keyframesAt({ 0.5 }) }, keyframeIndex = 1,
  }
  eq(pressKeyframe(state, WIDTH * 0.1), nil, 'pressed away from it')
  eq(pressKeyframe(state, WIDTH * 0.5), nil, 'and crossing it changes nothing')
  band.reset()
end)
