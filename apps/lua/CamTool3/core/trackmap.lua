--[[
  Laying a camera set out on a 2D map of the track -- pure logic, no ac/CSP
  dependency.

  Two jobs, deliberately kept apart:

  1. GEOMETRY. Turning an outline of the track into screen coordinates: find
     its bounding box, fit it into a rectangle without distorting it, flip the
     vertical axis because screens grow downwards and the world does not.

  2. OWNERSHIP. Deciding which camera covers which part of the lap, so the
     outline can be tinted camera by camera.

  The outline itself comes from the game (adapters sample the AI spline), and
  the drawing happens in the UI. Neither belongs here.

  Coordinates are CamTool space (Z-up), so `x` and `y` are the horizontal pair
  and a top-down map is just those two. That is the space the cameras store
  their own positions in, so drawing those later needs no conversion.

  Points are { x = , y = , p = } tables rather than parallel arrays: the drawing
  loop walks them one by one, and `p` -- the lap progress that point was
  sampled at -- makes ownership exact whatever sampling the caller chose.
]]

local trackmap = {}

---Lua answers a bad division with inf rather than raising, and inf reaches the
---drawing code as a coordinate. Every number entering this module is checked.
local function isFinite(v)
  return type(v) == 'number' and v == v and v - v == 0
end

---Bounding box of an outline, ignoring points that are not finite.
---
---A sampled spline can hand back a nan or an inf on a broken track, and one
---such point would stretch the box to infinity and collapse everything else
---into a dot. Skipping them keeps a usable map; returning nil when nothing
---finite is left lets the caller say "no track" rather than draw nonsense.
---@param points table[] @{ x = , y = } each
---@param angle number|nil @radians to turn the track by first, default none
---@return table|nil @{ minX = , minY = , maxX = , maxY = }
function trackmap.bounds(points, angle)
  if type(points) ~= 'table' then return nil end

  local cos, sin = 1, 0
  if isFinite(angle) and angle ~= 0 then
    cos, sin = math.cos(angle), math.sin(angle)
  end

  local minX, minY, maxX, maxY

  for i = 1, #points do
    local point = points[i]
    if type(point) == 'table' and isFinite(point.x) and isFinite(point.y) then
      local x = point.x * cos - point.y * sin
      local y = point.x * sin + point.y * cos
      if minX == nil or x < minX then minX = x end
      if maxX == nil or x > maxX then maxX = x end
      if minY == nil or y < minY then minY = y end
      if maxY == nil or y > maxY then maxY = y end
    end
  end

  if minX == nil then return nil end
  return { minX = minX, minY = minY, maxX = maxX, maxY = maxY }
end

---Fit a bounding box into a rectangle, keeping the track's shape.
---
---One scale for both axes -- a squashed circuit is unreadable and, worse,
---misleading about where a corner is. Whatever room the aspect ratio leaves
---over becomes equal margins, so the track sits centred.
---@param bounds table|nil @from trackmap.bounds
---@param width number @the rectangle, in pixels
---@param height number
---@param margin number|nil @pixels kept clear on every side, default 0
---@param angle number|nil @the rotation `bounds` was measured with, carried so
---  that project turns each point the same way
---@return table|nil @{ scale = , offsetX = , offsetY = }, nil if it cannot fit
function trackmap.fit(bounds, width, height, margin, angle)
  if type(bounds) ~= 'table' then return nil end
  if not isFinite(width) or not isFinite(height) then return nil end

  margin = isFinite(margin) and margin or 0

  local usableW = width - 2 * margin
  local usableH = height - 2 * margin
  if usableW <= 0 or usableH <= 0 then return nil end

  local spanX = bounds.maxX - bounds.minX
  local spanY = bounds.maxY - bounds.minY

  -- A track with no extent in one direction is not a drawing bug, it is a
  -- straight line -- an A-B hillclimb sampled along one axis, or an outline of
  -- a single point. Dividing by its zero span would give inf, so that axis
  -- simply does not constrain the scale. When neither does, the scale is zero
  -- and everything lands on the centre, which is the honest picture.
  local scale
  if spanX > 0 and spanY > 0 then
    scale = math.min(usableW / spanX, usableH / spanY)
  elseif spanX > 0 then
    scale = usableW / spanX
  elseif spanY > 0 then
    scale = usableH / spanY
  else
    scale = 0
  end

  -- Centre what is left over. The vertical offset is measured from the bottom
  -- of the box because project flips the axis.
  local offsetX = margin + (usableW - spanX * scale) / 2
  local offsetY = margin + (usableH - spanY * scale) / 2

  local turned = isFinite(angle) and angle ~= 0
  return {
    scale = scale,
    offsetX = offsetX,
    offsetY = offsetY,
    minX = bounds.minX,
    minY = bounds.minY,
    spanX = spanX,
    spanY = spanY,
    angle = turned and angle or 0,
    cos = turned and math.cos(angle) or 1,
    sin = turned and math.sin(angle) or 0,
    -- What the drawing is worth: pixels per metre. Comparing two candidate
    -- angles is comparing these.
    width = width,
    height = height,
  }
