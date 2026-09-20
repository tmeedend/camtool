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
  local did = band.draw(state, WIDTH)
  handle.restoreIo()
  return did.camera, did.keyframe, handle.drawn
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
  local did = band.draw(state, WIDTH)
  handle.restoreIo()
  return did.move, did.camera, did.keyframe
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
  local rename = band.draw(state, WIDTH).rename
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
  local rename = band.draw(state, WIDTH).rename
  handle.restoreIo()
  eq(rename, nil)

  -- And the field is gone: nothing comes back on the next frame either.
  handle = fakes.install({ typed = 'nope', enterPressed = true })
  local after = band.draw(state, WIDTH).rename
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
  local rename = band.draw(state, WIDTH).rename
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
  local rename = band.draw(state, WIDTH).rename
  handle.restoreIo()
  eq(rename, nil)
  band.reset()
end)

--------------------------------------------------------------------------
-- The diamonds stay put
--------------------------------------------------------------------------

test('a diamond cannot be dragged from the ribbon', function()
  -- They could for one round, and it came straight back out: four pixels on a
  -- ribbon you also click to select cameras means a slightly missed click
  -- moves a keyframe, and that is only noticed in the edit. The KEYFRAME
  -- field moves them instead.
  band.reset()
  local state = {
    cameras = cameras({ 0 }), cameraIndex = 1,
    camera = { keyframes = keyframesAt({ 0.2 }) }, keyframeIndex = 1,
  }

  local handle = fakes.install({
    itemActive = true, itemHovered = true,
    mouseX = ORIGIN_X + WIDTH * 0.2, mouseY = ORIGIN_Y + 10,
  })
  local did = band.draw(state, WIDTH)
  handle.restoreIo()

  eq(did.moveKeyframe, nil)
  eq(state.camera.keyframes[1].keyframe, 0.2, 'and nothing moved')
  band.reset()
end)

test('the camera handle is still draggable', function()
  -- A deliberate grab on a marked grip is not a stray click, and this is the
  -- gesture the ribbon is for.
  band.reset()
  local state = { cameras = cameras({ 0.25, 0.75 }), cameraIndex = 1 }

  local handle = fakes.install({
    itemActive = true, itemHovered = true,
    mouseX = ORIGIN_X + WIDTH * 0.25, mouseY = ORIGIN_Y + 10,
  })
  local did = band.draw(state, WIDTH)
  handle.restoreIo()

  eq(did.move ~= nil, true)
  band.reset()
end)


--------------------------------------------------------------------------
-- Adding and removing from the ribbon
--------------------------------------------------------------------------

---Right click somewhere, then pick an item from the menu it opens.
local function pickFromMenu(state, mouseX, item)
  band.reset()

  -- The right click, which is what records where the menu is about.
  local handle = fakes.install({
    itemHovered = true, rightClicked = true,
    mouseX = ORIGIN_X + mouseX, mouseY = ORIGIN_Y + 10,
  })
  band.draw(state, WIDTH)
  handle.restoreIo()

  -- And the frame where the menu is open and something in it is chosen.
  handle = fakes.install({
    itemHovered = true, popupOpen = true,
    clicks = item ~= nil and { [item] = true } or {},
    mouseX = -1, mouseY = -1,
  })
  local did = band.draw(state, WIDTH)
  handle.restoreIo()
  band.reset()
  return did
end

test('the menu adds a camera where the click landed', function()
  -- Not at the playhead: the right click has already said where.
  local did = pickFromMenu({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 },
    WIDTH * 0.3, 'Add a camera here')
  eq(did.addCamera ~= nil, true)
  near(did.addCamera, 0.3, 0.01)
end)

test('the menu removes the camera that was under the pointer', function()
  -- And not the selected one, which is the strip's minus and a different
  -- thing entirely.
  local did = pickFromMenu(
    { cameras = cameras({ 0, 0.25, 0.5, 0.75 }), cameraIndex = 1 },
    WIDTH * 0.6, 'Remove this camera')
  eq(did.removeCamera, 3)
end)

