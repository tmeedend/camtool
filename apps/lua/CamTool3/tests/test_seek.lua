--[[
  Tests for core/seek.lua: turning "here on the track" into "there in the
  replay".

  A replay is several laps of the same track positions, so almost every
  question here is really about WHICH pass -- and the answer is always the one
  nearest in time to where the replay already is. A search that quietly
  returned the first lap would look right on a one-lap replay and be wrong on
  every real one, which is exactly the kind of thing that has to be pinned
  before the game is ever launched.
]]

local runner = require('tests/runner')
local seek = require('core/seek')

local test, eq, near = runner.test, runner.eq, runner.near

---A replay of `laps` laps, `framesPerLap` frames each, sampled every frame.
---The car runs at a constant pace, which is not realistic and does not need
---to be: the index records what it is told.
local function replay(laps, framesPerLap, from)
  local index = seek.new()
  from = from or 0
  for frame = from, laps * framesPerLap - 1 do
    seek.record(index, (frame % framesPerLap) / framesPerLap, frame)
  end
  return index
end

--------------------------------------------------------------------------
-- Buckets
--------------------------------------------------------------------------

test('a lap is cut into buckets, first to last', function()
  eq(seek.bucketOf(0), 1)
  eq(seek.bucketOf(0.5), seek.BUCKETS / 2 + 1)
  eq(seek.bucketOf(0.99999), seek.BUCKETS)
end)

test('the lap is a ring, so a position at 1 is a position at 0', function()
  -- A replay can report a hair past the line, and that is the beginning of a
  -- lap rather than the end of one.
  eq(seek.bucketOf(1), 1)
  eq(seek.bucketOf(1.25), seek.bucketOf(0.25))
  eq(seek.bucketOf(-0.25), seek.bucketOf(0.75))
end)

--------------------------------------------------------------------------
-- Recording
--------------------------------------------------------------------------

test('what was recorded can be found again', function()
  local index = seek.new()
  seek.record(index, 0.25, 1500)
  local frame, away = seek.nearest(index, 0.25, 0)
  eq(frame, 1500)
  eq(away, 0, 'the target itself, not a neighbour')
end)

test('an empty index knows nothing', function()
  eq(seek.nearest(seek.new(), 0.5, 0), nil)
end)

test('a car standing still does not fill the memory of its bucket', function()
  -- Thousands of frames in one place would push out every real lap. They are
  -- one visit, and one visit is one entry.
  local index = seek.new()
  for frame = 0, 60 do seek.record(index, 0.25, frame) end

  local bucket = seek.bucketOf(0.25)
  eq(index.count[bucket], 1)
  eq(seek.nearest(index, 0.25, 0), 60, 'and it is the latest of them')
end)

test('a bucket remembers each lap separately', function()
  local index = seek.new()
  seek.record(index, 0.25, 1000)
  seek.record(index, 0.25, 5000)
  seek.record(index, 0.25, 9000)
  eq(index.count[seek.bucketOf(0.25)], 3)
end)

test('past its memory a bucket keeps the most recent passes', function()
  local index = seek.new()
  for lap = 1, seek.PASSES + 3 do
    seek.record(index, 0.4, lap * 10000)
  end

  local bucket = seek.bucketOf(0.4)
  eq(index.count[bucket], seek.PASSES, 'it cannot grow past its size')

  -- The newest lap is still there; the first ones have gone.
  eq(seek.nearest(index, 0.4, (seek.PASSES + 3) * 10000),
    (seek.PASSES + 3) * 10000)
end)

test('nonsense is not recorded', function()
  local index = seek.new()
  seek.record(index, 0 / 0, 100)
  seek.record(index, 0.5, 0 / 0)
  seek.record(index, 0.5, -5)
  eq(seek.nearest(index, 0.5, 0), nil)
end)

test('clearing really clears', function()
  local index = replay(3, 6000)
  eq(seek.nearest(index, 0.5, 0) ~= nil, true)
  seek.clear(index)
  eq(seek.nearest(index, 0.5, 0), nil)
  eq(seek.framesPerLap(index), nil)
end)

--------------------------------------------------------------------------
-- Which pass: the whole point
--------------------------------------------------------------------------

test('the nearest pass in time wins, not the first lap', function()
  -- The failure this exists to prevent: a search that always answers the
  -- first lap looks correct on a single-lap replay and throws the viewer back
  -- to the beginning of every real one.
  local index = seek.new()
  seek.record(index, 0.25, 1000)
  seek.record(index, 0.25, 5000)
  seek.record(index, 0.25, 9000)

  eq(seek.nearest(index, 0.25, 4800), 5000, 'the lap we are in')
  eq(seek.nearest(index, 0.25, 8900), 9000, 'the last one')
  eq(seek.nearest(index, 0.25, 900), 1000, 'and the first, when that is nearest')
end)

