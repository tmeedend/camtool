--[[
  The track band: one lap laid out as a ribbon, 0 to the finish line.

  The same ownership the map draws, projected onto a line instead of onto the
  circuit. Which of the two is more useful depends on the question: the map
  answers "where on the track does this happen", the band answers "when in the
  lap, and how long does each shot last". A camera covering a third of the lap
  is obvious here and easy to miss on a map.

  It also scales where the numbered strip does not. That strip gives every
  camera a cell twenty to a row, so a file with a hundred cameras is five rows
  of numbers nobody can read -- issue #6. A ribbon does not care how many
  there are.

  Presentation only. The spans come from core/trackmap, the edits go through
  the panel, and nothing here touches a camera.

  What it shows, bottom to top: each camera's stretch of the lap in its own
  tint, the selected camera's keyframes as diamonds, and the car.
]]

local theme = require('ui/theme')
local trackmap = require('core/trackmap')

local band = {}

---Where a lap position sits along the ribbon.
---@return number @pixels from the ribbon's left edge
local function xOf(position, width)
  return position * width
end

---And back again, for a click.
---@return number @0..1
local function positionOf(x, width)
  if width <= 0 then return 0 end
  local p = x / width
  if p < 0 then return 0 end
  if p > 1 then return 1 end
  return p
end

---Draw one keyframe marker.
local function diamond(originX, originY, x, y, size, colour)
  local cx, cy = originX + x, originY + y
  ui.drawQuadFilled(
    vec2(cx, cy - size), vec2(cx + size, cy),
    vec2(cx, cy + size), vec2(cx - size, cy), colour)
end

---@param state table
---  cameras          the camera list being edited
---  cameraIndex      the camera being edited
---  liveCameraIndex  the camera the car has made live
---  camera           that camera, for its keyframes
---  keyframeIndex    the selected keyframe
---  trackPos         the car, 0..1
---@param width number
---@return number|nil camera @a camera the user clicked on
---@return number|nil keyframe @or a keyframe of the selected camera
function band.draw(state, width)
  local height = theme.bandHeight
  local origin = ui.getCursor()

  local clicked = ui.invisibleButton('##trackBand', vec2(width, height))
  local hovered = ui.itemHovered()

  ui.drawRectFilled(origin, vec2(origin.x + width, origin.y + height),
    theme.mapBackground, theme.rounding)

  local segments = trackmap.segments(state.cameras)
  local spans = trackmap.bandSpans(segments)

  ------------------------------------------------------------------
  -- The lap, camera by camera
  ------------------------------------------------------------------
  local top = origin.y + height - theme.bandRibbon
  for i = 1, #spans do
    local span = spans[i]
    local colour = theme.mapTrackAlt
    if span.index == state.cameraIndex then
      colour = theme.stripActive
    elseif span.index == state.liveCameraIndex then
      colour = theme.stripLive
    elseif span.index % 2 == 0 then
      colour = theme.mapTrack
    end

    -- A hair of a gap between neighbours, so two cameras of the same tint
    -- still read as two. Never wider than the span itself.
    local x1 = origin.x + xOf(span.from, width)
    local x2 = origin.x + xOf(span.to, width)
    if x2 - x1 > 2 then x2 = x2 - 1 end

    ui.drawRectFilled(vec2(x1, top), vec2(x2, origin.y + height), colour)
  end

  ------------------------------------------------------------------
  -- The keyframes of the camera being edited
  ------------------------------------------------------------------
  -- Only that camera's. All of them at once would be a row of diamonds with
  -- nothing to say which belongs to what, and the panel edits one camera.
  local keyframes = state.camera ~= nil and state.camera.keyframes or nil
  local keyframeY = origin.y + theme.bandKeyframeY

  if type(keyframes) == 'table' then
    for i = 1, #keyframes do
      local at = keyframes[i].keyframe
      if type(at) == 'number' and at == at and at >= 0 and at <= 1 then
        diamond(origin.x, 0, xOf(at, width), keyframeY, theme.bandDiamond,
          i == state.keyframeIndex and theme.diamondFilled
            or theme.diamondHollow)
      end
    end
  end

  ------------------------------------------------------------------
  -- The car
  ------------------------------------------------------------------
  if type(state.trackPos) == 'number' and state.trackPos == state.trackPos then
    local x = origin.x + xOf(state.trackPos, width)
    ui.drawLine(vec2(x, origin.y), vec2(x, origin.y + height),
      theme.mapPlayhead, 1.5)
  end

  ui.setCursor(vec2(origin.x, origin.y + height))

  ------------------------------------------------------------------
  -- Clicking
  ------------------------------------------------------------------
  -- A keyframe first, then the camera under the click. Diamonds are small and
  -- sit on top of the ribbon, so anything else would make them unclickable.
  if not clicked or not hovered then return nil, nil end

  local mouse = ui.mouseLocalPos()
  if mouse == nil or mouse.x < 0 then return nil, nil end

  local at = positionOf(mouse.x - origin.x, width)

  if type(keyframes) == 'table' then
    local best, bestDistance = nil, nil
    for i = 1, #keyframes do
      local position = keyframes[i].keyframe
      if type(position) == 'number' then
        local distance = math.abs(xOf(position, width) - (mouse.x - origin.x))
        if distance <= theme.bandClickRadius
            and (bestDistance == nil or distance < bestDistance) then
          best, bestDistance = i, distance
        end
      end
    end
    if best ~= nil then return nil, best end
  end

  return trackmap.ownerAt(segments, at), nil
end

return band
