--[[
  Camera shake -- pure logic, no ac/CSP dependency.

  Two separate effects, which the UI labels "Camera" and "Tracking" under Shake,
  and which do quite different things:

    rotation()       shakes the camera's aim          camera_shake_strength
    trackingOffset() wobbles the point it aims at     camera_offset_shake_strength

  Both are built from sums of sines at unrelated frequencies, which is what keeps
  them from looking periodic, and both grow with `momentum` -- how fast the camera
  is currently panning -- so a still camera barely trembles while a fast pan
  judders.

  Only the first is keyframable. camera_offset_shake_strength is read off the
  camera and never interpolated, which is issue #25; see docs/legacy.md.

  THE CLOCK MATTERS. The legacy derives its time from the replay position when
  the replay is synced, so the same footage shakes identically every time it is
  played. That determinism is the point for video work -- a shake driven by wall
  clock would differ on every render. Callers pass `t` and own that choice.
]]

local shake = {}

---Matches __n_prev_cam_heading in Camera.py.
shake.DEFAULT_MOMENTUM_WINDOW = 50

---How fast the camera is panning, 0..1, from its recent heading history.
---Ported from Camera.__set_offset_shake: the latest heading against the mean of
---the rest, scaled hard and clamped.
---@param headings number[] @most recent first
---@return number
function shake.momentum(headings)
  if type(headings) ~= 'table' or #headings < 2 then return 0 end

  local sum = 0
  for i = 2, #headings do
    sum = sum + headings[i]
  end
  local average = sum / (#headings - 1)

  local momentum = math.abs(headings[1] - average) * 25
  if momentum > 1 then momentum = 1 end
  return momentum
end

---Shake applied to the camera's aim.
---@param strength number @camera_shake_strength, 0..1
---@param t number @shake clock, see the note above
---@param momentum number @0..1
---@param replaySpeed number|nil @scales the result, as in the legacy
---@return number pitch, number heading @radians, to add to the aim
function shake.rotation(strength, t, momentum, replaySpeed)
  strength = (strength or 0) * ((momentum or 0) * 0.2 + 0.8) * 0.001

  -- Three sines per axis at unrelated frequencies. The pitch set reuses 8,
  -- which the heading set also uses, so the two axes are not independent --
  -- faithful to the legacy, odd as it looks.
  local heading = (math.sin(t * 8) + math.sin(t * 5) + math.sin(t)) * strength
  local pitch = (math.sin(t * 7) + math.sin(t * 2) + math.sin(t * 8)) * strength

  local speed = replaySpeed == nil and 1 or replaySpeed
  return pitch * speed, heading * speed
end

---Wobble added to the tracking offset, moving the aim point along the car's
---path rather than rotating the camera.
---
---The two sine terms are crossfaded by momentum: a slow camera gets the beating
---of sin(3t)*sin(4t), a fast one the plain sin(9t).
---@param strength number @camera_offset_shake_strength
---@param t number
---@param momentum number @0..1
---@return number @added to |tracking_offset| before the lead/lag blend
function shake.trackingOffset(strength, t, momentum)
  momentum = momentum or 0

  local slow = math.sin(t * 3) * math.sin(t * 4)
  local fast = math.sin(t * 9)

  local offset = slow * (1 - momentum) + fast * momentum
  offset = offset * (momentum * 0.2 + 0.8)
  offset = offset * (strength or 0)
  offset = offset * 0.25

  -- LEGACY BUG, reproduced. The next line in Camera.py reads
  --     self.__shake_offset / info.graphics.replayTimeMultiplier
  -- with no assignment, so the division is computed and thrown away. The shake
  -- is therefore NOT scaled by replay speed, whatever the author intended.
  -- Dividing here would change how existing cameras shake in slow motion.

  return offset
end

return shake
