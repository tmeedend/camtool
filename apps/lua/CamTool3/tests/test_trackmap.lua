--[[
  Tests for core/trackmap.lua.

  Two kinds of assertion here. The geometry is checked against a synthetic
  track whose answers can be worked out by hand -- a circle of known radius,
  a square, a straight line -- because "it looked right" is exactly what this
  project cannot do out of game.

  The ownership is checked against core/evaluate.activeCameraIndex on a real
  camera file. That one matters most: if the map tints a stretch of track for
  camera 4 while the playback runs camera 5 there, the map lies, and it lies
  about the one thing it exists to show.
]]

local runner = require('tests/runner')
local trackmap = require('core/trackmap')
local evaluate = require('core/evaluate')
local data = require('core/data')
local rawFile = require('tests/fixtures/camera_file_lap')

local test, eq, near = runner.test, runner.eq, runner.near

---A circle of radius `r`, sampled `n` times, closed. Progress runs 0..1 the way
---the AI spline does, so the outline and the cameras share one axis.
local function circle(r, n)
  local points = {}
  for i = 0, n - 1 do
    local p = i / n
    local angle = p * 2 * math.pi
    points[#points + 1] = {
      x = r * math.cos(angle),
      y = r * math.sin(angle),
      p = p,
    }
  end
  return points
end

local function cameraSet(starts, pit)
  local cameras = {}
  for i = 1, #starts do
    cameras[i] = {
      camera_in = starts[i],
      camera_pit = pit ~= nil and pit[i] or false,
    }
  end
  return cameras
end

--------------------------------------------------------------------------
-- Bounds
--------------------------------------------------------------------------

test('bounds of a circle are its radius on both axes', function()
  local b = trackmap.bounds(circle(500, 360))
  near(b.minX, -500, 1e-9)
  near(b.maxX, 500, 1e-9)
  near(b.minY, -500, 1e-9)
  near(b.maxY, 500, 1e-9)
end)

test('bounds ignore points that are not finite', function()
  -- The whole point of the guard: one inf would stretch the box to infinity
  -- and squash the real track into a single pixel.
  local points = {
    { x = 0, y = 0, p = 0 },
    { x = 1 / 0, y = 3, p = 0.25 },
    { x = 0 / 0, y = 0 / 0, p = 0.5 },
    { x = 10, y = 20, p = 0.75 },
  }
  local b = trackmap.bounds(points)
  eq(b.minX, 0)
  eq(b.maxX, 10)
  eq(b.minY, 0)
  eq(b.maxY, 20)
end)

test('bounds are nil when nothing finite is left', function()
  eq(trackmap.bounds({}), nil)
  eq(trackmap.bounds(nil), nil)
  eq(trackmap.bounds({ { x = 1 / 0, y = 0 } }), nil, 'a single inf is no track')
end)

--------------------------------------------------------------------------
-- Fit
--------------------------------------------------------------------------

test('a square track fills a square box, less the margin', function()
  local b = { minX = -500, maxX = 500, minY = -500, maxY = 500 }
  local fit = trackmap.fit(b, 200, 200, 10)
  -- 180 usable pixels for 1000 metres.
  near(fit.scale, 0.18, 1e-12)
  near(fit.offsetX, 10, 1e-12)
  near(fit.offsetY, 10, 1e-12)
end)

test('a wide track keeps its shape and gets centred vertically', function()
  -- 1000 x 500 metres into a 200 x 200 box: width binds, so half the height
  -- is left over and becomes equal margins top and bottom.
  local b = { minX = 0, maxX = 1000, minY = 0, maxY = 500 }
  local fit = trackmap.fit(b, 200, 200, 0)
  near(fit.scale, 0.2, 1e-12)
  near(fit.offsetX, 0, 1e-12)
  near(fit.offsetY, 50, 1e-12, 'half the leftover height')
end)

