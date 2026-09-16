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

--------------------------------------------------------------------------------
-- Cubic solving, for the bezier curve below.
--------------------------------------------------------------------------------

local function squared(f) return f * f end
local function cubed(f) return f * f * f end
local function cubicRoot(f) return f ^ (1 / 3) end

---Solve ax^2 + bx + c = 0, returning the first root in [0, 1], else nil.
---
---When the discriminant is negative, Python raises a TypeError comparing a
---complex root against a number, and the caller swallows that into None. Lua
---gets nan instead, and every comparison against nan is false, so it falls
---through to nil on its own. Same answer, no special case needed.
local function solveQuadratic(a, b, c)
  if a == 0 then
    -- Legacy oddity: with no equation left it hands back the constant, which is
    -- not a curve parameter at all and can land far outside [0, 1].
    if b == 0 then return c end
    return -c / b
  end

  local root = (squared(b) - 4 * a * c) ^ 0.5

  local result = (-b + root) / (2 * a)
  if result >= 0 and result <= 1 then return result end

  result = (-b - root) / (2 * a)
  if result >= 0 and result <= 1 then return result end

  return nil
end

---Solve ax^3 + bx^2 + cx + d = 0, returning the first root in [0, 1], else nil.
---@return number|nil
local function solveCubic(a, b, c, d)
  if a == 0 then return solveQuadratic(b, c, d) end
  if d == 0 then return 0 end

  b = b / a
  c = c / a
  d = d / a

  local q = (3.0 * c - squared(b)) / 9.0
  local r = (-27.0 * d + b * (9.0 * c - 2.0 * squared(b))) / 54.0
  local disc = cubed(q) + squared(r)
  local term1 = b / 3.0

  if disc > 0 then
    local s = r + disc ^ 0.5
    if s < 0 then s = -cubicRoot(-s) else s = cubicRoot(s) end

    local t = r - disc ^ 0.5
    if t < 0 then t = -cubicRoot(-t) else t = cubicRoot(t) end

    local result = -term1 + s + t
    if result >= 0 and result <= 1 then return result end

  elseif disc == 0 then
    local r13
    if r < 0 then r13 = -cubicRoot(-r) else r13 = cubicRoot(r) end

    local result = -term1 + 2.0 * r13
    if result >= 0 and result <= 1 then
      -- LEGACY BUG, reproduced deliberately. The Python here reads
      -- `return result` where every other line says `self.result`, so it raises
      -- NameError. GetY swallows that into None, interpolate then does
      -- arithmetic on None and swallows its own TypeError, and the parameter
      -- ends up nil for that frame.
      --
      -- Returning the root instead would be the obvious fix, and it would also
      -- silently change footage people have already cut. Not ours to decide:
      -- see the note in CLAUDE.md.
      --
      -- Python raises before trying the second root, so we stop here too.
      return nil
    end

    result = -(r13 + term1)
    if result >= 0 and result <= 1 then return result end

  else
    q = -q
    local dum1 = q * q * q
    dum1 = math.acos(r / (dum1 ^ 0.5))
    local r13 = 2.0 * (q ^ 0.5)

    local result = -term1 + r13 * math.cos(dum1 / 3.0)
    if result >= 0 and result <= 1 then return result end

    result = -term1 + r13 * math.cos((dum1 + 2.0 * math.pi) / 3.0)
    if result >= 0 and result <= 1 then return result end

    result = -term1 + r13 * math.cos((dum1 + 4.0 * math.pi) / 3.0)
    if result >= 0 and result <= 1 then return result end
  end

  return nil
end

-- Exposed for the golden-master tests, which drive the solver directly: it is
-- where the numerics live, and reaching every branch through interpolate alone
-- would take contrived keyframe geometry.
interpolation._solveCubic = solveCubic

---Evaluate a cubic bezier segment at `time`, given its four x and four y
---coordinates (knot, control, control, knot).
---Returns nil when the solver cannot place `time` on the curve -- the legacy
---swallows that into None the same way.
local function getY(time, x, y)
  local t

  if time == x[1] then
    -- Handled explicitly to dodge rounding at the ends.
    t = 0
  elseif time == x[4] then
    t = 1
  else
    local a = -x[1] + 3 * x[2] - 3 * x[3] + x[4]
    local b = 3 * x[1] - 6 * x[2] + 3 * x[3]
    local c = -3 * x[1] + 3 * x[2]
    local d = x[1] - time
    t = solveCubic(a, b, c, d)
    if t == nil then return nil end
  end

  return cubed(1 - t) * y[1]
    + 3 * t * squared(1 - t) * y[2]
    + 3 * squared(t) * (1 - t) * y[3]
    + cubed(t) * y[4]
end