test('nearest means nearest, backwards as readily as forwards', function()
  local index = seek.new()
  seek.record(index, 0.6, 2000)
  seek.record(index, 0.6, 8000)
  eq(seek.nearest(index, 0.6, 2400), 2000, 'behind us, but closer')
end)

test('a five lap replay answers with the lap being watched', function()
  local index = replay(5, 6000)
  -- Three and a half laps in, asking for a quarter of the way round.
  local frame = seek.nearest(index, 0.25, 21000)

  -- Lap four begins at 18000, so a quarter of the way round is about 19500.
  -- About, and not exactly: a bucket is a stretch of track, not a point, and
  -- what comes back is the last frame recorded inside it -- some six frames
  -- later at this pace. Precision finer than a bucket is not on offer and is
  -- not wanted; the point is the lap.
  near(frame, 19500, 10, 'lap four, not lap one')
end)

--------------------------------------------------------------------------
-- Across the start line
--------------------------------------------------------------------------

test('a target just before the line finds a pass just after it', function()
  -- The two are neighbours on the track and a lap apart in the numbers, which
  -- is where a search that treats the lap as a straight line goes wrong.
  local index = seek.new()
  seek.record(index, 0.0005, 4000)

  local frame, away = seek.nearest(index, 0.9995, 4000)
  eq(frame, 4000)
  eq(away ~= nil and away <= 2, true, 'a bucket or two away, round the line')
end)

test('a target just after the line finds a pass just before it', function()
  local index = seek.new()
  seek.record(index, 0.9995, 4000)
  eq(seek.nearest(index, 0.0005, 4000), 4000)
end)

test('two positions either side of the line are close together', function()
  near(seek.gap(0.99, 0.01), 0.02, 1e-9)
  near(seek.gap(0.01, 0.99), 0.02, 1e-9)
  near(seek.gap(0.25, 0.75), 0.5, 1e-9, 'and the far side is the far side')
end)

--------------------------------------------------------------------------
-- Stretches the replay never played
--------------------------------------------------------------------------

test('a stretch never visited has nothing, and says so', function()
  -- A replay started mid-lap, or one that ends in a retirement. The caller
  -- has to guess and correct rather than be handed a wrong answer.
  local index = seek.new()
  seek.record(index, 0.10, 1000)
  seek.record(index, 0.12, 1100)

  eq(seek.nearest(index, 0.80, 1000, 8), nil)
end)

test('a near miss comes back with how far off it is', function()
  local index = seek.new()
  seek.record(index, 0.500, 3000)

  local frame, away = seek.nearest(index, 0.503, 0)
  eq(frame, 3000)
  eq(away ~= nil and away > 0, true, 'close, but not the bucket asked for')
end)

test('the caller decides how far to look', function()
  local index = seek.new()
  seek.record(index, 0.5, 3000)
  eq(seek.nearest(index, 0.52, 0, 2), nil, 'twenty buckets away, looking two')
  eq(seek.nearest(index, 0.52, 0, 40) ~= nil, true)
end)

--------------------------------------------------------------------------
-- Correcting a guess
--------------------------------------------------------------------------

test('landing short asks for more frames, landing long asks for fewer', function()
  eq(seek.refine(1000, 0.20, 0.25, 6000) > 1000, true)
  eq(seek.refine(1000, 0.30, 0.25, 6000) < 1000, true)
end)

test('a correction is the short way round the lap', function()
  -- From 0.98 to 0.02 is four hundredths forwards, not ninety-six backwards.
  local next_ = seek.refine(5000, 0.98, 0.02, 6000)
  near(next_, 5000 + 0.04 * 6000, 1e-6)
end)

test('a correction converges on the target', function()
  -- The loop the app will actually run, played out against a car of known
  -- pace: five tries is more than enough.
  local framesPerLap = 6000
  local target = 0.371
  local frame = 0

  for _ = 1, 5 do
    local observed = (frame % framesPerLap) / framesPerLap
    frame = seek.refine(frame, observed, target, framesPerLap, 30000)
  end

  near((frame % framesPerLap) / framesPerLap, target, 1e-6)
end)

