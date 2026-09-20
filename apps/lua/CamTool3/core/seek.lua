--[[
  Finding the moment in a replay when the car was at a given point of the
  track -- pure logic, no ac/CSP dependency.

  The problem: the ribbon says "bring the car here", and here is a position on
  the track, while a replay is addressed by frame number. Nothing in the game
  converts between the two. But the app already reads both every frame, one
  beside the other, so the conversion can be written down as it goes by.

  THE INDEX. A flat table of buckets, one per quantised track position, each
  holding the last few frames the car was seen there. Built as the replay
  plays, for the cost of a multiply and a store per frame -- no allocation
  after the first call, and a size that cannot grow.

  WHY SEVERAL FRAMES PER BUCKET. A replay covers several laps, so a point of
  the track was passed several times, and "bring the car here" means the pass
  NEAREST IN TIME to where the replay already is -- not the first lap, which
  is what a single frame per bucket would always give.

  WHAT IT CANNOT DO. A stretch the replay has never played has no entry, and
  no amount of arithmetic invents one. The caller then guesses, moves, reads
  where it landed and corrects -- see refine -- and every such probe fills in
  another bucket.
]]

local seek = {}

---How finely the lap is cut up. 1024 buckets is about 6.8 metres on Spa and
---4 on a short circuit: finer than anyone can see a camera hand over, and a
---power of two, which keeps the arithmetic to a multiply and a floor.
seek.BUCKETS = 1024

---How many passes a bucket remembers. Eight laps of history is more than a
---replay usually holds, and the whole index is 8192 numbers however long the
---session runs.
seek.PASSES = 8

---Frames closer together than this are the same pass through the bucket, not
---two visits, and overwrite rather than accumulate.
---
---A car crossing one bucket takes several frames, and a car stopped in one
---takes thousands. Without this, standing still would fill the ring and push
---out the real laps. Two seconds at 60 frames a second, and a lap is never
---that short.
seek.SAME_PASS_FRAMES = 120

local function isFinite(v)
  return type(v) == 'number' and v == v and v - v == 0
end

---Which bucket a lap position falls in, 1..BUCKETS.
---
---Positions outside the lap are wrapped rather than clamped: a replay can
---report slightly past 1 at the line, and that is the start of the lap, not
---its end.
---@param position number @0..1
---@return number
function seek.bucketOf(position)
  local p = position % 1
  if p < 0 then p = p + 1 end
  local bucket = math.floor(p * seek.BUCKETS) + 1
  if bucket > seek.BUCKETS then bucket = seek.BUCKETS end
  return bucket
end

---An empty index, allocated once and then written in place for ever.
---@return table
function seek.new()
  local index = { frames = {}, count = {}, head = {} }

  for i = 1, seek.BUCKETS * seek.PASSES do index.frames[i] = -1 end
  for b = 1, seek.BUCKETS do
    index.count[b] = 0
    index.head[b] = 0
  end

  return index
end

---Forget everything. Called when the replay or the car changes underneath us,
---since the frames recorded mean nothing then.
---@param index table
function seek.clear(index)
  if type(index) ~= 'table' then return end
  for i = 1, seek.BUCKETS * seek.PASSES do index.frames[i] = -1 end
  for b = 1, seek.BUCKETS do
    index.count[b] = 0
    index.head[b] = 0
  end
end

---Note that the car was at `position` on `frame`.
---
---This runs every frame of every replay. It allocates nothing, loops over
---nothing, and touches three array slots.
---@param index table
---@param position number @0..1
---@param frame number
function seek.record(index, position, frame)
  if type(index) ~= 'table' then return end
  if not isFinite(position) or not isFinite(frame) or frame < 0 then return end

  local bucket = seek.bucketOf(position)
  local base = (bucket - 1) * seek.PASSES
  local head = index.head[bucket]

  -- Still the same pass through this bucket: move the entry rather than add
  -- one beside it.
  if head > 0 then
    local newest = index.frames[base + head]
    if newest >= 0 and math.abs(frame - newest) <= seek.SAME_PASS_FRAMES then
      index.frames[base + head] = frame
      return
    end
  end

  head = head + 1
  if head > seek.PASSES then head = 1 end
  index.head[bucket] = head
  index.frames[base + head] = frame
  if index.count[bucket] < seek.PASSES then
    index.count[bucket] = index.count[bucket] + 1
  end
end

