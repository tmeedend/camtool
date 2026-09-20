--[[
  Tests for ui/map.lua, against the fake CSP.

  These cannot say the map looks right -- nothing out of game can. What they
  can say is what reached the screen: that every coordinate is a real number,
  that nothing was drawn outside its box, that the camera being edited is the
  one drawn in red, and that a track with no outline gets a sentence instead
  of a guess.

  That is the same bargain tests/sweep.lua makes for the camera: check out of
  game the things that would otherwise be checked by squinting at a replay.
]]

local runner = require('tests/runner')
local fakes = require('tests/fakes/csp')
local trackMap = require('ui/map')
local theme = require('ui/theme')

local test, eq, near = runner.test, runner.eq, runner.near

local WIDTH, HEIGHT = 300, 150
-- Where the fake puts the cursor. The map draws from there, not from the
-- corner of the screen.
local ORIGIN_X, ORIGIN_Y = 17, 23

---An outline the way the adapter hands it over: a circle of known radius.
local function outline(n, closed)
  local points = {}
  for i = 0, (n or 120) - 1 do
    local p = i / (n or 120)
    local angle = p * 2 * math.pi
    points[#points + 1] = { x = 500 * math.cos(angle), y = 500 * math.sin(angle), p = p }
  end
  return { points = points, closed = closed ~= false, source = 'ai-spline' }
end

local function cameras(starts)
  local out = {}
  for i = 1, #starts do out[i] = { camera_in = starts[i], camera_pit = false } end
  return out
end

---Draw one frame and hand back what was drawn.
local function drawOnce(state)
  local handle = fakes.install({})
  trackMap.reset()
  trackMap.draw(state, WIDTH, HEIGHT)
  handle.restoreIo()
  return handle.drawn
end

local function countOf(drawn, op)
  local n = 0
  for i = 1, #drawn do if drawn[i].op == op then n = n + 1 end end
  return n
end

test('the track is drawn', function()
  local drawn = drawOnce({
    outline = outline(),
    cameras = cameras({ 0.1, 0.5 }),
    cameraIndex = 1,
    trackPos = 0.3,
  })
  eq(countOf(drawn, 'pathLineTo') > 100, true, 'the outline reached the screen')
  eq(countOf(drawn, 'pathStroke') > 0, true)
end)

test('nothing is drawn outside the box', function()
  -- The one failure that costs a game launch to see: an outline that runs off
  -- across the panel, or a fit that forgot its margin.
  local drawn = drawOnce({
    outline = outline(),
    cameras = cameras({ 0.1, 0.5, 0.9 }),
    cameraIndex = 2,
    trackPos = 0.7,
  })

  for i = 1, #drawn do
    local call = drawn[i]
    if call.x ~= nil then
      eq(call.x >= ORIGIN_X and call.x <= ORIGIN_X + WIDTH, true,
        string.format('%s at x=%s', call.op, tostring(call.x)))
      eq(call.y >= ORIGIN_Y and call.y <= ORIGIN_Y + HEIGHT, true,
        string.format('%s at y=%s', call.op, tostring(call.y)))
    end
  end
end)

test('the track fills its box, from the cursor the panel left it at', function()
  -- Stronger than "inside the box", and deliberately so: a widget that draws
  -- at its own coordinates and forgets to add the cursor still lands inside,
  -- it just lands in the wrong place. This pins where.
  --
  -- A circle in a 300 x 150 box: the height binds, so the outline spans the
  -- full height less the padding and sits centred across the width.
  local drawn = drawOnce({
    outline = outline(120),
    cameras = cameras({ 0 }),
    cameraIndex = 1,
  })

  local minX, maxX, minY, maxY
  for i = 1, #drawn do
    local call = drawn[i]
    if call.op == 'pathLineTo' then
      if minX == nil or call.x < minX then minX = call.x end
      if maxX == nil or call.x > maxX then maxX = call.x end
      if minY == nil or call.y < minY then minY = call.y end
      if maxY == nil or call.y > maxY then maxY = call.y end
    end
  end

  local pad = theme.mapPadding
  near(minY, ORIGIN_Y + pad, 0.5, 'the top of the track is a padding in')
  near(maxY, ORIGIN_Y + HEIGHT - pad, 0.5, 'and the bottom likewise')
  near((minX + maxX) / 2, ORIGIN_X + WIDTH / 2, 0.5, 'centred across the width')
  near(maxY - minY, maxX - minX, 0.5, 'a circle comes out round, not oval')
end)

test('no coordinate is inf or nan', function()
  -- Lua divides by zero without raising, and the result lands here as a
  -- coordinate. The straight-track case is where it would come from.
  local flat = outline(40)
  for i = 1, #flat.points do flat.points[i].y = 0 end

  local drawn = drawOnce({
    outline = flat,
    cameras = cameras({ 0.25 }),
    cameraIndex = 1,
    trackPos = 0.5,
  })

  eq(#drawn > 2, true, 'something was drawn at all')
  for i = 1, #drawn do
    local call = drawn[i]
    if call.x ~= nil then
      eq(call.x == call.x and call.x - call.x == 0, true, call.op .. ' x')
      eq(call.y == call.y and call.y - call.y == 0, true, call.op .. ' y')
    end
  end
end)

test('the camera being edited is the one in red', function()
  local drawn = drawOnce({
    outline = outline(),
    cameras = cameras({ 0.0, 0.33, 0.66 }),
    cameraIndex = 2,
    liveCameraIndex = 3,
    trackPos = 0.1,
  })

  local reds, lives = 0, 0
  for i = 1, #drawn do
    if drawn[i].colour == theme.stripActive then reds = reds + 1 end
    if drawn[i].colour == theme.stripLive then lives = lives + 1 end
  end
  eq(reds > 0, true, 'the edited camera is red, as in the strip')
  eq(lives > 0, true, 'the live one keeps its paler tint')
end)

test('one stroke per run of colour, not one per point', function()
  -- Point by point this would be a thousand draw calls a frame for the same
  -- picture.
  local drawn = drawOnce({
    outline = outline(120),
    cameras = cameras({ 0.0, 0.5 }),
    cameraIndex = 1,
    trackPos = 0,
  })
  local strokes = countOf(drawn, 'pathStroke')
  eq(strokes <= 4, true, 'two cameras, at most a stroke each plus the wrap')
  eq(strokes >= 2, true)
end)

test('the car and the start line are drawn on top', function()
  local drawn = drawOnce({
    outline = outline(),
    cameras = cameras({ 0.2 }),
    cameraIndex = 1,
    trackPos = 0.5,
  })
  -- Two filled circles now: the car and the selected camera's drag handle.
  -- They are told apart by colour, which is also what a user does.
  local function filledOf(colour)
    local n = 0
    for i = 1, #drawn do
      if drawn[i].op == 'drawCircleFilled' and drawn[i].colour == colour then
        n = n + 1
      end
    end
    return n
  end
  eq(filledOf(theme.mapPlayhead), 1, 'the car')
  eq(countOf(drawn, 'drawCircle'), 1, 'the start line')

  -- Halfway round a circle that starts at (500, 0) is (-500, 0): opposite
  -- sides of the map, so a sign slip anywhere would show here.
  local car, start
  for i = 1, #drawn do
    if drawn[i].op == 'drawCircleFilled'
      and drawn[i].colour == theme.mapPlayhead then car = drawn[i] end
    if drawn[i].op == 'drawCircle' then start = drawn[i] end
  end
  eq(math.abs(car.x - start.x) > WIDTH / 3, true,
    'the car is across the map from the start line')
end)

test('a lap with no car position still draws the track', function()
  local drawn = drawOnce({
    outline = outline(),
    cameras = cameras({ 0.2 }),
    cameraIndex = 1,
    trackPos = nil,
  })
  eq(countOf(drawn, 'pathStroke') > 0, true)
  local cars = 0
  for i = 1, #drawn do
    if drawn[i].op == 'drawCircleFilled'
      and drawn[i].colour == theme.mapPlayhead then cars = cars + 1 end
  end
  eq(cars, 0, 'no car, no dot')
end)

test('a closed track joins up, an A-B track does not', function()
  local closed = drawOnce({
    outline = outline(60, true),
    cameras = cameras({ 0 }),
    cameraIndex = 1,
  })
  trackMap.reset()
  local open = drawOnce({
    outline = outline(60, false),
    cameras = cameras({ 0 }),
    cameraIndex = 1,
  })
  eq(countOf(closed, 'drawLine'), 1, 'the lap is closed')
  eq(countOf(open, 'drawLine'), 0, 'no line drawn across the map between ends')
end)

test('a track with no outline says so instead of guessing', function()
  local drawn = drawOnce({
    outline = nil,
    cameras = cameras({ 0.2 }),
    cameraIndex = 1,
    trackPos = 0.5,
  })
  eq(countOf(drawn, 'pathStroke'), 0, 'nothing drawn')

  local said = false
  for i = 1, #drawn do
    if drawn[i].op == 'text' then said = true end
  end
  eq(said, true, 'the panel explains itself')
end)

test('an outline too short to be a track is treated as none', function()
  local drawn = drawOnce({
    outline = { points = { { x = 0, y = 0, p = 0 } }, closed = true },
    cameras = cameras({ 0.2 }),
    cameraIndex = 1,
  })
  eq(countOf(drawn, 'pathStroke'), 0)
end)

test('a file with no cameras draws the track anyway', function()
  -- Opening the app before loading a file. The track is still worth seeing.
  local drawn = drawOnce({ outline = outline(), cameras = nil, trackPos = 0.4 })
  eq(countOf(drawn, 'pathStroke') > 0, true)
end)

test('drawing twice does not project twice', function()
  local handle = fakes.install({})
  trackMap.reset()

  local state = {
    outline = outline(),
    cameras = cameras({ 0.1, 0.6 }),
    cameraIndex = 1,
    trackPos = 0.2,
  }

  trackMap.draw(state, WIDTH, HEIGHT)
  local first = #handle.drawn
  trackMap.draw(state, WIDTH, HEIGHT)
  eq(#handle.drawn, first * 2, 'the same picture both times')

  handle.restoreIo()
end)

test('resizing the panel moves the track with it', function()
  local handle = fakes.install({})
  trackMap.reset()

  local state = { outline = outline(), cameras = cameras({ 0 }), cameraIndex = 1 }

  trackMap.draw(state, 300, 150)
  local narrow = nil
  for i = 1, #handle.drawn do
    if handle.drawn[i].op == 'pathLineTo' then narrow = handle.drawn[i] break end
  end

  local mark = #handle.drawn
  trackMap.draw(state, 600, 300)
  local wide = nil
  for i = mark + 1, #handle.drawn do
    if handle.drawn[i].op == 'pathLineTo' then wide = handle.drawn[i] break end
  end

  eq(math.abs(wide.x - narrow.x) > 1, true,
    'the cached projection was rebuilt for the new size')

  handle.restoreIo()
end)

test('moving a camera retints the track without a resize', function()
  local handle = fakes.install({})
  trackMap.reset()

  local state = {
    outline = outline(60),
    cameras = cameras({ 0.0, 0.5 }),
    cameraIndex = 2,
  }
  trackMap.draw(state, WIDTH, HEIGHT)

  ---How many points the first camera's stretch got: the count of line points
  ---before the first stroke ends it. The colour alone would not do -- the
  ---first camera stays the first camera, what changes is its share of the lap.
  local function firstRunLength(from)
    local n = 0
    for i = from, #handle.drawn do
      if handle.drawn[i].op == 'pathStroke' then return n end
      if handle.drawn[i].op == 'pathLineTo' then n = n + 1 end
    end
    return n
  end

  local before = firstRunLength(1)
  local mark = #handle.drawn

  -- The second camera now starts almost at once, so the first camera's share
  -- of the lap all but disappears.
  state.cameras = cameras({ 0.0, 0.02 })
  trackMap.draw(state, WIDTH, HEIGHT)
  local after = firstRunLength(mark + 1)

  eq(before > 25, true, 'half the lap, before the edit')
  eq(after < 5, true, 'a sliver of it, after -- the ownership cache noticed')

  handle.restoreIo()
end)

--------------------------------------------------------------------------
-- Filling the panel: how tall, and which way up
--------------------------------------------------------------------------

---An ellipse, to stand in for a circuit longer one way than the other.
local function ellipse(long, short, n)
  local points = {}
  n = n or 180
  for i = 0, n - 1 do
    local p = i / n
    local a = p * 2 * math.pi
    points[#points + 1] =
      { x = long * math.cos(a), y = short * math.sin(a), p = p }
  end
  return { points = points, closed = true, source = 'ai-spline' }
end

---What the drawn outline measures on screen.
local function drawnSpan(drawn)
  local minX, maxX, minY, maxY
  for i = 1, #drawn do
    local call = drawn[i]
    if call.op == 'pathLineTo' then
      if minX == nil or call.x < minX then minX = call.x end
      if maxX == nil or call.x > maxX then maxX = call.x end
      if minY == nil or call.y < minY then minY = call.y end
      if maxY == nil or call.y > maxY then maxY = call.y end
    end
  end
  return maxX - minX, maxY - minY
end

test('a portrait circuit in a wide band is turned to fill it', function()
  -- Spa in the panel: the band is wide, the circuit is taller than it is
  -- wide, and unturned it drew small in the middle of a lot of nothing.
  local handle = fakes.install({})
  trackMap.reset()
  trackMap.draw({ outline = ellipse(100, 500), cameras = cameras({ 0 }),
    cameraIndex = 1 }, 1200, 300)
  local turnedW, turnedH = drawnSpan(handle.drawn)
  handle.restoreIo()

  eq(turnedW > turnedH, true, 'the long axis now lies across the panel')
  eq(turnedW > 400, true, 'and it uses the width it was given')
end)

test('a circuit that already fits is left the way everyone pictures it', function()
  local handle = fakes.install({})
  trackMap.reset()
  trackMap.draw({ outline = ellipse(500, 100), cameras = cameras({ 0 }),
    cameraIndex = 1 }, 1200, 300)
  local w, h = drawnSpan(handle.drawn)
  handle.restoreIo()

  eq(w > h, true, 'still lying the way it was drawn')
end)

test('the map takes the height its shape needs, not the whole ceiling', function()
  -- A wide circuit in a wide panel does not need 300 px of band, and the
  -- parameters below would rather have the room.
  local handle = fakes.install({})
  trackMap.reset()
  trackMap.draw({ outline = ellipse(500, 50), cameras = cameras({ 0 }),
    cameraIndex = 1 }, 1200, 300)

  local reserved = nil
  for i = 1, #handle.drawn do
    if handle.drawn[i].op == 'drawRectFilled' then
      reserved = handle.drawn[i].y2 - handle.drawn[i].y
    end
  end
  handle.restoreIo()

  eq(reserved < 300, true, 'less than the ceiling')
  eq(reserved >= theme.mapHeightMin, true, 'and never squashed below the floor')
end)

test('a very long thin circuit still gets the floor height', function()
  local handle = fakes.install({})
  trackMap.reset()
  trackMap.draw({ outline = ellipse(5000, 20), cameras = cameras({ 0 }),
    cameraIndex = 1 }, 1200, 300)

  local reserved = nil
  for i = 1, #handle.drawn do
    if handle.drawn[i].op == 'drawRectFilled' then
      reserved = handle.drawn[i].y2 - handle.drawn[i].y
    end
  end
  handle.restoreIo()

  eq(reserved, theme.mapHeightMin)
end)

--------------------------------------------------------------------------
-- Clicking a camera
--------------------------------------------------------------------------

---Draw once with the mouse somewhere, and say whether it was clicked.
local function clickAt(state, x, y, clickedIt)
  -- The pointer has to be over the map for either the ring or the click to
  -- mean anything, which is how the real thing works too.
  local handle = fakes.install({
    clicks = clickedIt ~= false and { ['##trackMap'] = true } or {},
    itemHovered = true,
    mouseX = ORIGIN_X + x, mouseY = ORIGIN_Y + y,
  })
  trackMap.reset()
  local picked = trackMap.draw(state, WIDTH, HEIGHT)
  handle.restoreIo()
  return picked, handle.drawn
end

test('clicking a stretch of track selects the camera that covers it', function()
  local state = {
    outline = outline(120),
    cameras = cameras({ 0.0, 0.25, 0.5, 0.75 }),
    cameraIndex = 1,
  }

  -- Draw once to learn where the track landed, then click one of its points.
  local _, drawn = clickAt(state, -999, -999)
  local target = nil
  for i = 1, #drawn do
    if drawn[i].op == 'pathLineTo' then target = drawn[i] end
  end

  -- That last point is the end of the lap, so the last camera owns it.
  local picked = clickAt(state, target.x - ORIGIN_X, target.y - ORIGIN_Y)
  eq(picked, 4)
end)

test('clicking the empty middle of the map selects nothing', function()
  -- Otherwise a click meant for nothing would move the panel to whichever
  -- camera happened to be least far away.
  local picked = clickAt({
    outline = outline(120),
    cameras = cameras({ 0.0, 0.5 }),
    cameraIndex = 1,
  }, WIDTH / 2, HEIGHT / 2)
  eq(picked, nil)
end)

test('hovering without clicking selects nothing', function()
  local state = {
    outline = outline(120),
    cameras = cameras({ 0.0, 0.5 }),
    cameraIndex = 1,
  }
  local _, drawn = clickAt(state, -999, -999)
  local target
  for i = 1, #drawn do
    if drawn[i].op == 'pathLineTo' then target = drawn[i] break end
  end

  eq(clickAt(state, target.x - ORIGIN_X, target.y - ORIGIN_Y, false), nil,
    'the mouse was over the track, but nobody pressed anything')
end)

test('clicking a track with no outline does not raise', function()
  eq(clickAt({ outline = nil, cameras = cameras({ 0.2 }) }, 10, 10), nil)
end)

test('the ring shows which camera a click would take, before clicking', function()
  -- A hit test you cannot see is a hit test you cannot debug. This is what
  -- was missing when the click silently did nothing: no way, in game, to tell
  -- a click that was never reported from coordinates measured on the wrong
  -- ruler.
  local state = {
    outline = outline(120),
    cameras = cameras({ 0.0, 0.5 }),
    cameraIndex = 1,
  }

  local _, drawn = clickAt(state, -999, -999, false)
  local target
  for i = 1, #drawn do
    if drawn[i].op == 'pathLineTo' then target = drawn[i] break end
  end

  -- Hovering the track, without pressing anything.
  local _, hoverDrawn =
    clickAt(state, target.x - ORIGIN_X, target.y - ORIGIN_Y, false)

  local ring = nil
  for i = 1, #hoverDrawn do
    local call = hoverDrawn[i]
    if call.op == 'drawCircle' and call.colour == theme.mapHover then
      ring = call
    end
  end

  eq(ring ~= nil, true, 'the pointer is over the track, so the ring is drawn')
  eq(math.abs(ring.x - target.x) < 2 and math.abs(ring.y - target.y) < 2, true,
    'and it sits on the point the click would take')
end)

test('no ring over the empty middle of the map', function()
  local _, drawn = clickAt({
    outline = outline(120),
    cameras = cameras({ 0.0, 0.5 }),
    cameraIndex = 1,
  }, WIDTH / 2, HEIGHT / 2, false)

  for i = 1, #drawn do
    eq(drawn[i].colour ~= theme.mapHover, true, 'nothing to select there')
  end
end)

test('the click and the ring cannot disagree', function()
  -- They are one calculation now. Two would be two chances to get the ruler
  -- wrong, and only one of them visible.
  local state = {
    outline = outline(120),
    cameras = cameras({ 0.0, 0.33, 0.66 }),
    cameraIndex = 1,
  }

  local _, drawn = clickAt(state, -999, -999, false)
  local points = {}
  for i = 1, #drawn do
    if drawn[i].op == 'pathLineTo' then points[#points + 1] = drawn[i] end
  end

  for _, at in ipairs({ 1, 20, 50, 90 }) do
    local point = points[at]
    local picked, hoverDrawn =
      clickAt(state, point.x - ORIGIN_X, point.y - ORIGIN_Y)

    local ring = nil
    for i = 1, #hoverDrawn do
      if hoverDrawn[i].op == 'drawCircle'
        and hoverDrawn[i].colour == theme.mapHover then ring = hoverDrawn[i] end
    end

    eq(ring ~= nil, true, 'a ring at point ' .. at)
    eq(picked ~= nil, true, 'and a camera taken at point ' .. at)
  end
end)

--------------------------------------------------------------------------
-- Dragging a camera's start along the outline
--------------------------------------------------------------------------

---Press on the map at a point, and report what came back.
local function pressMap(state, x, y)
  local handle = fakes.install({
    itemActive = true, itemHovered = true,
    mouseX = ORIGIN_X + x, mouseY = ORIGIN_Y + y,
  })
  local picked, move = trackMap.draw(state, WIDTH, HEIGHT)
  handle.restoreIo()
  return move, picked
end

---Where the map put a given lap position, and where the handle was drawn.
local function handleOf(state)
  local _, drawn = clickAt(state, -999, -999, false)
  for i = 1, #drawn do
    if drawn[i].op == 'drawCircleFilled'
      and drawn[i].colour == theme.stripActive then return drawn[i] end
  end
end

test('the selected camera shows a handle on the outline', function()
  trackMap.reset()
  local handle = handleOf({
    outline = outline(120), cameras = cameras({ 0.25, 0.75 }), cameraIndex = 1,
  })
  eq(handle ~= nil, true, 'a grip where that camera takes over')
end)

test('dragging the handle reports lap positions, not pixels', function()
  -- The whole reason the AI spline was chosen over a picture of the track:
  -- every point of the outline IS a value of camera_in, so a drag reads an
  -- index rather than inverting a projection.
  trackMap.reset()
  local state = {
    outline = outline(120), cameras = cameras({ 0.25, 0.75 }), cameraIndex = 1,
  }

  local handle = handleOf(state)
  trackMap.reset()

  local move = pressMap(state, handle.x - ORIGIN_X, handle.y - ORIGIN_Y)
  eq(move ~= nil, true, 'the press landed on the handle')
  near(move.position, 0.25, 0.02, 'and it reads as a lap position')
  trackMap.reset()
end)

test('a press away from the handle selects instead of dragging', function()
  trackMap.reset()
  local state = {
    outline = outline(120), cameras = cameras({ 0.25, 0.75 }), cameraIndex = 1,
  }
  local handle = handleOf(state)
  trackMap.reset()

  -- The far side of the circle from the handle.
  local move = pressMap(state, WIDTH - (handle.x - ORIGIN_X),
    HEIGHT - (handle.y - ORIGIN_Y))
  eq(move, nil)
  trackMap.reset()
end)

test('with no camera selected the map has no handle to drag', function()
  trackMap.reset()
  eq(handleOf({ outline = outline(120), cameras = cameras({ 0.25 }) }), nil)
  trackMap.reset()
end)

--------------------------------------------------------------------------
-- Click the map to bring the car there
--------------------------------------------------------------------------

---Click the map at a point of the outline, optionally with shift held.
local function clickOutline(state, index, shift)
  trackMap.reset()
  local _, drawn = clickAt(state, -999, -999, false)
  local points = {}
  for i = 1, #drawn do
    if drawn[i].op == 'pathLineTo' then points[#points + 1] = drawn[i] end
  end
  trackMap.reset()

  local target = points[index]
  local handle = fakes.install({
    clicks = { ['##trackMap'] = true },
    itemHovered = true, shiftHeld = shift == true,
    mouseX = target.x, mouseY = target.y,
  })
  local picked, move, seekTo, hint = trackMap.draw(state, WIDTH, HEIGHT)
  handle.restoreIo()
  trackMap.reset()
  return picked, seekTo, hint
end

test('clicking the outline selects the camera under it', function()
  local state = {
    outline = outline(120), cameras = cameras({ 0.0, 0.5 }), cameraIndex = 1,
  }
  local picked = clickOutline(state, 40)

  eq(picked ~= nil, true, 'a camera was selected')
end)

test('selecting on the map leaves the replay where it was, modifier or not', function()
  -- The ribbon's rule, and it has to be the same in both surfaces or neither
  -- can be relied on. The ruler is the only thing that moves the playhead.
  local state = {
    outline = outline(120), cameras = cameras({ 0.0, 0.5 }), cameraIndex = 1,
  }

  local _, plain = clickOutline(state, 40)
  eq(plain, nil)

  local _, shifted = clickOutline(state, 40, true)
  eq(shifted, nil)
end)

test('hovering the map says what clicking it does', function()
  local state = {
    outline = outline(120), cameras = cameras({ 0.0, 0.5 }), cameraIndex = 1,
  }
  local _, _, hint = clickOutline(state, 40)
  eq(type(hint), 'string')
  eq(hint:find('select', 1, true) ~= nil, true)
  eq(hint:lower():find('shift', 1, true), nil, 'and offers no dead modifier')
end)

test('clicking the empty middle of the map moves nothing', function()
  trackMap.reset()
  local handle = fakes.install({
    clicks = { ['##trackMap'] = true }, itemHovered = true,
    mouseX = ORIGIN_X + WIDTH / 2, mouseY = ORIGIN_Y + HEIGHT / 2,
  })
  local picked, _, seekTo = trackMap.draw({
    outline = outline(120), cameras = cameras({ 0.0, 0.5 }), cameraIndex = 1,
  }, WIDTH, HEIGHT)
  handle.restoreIo()
  trackMap.reset()

  eq(picked, nil)
  eq(seekTo, nil, 'a click on nothing asks for nothing')
end)