test('a correction never lands outside the replay', function()
  -- Whichever way round it goes, and whatever it is asked, the answer is a
  -- frame the replay actually has.
  for _, case in ipairs({
    { 100, 0.1, 0.9 }, { 29900, 0.9, 0.1 }, { 0, 0.5, 0.5001 },
    { 30000, 0.2, 0.8 }, { 15000, 0.99, 0.01 },
  }) do
    local next_ = seek.refine(case[1], case[2], case[3], 6000, 30000)
    eq(next_ >= 0 and next_ <= 30000, true,
      string.format('frame %d gave %s', case[1], tostring(next_)))
  end
end)

test('a correction with nothing to go on gives nothing', function()
  eq(seek.refine(1000, 0.2, 0.3, nil), nil)
  eq(seek.refine(1000, 0.2, 0.3, 0), nil, 'a lap of no frames is no measure')
  eq(seek.refine(1000, 0 / 0, 0.3, 6000), nil)
end)

--------------------------------------------------------------------------
-- How long a lap takes, read off the index
--------------------------------------------------------------------------

test('two passes through one bucket are a lap apart', function()
  local index = seek.new()
  seek.record(index, 0.25, 1000)
  seek.record(index, 0.25, 7000)
  eq(seek.framesPerLap(index), 6000)
end)

test('a real index gives the lap length', function()
  eq(seek.framesPerLap(replay(4, 6000)), 6000)
end)

test('one lap is not enough to measure one', function()
  eq(seek.framesPerLap(replay(1, 6000)), nil)
end)

test('a stop or a pit stop makes gaps longer, never shorter', function()
  -- So the smallest gap is the honest lap, and a long one does not poison it.
  local index = seek.new()
  seek.record(index, 0.25, 1000)
  seek.record(index, 0.25, 7000)
  seek.record(index, 0.25, 40000)
  eq(seek.framesPerLap(index), 6000)
end)

--------------------------------------------------------------------------
-- Measuring the pace from two probes
--------------------------------------------------------------------------

test('two probes give the length of a lap', function()
  -- The fallback for a replay too short to have a bucket with two passes in
  -- it: there is nothing to subtract, so the pace is measured instead.
  eq(seek.paceFrom(1000, 0.10, 1600, 0.20), 6000)
end)

test('a measurement across the start line is still a measurement', function()
  near(seek.paceFrom(1000, 0.95, 1600, 0.05), 6000, 1e-9)
end)

test('going backwards through the replay measures the same lap', function()
  near(seek.paceFrom(1600, 0.20, 1000, 0.10), 6000, 1e-9)
end)

test('a measurement over too short a distance is refused', function()
  -- A hundredth of a lap is a few frames of travel, and dividing by it turns
  -- one frame of noise into a pace out by a factor of ten.
  eq(seek.paceFrom(1000, 0.200, 1005, 0.2005), nil)
end)

test('two probes at the same frame, or the same place, measure nothing', function()
  eq(seek.paceFrom(1000, 0.1, 1000, 0.3), nil)
  eq(seek.paceFrom(1000, 0.2, 1600, 0.2), nil)
end)

test('a pace measured backwards in one axis only is refused', function()
  -- Frames forward, position backward: the car cannot have done that, so the
  -- pair is noise and a negative lap length would poison every correction.
  eq(seek.paceFrom(1000, 0.30, 1600, 0.20), nil)
end)

test('nonsense measures nothing', function()
  eq(seek.paceFrom(0 / 0, 0.1, 1600, 0.2), nil)
  eq(seek.paceFrom(1000, 0.1, 1600, 0 / 0), nil)
end)

test('when the short way leaves the replay, it goes the long way round', function()
  -- Found by a test of the whole thing, not by reading: near the start of a
  -- replay the nearer pass is often before frame zero, and clamping to zero
  -- leaves the search stuck against the wall repeating itself.
  --
  -- Frame 100, a sixtieth of the way round, wanting two thirds. The short way
  -- is backwards, out of the replay; the long way is forwards, inside it.
  local next_ = seek.refine(100, 0.0167, 0.62, 6000, 30000)
  eq(next_ > 100, true, 'forwards, got ' .. tostring(next_))
  near(next_, 100 + (0.62 - 0.0167) * 6000, 1)
end)

test('and the long way round at the end of a replay goes backwards', function()
  local next_ = seek.refine(29900, 0.9, 0.1, 6000, 30000)
  eq(next_ < 29900, true, 'backwards, got ' .. tostring(next_))
end)

test('with nowhere to go it stays inside the replay', function()
  -- A replay of half a lap: neither way round reaches, so it clamps and the
  -- caller runs out of tries and says so.
  local next_ = seek.refine(100, 0.05, 0.60, 6000, 200)
  eq(next_ >= 0 and next_ <= 200, true)
end)