---The frame in one bucket closest in time to where the replay is now.
---
---The lap is a ring, so a bucket index off either end comes back on the
---other: a target at 0.999 has 0.001 for a neighbour.
---@return number|nil frame, number|nil distance
local function bestInBucket(index, bucket, currentFrame)
  while bucket < 1 do bucket = bucket + seek.BUCKETS end
  while bucket > seek.BUCKETS do bucket = bucket - seek.BUCKETS end

  local base = (bucket - 1) * seek.PASSES
  local best, bestDistance = nil, nil

  for slot = 1, seek.PASSES do
    local frame = index.frames[base + slot]
    if frame >= 0 then
      local distance = math.abs(frame - currentFrame)
      if bestDistance == nil or distance < bestDistance then
        best, bestDistance = frame, distance
      end
    end
  end

  return best, bestDistance
end

---The recorded frame nearest in time to where the replay is now.
---
---Searches the bucket the target falls in, then widens outwards a bucket at a
---time, wrapping around the start line -- the track is a loop, and a target
---at 0.999 has 0.001 for a neighbour.
---@param index table
---@param target number @lap position wanted, 0..1
---@param currentFrame number @where the replay is, so "nearest" means in time
---@param maxBuckets number|nil @how far to widen, default 8
---@return number|nil frame
---@return number|nil bucketsAway @0 when the target itself was recorded
function seek.nearest(index, target, currentFrame, maxBuckets)
  if type(index) ~= 'table' then return nil, nil end
  if not isFinite(target) or not isFinite(currentFrame) then return nil, nil end

  maxBuckets = isFinite(maxBuckets) and maxBuckets or 8
  local wanted = seek.bucketOf(target)

  for away = 0, maxBuckets do
    local before, beforeDistance = bestInBucket(index, wanted - away, currentFrame)
    if away == 0 then
      if before ~= nil then return before, 0 end
    else
      local after, afterDistance = bestInBucket(index, wanted + away, currentFrame)
      if before ~= nil and (after == nil or beforeDistance <= afterDistance) then
        return before, away
      end
      if after ~= nil then return after, away end
    end
  end

  return nil, nil
end

---How many frames a lap takes, read off the index.
---
---Two passes through the same bucket are one lap apart, which is the whole
---measurement. The smallest such gap is taken: a car that pitted or stopped
---makes some gaps longer, none shorter.
---@param index table
---@return number|nil
function seek.framesPerLap(index)
  if type(index) ~= 'table' then return nil end

  local best = nil

  for bucket = 1, seek.BUCKETS do
    if index.count[bucket] > 1 then
      local base = (bucket - 1) * seek.PASSES
      -- Every pair in the bucket, which is at most 8 of them.
      for a = 1, seek.PASSES do
        local first = index.frames[base + a]
        if first >= 0 then
          for b = a + 1, seek.PASSES do
            local second = index.frames[base + b]
            if second >= 0 then
              local gap = math.abs(second - first)
              if gap > 0 and (best == nil or gap < best) then best = gap end
            end
          end
        end
      end
    end
  end

  return best
end

---Where to try next, having landed somewhere that was not the target.
---
---The correction is the shortest way round the lap: from 0.98 to 0.02 is four
---hundredths forwards, not ninety-six backwards.
---@param frame number @where the probe landed
---@param observed number @the lap position it turned out to be
---@param target number @the lap position wanted
---@param framesPerLap number
---@param lastFrame number|nil @the end of the replay, to stay inside it
---@return number|nil @the next frame to try
function seek.refine(frame, observed, target, framesPerLap, lastFrame)
  if not isFinite(frame) or not isFinite(observed) or not isFinite(target) then
    return nil
  end
  if not isFinite(framesPerLap) or framesPerLap <= 0 then return nil end

  local delta = (target % 1) - (observed % 1)
  if delta > 0.5 then delta = delta - 1 end
  if delta < -0.5 then delta = delta + 1 end

  local next_ = frame + delta * framesPerLap

  if next_ < 0 then next_ = 0 end
  if isFinite(lastFrame) and next_ > lastFrame then next_ = lastFrame end

  return next_
end

---How far apart two lap positions are, the short way round. 0 to 1, where
---0.5 is the far side of the track.
---@return number|nil
function seek.gap(a, b)
  if not isFinite(a) or not isFinite(b) then return nil end
  local delta = math.abs((a % 1) - (b % 1))
  if delta > 0.5 then delta = 1 - delta end
  return delta
end

return seek