test('the position is the one from the right click, not from later', function()
  -- By the time an item is chosen the pointer is on the menu, nowhere near
  -- the ribbon. Taking the position then would put the camera anywhere.
  local did = pickFromMenu({ cameras = cameras({ 0 }), cameraIndex = 1 },
    WIDTH * 0.8, 'Add a camera here')
  near(did.addCamera, 0.8, 0.01)
end)

test('opening the menu and choosing nothing changes nothing', function()
  local did = pickFromMenu({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 },
    WIDTH * 0.3, nil)
  eq(did.addCamera, nil)
  eq(did.removeCamera, nil)
end)

test('a menu choice outranks anything else happening that frame', function()
  -- It is the one thing the user asked for explicitly. Selecting a camera
  -- underneath it as well would be two edits from one click.
  local did = pickFromMenu({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 },
    WIDTH * 0.3, 'Add a camera here')
  eq(did.camera, nil)
  eq(did.keyframe, nil)
end)

--------------------------------------------------------------------------
-- The name the track suggests
--------------------------------------------------------------------------

---Double click a segment and read what the field was filled with.
---
---An empty field comes back as '' rather than nil: the band reports what was
---typed, and core/edit is what turns an empty name into no name at all. That
---split is deliberate -- the band should not be deciding what an empty string
---means.
local function renameSuggestion(state, mouseX)
  band.reset()
  local handle = fakes.install({
    itemHovered = true, mouseDoubleClicked = true,
    mouseX = ORIGIN_X + mouseX, mouseY = ORIGIN_Y + 10,
  })
  band.draw(state, WIDTH)
  handle.restoreIo()

  -- Whatever is in the field is what a plain Enter would commit.
  handle = fakes.install({ enterPressed = true })
  local rename = band.draw(state, WIDTH).rename
  handle.restoreIo()
  band.reset()
  return rename ~= nil and rename.name or nil
end

test('naming an unnamed camera offers the name of where it stands', function()
  -- Spa really does answer Kemmel Straight there. Offered, not imposed: the
  -- field selects all, so a keystroke replaces it.
  eq(renameSuggestion({
    cameras = named({ { 0, nil }, { 0.5, nil } }), cameraIndex = 1,
    sectionNameAt = function(at) return at >= 0.5 and 'Kemmel Straight' or nil end,
  }, WIDTH * 0.75), 'Kemmel Straight')
end)

test('a camera on an unnamed stretch gets an empty field', function()
  -- Most of a lap is not in any section, and inventing something there would
  -- be worse than leaving it blank.
  eq(renameSuggestion({
    cameras = named({ { 0, nil } }), cameraIndex = 1,
    sectionNameAt = function() return nil end,
  }, WIDTH * 0.5), '', 'nothing offered, so nothing in the field')
end)

test('a camera that already has a name keeps it, suggestion or not', function()
  eq(renameSuggestion({
    cameras = named({ { 0, 'My Corner' } }), cameraIndex = 1,
    sectionNameAt = function() return 'Eau Rouge' end,
  }, WIDTH * 0.5), 'My Corner')
end)

test('the suggestion is asked for where the camera takes over', function()
  -- Not where the double click landed, which can be anywhere in the segment.
  local askedAt = nil
  renameSuggestion({
    cameras = named({ { 0.25, nil } }), cameraIndex = 1,
    sectionNameAt = function(at) askedAt = at return nil end,
  }, WIDTH * 0.9)
  near(askedAt, 0.25, 1e-9)
end)

test('a panel with no track to ask still renames', function()
  eq(renameSuggestion({
    cameras = named({ { 0, nil } }), cameraIndex = 1,
  }, WIDTH * 0.5), '', 'no suggestion to be had, and no error either')
end)

--------------------------------------------------------------------------
-- Counting cameras a segment is too thin to name
--------------------------------------------------------------------------

local function ticks(drawn)
  local n = 0
  for i = 1, #drawn do
    if drawn[i].op == 'drawLine' and drawn[i].colour == theme.bandTick then
      n = n + 1
    end
  end
  return n
end

