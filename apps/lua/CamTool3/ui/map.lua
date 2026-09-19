--[[
  The track map: the camera set seen from above.

  Presentation only. The geometry is core/trackmap's, the outline is the track
  adapter's, and this file decides how it looks and nothing else.

  Read only for now -- it shows, it does not edit. Clicking a camera comes
  next, and keeping that out of this step means the drawing can be wrong in
  the game without anything being lost by it.

  What it shows is COVERAGE: which stretch of the lap each camera is
  responsible for. Not where the cameras physically stand, which is a
  different picture -- a camera can sit two hundred metres off the track on a
  hill -- and a different question.

  The colours are the camera strip's, on purpose. Red is the camera being
  edited, the paler tint is the one the car has made live, and the two greys
  alternate so that neighbouring cameras can be told apart. Someone who has
  learned the strip has already learned the map.

  One thing deliberately not drawn: the real width of the track. The adapter
  measures it, but a 4 km circuit across a 300 px panel puts a metre at a
  fifteenth of a pixel, so the ribbon is a constant thickness instead. The
  measurement is kept for a zoom, which is when it would start to mean
  something.
]]

local theme = require('ui/theme')
local trackmap = require('core/trackmap')

local map = {}

-- Reused across frames. Projecting a thousand points and working out who owns
-- each of them costs nothing once and rather a lot sixty times a second, and
-- neither answer changes until the panel is resized or a camera is moved.
local projected = {}
local owners = {}
local cachedFit = nil
local cachedOutline = nil
local cachedWidth, cachedHeight = nil, nil
local cachedSegments = nil
---The height the track's shape asked for, and the turn it was given.
local cachedDrawnHeight = nil
local cachedAngle = nil

---Have the cameras moved since the last frame?
---
---Compared field by field rather than by building a key: this runs every
---frame, and a set can hold hundreds of cameras.
local function sameSegments(a, b)
  if a == nil or b == nil then return false end
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i].index ~= b[i].index or a[i].from ~= b[i].from then return false end
  end
  return true
end

---The point of the outline closest to a position in the lap.
---
---A plain scan. Progress climbs along the outline, so a binary search would
---be quicker, but a spline recorded across the start line folds back to zero
---in the middle of the array and would send that search the wrong way. A
---thousand comparisons is not what makes a frame slow.
local function nearestIndex(points, position)
  local best, bestDistance = nil, nil
  for i = 1, #points do
    local distance = math.abs(points[i].p - position)
    -- The short way round: 0.98 and 0.02 are neighbours, not a lap apart.
    if distance > 0.5 then distance = 1 - distance end
    if bestDistance == nil or distance < bestDistance then
      best, bestDistance = i, distance
    end
  end
  return best
end

---The colour of one camera's stretch of track.
local function colourFor(index, state)
  if index == state.cameraIndex then return theme.stripActive end
  if index == state.liveCameraIndex then return theme.stripLive end
  return index % 2 == 0 and theme.mapTrack or theme.mapTrackAlt
end

