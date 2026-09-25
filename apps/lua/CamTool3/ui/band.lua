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

  TWO ZONES, ONE RIBBON. A thin ruler along the top -- distances round the
  lap, and the names the track gives its own stretches -- and under it the
  cameras. The ruler has a background of its own, and that is what makes the
  split obvious without a word of explanation: above the line you move the
  playhead, below it you pick a camera.

  What it shows, bottom to top: each camera's stretch of the lap in its own
  tint, the selected camera's keyframes as diamonds, the playhead, and the
  ruler.

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
local ruler = require('core/ruler')
local sections = require('core/sections')

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
-- Whether the field has yet had the keyboard. Two things hang on it, and both
-- were wrong without it: the focus is asked for on the frame it opens and not
-- after, and a click elsewhere only closes the field once it has actually
-- been open.
local renameWasActive = false


-- Where the right click landed, kept from the moment the menu opens. By the
-- time an item is chosen the pointer is on the menu, nowhere near the place
-- the camera is meant to go.
local menuAt = nil
local menuIndex = nil

-- Whether the mouse was already down on this widget last frame. The press is
-- the frame it goes from up to down, and only a press may take the handle:
-- otherwise a drag that started elsewhere picks it up as it crosses over.
local wasActive = false

-- The scrub: whether the playhead is being dragged along the ruler, and where
-- it was last put. Module state rather than a local, because the answer has
-- to survive between the frame a drag starts and the frame it ends.
local scrubbing = false
local scrubAt = nil
-- What to tell the panel about it this frame: a position to follow while the
-- drag runs, and one to land on exactly when it ends.
local scrubReport = nil
local scrubLanding = nil

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

---Where the playhead belongs this frame, 0..1, or nil when there is nothing
---to draw.
---
---A function of its own because it is about to have a second answer: while
---the ribbon is being scrubbed the head belongs to the pointer, not to a
---replay still catching up with it.
local function playheadAt(state)
  -- The pointer wins while a drag is running. The replay is chasing it a
  -- tenth of a second behind, and a head that jumped back to where the replay
  -- had got to would stutter under the finger holding it.
  if scrubbing and scrubAt ~= nil then return scrubAt end

  local at = state.trackPos
  if type(at) ~= 'number' or at ~= at then return nil end
  return at
end

---Draw one keyframe marker.
local function diamond(originX, originY, x, y, size, colour)
  local cx, cy = originX + x, originY + y
  ui.drawQuadFilled(
    vec2(cx, cy - size), vec2(cx + size, cy),
    vec2(cx, cy + size), vec2(cx - size, cy), colour)
end

