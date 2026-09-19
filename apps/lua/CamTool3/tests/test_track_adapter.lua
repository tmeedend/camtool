--[[
  Tests for adapters/track.lua, against the fake CSP.

  The fake track is a circle of known radius, so the sampled outline can be
  checked against arithmetic rather than against a screenshot. What these
  cannot say is whether the real fast_lane of a real circuit comes back the
  shape we expect -- that is the in-game checklist's job.

  The case worth the most here is the track with no AI spline at all. It is
  rare, it is real, and it is the one nobody would think to try in game.
]]

local runner = require('tests/runner')
local fakes = require('tests/fakes/csp')
local track = require('adapters/track')

local test, eq, near = runner.test, runner.eq, runner.near

---Install the fakes and clear whatever a previous case cached.
local function withTrack(opts)
  local handle = fakes.install(opts)
  track.clearCache()
  return handle
end

test('the outline follows the track and carries its lap progress', function()
  local handle = withTrack({ trackRadius = 500 })
  local outline = track.outline(5)

  eq(outline ~= nil, true)
  eq(#outline.points > 100, true, 'a 3 km circle at 5 m spacing')
  eq(outline.source, 'ai-spline')
  eq(outline.closed, true)

  -- Every point sits on the circle, and the first is at progress zero.
  for i = 1, #outline.points do
    local point = outline.points[i]
    near(math.sqrt(point.x * point.x + point.y * point.y), 500, 1e-6,
      'point ' .. i .. ' is on the circle')
  end
  near(outline.points[1].p, 0)
  near(outline.points[1].x, 500, 1e-9)
  near(outline.points[1].y, 0, 1e-9)

  handle.restoreIo()
end)

test('AC is Y-up and the outline is Z-up, so the horizontal pair is x and z', function()
  -- The fake puts the circle in AC's x/z plane with y flat at 0. If the
  -- adapter read y instead of z, every point would land on a single line.
  local handle = withTrack({ trackRadius = 500 })
  local outline = track.outline(50)

  local movedInY = false
  for i = 1, #outline.points do
    if math.abs(outline.points[i].y) > 1e-6 then movedInY = true end
  end
  eq(movedInY, true, 'the outline has extent on both axes')

  handle.restoreIo()
end)

test('spacing decides how many points come back', function()
  local handle = withTrack({ trackRadius = 500, trackLengthM = 3000 })
  eq(#track.outline(10).points, 300)
  track.clearCache()
  eq(#track.outline(30).points, 100)
  handle.restoreIo()
end)

test('the sample count stays between its bounds', function()
  -- A 100 m parking lot must not come back as a triangle, and the Nordschleife
  -- must not come back as 25000 points.
  local handle = withTrack({ trackRadius = 20, trackLengthM = 100 })
  eq(#track.outline(5).points, 64, 'floor')
  track.clearCache()
  handle.restoreIo()

  handle = withTrack({ trackRadius = 500, trackLengthM = 200000 })
  eq(#track.outline(1).points, 3000, 'ceiling')
  handle.restoreIo()
end)

test('a track with no AI spline gives nil, and says so before sampling', function()
  -- Drift layouts, gymkhana maps, the odd scenic mod. The panel has to be able
  -- to say "no track" rather than draw a guess.
  local handle = withTrack({ noTrackSpline = true })
  eq(track.hasOutline(), false)
  eq(track.outline(5), nil)
  handle.restoreIo()
end)

test('a track length of zero gives nil rather than dividing by it', function()
  local handle = withTrack({ trackLengthM = 0 })
  eq(track.outline(5), nil)
  handle.restoreIo()
end)

test('an A-B track is not closed, so no line is drawn across the map', function()
  local handle = withTrack({ isTrackOpen = true })
  eq(track.outline(5).closed, false)
  handle.restoreIo()
end)

test('the width of the track comes from its sides', function()
  local handle = withTrack({
    trackSides = function() return { x = 7, y = 4 } end,
  })
  local point = track.outline(50).points[1]
  near(point.halfLeft, 7)
  near(point.halfRight, 4)
  handle.restoreIo()
end)

test('an absurd width is clamped, not drawn', function()
  -- A hand-made fast_lane can hold anything. At map scale a 900 m half-width
  -- would swamp the panel, and Lua hands inf to the drawing code rather than
  -- raising on the division that produced it.
  local handle = withTrack({
    trackSides = function() return { x = 1 / 0, y = 900 } end,
  })
  local point = track.outline(50).points[1]
  near(point.halfLeft, 5, 1e-9, 'inf falls back to the default')
  near(point.halfRight, 30, 1e-9, 'the ceiling')
  handle.restoreIo()
end)

test('a track that reports no sides at all still has a width', function()
  local handle = withTrack({ trackSides = function() return nil end })
  local point = track.outline(50).points[1]
  near(point.halfLeft, 5)
  near(point.halfRight, 5)
  handle.restoreIo()
end)

test('the outline is sampled once and then cached', function()
  local handle = withTrack({ trackRadius = 500 })

  local calls = 0
  local real = ac.trackProgressToWorldCoordinate
  ac.trackProgressToWorldCoordinate = function(p)
    calls = calls + 1
    return real(p)
  end

  track.currentOutline(50)
  local afterFirst = calls
  track.currentOutline(50)
  eq(calls, afterFirst, 'the second call sampled nothing')
  eq(afterFirst > 0, true)

  handle.restoreIo()
end)

test('a track with no spline is cached too, so nothing re-samples per frame', function()
  local handle = withTrack({ noTrackSpline = true })

  local asked = 0
  local real = ac.hasTrackSpline
  ac.hasTrackSpline = function()
    asked = asked + 1
    return real()
  end

  eq(track.currentOutline(50), nil)
  eq(track.currentOutline(50), nil)
  eq(asked, 1, 'the empty answer is remembered')

  handle.restoreIo()
end)

test('changing track drops the cache', function()
  local handle = withTrack({ trackRadius = 500, trackID = 'first' })
  local first = track.currentOutline(50)
  handle.restoreIo()

  -- A new session on another track, without clearing the cache by hand.
  handle = fakes.install({ trackRadius = 100, trackID = 'second' })
  local second = track.currentOutline(50)
  eq(rawequal(first, second), false, 'a different track, a different outline')
  near(math.sqrt(second.points[1].x ^ 2 + second.points[1].y ^ 2), 100, 1e-9)
  handle.restoreIo()
end)
