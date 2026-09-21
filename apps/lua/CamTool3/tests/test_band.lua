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

-- The widget starts with the ruler, so everything about the cameras is
-- measured from under it. Written once here rather than spelled out in each
-- case: the ruler's height is the panel's business, not these tests'.
local BAND_TOP = ORIGIN_Y + theme.bandRulerHeight
local BAND_BOTTOM = BAND_TOP + theme.bandHeight

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
  local top = BAND_BOTTOM - theme.bandRibbon
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
  near(line.y, ORIGIN_Y, 0.001, 'from the top of the ruler')
  near(line.y2, BAND_BOTTOM, 0.001, 'to the bottom of the ribbon')
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
    itemActive = '##trackBand', itemHovered = true,
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
      and math.abs(bar.y - BAND_TOP) < 0.001 then handle = bar end
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

test('a named camera still shows its number, never its name', function()
  -- The label used to be the name if it fitted and the number if it did not,
  -- so it changed nature with the room available -- which is not read, it is
  -- guessed. The number is what makes a set countable; the name goes to the
  -- status line, which never runs out of room.
  local _, _, drawn = draw({
    cameras = named({ { 0, 'Eau Rouge' }, { 0.5, nil } }), cameraIndex = 1,
  })
  local written = labels(drawn)
  eq(written[1].text, '1')
  eq(written[2].text, '2')
end)