---Draw the ruler: how far round the lap, and what the track calls the place.
---
---A NAME BEATS A NUMBER, and the marks stay either way. The two cannot share
---the row -- there is one line of text in sixteen pixels -- so a distance
---whose label would land on a named stretch gives up the label and keeps the
---mark. Nothing is lost: the marks are evenly spaced, so a reader counts on
---from the last number they can see, which is what a ruler is for.
---
---Nothing is allocated here. The marks come back from core/ruler as the same
---table they were last frame, and the names were read once when the track
---loaded.
---@param originX number
---@param y number @the top of the ruler
---@param width number
---@param state table @for trackLength and sections
local function drawRuler(originX, y, width, state)
  local height = theme.bandRulerHeight
  local bottom = y + height

  ui.drawRectFilled(vec2(originX, y), vec2(originX + width, bottom),
    theme.bandRulerBackground, theme.rounding)

  local named = type(state.sections) == 'table' and state.sections or nil

  -- The named stretches, as a tint behind their own text. A box round each
  -- one would be louder than what is in it.
  if named ~= nil then
    for i = 1, #named do
      local section = named[i]
      local x1 = originX + xOf(section.from, width)
      local x2 = originX + xOf(section.to, width)
      if x2 - x1 >= 1 then
        ui.drawRectFilled(vec2(x1, y), vec2(x2, bottom), theme.bandRulerSection)
      end
    end
  end

  local marks = ruler.ticks(state.trackLength, width)

  for i = 1, #marks do
    local mark = marks[i]
    local x = originX + xOf(mark.position, width)
    ui.drawLine(vec2(x, mark.major and y or (bottom - theme.bandRulerMinorTick)),
      vec2(x, bottom), theme.bandRulerTick, 1)
  end

  -- The distances, beside the mark they belong to rather than above it: the
  -- strip is one line of text tall and there is no above.
  for i = 1, #marks do
    local mark = marks[i]
    if mark.label ~= nil then
      local x = originX + xOf(mark.position, width) + theme.bandRulerLabelGap
      local textWidth = ui.measureText(mark.label).x

      -- Written only if the whole of it fits before the end of the lap, and
      -- only where the track has not named the ground it would be written on.
      -- A number half off the edge is worse than no number.
      local clear = x + textWidth <= originX + width
      if clear and named ~= nil then
        clear = sections.at(named, mark.position) == nil
          and sections.at(named, positionOf(x + textWidth - originX, width)) == nil
      end

      if clear then
        ui.drawTextClipped(mark.label, vec2(x, y), vec2(x + textWidth, bottom),
          theme.bandRulerLabel, vec2(0, 0.5), false)
      end
    end
  end

  -- And the names on top, each one inside its own stretch. A name that does
  -- not fit is not written: an ellipsis in a strip this thin is three dots
  -- saying a name is there, which the tint already says.
  if named ~= nil then
    for i = 1, #named do
      local section = named[i]
      if section.text ~= nil then
        local x1 = originX + xOf(section.from, width)
        local x2 = originX + xOf(section.to, width)
        local room = x2 - x1 - 2 * theme.bandLabelPadding

        if ui.measureText(section.text).x <= room then
          ui.drawTextClipped(section.text,
            vec2(x1 + theme.bandLabelPadding, y),
            vec2(x2 - theme.bandLabelPadding, bottom),
            theme.bandRulerName, vec2(0.5, 0.5), false)
        end
      end
    end
  end
end

