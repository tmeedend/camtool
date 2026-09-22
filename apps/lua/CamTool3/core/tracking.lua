--[[
  Tracking aim point -- pure logic, no ac/CSP dependency.

  Ported from Camera.calculate_cam_rot_to_tracking_car. The camera does not aim
  at the car: it aims at a blend of where the car is now and either where it has
  recently been (lagging) or where it is about to be (leading).

      average   = mean of the last 50 positions
      predicted = latest + (latest - average)      -- mirror the lag into a lead
      weight    = (|tracking_offset| + shake) / replay speed
      target    = base * weight + latest * (1 - weight)

  where base is `predicted` when tracking_offset is negative and `average` when
  it is positive. So the sign of tracking_offset chooses lead or lag, and its
  magnitude says how much. Dividing by replay speed keeps the lead constant in
  wall-clock terms when a replay is slowed down.

  ONE DELIBERATE DIVERGENCE. The legacy fills the buffer with 50 zero vectors,
  so for the first 50 frames of tracking the average is dragged toward the world
  origin and `predicted` overshoots away from it. This primes the buffer with
  the first real sample instead, so the aim is correct from frame one.

  That transient IS issue #16, the camera sliding when it activates -- 20
  degrees over 0.8 s for a trackside camera on a circuit modelled a kilometre
  from its origin, and 1.56 rad on the real CamTool 2 session tests/trace
  replays. It is no longer reproduced for legacy files: see
  playback.applyMode. Pass legacyZeroFill to bring it back and compare.
]]

local tracking = {}

---Matches __max_tracked_car_positions in Camera.py.
tracking.DEFAULT_SMOOTHNESS = 50

---@param smoothness number|nil @how many frames to average over
---@param legacyZeroFill boolean|nil @start from the origin, like the legacy
function tracking.new(smoothness, legacyZeroFill)
  local size = smoothness or tracking.DEFAULT_SMOOTHNESS
  if size < 1 then size = 1 end

  local buffer = { size = size, head = size, primed = false, x = {}, y = {}, z = {} }

  if legacyZeroFill then
    for i = 1, size do
      buffer.x[i], buffer.y[i], buffer.z[i] = 0, 0, 0
    end
    buffer.primed = true
  end

  return buffer
end

---Record a car position, in CamTool space (Z-up).
function tracking.push(buffer, x, y, z)
  if not buffer.primed then
    -- Prime every slot with this first sample: see the divergence note above.
    for i = 1, buffer.size do
      buffer.x[i], buffer.y[i], buffer.z[i] = x, y, z
    end
    buffer.primed = true
    buffer.head = 1
    return
  end

  buffer.head = buffer.head % buffer.size + 1
  buffer.x[buffer.head] = x
  buffer.y[buffer.head] = y
  buffer.z[buffer.head] = z
end

---@return number x, number y, number z
function tracking.latest(buffer)
  local h = buffer.head
  return buffer.x[h] or 0, buffer.y[h] or 0, buffer.z[h] or 0
end

---Mean of the buffer. Summed fresh each time rather than kept as a running
---total: 50 additions a frame is nothing, and a running sum drifts.
---@return number x, number y, number z
function tracking.average(buffer)
  local sx, sy, sz = 0, 0, 0
  for i = 1, buffer.size do
    sx = sx + (buffer.x[i] or 0)
    sy = sy + (buffer.y[i] or 0)
    sz = sz + (buffer.z[i] or 0)
  end
  return sx / buffer.size, sy / buffer.size, sz / buffer.size
end

---Where the car is heading, by mirroring its recent lag into a lead.
---@return number x, number y, number z
function tracking.predicted(buffer)
  local lx, ly, lz = tracking.latest(buffer)
  local ax, ay, az = tracking.average(buffer)
  return lx + (lx - ax), ly + (ly - ay), lz + (lz - az)
end

---The point the camera should aim at.
---@param buffer table
---@param offset number|nil @tracking_offset: negative leads, positive lags
---@param replaySpeed number|nil @0 or nil is treated as 1, as in the legacy
---@param shakeOffset number|nil @added to the magnitude; 0 until shake is ported
---@return number x, number y, number z
function tracking.target(buffer, offset, replaySpeed, shakeOffset)
  offset = offset or 0

  local speed = replaySpeed
  if speed == nil or speed == 0 then speed = 1 end

  -- Not clamped to [0, 1]: the legacy does not clamp either, and a
  -- tracking_offset beyond 1 is a real setting that overshoots on purpose.
  local weight = (math.abs(offset) + (shakeOffset or 0)) / speed

  local lx, ly, lz = tracking.latest(buffer)

  local bx, by, bz
  if offset < 0 then
    bx, by, bz = tracking.predicted(buffer)
  else
    bx, by, bz = tracking.average(buffer)
  end

  return bx * weight + lx * (1 - weight),
         by * weight + ly * (1 - weight),
         bz * weight + lz * (1 - weight)
end

return tracking