test('a straight track does not divide by its zero span', function()
  -- Lua would answer inf rather than raising, and inf reaches the drawing
  -- code as a coordinate. An A-B track sampled along one axis is a real case.
  local b = { minX = 0, maxX = 1000, minY = 42, maxY = 42 }
  local fit = trackmap.fit(b, 200, 100, 0)
  near(fit.scale, 0.2, 1e-12)
  local _, sy = trackmap.project(fit, 500, 42)
  eq(sy == sy, true, 'not a nan')
  near(sy, 50, 1e-12, 'centred in the box')
end)

test('a track with no extent at all collapses to the centre, not to inf', function()
  local b = { minX = 3, maxX = 3, minY = 7, maxY = 7 }
  local fit = trackmap.fit(b, 200, 100, 0)
  eq(fit.scale, 0)
  local sx, sy = trackmap.project(fit, 3, 7)
  near(sx, 100, 1e-12)
  near(sy, 50, 1e-12)
end)

test('fit refuses a box the margins have eaten', function()
  local b = { minX = 0, maxX = 10, minY = 0, maxY = 10 }
  eq(trackmap.fit(b, 20, 20, 10), nil)
  eq(trackmap.fit(b, 10, 200, 20), nil)
end)

test('fit refuses a nil bounds, which is how "no track" arrives', function()
  eq(trackmap.fit(nil, 200, 200, 10), nil)
end)

--------------------------------------------------------------------------
-- Project
--------------------------------------------------------------------------

test('the vertical axis is flipped: north is up on screen', function()
  local b = { minX = 0, maxX = 100, minY = 0, maxY = 100 }
  local fit = trackmap.fit(b, 100, 100, 0)

  local _, top = trackmap.project(fit, 0, 100)
  local _, bottom = trackmap.project(fit, 0, 0)
  near(top, 0, 1e-12, 'the northernmost point is at the top of the box')
  near(bottom, 100, 1e-12)
end)

test('the corners of the box are the corners of the track', function()
  local fit = trackmap.fit(trackmap.bounds(circle(500, 360)), 200, 200, 20)
  local sx, sy = trackmap.project(fit, -500, 500)
  near(sx, 20, 1e-9)
  near(sy, 20, 1e-9)
  sx, sy = trackmap.project(fit, 500, -500)
  near(sx, 180, 1e-9)
  near(sy, 180, 1e-9)
end)

test('projecting a point that is not finite gives nil, not a coordinate', function()
  local fit = trackmap.fit({ minX = 0, maxX = 1, minY = 0, maxY = 1 }, 10, 10, 0)
  eq(trackmap.project(fit, 1 / 0, 0), nil)
  eq(trackmap.project(fit, 0, 0 / 0), nil)
  eq(trackmap.project(nil, 0, 0), nil)
end)

--------------------------------------------------------------------------
-- projectAll
--------------------------------------------------------------------------

