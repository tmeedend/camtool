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
  eq(countOf(drawn, 'drawCircleFilled'), 1, 'the car')
  eq(countOf(drawn, 'drawCircle'), 1, 'the start line')

  -- Halfway round a circle that starts at (500, 0) is (-500, 0): opposite
  -- sides of the map, so a sign slip anywhere would show here.
  local car, start
  for i = 1, #drawn do
    if drawn[i].op == 'drawCircleFilled' then car = drawn[i] end
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
  eq(countOf(drawn, 'drawCircleFilled'), 0, 'no car, no dot')
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