---@param state table
---  cameras          the camera list being edited
---  cameraIndex      the camera being edited
---  liveCameraIndex  the camera the car has made live
---  camera           that camera, for its keyframes
---  keyframeIndex    the selected keyframe
---  trackPos         the car, 0..1
---  trackLength      the lap in metres, for the ruler's distances
---  sections         the track's named stretches, as core/sections gives them
---@param width number
---@return table @what the user did, any of:
---  camera        a camera they clicked on
---  keyframe      a keyframe of the selected camera they clicked on
---  move          { position, gesture } while a camera start is dragged
---  rename        { index, name } when a name is committed
---  scrubTo       a lap position the playhead is being dragged over, this
---                frame, while the drag is still running
---  seekTo        a lap position to bring the car to
---  hint          what to say in the status line while the pointer is here
---  addCamera     a lap position to put a new camera at
---  removeCamera  the index of one to take away
---
---One table rather than a row of return values. Six of those had accumulated,
---and the seventh is what made the point: every caller had to count commas to
---find out which nil was which.
local function drawBand(state, width)
  -- The two zones. Everything below measures from `bandTop` and `bottom`
  -- rather than from the widget's own origin, so the ruler can change height
  -- without every keyframe and label moving with it.
  local height = theme.bandRulerHeight + theme.bandHeight
  local origin = ui.getCursor()
  local bandTop = origin.y + theme.bandRulerHeight
  local bottom = bandTop + theme.bandHeight

  -- A button each, so the two zones can hover, point and drag differently.
  -- One button spanning both would make the ruler answer for gestures that
  -- belong to the cameras under it.
  ui.setCursor(vec2(origin.x, origin.y))
  ui.invisibleButton('##bandRuler', vec2(width, theme.bandRulerHeight))
  local rulerHovered = ui.itemHovered()
  local rulerActive = ui.itemActive()

  ui.setCursor(vec2(origin.x, bandTop))
  local clicked = ui.invisibleButton('##trackBand', vec2(width, theme.bandHeight))
  local hovered = ui.itemHovered()

  ------------------------------------------------------------------
  -- Dragging the playhead
  ------------------------------------------------------------------
  -- ANYWHERE ON THE RULER, and that is the whole rule. The triangle says
  -- where the head is; aiming at five pixels of it before the replay will
  -- move is a test of nerve, not a gesture. Every editor worth copying lets
  -- the whole ruler be dragged.
  --
  -- A click is a drag of one frame, so clicking somewhere on the ruler and
  -- dragging along it are the same code and need no telling apart.
  --
  -- NONE OF THIS IS AN EDIT. It moves the replay, reaches no camera data, and
  -- has no business on the undo stack.
  local pointer = ui.mouseLocalPos()
  local pointerAt = (pointer ~= nil and pointer.x >= 0)
    and positionOf(pointer.x - origin.x, width) or nil

  scrubReport, scrubLanding = nil, nil

  -- While a drag runs the pointer may leave the ribbon, and it will: pulling
  -- the head onto the start line means going past it. So this reading is not
  -- the one above -- that one treats a pointer outside the window as no
  -- pointer at all, which is right for a click and wrong here, where letting
  -- the gesture drop would leave the head stuck a few pixels short of the end
  -- it was being dragged to. positionOf clamps, so it stops AT the line.
  local dragAt = pointer ~= nil
    and positionOf(pointer.x - origin.x, width) or nil

  if rulerActive and dragAt ~= nil then
    scrubbing = true
    scrubAt = dragAt
    scrubReport = dragAt
  elseif scrubbing then
    -- Let go. The exact landing is asked for once, here, rather than on every
    -- frame of the drag: what runs during the drag is deliberately rough.
    scrubbing = false
    scrubLanding = scrubAt
    scrubAt = nil
  end

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


  drawRuler(origin.x, origin.y, width, state)

  ui.drawRectFilled(vec2(origin.x, bandTop), vec2(origin.x + width, bottom),
    theme.mapBackground, theme.rounding)

  -- Who owns what, worked out before anything is written: the hint below is
  -- mostly the name of the camera under the pointer, and it needs the spans
  -- to find it.
  -- One list at a time: the track cameras, or with the pit view on, the pit
  -- lane ones. They share the lap but never play together.
  local segments = trackmap.segments(state.cameras, state.pitView)
  local spans = trackmap.bandSpans(segments)

  -- The pointer says the ribbon does something, and the line at the bottom of
  -- the panel says what. Between them they cost no height at all, which is
  -- the whole reason for putting it there.
  local hoveredIndex = nil
  if hovered and pointerAt ~= nil then
    hoveredIndex = trackmap.ownerAt(segments, pointerAt)
  end

  local hint = nil
  if rulerHovered or scrubbing then
    -- The same arrow a value shows when it can be dragged sideways, which is
    -- the same promise: hold and move, and the number under you changes.
    ui.setMouseCursor(ui.MouseCursor.ResizeEW)
    hint = 'Drag anywhere on the ruler to move the playhead; ' ..
      'the replay follows.'
  end
  if hovered then
    ui.setMouseCursor(ui.MouseCursor.Hand)

    -- The name lives here now, and this is the whole reason the segments
    -- carry a number alone. A camera nobody has named answers with its
    -- number, which is what data.cameraLabel does.
    local camera = hoveredIndex ~= nil and state.cameras ~= nil
      and state.cameras[hoveredIndex] or nil
    local named = hoveredIndex ~= nil
      and ('Camera ' .. hoveredIndex
        .. (type(camera) == 'table' and type(camera.name) == 'string'
          and camera.name ~= '' and ('  --  ' .. camera.name) or ''))
      or nil

    hint = (state.pitView and 'Pit lane cameras.  ' or '') ..
      (named ~= nil and (named .. '.  ') or '') ..
      'Click: select.  Double click: rename.  ' ..
      'Right click: bring the car here, add a camera, or remove one.'
  end

  ------------------------------------------------------------------
  -- The lap, camera by camera
  ------------------------------------------------------------------
  local top = bottom - theme.bandRibbon
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

    ui.drawRectFilled(vec2(x1, top), vec2(x2, bottom), colour)
    span.x1, span.x2 = x1, x2
  end

  -- An empty pit view says what it is, rather than looking like a file with
  -- no cameras at all.
  if state.pitView and #spans == 0 then
    ui.drawTextClipped('no pit lane camera -- right click to add one',
      vec2(origin.x, top), vec2(origin.x + width, bottom),
      theme.bandLabel, vec2(0.5, 0.5), true)
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
      ui.drawLine(vec2(x, top), vec2(x, bottom), theme.bandTick, 1)
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

  local pointerX = pointerAt ~= nil and (pointer.x - origin.x) or nil

  ------------------------------------------------------------------
  -- Which camera is which
  ------------------------------------------------------------------
  -- THE NUMBER, AND NOTHING ELSE. It used to be the name if it fitted, else
  -- the number if it fitted, else nothing -- except the one under the pointer,
  -- which wrote its name above the ribbon. Three states for one label, and
  -- nothing on screen to say which of them you were reading. Théo's words:
  -- "it is not clear to show sometimes a number and sometimes the name", and
  -- he is right -- a label that changes its nature with the room available is
  -- not read, it is guessed.
  --
  -- The number is the right thing to keep here because it is what makes a set
  -- COUNTABLE: short, the same shape on every segment, and it fits almost
  -- everywhere. The name is longer and more useful, and it now has somewhere
  -- that never runs out of room -- the status line, which names whatever is
  -- under the pointer.
  --
  -- A segment too thin even for a digit is left blank. It is still perfectly
  -- visible -- its colour and its hand-over tick are drawn whatever its width
  -- -- and hovering it says what it is.
  for i = 1, #spans do
    local span = spans[i]
    local room = span.x2 - span.x1 - 2 * theme.bandLabelPadding
    local rank = tostring(span.index)

    -- Room enough to hold the text AND not be ellipsised. Asking only whether
    -- it fits exactly gets "22" drawn as "..." -- the ellipsis wants room of
    -- its own, and a number that just fits has none to give it.
    if room >= theme.bandLabelMin
        and ui.measureText(rank).x + theme.bandLabelSlack <= room then
      ui.drawTextClipped(rank,
        vec2(span.x1 + theme.bandLabelPadding, top),
        vec2(span.x2 - theme.bandLabelPadding, bottom),
        theme.bandLabel, vec2(0.5, 0.5), true)
    end
  end

  ------------------------------------------------------------------
  -- The keyframes of the camera being edited
  ------------------------------------------------------------------
  -- Only that camera's. All of them at once would be a row of diamonds with
  -- nothing to say which belongs to what, and the panel edits one camera.
  local keyframes = state.camera ~= nil and state.camera.keyframes or nil
  local keyframeY = bandTop + theme.bandKeyframeY

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
    ui.setCursor(vec2(origin.x, bottom))
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

      ui.setCursor(vec2(fieldX, bottom - theme.bandRibbon))

      -- TAKE THE KEYBOARD ON THE FRAME IT OPENS, or every keystroke goes
      -- somewhere else. Without this the field appeared -- a grey box over
      -- the ribbon -- and typing did nothing at all, which reads as a rename
      -- that is not implemented rather than a field waiting to be clicked.
      -- ui/atr does the same for the file name and says the same thing.
      if not renameWasActive then ui.setKeyboardFocusHere() end

      ui.setNextItemWidth(fieldWidth)
      local text, _, entered = ui.inputText('##bandRename', renameBuffer,
        ui.InputTextFlags.AutoSelectAll)
      renameBuffer = text or renameBuffer

      if entered then
        renamed = { index = span.index, name = renameBuffer }
        renaming, renameWasActive = nil, false
      elseif ui.itemActive() then
        renameWasActive = true
      elseif renameWasActive then
        -- Clicked away: dropped, like every other typed entry in this panel.
        -- Not Escape -- see ui/parameter for why that key is left alone.
        --
        -- ONCE IT HAS BEEN ACTIVE, and not before: a field is not active on
        -- the frame it appears. The old test asked instead whether the buffer
        -- was empty, so naming a camera that had no name -- the only kind
        -- anyone wants to name -- left the field open for ever, unfocused,
        -- with nothing able to close it.
        renaming, renameWasActive = nil, false
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
    ui.drawRectFilled(vec2(x - 2, bandTop), vec2(x + 2, bottom),
      theme.stripActive, theme.rounding)
  end

  ------------------------------------------------------------------
  -- The playhead
  ------------------------------------------------------------------
  -- Where the replay is, which on a ribbon measured in track position is
  -- where the car is. It follows the replay on its own and needs nobody to
  -- move it.
  --
  -- A LINE ACROSS BOTH ZONES, WITH A GRIP IN THE RULER. The line has to cross
  -- the cameras -- reading it against them is the whole point of having it --
  -- but a line is not something anyone thinks to take hold of, and one two
  -- pixels wide is not something anyone could. The triangle in the ruler is
  -- the part that says "pull me", and it sits in the zone where pulling is
  -- what happens.
  local playAt = playheadAt(state)
  if playAt ~= nil then
    local x = origin.x + xOf(playAt, width)
    ui.drawLine(vec2(x, origin.y), vec2(x, bottom), theme.mapPlayhead, 1.5)

    -- Apex down, at the foot of the ruler, so the point of the triangle and
    -- the line it belongs to are the same place.
    local grip = theme.bandPlayheadGrip
    ui.drawTriangleFilled(
      vec2(x, bandTop),
      vec2(x - grip, bandTop - grip),
      vec2(x + grip, bandTop - grip), theme.mapPlayhead)
  end

  ui.setCursor(vec2(origin.x, origin.y + height))

  ------------------------------------------------------------------
  -- Clicking
  ------------------------------------------------------------------
  -- A keyframe first, then the camera under the click. Diamonds are small and
  -- sit on top of the ribbon, so anything else would make them unclickable.
  local mouse, at = pointer, pointerAt

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

  -- A CLICK SELECTS, AND THAT IS ALL IT DOES. It used to move the replay as
  -- well, with Shift to hold it still, and both halves of that were wrong.
  -- Moving the replay on every selection is in the way while a set is being
  -- built: picking a camera to edit is not a request to go and watch it, and
  -- the moment you were looking at is gone. And a modifier that turns a
  -- behaviour off is a thing only its author knows about -- there is nothing
  -- on screen that could tell you Shift was there.
  --
  -- The playhead has a zone of its own now, which is where an editor puts it,
  -- and nothing outside that zone touches it.
  return {
    hint = hint,
    camera = trackmap.ownerAt(segments, at),
    rename = renamed,
  }
end

---What the ribbon did this frame, the scrub included.
---
---The scrub is added here rather than at each of the half-dozen places the
---body returns from. It is decided at the top of the frame, before anything
---is drawn, because the playhead is drawn from it -- so by the time any of
---those returns is reached the answer has been known for a while.
function band.draw(state, width)
  local did = drawBand(state, width)

  if scrubReport ~= nil then did.scrubTo = scrubReport end
  -- The landing outranks anything else asking for a seek this frame: it is
  -- the end of a gesture the user is still holding in their hand.
  if scrubLanding ~= nil then did.seekTo = scrubLanding end

  return did
end

---Give up any drag in progress. For tests.
function band.reset()
  dragging, wasActive = false, false
  scrubbing, scrubAt = false, nil
  scrubReport, scrubLanding = nil, nil
  menuAt, menuIndex = nil, nil
  renaming, renameBuffer, renameWasActive = nil, '', false
end

return band
