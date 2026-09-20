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

  THE DIAMONDS DO NOT MOVE, and that is deliberate. They were draggable for
  one round and Théo asked for it back out: a diamond is four pixels on a
  ribbon you also click to select cameras, so a slightly missed click moves a
  keyframe instead of selecting something -- and a keyframe that moved by
  accident is only noticed in the edit. The KEYFRAME field moves them, where
  the gesture cannot be mistaken for anything else. The camera handle stays
  draggable: it is a deliberate grab on a marked grip, not a stray click.
]]

local theme = require('ui/theme')
local trackmap = require('core/trackmap')
local data = require('core/data')

local band = {}

-- The drag in progress, and which gesture it is. Counted, not named, so two
-- drags of the same camera are two entries on the undo stack -- the same
-- reasoning as ui/parameter.
local dragging = false
local dragToken = 0

-- The camera being renamed, by its id rather than its rank: the rank is
-- exactly what moves when a camera is inserted, and a rename that followed it
-- would land on the wrong camera.
local renaming = nil
local renameBuffer = ''


-- Where the right click landed, kept from the moment the menu opens. By the
-- time an item is chosen the pointer is on the menu, nowhere near the place
-- the camera is meant to go.
local menuAt = nil
local menuIndex = nil

-- Whether the mouse was already down on this widget last frame. The press is
-- the frame it goes from up to down, and only a press may take the handle:
-- otherwise a drag that started elsewhere picks it up as it crosses over.
local wasActive = false

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
---@return table @what the user did, any of:
---  camera        a camera they clicked on
---  keyframe      a keyframe of the selected camera they clicked on
---  move          { position, gesture } while a camera start is dragged
---  rename        { index, name } when a name is committed
---  seekTo        a lap position to bring the car to
---  hint          what to say in the status line while the pointer is here
---  addCamera     a lap position to put a new camera at
---  removeCamera  the index of one to take away
---
---One table rather than a row of return values. Six of those had accumulated,
---and the seventh is what made the point: every caller had to count commas to
---find out which nil was which.
function band.draw(state, width)
  local height = theme.bandHeight
  local origin = ui.getCursor()

  local clicked = ui.invisibleButton('##trackBand', vec2(width, height))
  local hovered = ui.itemHovered()

  -- Adding and removing, where the thing is. A plus button has to decide for
  -- you where the camera goes; a right click on the ribbon has already said.
  -- And a delete behind a menu is a delete nobody reaches by accident, which
  -- matters more here than a saved click: the strip's minus button sits next
  -- to its plus.
  local menu = nil
  ui.itemPopup('##bandMenu', ui.MouseButton.Right, function()
    if menuAt ~= nil and ui.selectable('Bring the car here') then
      menu = { seekTo = menuAt }
    end
    if menuAt ~= nil and ui.selectable('Add a camera here') then
      menu = { addCamera = menuAt }
    end
    if menuIndex ~= nil and ui.selectable('Remove this camera') then
      menu = { removeCamera = menuIndex }
    end
  end)


  ui.drawRectFilled(origin, vec2(origin.x + width, origin.y + height),
    theme.mapBackground, theme.rounding)

  -- The pointer says the ribbon does something, and the line at the bottom of
  -- the panel says what. Between them they cost no height at all, which is
  -- the whole reason for putting it there.
  local hint = nil
  if hovered then
    ui.setMouseCursor(ui.MouseCursor.Hand)
    hint = 'Click: select the camera and bring the car here.  ' ..
      'Shift+click: select only.  ' ..
      'Right click: add a camera here, or remove one.'
  end

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
    span.x1, span.x2 = x1, x2
  end

  ------------------------------------------------------------------
  -- Where one camera hands over to the next
  ------------------------------------------------------------------
  -- A tick at every start, drawn after the segments so it survives being a
  -- fraction of a pixel wide.
  --
  -- This is what makes a set countable. ATR's Spa file has 22 cameras and the
  -- last of them starts at 0.99579 -- 29 metres of a 7 km lap, five pixels of
  -- ribbon. It was drawn all along, but too narrow to hold a digit, so the
  -- ribbon read as 21 cameras. Ticks say how many there are even when a
  -- segment is too thin to say anything else.
  for i = 1, #spans do
    local span = spans[i]
    if not span.wrapped and span.from > 0 then
      local x = origin.x + xOf(span.from, width)
      ui.drawLine(vec2(x, top), vec2(x, origin.y + height),
        theme.bandTick, 1)
    end
  end

  ------------------------------------------------------------------
  -- What each segment is called
  ------------------------------------------------------------------
  -- The name if it fits, the number if only that fits, and nothing at all on
  -- a segment too thin for either -- except the one being pointed at or
  -- worked on, which says who it is however little room it has. That last
  -- part is what keeps a set of a hundred readable instead of a row of
  -- clipped stubs.
  if hovered and ui.mouseClicked(ui.MouseButton.Right) then
    local where = ui.mouseLocalPos()
    if where ~= nil and where.x >= 0 then
      menuAt = positionOf(where.x - origin.x, width)
      menuIndex = trackmap.ownerAt(segments, menuAt)
    end
  end

  local pointer = ui.mouseLocalPos()
  local pointerX = (pointer ~= nil and pointer.x >= 0)
    and (pointer.x - origin.x) or nil

  for i = 1, #spans do
    local span = spans[i]
    local room = span.x2 - span.x1 - 2 * theme.bandLabelPadding
    local under = pointerX ~= nil and hovered
      and pointerX >= span.x1 - origin.x and pointerX < span.x2 - origin.x

    local focused = under or span.index == state.cameraIndex
    local camera = state.cameras ~= nil and state.cameras[span.index] or nil
    local label = data.cameraLabel(camera, span.index)
    local rank = tostring(span.index)

    -- Room enough to hold the text AND not be ellipsised. Asking only whether
    -- it fits exactly gets "22" drawn as "..." -- the ellipsis wants room of
    -- its own, and a name that just fits has none to give it.
    local function fits(text)
      return room >= theme.bandLabelMin
        and ui.measureText(text).x + theme.bandLabelSlack <= room
    end

    local text, x1, x2, y1 = nil, span.x1, span.x2, top

    if fits(label) then
      text = label
    elseif fits(rank) then
      text = rank
    elseif focused then
      -- Too thin for even a digit, and this is the one being pointed at. It
      -- says what it is ABOVE the ribbon, where there is room, rather than
      -- squeezed into a segment five pixels wide -- which is what produced
      -- " ..." for camera 22 and "1..." for camera 16.
      text = label
      y1 = origin.y

      local wanted = ui.measureText(label).x
        + 2 * theme.bandLabelPadding + theme.bandLabelSlack
      local middle = (span.x1 + span.x2) / 2
      x1 = middle - wanted / 2
      x2 = x1 + wanted

      -- At the edges the box MOVES rather than shrinks. Clamping both sides
      -- independently is what squeezed the label of the last camera on the
      -- lap, which starts a few pixels from the end of the ribbon.
      if x1 < origin.x then x1, x2 = origin.x, origin.x + wanted end
      if x2 > origin.x + width then
        x2 = origin.x + width
        x1 = x2 - wanted
      end
      if x1 < origin.x then x1 = origin.x end
    end

    if text ~= nil then
      ui.drawTextClipped(text,
        vec2(x1 + theme.bandLabelPadding, y1),
        vec2(x2 - theme.bandLabelPadding, y1 == top and (origin.y + height) or top),
        theme.bandLabel, vec2(0.5, 0.5), true)
    end
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

  if menu ~= nil then
    ui.setCursor(vec2(origin.x, origin.y + height))
    menu.hint = hint
    return menu
  end

  ------------------------------------------------------------------
  -- Renaming, in place
  ------------------------------------------------------------------
  -- Double click a segment and type. This is the moment for it: you are
  -- already looking at where the camera is, which is what makes a name worth
  -- giving. The field is never narrower than a name needs, however thin the
  -- segment under it, and never runs past the end of the band.
  local renamed = nil

  if renaming ~= nil then
    local span, camera = nil, nil
    for i = 1, #spans do
      local candidate = state.cameras ~= nil
        and state.cameras[spans[i].index] or nil
      if type(candidate) == 'table' and candidate.id == renaming then
        span, camera = spans[i], candidate
      end
    end

    if span == nil then
      -- The camera went away underneath the field: deleted, or another file
      -- loaded. Nothing to name.
      renaming = nil
    else
      local fieldWidth = math.max(span.x2 - span.x1, theme.bandRenameWidth)
      local fieldX = math.min(span.x1, origin.x + width - fieldWidth)
      if fieldX < origin.x then fieldX = origin.x end

      ui.setCursor(vec2(fieldX, origin.y + height - theme.bandRibbon))
      ui.setNextItemWidth(fieldWidth)
      local text, _, entered = ui.inputText('##bandRename', renameBuffer,
        ui.InputTextFlags.AutoSelectAll)
      renameBuffer = text or renameBuffer

      if entered then
        renamed = { index = span.index, name = renameBuffer }
        renaming = nil
      elseif not ui.itemActive() and renameBuffer ~= '' then
        -- Clicked away: dropped, like every other typed entry in this panel.
        -- Not Escape -- see ui/parameter for why that key is left alone.
        renaming = nil
      end
    end
  end

  ------------------------------------------------------------------
  -- The handle: where the selected camera takes over
  ------------------------------------------------------------------
  -- Only the selected one. A handle on every camera would be a row of grips
  -- on a ribbon a few pixels tall, and dragging the wrong one is the kind of
  -- mistake that only shows up in the edit.
  local selected = state.cameras ~= nil and state.cameraIndex ~= nil
    and state.cameras[state.cameraIndex] or nil
  local handleAt = type(selected) == 'table'
    and type(selected.camera_in) == 'number' and selected.camera_in or nil

  if handleAt ~= nil then
    local x = origin.x + xOf(handleAt, width)
    ui.drawRectFilled(vec2(x - 2, origin.y), vec2(x + 2, origin.y + height),
      theme.stripActive, theme.rounding)
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
  local mouse = ui.mouseLocalPos()
  local at = (mouse ~= nil and mouse.x >= 0)
    and positionOf(mouse.x - origin.x, width) or nil

  -- Dragging the handle moves where the camera takes over. Held down and
  -- near it: the press has to start on the handle, so dragging across the
  -- ribbon from somewhere else cannot grab it by passing over.
  local active = ui.itemActive()
  local pressed = active and not wasActive
  wasActive = active

  if active and at ~= nil then
    if pressed and handleAt ~= nil
        and math.abs(xOf(handleAt, width) - (mouse.x - origin.x))
          <= theme.bandClickRadius then
      dragging, dragToken = true, dragToken + 1
    end
    if dragging then
      return { hint = hint, rename = renamed,
        move = { position = at, gesture = 'band:' .. dragToken } }
    end
  elseif dragging then
    dragging = false
  end

  -- A double click opens the name of whatever is under it. Checked before the
  -- single-click handling below, which would otherwise select first and treat
  -- the second click as another selection.
  if hovered and at ~= nil and ui.mouseDoubleClicked(0) and renaming == nil then
    local index = trackmap.ownerAt(segments, at)
    local camera = index ~= nil and state.cameras ~= nil
      and state.cameras[index] or nil
    if type(camera) == 'table' and type(camera.id) == 'number' then
      renaming = camera.id
      renameBuffer = type(camera.name) == 'string' and camera.name or ''

      -- A camera with no name is offered the name of the place it stands,
      -- from the track's own sections.ini. Offered, never imposed: the field
      -- selects all, so the first keystroke replaces it and Escape drops it.
      -- Plenty of stretches are not named at all, and there the field opens
      -- empty rather than with something invented.
      if renameBuffer == '' and type(state.sectionNameAt) == 'function' then
        renameBuffer = state.sectionNameAt(camera.camera_in) or ''
      end

      return { hint = hint, rename = renamed }
    end
  end

  if not clicked or not hovered or at == nil then
    return { hint = hint, rename = renamed }
  end

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
    if best ~= nil then return { hint = hint, keyframe = best, rename = renamed } end
  end

  -- A plain click does both: picks the camera and takes the replay to the
  -- spot. Shift holds the replay still, for choosing a camera without losing
  -- the moment being watched.
  --
  -- Moving the replay is not an edit. Nothing here reaches camera data, and
  -- nothing here belongs on the undo stack.
  return {
    hint = hint,
    camera = trackmap.ownerAt(segments, at),
    seekTo = (not ui.hotkeyShift()) and at or nil,
    rename = renamed,
  }
end

---Give up any drag in progress. For tests.
function band.reset()
  dragging, wasActive = false, false
  menuAt, menuIndex = nil, nil
  renaming, renameBuffer = nil, ''
end

return band