---Draw the map.
---
---@param state table
---  outline      from adapters/track, or nil when the track has no spline
---  outlineReason  why there is none, shown in its place
---  cameras      the camera list being edited, for the segments
---  cameraIndex  the camera being edited
---  liveCameraIndex  the camera the car has made live
---  trackPos     the car, 0..1
---@param width number
---@param maxHeight number @the most the map may take; it often takes less
---@return number|nil @a camera the user clicked on, if any
function map.draw(state, width, maxHeight)
  local outline = state.outline
  local points = outline ~= nil and outline.points or nil

  ------------------------------------------------------------------
  -- How much room to take, and which way up
  ------------------------------------------------------------------
  -- Both answers depend on each other, so the turn is worked out against the
  -- tallest box allowed and the height then follows from it.
  local height = math.min(maxHeight, theme.mapHeightMax)
  local angle = 0

  if points ~= nil and #points >= 2 then
    if cachedOutline ~= outline or cachedWidth ~= width
        or cachedHeight ~= maxHeight then
      cachedAngle = trackmap.bestAngle(points, width, height, theme.mapPadding)

      -- Then only as tall as the turned track needs. A band that is mostly
      -- empty is a band the parameters would rather have.
      local turned = trackmap.bounds(points, cachedAngle)
      local spanX = turned.maxX - turned.minX
      local spanY = turned.maxY - turned.minY
      if spanX > 0 and spanY > 0 then
        local wanted = (width - 2 * theme.mapPadding) * spanY / spanX
          + 2 * theme.mapPadding
        height = math.max(theme.mapHeightMin, math.min(height, wanted))
      end
      cachedDrawnHeight = height
    else
      height = cachedDrawnHeight or height
    end
    angle = cachedAngle or 0
  end

  local origin = ui.getCursor()
  -- Reserve the room, and take the click with it. invisibleButton rather than
  -- dummy: a dummy does not answer for the mouse.
  local clicked = ui.invisibleButton('##trackMap', vec2(width, height))

  ui.drawRectFilled(origin, vec2(origin.x + width, origin.y + height),
    theme.mapBackground, theme.rounding)

  if points == nil or #points < 2 then
    -- A drift layout, a gymkhana map, a track whose fast_lane was never made.
    -- Saying so is the honest answer; drawing a guess is not.
    ui.pushStyleColor(ui.StyleColor.Text, theme.absent)
    ui.setCursor(vec2(origin.x, origin.y + height / 2 - 8))
    ui.textAligned('no track map -- '
      .. (state.outlineReason or 'the game gave no outline'),
      vec2(0.5, 0.5), vec2(width, 16))
    ui.popStyleColor()
    ui.setCursor(vec2(origin.x, origin.y + height))
    return nil
  end

  ------------------------------------------------------------------
  -- Fit and ownership, recomputed only when something has changed
  ------------------------------------------------------------------
  if cachedOutline ~= outline or cachedWidth ~= width
      or cachedHeight ~= maxHeight then
    cachedFit = trackmap.fit(trackmap.bounds(points, angle), width, height,
      theme.mapPadding, angle)
    trackmap.projectAll(cachedFit, points, projected)
    cachedOutline, cachedWidth, cachedHeight = outline, width, maxHeight
    cachedSegments = nil
  end

  local segments = trackmap.segments(state.cameras)
  if not sameSegments(segments, cachedSegments) then
    trackmap.assign(points, segments, owners)
    cachedSegments = segments
  end

  if cachedFit == nil or #projected < 2 then
    ui.setCursor(vec2(origin.x, origin.y + height))
    return nil
  end

  ------------------------------------------------------------------
  -- The track, one stroke per camera
  ------------------------------------------------------------------
  -- Runs of points that share an owner are drawn as a single path. Point by
  -- point it would be a thousand draw calls a frame for the same picture.
  local i = 1
  while i <= #projected do
    local owner = owners[i]
    local colour = owner and colourFor(owner, state) or theme.mapTrackAlt

    ui.pathLineTo(vec2(origin.x + projected[i].x, origin.y + projected[i].y))
    local j = i + 1
    while j <= #projected and owners[j] == owner do
      ui.pathLineTo(vec2(origin.x + projected[j].x, origin.y + projected[j].y))
      j = j + 1
    end
    -- Carry on to the first point of the next run, or the track would show a
    -- gap at every camera change.
    if j <= #projected then
      ui.pathLineTo(vec2(origin.x + projected[j].x, origin.y + projected[j].y))
    end

    ui.pathStroke(colour, false, theme.mapThickness)
    i = j
  end

  -- Close the lap. An A-B track must not have its two ends joined.
  if outline.closed then
    local first, last = projected[1], projected[#projected]
    local colour = owners[#projected]
      and colourFor(owners[#projected], state) or theme.mapTrackAlt
    ui.drawLine(vec2(origin.x + last.x, origin.y + last.y),
      vec2(origin.x + first.x, origin.y + first.y),
      colour, theme.mapThickness)
  end

  ------------------------------------------------------------------
  -- The start line, and the car
  ------------------------------------------------------------------
  local start = projected[nearestIndex(points, 0)]
  if start ~= nil then
    ui.drawCircle(vec2(origin.x + start.x, origin.y + start.y), 4,
      theme.mapStartLine, 8, 1.5)
  end

  if type(state.trackPos) == 'number' and state.trackPos == state.trackPos then
    local here = projected[nearestIndex(points, state.trackPos)]
    if here ~= nil then
      ui.drawCircleFilled(vec2(origin.x + here.x, origin.y + here.y), 3.5,
        theme.mapPlayhead, 10)
    end
  end

  -- Leave the cursor below the map whatever the drawing did to it.
  ui.setCursor(vec2(origin.x, origin.y + height))

  ------------------------------------------------------------------
  -- Clicking a camera
  ------------------------------------------------------------------
  -- Where the click landed is measured from the item's own rectangle rather
  -- than from the cursor: the rectangle and the mouse are both in screen
  -- coordinates, so the two cannot disagree about padding or scrolling.
  -- ui/parameter reads its drag the same way.
  if clicked then
    local rect, mouse = ui.itemRectMin(), ui.mousePos()
    if rect ~= nil and mouse ~= nil then
      local index = trackmap.nearest(projected, mouse.x - rect.x,
        mouse.y - rect.y, theme.mapClickRadius)
      if index ~= nil and owners[index] then return owners[index] end
    end
  end

  return nil
end

---Forget what was cached. For tests, and for a track change.
function map.reset()
  projected, owners = {}, {}
  cachedFit, cachedOutline, cachedSegments = nil, nil, nil
  cachedWidth, cachedHeight = nil, nil
  cachedAngle, cachedDrawnHeight = nil, nil
end

return map