---Fit control points through the knots, so consecutive bezier segments join
---smoothly. Tridiagonal system solved with the Thomas algorithm.
---
---Ported from CubicCurveAlgorithm.controlPointsFromPoints. Two y coordinates
---are overridden rather than used as computed -- the first control point takes
---the first knot's y, and the last second-control-point takes the last knot's y.
---Those are the special first and last segment corrections CLAUDE.md mentions;
---they are what makes the curve leave and arrive flat.
---
---Returns a list of segments, one per interval, each {cp1 = vec, cp2 = vec}.
local function controlPointsFromPoints(dataPoints)
  local firstControlPoints = {}
  local secondControlPoints = {}

  local count = #dataPoints - 1

  if count == 1 then
    local p0, p3 = dataPoints[1], dataPoints[2]

    -- 3*P1 = 2*P0 + P3
    local p1x = (2 * p0.x + p3.x) / 3
    local p1y = (2 * p0.y + p3.y) / 3
    firstControlPoints[1] = { x = p1x, y = p1y }

    -- P2 = 2*P1 - P0
    secondControlPoints[1] = { x = 2 * p1x - p0.x, y = 2 * p1y - p0.y }
  else
    local rhs = {}
    local a, b, c = {}, {}, {}

    for i = 1, count do
      local p0, p3 = dataPoints[i], dataPoints[i + 1]
      local rx, ry

      if i == 1 then
        a[i], b[i], c[i] = 0, 2, 1
        rx = p0.x + 2 * p3.x
        ry = p0.y + 2 * p3.y
      elseif i == count then
        a[i], b[i], c[i] = 2, 7, 0
        rx = 8 * p0.x + p3.x
        ry = 8 * p0.y + p3.y
      else
        a[i], b[i], c[i] = 1, 4, 1
        rx = 4 * p0.x + 2 * p3.x
        ry = 4 * p0.y + 2 * p3.y
      end

      rhs[i] = { x = rx, y = ry }
    end

    -- Forward sweep of the Thomas algorithm.
    for i = 2, count do
      local m = a[i] / b[i - 1]
      b[i] = b[i] - m * c[i - 1]
      rhs[i] = {
        x = rhs[i].x - m * rhs[i - 1].x,
        y = rhs[i].y - m * rhs[i - 1].y,
      }
    end

    -- Back substitution, starting from the last control point.
    firstControlPoints[count] = {
      x = rhs[count].x / b[count],
      y = rhs[count].y / b[count],
    }

    for i = count - 1, 1, -1 do
      local nextPoint = firstControlPoints[i + 1]
      local cx = (rhs[i].x - c[i] * nextPoint.x) / b[i]
      local cy = (rhs[i].y - c[i] * nextPoint.y) / b[i]

      if i == 1 then
        -- First correction: y comes from the knot, not the solve.
        firstControlPoints[i] = { x = cx, y = dataPoints[1].y }
      else
        firstControlPoints[i] = { x = cx, y = cy }
      end
    end

    -- Second control points follow from the first.
    for i = 1, count do
      local p3 = dataPoints[i + 1]

      if i == count then
        local p1 = firstControlPoints[i]
        -- Last correction: y comes from the final knot, not the midpoint.
        secondControlPoints[i] = {
          x = (p3.x + p1.x) / 2,
          y = dataPoints[count + 1].y,
        }
      else
        local nextP1 = firstControlPoints[i + 1]
        secondControlPoints[i] = {
          x = 2 * p3.x - nextP1.x,
          y = 2 * p3.y - nextP1.y,
        }
      end
    end
  end

  local segments = {}
  for i = 1, count do
    segments[i] = {
      cp1 = firstControlPoints[i],
      cp2 = secondControlPoints[i],
    }
  end

  return segments
end

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

---Cubic bezier through the keyframes. This is what carries position and
---rotation, so it is the one you actually see on screen.
---
---The first and last segments get an extra sine ramp on top of the curve,
---blending toward the end knot's value. That is what makes a camera ease out of
---its first keyframe and into its last.
---@param time number
---@param x number[] @keyframe positions
---@param y number[] @keyframe values
---@return number|nil
function interpolation.interpolate(time, x, y)
  if #y == 0 then return nil end

  local points = sanitize(x, y)
  if #points == 0 then return nil end
  if #points == 1 then return points[1].y end

  local n = #points
  local last = points[n]

  -- As in interpolate_sin, the legacy tests this inside the search loop even
  -- though it cannot change across iterations. Hoisted; same outcome.
  if time >= last.x then return last.y end

  -- Note the range: the legacy stops one short of the end here, unlike
  -- interpolate_sin which walks every point. Kept as is.
  local activeIndex = nil
  for i = 1, n - 1 do
    if time > points[i].x then activeIndex = i end
  end

  if activeIndex == nil then return points[1].y end

  local controlPoints = controlPointsFromPoints(points)
  local segment = controlPoints[activeIndex]

  local cx = {
    points[activeIndex].x, segment.cp1.x, segment.cp2.x, points[activeIndex + 1].x,
  }
  local cy = {
    points[activeIndex].y, segment.cp1.y, segment.cp2.y, points[activeIndex + 1].y,
  }

  -- With only two keyframes the whole curve is both the first and the last
  -- segment, so the ramps have to run twice as fast to fit.
  local multiplier = (n == 2) and 2 or 1

  -- Ease out of the first keyframe.
  if activeIndex == 1 then
    local smooth = (time - points[1].x) / (points[2].x - points[1].x)
    if smooth < (1 / multiplier) then
      smooth = math.sin(math.min(smooth * multiplier, 1) * 90 * math.pi / 180)
      local value = getY(time, cx, cy)
      if value == nil then return nil end
      return value * smooth + points[1].y * (1 - smooth)
    end
  end

  -- Ease into the last keyframe.
  if activeIndex == n - 1 then
    local duration = points[n].x - points[n - 1].x
    local smooth = 1 - (math.max((time - points[n - 1].x - (duration / 2)) / duration, 0) * multiplier)
    smooth = math.sin(smooth * 90 * math.pi / 180)
    local value = getY(time, cx, cy)
    if value == nil then return nil end
    return value * smooth + points[n].y * (1 - smooth)
  end

  return getY(time, cx, cy)
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
