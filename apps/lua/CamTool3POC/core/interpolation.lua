--[[
  Keyframe interpolation -- pure logic, no ac/CSP dependency.

  Ported from classes/CubicBezierInterpolation.py. Checked against fixtures
  generated from that very module (tools/gen_golden.py), not against a reading
  of it: these curves shaped videos people already published, so "close enough"
  is not good enough.

  Two deliberate departures from the original, both structural rather than
  behavioural:

  1. The legacy is a singleton that keeps its working variables on self
     (self.i, self.points, self.ratio...), so concurrent or nested calls leak
     state into each other. CLAUDE.md flags this as the first thing to fix.
     Everything here is a local.

  2. The legacy wraps each function in try/except and calls debug(e), which
     swallows the error and returns nil. Lua has no equivalent ambient handler,
     and silently returning nil is what makes these bugs hard to find, so
     errors are left to propagate. Callers decide.

  Still to port: interpolate (cubic bezier) and interpolate_spline.
]]

local interpolation = {}

---Drop entries with no position or no value, and pair the rest up.
---Faithful to __sanitize: it does NOT sort and does NOT deduplicate, so
---callers keep whatever order they stored.
---
---Divergence worth knowing: Python iterates over y and indexes into x, so a
---short x raises IndexError, which debug(e) swallows into a nil result. Lua
---reads nil instead and quietly drops the entry, yielding a shorter list. Feed
---this equal-length lists.
local function sanitize(x, y)
  local points = {}
  for i = 1, #y do
    if x[i] ~= nil and y[i] ~= nil then
      points[#points + 1] = { x = x[i], y = y[i] }
    end
  end
  return points
end

---Sine easing between keyframes: eases in and out of every keyframe, which is
---why the legacy comes to a visible stop at each one (issue #37).
---Used for FOV, shake, and tracking offsets and strengths.
---@param time number
---@param x number[] @keyframe positions
---@param y number[] @keyframe values
---@return number|nil
function interpolation.interpolate_sin(time, x, y)
  if #y == 0 then return nil end

  local points = sanitize(x, y)
  if #points == 0 then return nil end
  if #points == 1 then return points[1].y end

  -- The legacy computes control points here and then never reads them in this
  -- function. Not reproduced: it is dead work, and it cannot change the result.

  local last = points[#points]

  -- The legacy expresses this as a test inside the search loop, but the
  -- condition does not depend on the loop variable, so it always decides on the
  -- first iteration. Hoisted, same outcome.
  if time >= last.x then return last.y end

  local activeIndex = nil
  for i = 1, #points do
    if time > points[i].x then activeIndex = i end
  end

  -- Before the first keyframe: hold the first value.
  if activeIndex == nil then return points[1].y end

  local from = points[activeIndex]
  local to = points[activeIndex + 1]

  local t = time - from.x
  local tx = to.x - from.x

  local ratio
  if tx ~= 0 then
    ratio = math.sin((t / tx) * math.pi - math.pi / 2) * 0.5 + 0.5
  else
    -- Two keyframes at the same position: jump straight to the later value.
    ratio = 1
  end

  if ratio > 1 then ratio = 1 elseif ratio < 0 then ratio = 0 end

  return from.y * (1 - ratio) + to.y * ratio
end

---Plain linear interpolation, used for recorded splines.
---With cyclic = true the ends are joined through a wrap of length 1, which is
---how a lap closes: track position is normalised 0..1, so the gap from the last
---sample back to the first is (x[1] + 1 - x[n]).
---
---Unlike the other two, this one does NOT sanitize: it indexes x and y
---directly, so a nil in either blows up rather than being skipped. Faithful to
---the legacy.
---@param time number
---@param x number[] @sample positions
---@param y number[] @sample values
---@param cyclic boolean|nil
---@return number|nil
function interpolation.interpolate_spline(time, x, y, cyclic)
  local n = #y
  if n == 0 then return nil end
  if n == 1 then return y[1] end

  local first, last = 1, n

  -- Before the first sample.
  if x[first] >= time then
    if not cyclic then return y[first] end
    local t = time - x[last] + 1
    local tx = x[first] - x[last] + 1
    local ratio = tx ~= 0 and (t / tx) or 1
    return y[last] * (1 - ratio) + y[first] * ratio
  end

  -- At or after the last sample.
  if x[last] <= time then
    if not cyclic then return y[last] end
    local t = time - x[last]
    local tx = x[first] + 1 - x[last]
    local ratio = tx ~= 0 and (t / tx) or 1
    return y[last] * (1 - ratio) + y[first] * ratio
  end

  -- First sample at or past the query point; the segment starts just before it.
  -- The guards above already rule out i == first, so the legacy's early return
  -- for that case is unreachable. Kept out rather than ported as dead code.
  local index = nil
  for i = 1, n do
    if x[i] >= time then
      index = i - 1
      break
    end
  end

  -- The legacy leaves this index on the instance between calls and exposes it
  -- through get_last_active_index(). Nothing outside the module reads it
  -- (Camera.py keeps its own spline index), so it is dropped here.
  if index == nil or index < first then return y[first] end

  local t = time - x[index]
  local tx = x[index + 1] - x[index]
  local ratio = tx ~= 0 and (t / tx) or 1

  return y[index] * (1 - ratio) + y[index + 1] * ratio
end

return interpolation