end

---World position -> position inside the rectangle, in pixels from its corner.
---
---THE VERTICAL AXIS IS NOT FLIPPED, and that is the whole of the matter.
---
---It was, on the reasoning that screens grow downwards while the world does
---not. That reasoning is sound for a right-handed world and Assetto Corsa's
---is left-handed, so the map came out MIRRORED: a corner the car took to the
---left bent right on screen. Théo saw it immediately, which is the only way
---this was ever going to be settled -- the derivation is exactly what got it
---wrong, so the answer here is the one the game gave, not the one the axes
---argue for.
---
---The caller adds the rectangle's own origin.
---@param fit table|nil @from trackmap.fit
---@param x number
---@param y number
---@return number|nil sx, number|nil sy
function trackmap.project(fit, x, y)
  if type(fit) ~= 'table' or not isFinite(x) or not isFinite(y) then
    return nil, nil
  end

  local rx = x * fit.cos - y * fit.sin
  local ry = x * fit.sin + y * fit.cos

  local sx = fit.offsetX + (rx - fit.minX) * fit.scale
  local sy = fit.offsetY + (ry - fit.minY) * fit.scale
  return sx, sy
end

---Project a whole outline in one pass.
---
---Reuses `out` when given, so a panel redrawing every frame allocates once.
---Points that are not finite are dropped, which breaks the line rather than
---dragging it to infinity.
---@param fit table|nil
---@param points table[]
---@param out table|nil @reused, truncated to the number of points written
---@return table @{ { x = , y = , p = }, ... } in screen space
function trackmap.projectAll(fit, points, out)
  out = out or {}
  local n = 0

  if type(fit) == 'table' and type(points) == 'table' then
    for i = 1, #points do
      local point = points[i]
      if type(point) == 'table' then
        local sx, sy = trackmap.project(fit, point.x, point.y)
        if sx ~= nil then
          n = n + 1
          local slot = out[n]
          if slot == nil then
            out[n] = { x = sx, y = sy, p = point.p }
          else
            slot.x, slot.y, slot.p = sx, sy, point.p
          end
        end
      end
    end
  end

  for i = #out, n + 1, -1 do out[i] = nil end
  return out
end