test('a long name never widens what is written on a segment', function()
  -- Twenty cameras on a 400 pixel band is 20 pixels each. Named or not, each
  -- one says the same thing it would have said empty.
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

test('a segment too thin for a digit writes nothing, selected or not', function()
  -- The selected one used to write its name ABOVE the ribbon when it was too
  -- thin, which is the third state that made the label unreadable. Nothing is
  -- lost: the segment is still perfectly visible -- its colour and its
  -- hand-over tick are drawn whatever its width -- and hovering it names it.
  local starts = {}
  for i = 1, 60 do starts[i] = (i - 1) / 60 end

  local _, _, drawn = draw({ cameras = cameras(starts), cameraIndex = 30 })
  eq(#labels(drawn), 0)

  -- And the thin ones are still there to look at and to click.
  eq(#ribbon(drawn), 60, 'every camera still has its stretch of colour')
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

test('a camera with no identity of its own cannot be renamed', function()
  -- The rename is held by id, because a rank moves the moment a camera is
  -- inserted ahead of it. A camera without one -- which no document written
  -- since version 2 has -- would open a field that could never find its way
  -- back, so it opens nothing.
  band.reset()
  local state = { cameras = cameras({ 0, 0.5 }), cameraIndex = 1 }
  openRename(state, WIDTH * 0.75)

  local handle = fakes.install({ typed = 'nowhere', enterPressed = true })
  eq(band.draw(state, WIDTH).rename, nil, 'a field opened over nothing')
  eq(handle.focusRequests, 0)
  handle.restoreIo()
  band.reset()
end)

test('the field takes the keyboard on the frame it opens', function()
  -- Without this it appears as a grey box over the ribbon and swallows every
  -- keystroke, which reads as a rename that was never implemented. It is what
  -- Théo hit: he double clicked, typed, and nothing happened.
  band.reset()
  local state = { cameras = named({ { 0, nil }, { 0.5, nil } }), cameraIndex = 1 }
  openRename(state, WIDTH * 0.75)

  local handle = fakes.install({})
  band.draw(state, WIDTH)
  eq(handle.focusRequests, 1, 'the caret was never put in the field')
  handle.restoreIo()

  -- And asked for once. Asking every frame would take the keyboard back from
  -- wherever the user moved it.
  handle = fakes.install({ itemActive = '##bandRename' })
  band.draw(state, WIDTH)
  handle.restoreIo()

  handle = fakes.install({ itemActive = '##bandRename' })
  band.draw(state, WIDTH)
  eq(handle.focusRequests, 0, 'it went on grabbing the keyboard')
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

test('clicking away drops the rename', function()
  -- Not Escape: that is the game's key for leaving the replay, and the panel
  -- leaves it alone. See ui/parameter.
  band.reset()
  local state = { cameras = named({ { 0, nil } }), cameraIndex = 1 }
  openRename(state, WIDTH * 0.5)

  -- The field has the keyboard.
  local handle = fakes.install({ itemActive = '##bandRename', typed = 'nope' })
  band.draw(state, WIDTH)
  handle.restoreIo()

  -- And now the click lands somewhere else.
  handle = fakes.install({})
  local rename = band.draw(state, WIDTH).rename
  handle.restoreIo()
  eq(rename, nil)

  -- The field is gone: nothing comes back on the next frame either.
  handle = fakes.install({ typed = 'nope', enterPressed = true })
  local after = band.draw(state, WIDTH).rename
  handle.restoreIo()
  eq(after, nil, 'the field closed rather than staying open')
  band.reset()
end)

test('a camera with no name at all can still be clicked away from', function()
  -- THE ONE THAT STUCK. The field used to close on a click elsewhere only if
  -- something had been typed into it, so naming a camera that had no name --
  -- the only kind anyone wants to name -- left a grey box sitting on the
  -- ribbon with nothing able to shift it.
  band.reset()
  local state = { cameras = named({ { 0, nil } }), cameraIndex = 1 }
  openRename(state, WIDTH * 0.5)

  local handle = fakes.install({ itemActive = '##bandRename' })
  band.draw(state, WIDTH)
  handle.restoreIo()

  handle = fakes.install({})
  band.draw(state, WIDTH)
  handle.restoreIo()

  -- Gone: a frame that would otherwise commit finds no field to commit.
  handle = fakes.install({ typed = 'late', enterPressed = true })
  eq(band.draw(state, WIDTH).rename, nil)
  handle.restoreIo()
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
    itemActive = '##trackBand', itemHovered = true,
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
    itemActive = '##trackBand', itemHovered = true,
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

test('a click on a segment selects that camera', function()
  local did = clickBand({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 },
    WIDTH * 0.3)
  eq(did.camera, 1, 'the camera whose stretch was clicked')
end)

test('selecting a camera leaves the replay exactly where it was', function()
  -- It used to move the replay too, with Shift to hold it still. Choosing a
  -- camera to edit is not a request to go and watch it, and the moment you
  -- were looking at does not come back.
  local did = clickBand({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 },
    WIDTH * 0.3)
  eq(did.seekTo, nil)
  eq(did.scrubTo, nil)
end)

test('no modifier changes what a click on a segment does', function()
  -- A modifier that turns a behaviour off is a thing only its author knows
  -- about: nothing on screen can tell you it is there.
  local plain = clickBand({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 },
    WIDTH * 0.7)
  local shifted = clickBand({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 },
    WIDTH * 0.7, true)

  eq(shifted.camera, plain.camera)
  eq(shifted.seekTo, plain.seekTo)
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
  eq(did.hint:find('select', 1, true) ~= nil, true, 'and says what a click does')
  eq(did.hint:lower():find('shift', 1, true), nil,
    'and no longer offers a modifier that does nothing')
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

test('the last camera on the lap stays countable without a label', function()
  -- ATR's Spa file: camera 22 starts at 0.99579, five pixels from the end of
  -- the ribbon. Too thin for a digit, and that is fine now -- what says it is
  -- there is its colour and its hand-over tick, both drawn whatever the
  -- width, and hovering it says which one it is.
  local starts = {}
  for i = 1, 21 do starts[i] = (i - 1) / 22 end
  starts[22] = 0.99579

  local handle = fakes.install({
    itemHovered = true,
    mouseX = ORIGIN_X + WIDTH - 1, mouseY = ORIGIN_Y + 10,
  })
  local did = band.draw({ cameras = cameras(starts), cameraIndex = 22 }, WIDTH)
  handle.restoreIo()

  eq(#ribbon(handle.drawn), 22, 'every camera has its stretch')
  eq(did.hint:find('Camera 22', 1, true) ~= nil, true,
    'and the line at the foot of the panel says which: ' .. tostring(did.hint))
end)

test('nothing is ever written outside the coloured strip', function()
  -- The third state of the old label: too thin for a digit AND focused, so it
  -- wrote its name above the ribbon, in the row the keyframes live in. That
  -- is what made the label unpredictable.
  local starts = {}
  for i = 1, 40 do starts[i] = (i - 1) / 40 end

  local handle = fakes.install({
    itemHovered = true,
    mouseX = ORIGIN_X + WIDTH * 0.5, mouseY = ORIGIN_Y + 10,
  })
  band.draw({ cameras = named({ { 0, 'Eau Rouge' } }), cameraIndex = 1 }, WIDTH)
  band.draw({ cameras = cameras(starts), cameraIndex = 20 }, WIDTH)

  for i = 1, #handle.drawn do
    local call = handle.drawn[i]
    if call.op == 'label' and call.colour == theme.bandLabel then
      eq(call.y >= BAND_BOTTOM - theme.bandRibbon - 0.001, true,
        '"' .. call.text .. '" was written above the strip')
    end
  end
  handle.restoreIo()
end)

test('a label that fits is not ellipsised for want of a few pixels', function()
  -- The ellipsis wants room of its own, so "fits exactly" is not enough: the
  -- text comes out as "..." instead of itself.
  local handle = fakes.install({})
  band.draw({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 }, WIDTH)

  local written = nil
  for i = 1, #handle.drawn do
    if handle.drawn[i].op == 'label' then written = handle.drawn[i] break end
  end
  handle.restoreIo()

  eq(written.x2 - written.x >= ui.measureText(written.text).x
    + theme.bandLabelSlack - 2 * theme.bandLabelPadding, true)
end)

--------------------------------------------------------------------------
-- The ruler
--------------------------------------------------------------------------
-- The thin strip along the top: how far round the lap, and what the track
-- calls the place. What these can check is what reached the screen and where
-- it landed; whether sixteen pixels of it look right is the in-game list.

local LAP_M = 7004

local function sectionsAt(list)
  return require('core/sections').normalise(list)
end

---Everything drawn in one colour, in the order it was drawn.
local function inColour(drawn, colour)
  local out = {}
  for i = 1, #drawn do
    if drawn[i].colour == colour then out[#out + 1] = drawn[i] end
  end
  return out
end

local function textsIn(drawn, colour)
  local out = {}
  for _, item in ipairs(inColour(drawn, colour)) do
    if item.op == 'label' then out[#out + 1] = item.text end
  end
  return out
end

test('the ruler has a background of its own, above the cameras', function()
  -- The tint is what makes two zones out of one ribbon. Without it the split
  -- has to be explained, and an explained split is one nobody reads.
  local _, _, drawn = draw({ cameras = cameras({ 0 }), cameraIndex = 1,
    trackLength = LAP_M })

  local strip = inColour(drawn, theme.bandRulerBackground)[1]
  eq(strip ~= nil, true)
  near(strip.y, ORIGIN_Y, 0.001, 'at the very top')
  near(strip.y2, BAND_TOP, 0.001, 'and stopping where the cameras start')
  near(strip.x, ORIGIN_X, 0.001)
  near(strip.x2, ORIGIN_X + WIDTH, 0.001)
end)

test('distances are written along the lap', function()
  local _, _, drawn = draw({ cameras = cameras({ 0 }), cameraIndex = 1,
    trackLength = LAP_M })

  local written = textsIn(drawn, theme.bandRulerLabel)
  eq(#written > 1, true, 'a ruler with one number on it measures nothing')
  eq(written[1], '1 km', 'and it starts at a round distance')
end)

test('a marked distance sits where that distance is', function()
  -- A short circuit, so the labels come out in metres and can be read back
  -- as a number. On a long one they are kilometres and prove less.
  local _, _, drawn = draw({ cameras = cameras({ 0 }), cameraIndex = 1,
    trackLength = 1200 })

  local checked = 0
  for _, item in ipairs(inColour(drawn, theme.bandRulerLabel)) do
    if item.op == 'label' then
      local metres = tonumber(item.text:match('^([%d%.]+) m$'))
      local km = tonumber(item.text:match('^([%d%.]+) km$'))
      if km ~= nil then metres = km * 1000 end
      eq(metres ~= nil, true, item.text .. ' is not a distance')
      near(item.x - ORIGIN_X, WIDTH * metres / 1200, 5,
        item.text .. ' is written away from its own mark')
      checked = checked + 1
    end
  end
  eq(checked > 0, true, 'no distance was written at all')
end)

test('a track that reports no length gets marks it cannot invent', function()
  -- The game has been seen to answer nothing while a session is still coming
  -- up. The strip is still drawn; it simply has nothing to say yet.
  local _, _, drawn = draw({ cameras = cameras({ 0 }), cameraIndex = 1 })

  eq(#inColour(drawn, theme.bandRulerBackground), 1, 'the strip is there')
  eq(#textsIn(drawn, theme.bandRulerLabel), 0, 'and empty')
end)

test('a stretch the track has a name for is tinted and named', function()
  local _, _, drawn = draw({
    cameras = cameras({ 0 }), cameraIndex = 1, trackLength = LAP_M,
    sections = sectionsAt({ { from = 0.4, to = 0.6, text = 'Kemmel' } }),
  })

  local tint = inColour(drawn, theme.bandRulerSection)[1]
  eq(tint ~= nil, true)
  near(tint.x, ORIGIN_X + WIDTH * 0.4, 1)
  near(tint.x2, ORIGIN_X + WIDTH * 0.6, 1)

  eq(textsIn(drawn, theme.bandRulerName)[1], 'Kemmel')
end)

test('a name is written inside its own stretch, never across the next', function()
  local _, _, drawn = draw({
    cameras = cameras({ 0 }), cameraIndex = 1, trackLength = LAP_M,
    sections = sectionsAt({
      { from = 0.1, to = 0.3, text = 'Eau Rouge' },
      { from = 0.3, to = 0.5, text = 'Kemmel' },
    }),
  })

  for _, item in ipairs(inColour(drawn, theme.bandRulerName)) do
    if item.text == 'Eau Rouge' then
      eq(item.x >= ORIGIN_X + WIDTH * 0.1 - 0.001, true)
      eq(item.x2 <= ORIGIN_X + WIDTH * 0.3 + 0.001, true)
    end
  end
end)

test('a name too wide for its stretch is not written at all', function()
  -- Three dots in a strip this thin say a name is there, which the tint has
  -- already said.
  local _, _, drawn = draw({
    cameras = cameras({ 0 }), cameraIndex = 1, trackLength = LAP_M,
    sections = sectionsAt({
      { from = 0.5, to = 0.505, text = 'Bus Stop Chicane' },
    }),
  })

  eq(#textsIn(drawn, theme.bandRulerName), 0)
  eq(#inColour(drawn, theme.bandRulerSection), 1, 'but the tint still shows')
end)

test('a distance is not written on top of a name', function()
  -- One line of text in sixteen pixels, so the two cannot share the row. A
  -- name beats a number, and the marks stay either way.
  local covered = sectionsAt({ { from = 0, to = 1, text = 'All of it' } })
  local _, _, drawn = draw({ cameras = cameras({ 0 }), cameraIndex = 1,
    trackLength = LAP_M, sections = covered })

  eq(#textsIn(drawn, theme.bandRulerLabel), 0, 'every number gave way')
  eq(#inColour(drawn, theme.bandRulerTick) > 0, true, 'and every mark stayed')
end)

test('a number that would run off the end is not written', function()
  local _, _, drawn = draw({ cameras = cameras({ 0 }), cameraIndex = 1,
    trackLength = LAP_M })

  for _, item in ipairs(inColour(drawn, theme.bandRulerLabel)) do
    if item.op == 'label' then
      eq(item.x2 <= ORIGIN_X + WIDTH + 0.001, true,
        item.text .. ' is written half off the edge')
    end
  end
end)

test('the ruler is drawn whether or not there are cameras', function()
  local _, _, drawn = draw({ trackLength = LAP_M })
  eq(#inColour(drawn, theme.bandRulerBackground), 1)
  eq(#textsIn(drawn, theme.bandRulerLabel) > 0, true)
end)

--------------------------------------------------------------------------
-- The playhead
--------------------------------------------------------------------------

local function playheadLine(drawn)
  for i = #drawn, 1, -1 do
    if drawn[i].op == 'drawLine' and drawn[i].colour == theme.mapPlayhead then
      return drawn[i]
    end
  end
  return nil
end

local function playheadGrip(drawn)
  for i = #drawn, 1, -1 do
    if drawn[i].op == 'drawTriangleFilled'
      and drawn[i].colour == theme.mapPlayhead then return drawn[i] end
  end
  return nil
end

test('the playhead crosses both zones and grips in the ruler', function()
  -- The line has to cross the cameras, which is what it is read against. The
  -- triangle is the part anyone would think to take hold of, and it sits in
  -- the zone where taking hold of things is what happens.
  local _, _, drawn = draw({ cameras = cameras({ 0 }), cameraIndex = 1,
    trackPos = 0.4, trackLength = LAP_M })

  local line = playheadLine(drawn)
  eq(line ~= nil, true)
  near(line.y, ORIGIN_Y, 0.001, 'from the top of the ruler')
  near(line.y2, BAND_BOTTOM, 0.001, 'to the bottom of the ribbon')

  local grip = playheadGrip(drawn)
  eq(grip ~= nil, true)
  near(grip.x, line.x, 0.001, 'the point of the triangle is on the line')
  near(grip.y, BAND_TOP, 0.001, 'and it sits at the foot of the ruler')
end)

test('the playhead follows the replay without being asked', function()
  for _, at in ipairs({ 0, 0.25, 0.9 }) do
    local _, _, drawn = draw({ cameras = cameras({ 0 }), cameraIndex = 1,
      trackPos = at, trackLength = LAP_M })
    near(playheadLine(drawn).x, ORIGIN_X + WIDTH * at, 0.001)
  end
end)

test('nothing is drawn for a car the game cannot place', function()
  -- Out of a replay, or before one settles, there is no position. A playhead
  -- at zero would be a lie told with a straight face.
  local _, _, drawn = draw({ cameras = cameras({ 0 }), cameraIndex = 1,
    trackLength = LAP_M })

  eq(playheadLine(drawn), nil)
  eq(playheadGrip(drawn), nil)

  local _, _, nan = draw({ cameras = cameras({ 0 }), cameraIndex = 1,
    trackPos = 0 / 0, trackLength = LAP_M })
  eq(playheadLine(nan), nil)
end)

--------------------------------------------------------------------------
-- Dragging the playhead
--------------------------------------------------------------------------

---Hold the mouse down on the ruler at `mouseX` pixels along it.
local function holdRuler(state, mouseX)
  local handle = fakes.install({
    itemActive = '##bandRuler', itemHovered = '##bandRuler',
    mouseX = ORIGIN_X + mouseX, mouseY = ORIGIN_Y + 4,
  })
  local did = band.draw(state, WIDTH)
  handle.restoreIo()
  return did, handle
end

---And let go, the frame after.
local function releaseRuler(state)
  local handle = fakes.install({ itemActive = false, mouseX = -1 })
  local did = band.draw(state, WIDTH)
  handle.restoreIo()
  return did
end

test('pressing the ruler takes hold of the playhead', function()
  band.reset()
  local did = holdRuler({ cameras = cameras({ 0 }), cameraIndex = 1,
    trackPos = 0.1, trackLength = LAP_M }, WIDTH * 0.6)

  near(did.scrubTo, 0.6, 0.01, 'the replay is asked to follow')
  eq(did.seekTo, nil, 'and not to land yet')
  band.reset()
end)

test('the ruler can be taken hold of anywhere, not only on the grip', function()
  -- Aiming at five pixels of triangle before anything will move is a test of
  -- nerve, not a gesture. The grip says where the head is; the strip is what
  -- is dragged.
  band.reset()
  local state = { cameras = cameras({ 0 }), cameraIndex = 1,
    trackPos = 0.9, trackLength = LAP_M }
  local did = holdRuler(state, WIDTH * 0.15)

  near(did.scrubTo, 0.15, 0.01, 'far from where the head was')
  band.reset()
end)

test('the head follows the pointer, not the replay catching up', function()
  -- The replay is a tenth of a second behind by design. A head that snapped
  -- back to it would stutter under the finger holding it.
  band.reset()
  local state = { cameras = cameras({ 0 }), cameraIndex = 1,
    trackPos = 0.1, trackLength = LAP_M }
  local _, handle = holdRuler(state, WIDTH * 0.75)

  near(playheadLine(handle.drawn).x, ORIGIN_X + WIDTH * 0.75, 1)
  near(playheadGrip(handle.drawn).x, ORIGIN_X + WIDTH * 0.75, 1)
  band.reset()
end)

test('a drag follows the pointer along the ruler', function()
  band.reset()
  local state = { cameras = cameras({ 0 }), cameraIndex = 1,
    trackPos = 0.1, trackLength = LAP_M }

  for _, at in ipairs({ 0.2, 0.35, 0.5 }) do
    local did = holdRuler(state, WIDTH * at)
    near(did.scrubTo, at, 0.01)
    eq(did.seekTo, nil, 'still nothing exact while it runs')
  end
  band.reset()
end)

test('letting go asks for the exact spot, once', function()
  band.reset()
  local state = { cameras = cameras({ 0 }), cameraIndex = 1,
    trackPos = 0.1, trackLength = LAP_M }

  holdRuler(state, WIDTH * 0.42)
  local did = releaseRuler(state)

  near(did.seekTo, 0.42, 0.01, 'where the drag ended')
  eq(did.scrubTo, nil, 'and the following stops')

  local after = releaseRuler(state)
  eq(after.seekTo, nil, 'asked once, not every frame afterwards')
  band.reset()
end)

test('a click on the ruler is a drag of one frame', function()
  -- Which is why there is no separate handling of one: press and release, and
  -- the head is where it was clicked.
  band.reset()
  local state = { cameras = cameras({ 0 }), cameraIndex = 1,
    trackPos = 0.1, trackLength = LAP_M }

  holdRuler(state, WIDTH * 0.8)
  near(releaseRuler(state).seekTo, 0.8, 0.01)
  band.reset()
end)

test('a drag past the end of the ribbon stops at the line', function()
  band.reset()
  local state = { cameras = cameras({ 0 }), cameraIndex = 1,
    trackPos = 0.5, trackLength = LAP_M }

  near(holdRuler(state, WIDTH + 200).scrubTo, 1, 0.001)
  band.reset()
  near(holdRuler(state, -50).scrubTo, 0, 0.001, 'and at the start')
  band.reset()
end)

test('the pointer over the ruler says it can be dragged', function()
  band.reset()
  local handle = fakes.install({
    itemHovered = '##bandRuler',
    mouseX = ORIGIN_X + WIDTH * 0.3, mouseY = ORIGIN_Y + 4,
  })
  local did = band.draw({ cameras = cameras({ 0 }), cameraIndex = 1,
    trackLength = LAP_M }, WIDTH)
  handle.restoreIo()

  eq(handle.cursor, ui.MouseCursor.ResizeEW,
    'the same arrow a draggable value shows')
  eq(type(did.hint), 'string')
  eq(did.hint:lower():find('playhead', 1, true) ~= nil, true)
  band.reset()
end)

test('holding the ruler does not move a camera', function()
  -- The two zones have a button each precisely so that this cannot happen.
  band.reset()
  local state = { cameras = cameras({ 0.25, 0.75 }), cameraIndex = 1 }
  local did = holdRuler(state, WIDTH * 0.25)

  eq(did.move, nil, 'the camera handle is in the other zone')
  eq(did.camera, nil)
  band.reset()
end)

--------------------------------------------------------------------------
-- The name, where the name lives now
--------------------------------------------------------------------------
-- The segments carry a number alone, so the status line is the only place a
-- camera says what it is called. That makes these the tests that keep names
-- worth giving at all.

---Hover a segment and hand back what the ribbon wants said.
local function hoverSegment(state, mouseX)
  local handle = fakes.install({
    itemHovered = true,
    mouseX = ORIGIN_X + mouseX, mouseY = ORIGIN_Y + theme.bandRulerHeight + 10,
  })
  local did = band.draw(state, WIDTH)
  handle.restoreIo()
  return did.hint
end

test('hovering a segment names the camera under the pointer', function()
  local state = {
    cameras = named({ { 0, 'Eau Rouge' }, { 0.5, 'Bus Stop' } }),
    cameraIndex = 1,
  }

  local first = hoverSegment(state, WIDTH * 0.25)
  eq(first:find('Camera 1', 1, true) ~= nil, true, first)
  eq(first:find('Eau Rouge', 1, true) ~= nil, true, 'and what it is called')

  local second = hoverSegment(state, WIDTH * 0.75)
  eq(second:find('Camera 2', 1, true) ~= nil, true)
  eq(second:find('Bus Stop', 1, true) ~= nil, true)
end)

test('a camera nobody has named still says which one it is', function()
  local hint = hoverSegment({ cameras = cameras({ 0, 0.5 }), cameraIndex = 1 },
    WIDTH * 0.75)
  eq(hint:find('Camera 2', 1, true) ~= nil, true, hint)
end)

test('the name reaches the line even when the segment cannot hold a digit', function()
  -- The case the whole change turns on: sixty cameras on four hundred pixels.
  -- Nothing is written on any of them, and the line still answers.
  local starts, names = {}, {}
  for i = 1, 60 do
    starts[i] = (i - 1) / 60
    names[i] = { starts[i], 'Corner ' .. i }
  end

  local hint = hoverSegment({ cameras = named(names), cameraIndex = 1 },
    WIDTH * 0.5)
  eq(hint:find('Corner 31', 1, true) ~= nil, true, hint)
end)

test('the hint still says what the gestures are', function()
  -- The name is added to it, not put in its place: someone who has never
  -- opened the legend learns the gestures from this line.
  local hint = hoverSegment({ cameras = named({ { 0, 'Eau Rouge' } }),
    cameraIndex = 1 }, WIDTH * 0.5)

  for _, word in ipairs({ 'Click', 'Double click', 'Right click' }) do
    eq(hint:find(word, 1, true) ~= nil, true, 'the line dropped ' .. word)
  end
end)