test('projectAll keeps the progress of each point', function()
  local points = circle(100, 8)
  local out = trackmap.projectAll(
    trackmap.fit(trackmap.bounds(points), 200, 200, 0), points)
  eq(#out, 8)
  for i = 1, 8 do
    near(out[i].p, (i - 1) / 8, 1e-12)
  end
end)

test('projectAll reuses its output table instead of allocating each frame', function()
  local fit = trackmap.fit({ minX = 0, maxX = 10, minY = 0, maxY = 10 }, 10, 10, 0)
  local out = trackmap.projectAll(fit, circle(5, 6))
  local first = out[1]
  trackmap.projectAll(fit, circle(5, 6), out)
  eq(rawequal(out[1], first), true, 'the same point table, written over')
end)

test('projectAll truncates when the outline gets shorter', function()
  local fit = trackmap.fit({ minX = 0, maxX = 10, minY = 0, maxY = 10 }, 10, 10, 0)
  local out = trackmap.projectAll(fit, circle(5, 10))
  eq(#out, 10)
  trackmap.projectAll(fit, circle(5, 3), out)
  eq(#out, 3, 'no stale points left behind from the longer outline')
end)

test('projectAll drops points that are not finite', function()
  local fit = trackmap.fit({ minX = 0, maxX = 10, minY = 0, maxY = 10 }, 10, 10, 0)
  local out = trackmap.projectAll(fit, {
    { x = 0, y = 0, p = 0 },
    { x = 1 / 0, y = 0, p = 0.5 },
    { x = 10, y = 10, p = 0.9 },
  })
  eq(#out, 2, 'the line breaks rather than running off to infinity')
end)

--------------------------------------------------------------------------
-- Segments
--------------------------------------------------------------------------

test('each camera runs until the next one starts', function()
  local segments = trackmap.segments(cameraSet({ 0.1, 0.4, 0.8 }))
  eq(#segments, 3)
  near(segments[1].from, 0.1)
  near(segments[1].to, 0.4)
  near(segments[2].from, 0.4)
  near(segments[2].to, 0.8)
end)

test('the last camera holds the view across the start line', function()
  local segments = trackmap.segments(cameraSet({ 0.1, 0.4, 0.8 }))
  near(segments[3].from, 0.8)
  near(segments[3].to, 1.1, 1e-12, 'past 1, back round to the first camera')
end)

test('segments carry the index into the camera list, not their own', function()
  -- With pit cameras filtered out, the third track camera may be the fifth
  -- entry in the file. The panel selects by file index.
  local cameras = cameraSet({ 0.1, 0.2, 0.3, 0.4 }, { false, true, true, false })
  local segments = trackmap.segments(cameras)
  eq(#segments, 2)
  eq(segments[1].index, 1)
  eq(segments[2].index, 4)
end)

test('pit cameras are a list of their own', function()
  local cameras = cameraSet({ 0.1, 0.2, 0.3, 0.4 }, { false, true, true, false })
  local segments = trackmap.segments(cameras, true)
  eq(#segments, 2)
  eq(segments[1].index, 2)
  eq(segments[2].index, 3)
end)

test('a single camera owns the whole lap', function()
  local segments = trackmap.segments(cameraSet({ 0.3 }))
  eq(#segments, 1)
  near(segments[1].from, 0.3)
  near(segments[1].to, 1.3)
end)

test('an empty or missing list gives no segments, not an error', function()
  eq(#trackmap.segments({}), 0)
  eq(#trackmap.segments(nil), 0)
end)

--------------------------------------------------------------------------
-- Ownership
--------------------------------------------------------------------------

test('a position before the first camera belongs to the last one', function()
  local segments = trackmap.segments(cameraSet({ 0.1, 0.4, 0.8 }))
  eq(trackmap.ownerAt(segments, 0.05), 3)
  eq(trackmap.ownerAt(segments, 0), 3)
end)

test('a camera owns its own starting point', function()
  local segments = trackmap.segments(cameraSet({ 0.1, 0.4, 0.8 }))
  eq(trackmap.ownerAt(segments, 0.4), 2, 'the boundary belongs to the new camera')
  eq(trackmap.ownerAt(segments, 0.4 - 1e-9), 1)
end)

test('ownership past the last camera stays with it', function()
  local segments = trackmap.segments(cameraSet({ 0.1, 0.4, 0.8 }))
  eq(trackmap.ownerAt(segments, 0.99), 3)
end)

test('ownerAt survives no cameras and a position that is not finite', function()
  eq(trackmap.ownerAt({}, 0.5), nil)
  eq(trackmap.ownerAt(trackmap.segments(cameraSet({ 0.1 })), 0 / 0), nil)
end)

--------------------------------------------------------------------------
-- The assertion that matters: the map agrees with the playback
--------------------------------------------------------------------------

test('the map tints each point for the camera the playback would run', function()
  local doc = data.load(rawFile)
  local cameras = doc.pos
  local segments = trackmap.segments(cameras)

  eq(#cameras > 1, true, 'the fixture has to have something to disagree about')

  -- Every tenth of a percent of the lap, plus every boundary and the points
  -- either side of it, which is where the two could drift apart.
  local positions = {}
  for i = 0, 1000 do positions[#positions + 1] = i / 1000 end
  for i = 1, #segments do
    positions[#positions + 1] = segments[i].from
    positions[#positions + 1] = segments[i].from - 1e-9
    positions[#positions + 1] = segments[i].from + 1e-9
  end

  for i = 1, #positions do
    local p = positions[i]
    if p >= 0 and p <= 1 then
      eq(trackmap.ownerAt(segments, p),
        evaluate.activeCameraIndex(cameras, p, false),
        string.format('at %.9f of the lap', p))
    end
  end
end)

test('the pit list agrees with the playback too', function()
  local doc = data.load(rawFile)
  local cameras = doc.pos
  local segments = trackmap.segments(cameras, true)

  -- The fixture's first camera is a pit camera, so this is not a vacuous pass.
  eq(#segments > 0, true, 'the fixture has to have a pit camera')

  for i = 0, 1000 do
    local p = i / 1000
    eq(trackmap.ownerAt(segments, p),
      evaluate.activeCameraIndex(cameras, p, true),
      string.format('pit camera at %.3f of the lap', p))
  end
end)

test('assign marks every point of the outline with its camera', function()
  local points = circle(500, 100)
  local segments = trackmap.segments(cameraSet({ 0.25, 0.75 }))
  local owners = trackmap.assign(points, segments)

  eq(#owners, 100)
  eq(owners[1], 2, 'the start line is still the last camera')
  eq(owners[30], 1, 'a quarter in, the first camera has taken over')
  eq(owners[80], 2)
end)

test('assign reuses its table and truncates, like projectAll', function()
  local segments = trackmap.segments(cameraSet({ 0.5 }))
  local owners = trackmap.assign(circle(1, 10), segments)
  eq(#owners, 10)
  trackmap.assign(circle(1, 4), segments, owners)
  eq(#owners, 4)
end)

test('assign says false, not nil, when no camera covers a point', function()
  -- An array with holes stops answering `#` honestly, and the drawing loop
  -- reads its length.
  local owners = trackmap.assign(circle(1, 5), {})
  eq(#owners, 5)
  eq(owners[3], false)
end)

--------------------------------------------------------------------------
-- The fallback outline, for a track with no AI spline
--------------------------------------------------------------------------

test('a recorded track spline becomes an outline', function()
  local doc = data.load(rawFile)
  local points = trackmap.fromRecordedSpline(doc.track_spline)

  eq(points ~= nil, true, 'the fixture has a recorded track spline')
  eq(#points > 50, true)

  -- It is a real lap of Red Bull Ring, so it has extent on both axes and its
  -- progress climbs.
  local b = trackmap.bounds(points)
  eq(b.maxX - b.minX > 100, true)
  eq(b.maxY - b.minY > 100, true)
  eq(points[2].p > points[1].p, true)
end)

test('a recorded spline is already in CamTool space, so nothing is converted', function()
  local doc = data.load(rawFile)
  local points = trackmap.fromRecordedSpline(doc.track_spline)
  near(points[1].x, doc.track_spline.loc_x[1], 1e-12)
  near(points[1].y, doc.track_spline.loc_y[1], 1e-12)
end)

test('progress past the start line folds back into the lap', function()
  -- A spline recorded across the line stores positions past 1, the same wrap
  -- core/spline deals with. Ownership works in lap fractions and would read
  -- 1.02 as past every camera.
  local points = trackmap.fromRecordedSpline({
    loc_x = { 0, 10, 20 },
    loc_y = { 0, 10, 20 },
    the_x = { 0.98, 1.01, 1.04 },
  })
  near(points[1].p, 0.98, 1e-12)
  near(points[2].p, 0.01, 1e-12)
  near(points[3].p, 0.04, 1e-12)
end)

test('an empty or missing recorded spline is nil, not an outline of nothing', function()
  local seb = data.load(require('tests/fixtures/camera_file_seb'))
  eq(trackmap.fromRecordedSpline(seb.track_spline), nil,
    'this file records no track spline')
  eq(trackmap.fromRecordedSpline(nil), nil)
  eq(trackmap.fromRecordedSpline({ loc_x = { 1 }, loc_y = { 1 }, the_x = { 0 } }),
    nil, 'a single point is not a track')
end)

test('a recorded spline with bad numbers in it loses those points only', function()
  local points = trackmap.fromRecordedSpline({
    loc_x = { 0, 1 / 0, 20, 30 },
    loc_y = { 0, 5, 0 / 0, 30 },
    the_x = { 0, 0.1, 0.2, 0.3 },
  })
  eq(#points, 2)
  near(points[2].p, 0.3, 1e-12)
end)

--------------------------------------------------------------------------
-- Turning the track to fill the panel
--------------------------------------------------------------------------

---An ellipse `long` by `short`, turned by `turn` radians. Stands in for a
---circuit that is longer one way than the other, which is most of them.
local function ellipse(long, short, turn, n)
  n = n or 180
  turn = turn or 0
  local points = {}
  for i = 0, n - 1 do
    local p = i / n
    local a = p * 2 * math.pi
    local x, y = long * math.cos(a), short * math.sin(a)
    points[#points + 1] = {
      x = x * math.cos(turn) - y * math.sin(turn),
      y = x * math.sin(turn) + y * math.cos(turn),
      p = p,
    }
  end
  return points
end

test('a track already the shape of the box is left alone', function()
  -- The rule that keeps Spa looking like Spa: turning it has to buy something.
  local angle, gain = trackmap.bestAngle(ellipse(500, 100), 600, 200, 0)
  eq(angle, 0)
  eq(gain, 1)
end)

test('a portrait track in a wide band gets turned onto its side', function()
  -- The case from the panel: the band is 5:1 and the circuit is taller than
  -- it is wide, so the height binds and most of the width goes to waste.
  local angle, gain = trackmap.bestAngle(ellipse(100, 500), 1200, 230, 8)

  -- A quarter turn, either way round -- both put the long axis across.
  local quarter = math.pi / 2
  near(math.min(math.abs(angle - quarter), math.abs(angle + quarter)),
    0, math.rad(2), 'within a couple of degrees of square')
  eq(gain > 2, true, 'and it draws at least twice as big')
end)

test('a diagonal track is straightened', function()
  local turned = ellipse(500, 120, math.rad(30))
  local angle = trackmap.bestAngle(turned, 1200, 230, 8)
  -- Bringing the long axis back to horizontal means undoing the 30 degrees.
  near(math.min(math.abs(angle - math.rad(-30)), math.abs(angle - math.rad(150))),
    0, math.rad(3))
end)

test('the angle really is the best one tried', function()
  local points = ellipse(100, 500)
  local angle = trackmap.bestAngle(points, 1200, 230, 8)
  local best = trackmap.fit(trackmap.bounds(points, angle), 1200, 230, 8, angle)

  for degrees = 0, 179, 3 do
    local a = math.rad(degrees)
    local other = trackmap.fit(trackmap.bounds(points, a), 1200, 230, 8, a)
    eq(best.scale >= other.scale - 1e-9, true,
      'no angle draws bigger than the one chosen, including ' .. degrees)
  end
end)

test('a turned track still projects inside its box', function()
  local points = ellipse(100, 500)
  local angle = trackmap.bestAngle(points, 1200, 230, 8)
  local fit = trackmap.fit(trackmap.bounds(points, angle), 1200, 230, 8, angle)
  local out = trackmap.projectAll(fit, points)

  eq(#out, #points)
  for i = 1, #out do
    eq(out[i].x >= -1e-9 and out[i].x <= 1200 + 1e-9, true, 'x of point ' .. i)
    eq(out[i].y >= -1e-9 and out[i].y <= 230 + 1e-9, true, 'y of point ' .. i)
  end
end)

test('no rotation projects exactly as before', function()
  -- The unturned path has to stay bit for bit what it was, or every existing
  -- expectation about the map moves.
  local points = circle(500, 90)
  local fit = trackmap.fit(trackmap.bounds(points), 200, 200, 20)
  local sx, sy = trackmap.project(fit, -500, 500)
  near(sx, 20, 1e-9)
  near(sy, 20, 1e-9)
  eq(fit.angle, 0)
end)

--------------------------------------------------------------------------
-- Clicking the map
--------------------------------------------------------------------------

test('a click on the track finds the point under it', function()
  local points = circle(500, 120)
  local fit = trackmap.fit(trackmap.bounds(points), 200, 200, 10)
  local out = trackmap.projectAll(fit, points)

  local target = out[30]
  local found = trackmap.nearest(out, target.x + 2, target.y - 3)
  eq(found, 30)
end)

test('a click on the empty middle of the map finds nothing', function()
  -- Otherwise every click anywhere would select whatever was least far away,
  -- and a click meant for nothing would move the panel.
  local points = circle(500, 120)
  local fit = trackmap.fit(trackmap.bounds(points), 200, 200, 10)
  local out = trackmap.projectAll(fit, points)

  eq(trackmap.nearest(out, 100, 100, 16), nil, 'the middle of a circle')
end)

test('the caller decides how near counts as near', function()
  local points = circle(500, 120)
  local fit = trackmap.fit(trackmap.bounds(points), 200, 200, 10)
  local out = trackmap.projectAll(fit, points)

  local target = out[1]
  eq(trackmap.nearest(out, target.x + 30, target.y, 16), nil)
  eq(trackmap.nearest(out, target.x + 30, target.y, 40), 1)
end)

test('nearest survives an empty outline and a click that is not a number', function()
  eq(trackmap.nearest({}, 1, 1), nil)
  eq(trackmap.nearest(nil, 1, 1), nil)
  eq(trackmap.nearest({ { x = 0, y = 0 } }, 0 / 0, 0), nil)
end)

--------------------------------------------------------------------------
-- The same thing on one line: the track band
--------------------------------------------------------------------------

test('every camera gets a span of the lap', function()
  local spans = trackmap.bandSpans(trackmap.segments(cameraSet({ 0, 0.4, 0.8 })))
  eq(#spans, 3)
  near(spans[1].from, 0)
  near(spans[1].to, 0.4)
  near(spans[3].from, 0.8)
  near(spans[3].to, 1, 1e-12, 'cut at the end of the lap, not past it')
end)

test('the camera holding the start line is drawn at both ends', function()
  -- On the map this is invisible: the outline closes on itself. On a ribbon
  -- it would run off the end, so the tail is drawn where it happens -- at the
  -- beginning.
  local spans = trackmap.bandSpans(trackmap.segments(cameraSet({ 0.1, 0.5 })))

  eq(#spans, 3)
  eq(spans[1].index, 2, 'the last camera, at the start of the ribbon')
  near(spans[1].from, 0)
  near(spans[1].to, 0.1)
  eq(spans[1].wrapped, true)

  eq(spans[2].index, 1)
  eq(spans[3].index, 2)
  near(spans[3].to, 1)
end)

test('nothing in a band span ever falls outside the lap', function()
  local sets = {
    { 0 }, { 0.999 }, { 0, 0.5 }, { 0.001, 0.999 },
    { 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9 },
  }
  for _, starts in ipairs(sets) do
    local spans = trackmap.bandSpans(trackmap.segments(cameraSet(starts)))
    eq(#spans > 0, true)
    for i = 1, #spans do
      eq(spans[i].from >= 0 and spans[i].from <= 1, true, 'from of span ' .. i)
      eq(spans[i].to >= 0 and spans[i].to <= 1, true, 'to of span ' .. i)
      eq(spans[i].to > spans[i].from, true, 'span ' .. i .. ' has width')
    end
  end
end)

test('the spans cover the whole lap, with no gap and no overlap', function()
  local spans = trackmap.bandSpans(trackmap.segments(cameraSet({ 0.15, 0.6, 0.62 })))
  near(spans[1].from, 0, 1e-12, 'starts at the line')
  for i = 2, #spans do
    near(spans[i].from, spans[i - 1].to, 1e-12, 'span ' .. i .. ' joins the last')
  end
  near(spans[#spans].to, 1, 1e-12, 'and ends at the line')
end)

test('a single camera owns the whole ribbon in one piece', function()
  local spans = trackmap.bandSpans(trackmap.segments(cameraSet({ 0 })))
  eq(#spans, 1)
  near(spans[1].from, 0)
  near(spans[1].to, 1)
end)

test('no cameras, no spans', function()
  eq(#trackmap.bandSpans({}), 0)
  eq(#trackmap.bandSpans(nil), 0)
end)