---Where each camera's stretch of the lap begins and ends.
---
---Mirrors core/evaluate.activeCameraIndex, which is what actually picks the
---live camera: pit cameras are a separate list that only plays in the pit
---lane, and the last camera holds the view across the start line until the
---first one takes over. So the last segment ends past 1, and a position below
---the first camera's start belongs to the last camera.
---
---Assumes cameras are in ascending camera_in order. core/edit sorts them on
---every insertion, and the legacy files are written that way; a file that is
---not would make the selection itself behave oddly, long before the map.
---@param cameras table[]|nil
---@param wantPit boolean|nil @pit-lane cameras instead of track ones
---@return table[] @{ { index = <index in `cameras`>, from = , to = }, ... }
function trackmap.segments(cameras, wantPit)
  local out = {}
  if type(cameras) ~= 'table' then return out end
  wantPit = wantPit and true or false

  for i = 1, #cameras do
    local camera = cameras[i]
    if type(camera) == 'table'
        and (camera.camera_pit and true or false) == wantPit then
      local start = camera.camera_in
      if not isFinite(start) then start = 0 end
      out[#out + 1] = { index = i, from = start, to = nil }
    end
  end

  for i = 1, #out do
    local next_ = out[i + 1]
    out[i].to = next_ ~= nil and next_.from or (out[1].from + 1)
  end

  return out
end

---Which camera covers this point of the lap.
---@param segments table[] @from trackmap.segments
---@param position number @0..1
---@return number|nil @index into the camera list, nil if there is no camera
function trackmap.ownerAt(segments, position)
  if type(segments) ~= 'table' or #segments == 0 then return nil end
  if not isFinite(position) then return nil end

  -- Before the first camera starts, the last one is still running: it holds
  -- the view across the start line.
  if position < segments[1].from then return segments[#segments].index end

  -- Segments are ascending, so the first one that starts after the position
  -- ends the search: everything past it starts later still.
  local owner = segments[#segments].index
  for i = 1, #segments do
    if position < segments[i].from then break end
    owner = segments[i].index
  end
  return owner
end

---Which camera owns each point of an outline.
---
---Computed once per set rather than per frame: the answer only changes when a
---camera is added, removed or moved.
---@param points table[] @{ p = } each
---@param segments table[]
---@param out table|nil @reused
---@return table @camera index per point, parallel to `points`, `false` where
---  no camera covers it -- false rather than nil so the array stays a proper
---  sequence and `#` keeps answering.
function trackmap.assign(points, segments, out)
  out = out or {}
  local n = 0

  if type(points) == 'table' then
    for i = 1, #points do
      n = n + 1
      local point = points[i]
      out[n] = (type(point) == 'table'
        and trackmap.ownerAt(segments, point.p)) or false
    end
  end

  for i = #out, n + 1, -1 do out[i] = nil end
  return out
end

---An outline built from a spline recorded in a camera file.
---
---The fallback for a track with no AI spline: `track_spline` is what CamTool 2
---wrote when the user drove or flew a lap with recording on. Coarse -- 96
---samples for a 4 km circuit in the reference files, against a thousand from
---the AI spline -- and present only in files where it was recorded, so it is a
---fallback and not the source.
---
---Already in CamTool space, since CamTool 2 wrote it, so loc_x and loc_y are
---the horizontal pair and nothing is converted.
---
---A spline recorded across the start line stores positions past 1, the same
---wrap core/spline deals with. Progress is folded back into 0..1 here so that
---ownership, which works in lap fractions, can read it.
---@param recorded table|nil @{ loc_x = {}, loc_y = {}, the_x = {} }
---@return table[]|nil @points, nil when there is nothing recorded
function trackmap.fromRecordedSpline(recorded)
  if type(recorded) ~= 'table' then return nil end

  local xs, ys, ps = recorded.loc_x, recorded.loc_y, recorded.the_x
  if type(xs) ~= 'table' or type(ys) ~= 'table' or type(ps) ~= 'table' then
    return nil
  end

  local count = math.min(#xs, #ys, #ps)
  if count < 2 then return nil end

  local points = {}
  for i = 1, count do
    if isFinite(xs[i]) and isFinite(ys[i]) and isFinite(ps[i]) then
      local p = ps[i] % 1
      points[#points + 1] = { x = xs[i], y = ys[i], p = p }
    end
  end

  if #points < 2 then return nil end
  return points
end

---How much bigger the drawing has to get before turning the track is worth
---the disorientation. A tenth is not worth it; half is.
trackmap.ROTATION_WORTH_IT = 1.15

---Degrees between the angles tried. The scale is a smooth function of the
---angle, so a degree costs a tenth of a percent of the answer.
local ANGLE_STEP_DEG = 1

---The angle that draws the track as large as the box allows.
---
---A wide band and a portrait circuit waste most of their width: Spa is about
---two units tall for one wide, so in a 5:1 band the height binds and four
---fifths of the panel stays empty. Turning the track is what recovers it.
---
---Tried rather than derived. The obvious derivation -- the principal axis of
---the points -- maximises their spread, which is not the same as filling a
---box of a given shape, and gets the answer wrong on a track with one long
---straight. Every degree of a half turn is cheap enough to try, once, and
---answers the question actually being asked. Half a turn because a bounding
---box repeats every 180 degrees.
---
---Returns no rotation unless it earns its keep, so a circuit that already
---fits stays the way everyone pictures it.
---@param points table[]
---@param width number
---@param height number
---@param margin number|nil
---@return number @radians, 0 when turning the track would not gain enough
---@return number @how much bigger it draws than it would unturned, 1 when flat
function trackmap.bestAngle(points, width, height, margin)
  local upright = trackmap.fit(trackmap.bounds(points), width, height, margin)
  if upright == nil or upright.scale <= 0 then return 0, 1 end

  local bestAngle, bestScale = 0, upright.scale

  for degrees = ANGLE_STEP_DEG, 180 - ANGLE_STEP_DEG, ANGLE_STEP_DEG do
    local angle = math.rad(degrees)
    local candidate = trackmap.fit(trackmap.bounds(points, angle),
      width, height, margin, angle)
    if candidate ~= nil and candidate.scale > bestScale then
      bestAngle, bestScale = angle, candidate.scale
    end
  end

  local gain = bestScale / upright.scale
  if gain < trackmap.ROTATION_WORTH_IT then return 0, 1 end
  return bestAngle, gain
end

---The point of a projected outline nearest to somewhere in the box.
---
---For clicking: the track is a line a few pixels wide and nobody hits a line
---exactly, so the click looks for what is near it. Beyond `maxDistance` it
---finds nothing, which is how a click on the empty part of the map means
---"nothing" rather than "whatever was least far away".
---@param projectedPoints table[] @from trackmap.projectAll
---@param x number @inside the box, same origin as the projection
---@param y number
---@param maxDistance number|nil @pixels, default 16
---@return number|nil @index into the projected outline
function trackmap.nearest(projectedPoints, x, y, maxDistance)
  if type(projectedPoints) ~= 'table' then return nil end
  if not isFinite(x) or not isFinite(y) then return nil end

  maxDistance = isFinite(maxDistance) and maxDistance or 16
  local limit = maxDistance * maxDistance

  local best, bestDistance = nil, nil
  for i = 1, #projectedPoints do
    local point = projectedPoints[i]
    local dx, dy = point.x - x, point.y - y
    local distance = dx * dx + dy * dy
    if distance <= limit and (bestDistance == nil or distance < bestDistance) then
      best, bestDistance = i, distance
    end
  end

  return best
end

---The same segments laid out on a single line, 0 to 1, nothing past the end.
---
---A ribbon of the lap rather than a picture of the circuit. Same ownership,
---same colours, different projection -- and the one place they differ is the
---wrap: the last camera holds the view across the start line, so its segment
---runs past 1. On a map that is invisible, because the outline closes on
---itself. On a straight ribbon it would run off the end, so it is cut in two
---and the tail is drawn at the beginning, which is where it actually happens.
---@param segments table[] @from trackmap.segments
---@return table[] @{ { index = , from = , to = }, ... }, all within 0..1
function trackmap.bandSpans(segments)
  local out = {}
  if type(segments) ~= 'table' or #segments == 0 then return out end

  for i = 1, #segments do
    local segment = segments[i]
    local from = math.max(0, math.min(1, segment.from))
    local to = math.min(1, segment.to)
    if to > from then
      out[#out + 1] = { index = segment.index, from = from, to = to }
    end
  end

  -- The piece before the first camera starts belongs to the last one.
  local first = segments[1]
  if first.from > 0 then
    table.insert(out, 1, {
      index = segments[#segments].index,
      from = 0,
      to = first.from,
      wrapped = true,
    })
  end

  return out
end

return trackmap
