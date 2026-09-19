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

--------------------------------------------------------------------------
-- What broke on Spa
--------------------------------------------------------------------------

test('a CSP function that is not type "function" is still called', function()
  -- The bug, reproduced. CSP binds much of the `ac` namespace through
  -- LuaJIT's FFI, and a C function pointer is cdata: callable, but `type`
  -- says 'cdata'. The guard here asked for 'function', so on a perfectly
  -- normal Kunos circuit the adapter decided the track had no AI spline and
  -- the panel said so.
  --
  -- A table with __call stands in for the cdata: same shape of failure,
  -- and it can be written in plain Lua.
  local handle = withTrack({ trackRadius = 500 })

  local real = ac.hasTrackSpline
  ac.hasTrackSpline = setmetatable({}, { __call = function() return real() end })

  eq(type(ac.hasTrackSpline) ~= 'function', true, 'the case under test')
  eq(track.hasOutline(), true, 'callable is what matters, not what type says')
  eq(track.outline(50) ~= nil, true)

  handle.restoreIo()
end)

test('the sides are read even when they come bound the same way', function()
  local handle = withTrack({ trackRadius = 500 })

  ac.getTrackAISplineSides = setmetatable({}, {
    __call = function() return { x = 8, y = 9 } end,
  })

  local point = track.outline(50).points[1]
  near(point.halfLeft, 8)
  near(point.halfRight, 9)

  handle.restoreIo()
end)

test('a function that raises when called is treated as absent', function()
  -- pcall is what settles it, now that the type no longer can.
  local handle = withTrack({})
  ac.hasTrackSpline = function() error('not available in this build') end
  eq(track.hasOutline(), false)
  local outline, reason = track.outline(50)
  eq(outline, nil)
  eq(reason, track.NO_SPLINE_API, 'a build whose API does not work, not a bare track')
  handle.restoreIo()
end)

test('an ac namespace without the function at all still answers', function()
  local handle = withTrack({})
  ac.hasTrackSpline = nil
  eq(track.hasOutline(), false)
  handle.restoreIo()
end)

--------------------------------------------------------------------------
-- Saying which failure it was
--------------------------------------------------------------------------

test('each way of failing names itself', function()
  local handle = withTrack({ noTrackSpline = true })
  local _, reason = track.outline(5)
  eq(reason, track.NO_SPLINE)
  handle.restoreIo()

  handle = withTrack({ trackLengthM = 0 })
  _, reason = track.outline(5)
  eq(reason, track.NO_LENGTH)
  handle.restoreIo()

  handle = withTrack({})
  ac.trackProgressToWorldCoordinate = function() return nil end
  _, reason = track.outline(5)
  eq(reason, track.NO_POINTS)
  handle.restoreIo()
end)

test('a track with an outline has nothing to explain', function()
  local handle = withTrack({ trackRadius = 500 })
  local outline, reason = track.currentOutline(50)
  eq(outline ~= nil, true)
  eq(reason, nil)
  handle.restoreIo()
end)

test('the reason is logged once per track, not once per frame', function()
  local handle = withTrack({ noTrackSpline = true })

  track.currentOutline(50)
  track.currentOutline(50)
  track.currentOutline(50)

  local said = 0
  for i = 1, #handle.logs do
    if handle.logs[i]:find('no track outline', 1, true) then said = said + 1 end
  end
  eq(said, 1, 'logged on the miss, not on the cached answers')
  eq(handle.logs[#handle.logs]:find(track.NO_SPLINE, 1, true) ~= nil, true,
    'and it says which failure it was')

  handle.restoreIo()
end)

--------------------------------------------------------------------------
-- Not giving up for the whole session
--------------------------------------------------------------------------

test('a track that was not ready yet gets asked again', function()
  -- The app loads when its window is first opened, which can be while the
  -- session is still coming up. Keeping that first "no" for good would leave
  -- the map empty for the rest of the session over a question that answers
  -- itself a second later.
  local handle = withTrack({ trackRadius = 500 })

  local ready = false
  ac.hasTrackSpline = function() return ready end

  eq(track.currentOutline(50), nil, 'nothing yet')

  ready = true
  local outline
  for _ = 1, 120 do
    outline = track.currentOutline(50)
    if outline ~= nil then break end
  end
  eq(outline ~= nil, true, 'the map arrives once the track does')

  handle.restoreIo()
end)

test('retrying does not mean asking on every single draw', function()
  local handle = withTrack({ noTrackSpline = true })

  local asked = 0
  ac.hasTrackSpline = function()
    asked = asked + 1
    return false
  end

  for _ = 1, 100 do track.currentOutline(50) end
  eq(asked <= 3, true, 'a couple of retries in a hundred draws, not a hundred')
  eq(asked >= 1, true)

  handle.restoreIo()
end)

test('an outline that worked is never re-sampled', function()
  -- The retry is for failures only. Sampling a real circuit is far too slow
  -- to do again, and the track does not change shape mid-session.
  local handle = withTrack({ trackRadius = 500 })

  local calls = 0
  local real = ac.trackProgressToWorldCoordinate
  ac.trackProgressToWorldCoordinate = function(p)
    calls = calls + 1
    return real(p)
  end

  track.currentOutline(50)
  local afterFirst = calls
  for _ = 1, 200 do track.currentOutline(50) end
  eq(calls, afterFirst, 'two hundred draws, one sampling')

  handle.restoreIo()
end)

test('the log carries the numbers, not just the verdict', function()
  -- What was missing the first time this ran on Spa: the message said there
  -- was no outline and nothing about why the adapter thought so.
  local handle = withTrack({ noTrackSpline = true })
  track.currentOutline(50)

  local line = nil
  for i = 1, #handle.logs do
    if handle.logs[i]:find('no track outline', 1, true) then line = handle.logs[i] end
  end

  eq(line ~= nil, true)
  eq(line:find('hasTrackSpline is', 1, true) ~= nil, true,
    'what type the game actually gave us')
  eq(line:find('trackLengthM is', 1, true) ~= nil, true)

  handle.restoreIo()
end)