test('every hand-over gets a tick, however thin the segment', function()
  -- ATR's Spa file: 22 cameras, the last starting at 0.99579 -- five pixels
  -- of ribbon, too thin for a digit. The ribbon read as 21 cameras until
  -- these went in.
  local starts = {
    0.0, 0.05506, 0.09675, 0.13821, 0.20548, 0.26144, 0.31154, 0.36234,
    0.39924, 0.44898, 0.5222, 0.57312, 0.63371, 0.65591, 0.69876, 0.71364,
    0.72721, 0.7869, 0.82752, 0.90536, 0.93002, 0.99579,
  }
  local _, _, drawn = draw({ cameras = cameras(starts), cameraIndex = 1 })

  -- One per camera except the first, which begins at the start line and
  -- needs no mark to say so.
  eq(ticks(drawn), 21, 'so 22 cameras can be counted off the ribbon')
end)

test('a camera starting at the line needs no tick of its own', function()
  local _, _, drawn = draw({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 })
  eq(ticks(drawn), 1)
end)

test('the wrapped tail is not a hand-over and gets no tick', function()
  -- It is the same camera as the one at the end of the lap, drawn twice.
  local _, _, drawn = draw({ cameras = cameras({ 0.25, 0.75 }), cameraIndex = 1 })
  eq(ticks(drawn), 2, 'two cameras, two starts, and no third mark')
end)

--------------------------------------------------------------------------
-- Click to bring the car here
--------------------------------------------------------------------------

---Click the ribbon, optionally with shift held.
local function clickBand(state, mouseX, shift)
  band.reset()
  local handle = fakes.install({
    clicks = { ['##trackBand'] = true },
    itemHovered = true, shiftHeld = shift == true,
    mouseX = ORIGIN_X + mouseX, mouseY = ORIGIN_Y + 10,
  })
  local did = band.draw(state, WIDTH)
  handle.restoreIo()
  band.reset()
  return did
end

test('a plain click selects the camera and asks for the car', function()
  local did = clickBand({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 },
    WIDTH * 0.3)
  eq(did.camera, 1, 'the camera whose stretch was clicked')
  near(did.seekTo, 0.3, 0.01, 'and the exact spot within it')
end)

test('shift selects without touching the replay', function()
  -- For picking a camera without losing the moment being watched.
  local did = clickBand({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 },
    WIDTH * 0.7, true)
  eq(did.camera, 2)
  eq(did.seekTo, nil)
end)

test('the spot asked for is where the click landed, not the camera start', function()
  local did = clickBand({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 },
    WIDTH * 0.85)
  eq(did.camera, 2, 'the second camera starts at half a lap')
  near(did.seekTo, 0.85, 0.01, 'but the car goes where the pointer was')
end)

test('hovering the ribbon says what clicking it will do', function()
  -- The status line at the bottom of the panel, which costs no height.
  local _, _, drawn = draw({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 },
    WIDTH * 0.3, false)
  local handle = fakes.install({ itemHovered = true, mouseX = ORIGIN_X + 10,
    mouseY = ORIGIN_Y + 10 })
  local did = band.draw({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 }, WIDTH)
  handle.restoreIo()

  eq(type(did.hint), 'string')
  eq(did.hint:find('Shift', 1, true) ~= nil, true, 'and names the modifier')
end)

test('the pointer changes over the ribbon', function()
  local handle = fakes.install({ itemHovered = true, mouseX = ORIGIN_X + 10,
    mouseY = ORIGIN_Y + 10 })
  band.draw({ cameras = cameras({ 0 }), cameraIndex = 1 }, WIDTH)
  handle.restoreIo()
  eq(handle.cursor, ui.MouseCursor.Hand)
end)

test('nothing is said or pointed at when the mouse is elsewhere', function()
  local handle = fakes.install({ itemHovered = false })
  local did = band.draw({ cameras = cameras({ 0 }), cameraIndex = 1 }, WIDTH)
  handle.restoreIo()
  eq(did.hint, nil)
  eq(handle.cursor, nil)
end)

test('the menu offers to bring the car, in so many words', function()
  local did = pickFromMenu({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 },
    WIDTH * 0.4, 'Bring the car here')
  near(did.seekTo, 0.4, 0.01)
  eq(did.addCamera, nil, 'and not the entry beside it')
end)
