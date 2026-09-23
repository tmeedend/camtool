--[[
  One parameter row of the ATR panel.

      ◆ FOCUS POINT  AF
      ‹   69.40 m     ›

  One component, reused for all twenty-one parameters. That is deliberate and
  it is why it is written before the panel becomes editable: CamTool 2 wired
  each field by hand and ended up with a hundred and fifty click handlers,
  which is why adding a gesture there costs a week. Here the arrows, the drag,
  the keyboard entry and the modifiers live in one place, and a new parameter
  is one line of table.

  The diamond on the left carries the keyframe state, in three steps:

    empty      this camera never animates the parameter
    hollow     it does, but not on the keyframe you have selected
    filled     it does, here

  That is the convention of every animation tool, and it buys two things. It
  frees the value itself, so clicking it can mean "type a number" instead of
  the hidden toggle CamTool 2 put there. And it answers out loud the question
  the old colour code left open: red meant "keyframed", and nobody could tell
  that from "in use".

  Presentation only: handed a formatted string and a state, hands back which
  part was touched. What a touch means is the caller's business.
]]

local theme = require('ui/theme')

local parameter = {}

---@alias ParameterAction
---| '"keyframe"' @the diamond: add or remove this parameter on the keyframe
---| '"decrement"' @the left arrow
---| '"increment"' @the right arrow
---| '"drag"' @the value was dragged; the payload is how many steps
---| '"dragCancel"' @Escape during a drag: put the value back as it was
---| '"commit"' @a number was typed; the payload is that number
---| '"badge"' @the marker beside the label, where there is one

---@alias KeyframeState '"none"'|'"elsewhere"'|'"here"'

local DIAMOND_SIZE = 9

---What you can do to a row, the same on every one of them -- which is the
---point of having one component. It goes to the status line after the
---sentence saying what the parameter does.
---
---Escape is not among them, and must not come back: the game leaves the
---replay on it. A drag is abandoned with a right click, a typed value by
---clicking away -- see the note above parameter.draw.
local GESTURES =
  'Diamond: keyframe here. Arrows: one step. Drag: scrub, right click to ' ..
  'abandon. Double click: type, click away to abandon. Ctrl: finer. ' ..
  'Shift: coarser.'
local GESTURES_READONLY = 'Read only.'
local GESTURES_NO_KEYFRAME = 'Arrows: one step. Drag: scrub, right click to ' ..
  'abandon. Double click: type, click away to abandon. Not keyframable.'

---How far the mouse travels for one step of the parameter. Eight pixels is
---about a comfortable nudge per centimetre of movement, and Ctrl and Shift
---still divide and multiply it because the drag goes through the same entry
---point as the arrows.
local PIXELS_PER_STEP = 8

---How far the pointer travels before the drag takes hold.
---
---A click that slips by a pixel must not move a value. Four is enough to tell
---the two apart and short enough that nobody notices it.
local DEAD_ZONE_PX = 4

-- Which row the mouse is holding, and how far that hold has got.
--
--   holding    pressed, but not yet past the dead zone
--   armed      dragging; every pixel now moves the value
--   cancelled  Escape was pressed; nothing moves until the button is let go
--
-- dragToken counts the gestures. Two drags of the same row are two entries on
-- the undo stack, and only a counter can tell them apart -- the row's own id
-- is the same both times.
local dragId = nil
local dragState = 'idle'
local dragToken = 0

-- What the mouse is over, for the status line at the foot of the panel.
--
-- THERE ARE NO TOOLTIPS. There were, with a delay of their own, and Théo had
-- them taken out: a bubble appears over the panel you are working in, and
-- what it covers is the row under the pointer and its neighbours -- the very
-- things you are looking at while you drag a value. Help that hides the work
-- is not help. The sentences are all still written and all still shown; they
-- go to the status line, which is always on screen, costs no height, and
-- covers nothing.
--
-- The status line has no delay either. It can afford to answer at once
-- precisely because it does not appear and disappear.
local hoverLabel = nil
local hoverHelp = nil
local hoverGestures = nil

-- Which row is being typed into, and what is in the field. One at a time,
-- so this is a plain pair rather than a table: opening a second field closes
-- the first, which is what anyone would expect.
local editing = nil
local buffer = ''
local editingWasActive = false

---Start a frame of the panel.
---
---Called once before any row is drawn: the rows themselves cannot tell that
---the mouse has left the panel entirely, only that it is not on them.
---@param dt number|nil @seconds since the last frame, kept for callers
function parameter.beginFrame(dt)
  parameter.frameDt = type(dt) == 'number' and dt or 0
  parameter.frameHovered = false
end

---Finish a frame: forget the hover if nothing claimed it.
function parameter.endFrame()
  if not parameter.frameHovered then
    hoverLabel, hoverHelp, hoverGestures = nil, nil, nil
  end
end

---What the mouse is over, for the status line.
---
---Three parts, because the line has to carry what the tooltip used to: the
---name of the row, what the parameter does, and what can be done to it.
---@return string|nil label, string|nil help, string|nil gestures
function parameter.hovered()
  return hoverLabel, hoverHelp, hoverGestures
end

---Note that this row is under the mouse, for the status line to name.
local function noteHover(id, spec)
  parameter.frameHovered = true
  hoverLabel, hoverHelp, hoverGestures = spec.label, spec.help, spec.gestures
end

---Draw the keyframe diamond and report whether it was clicked.
---@param state KeyframeState
local function diamond(id, state)
  local clicked = ui.invisibleButton('##' .. id .. 'kf',
    vec2(DIAMOND_SIZE + 4, theme.labelHeight))

  local a, b = ui.itemRectMin(), ui.itemRectMax()
  local cx, cy = (a.x + b.x) / 2, (a.y + b.y) / 2
  local r = DIAMOND_SIZE / 2

  local top = vec2(cx, cy - r)
  local right = vec2(cx + r, cy)
  local bottom = vec2(cx, cy + r)
  local left = vec2(cx - r, cy)

  if state == 'here' then
    ui.drawQuadFilled(top, right, bottom, left, theme.diamondFilled)
  else
    -- Outlined either way; the colour says whether the parameter is animated
    -- anywhere in this camera.
    local colour = state == 'elsewhere' and theme.diamondHollow
      or theme.diamondEmpty
    ui.drawLine(top, right, colour, 1)
    ui.drawLine(right, bottom, colour, 1)
    ui.drawLine(bottom, left, colour, 1)
    ui.drawLine(left, top, colour, 1)
  end

  return clicked
end

---Draw one row.
---
---@param id string @unique within the window, for ImGui
---@param spec table
---  label     what to write beside the diamond
---  text      the value, already formatted, units included
---  column    one of theme.columns
---  keyframe  a KeyframeState
---  present   false when there is nothing to show; the row greys out
---  badge     a short marker after the label, such as 'AF'
---  badgeOn   whether that marker is lit
---  width     the row's width in pixels
---@return ParameterAction|nil
---Nothing here holds the keyboard any more.
---
---It did, so that Escape could cancel a gesture without Assetto Corsa taking
---it as "leave the replay". The capture worked. What made it the wrong answer
---is that it trained the hand: press Escape to abandon a field, press it again
---a moment later with nothing open, and the session goes -- with every unsaved
---camera in it. A cancel gesture is not worth that.
---
---So a drag is abandoned with a right click, a typed value by clicking away,
---and Escape is left to mean what the game has always meant by it.

function parameter.draw(id, spec)
  local width = spec.width or 100


  -- Worked out here rather than written into every row: what a row allows is
  -- already described by the flags it carries.
  if spec.gestures == nil then
    if spec.runtime then
      spec.gestures = GESTURES_READONLY
    elseif spec.noDiamond then
      spec.gestures = spec.noTyping and GESTURES_READONLY or GESTURES_NO_KEYFRAME
    else
      spec.gestures = GESTURES
    end
  end
  local column = spec.column or theme.columns.camera
  local action = nil

  ui.beginGroup(width)

  ------------------------------------------------------------------
  -- Diamond, label, badge
  ------------------------------------------------------------------
  if spec.noDiamond then
    -- Nothing to keyframe, so nothing to show: an indent keeps the labels of
    -- the column lined up with those that do have one.
    ui.dummy(vec2(DIAMOND_SIZE + 4, theme.labelHeight))
  elseif diamond(id, spec.keyframe or 'none') then
    action = 'keyframe'
  end
  ui.sameLine(0, 2)

  local labelWidth = width - DIAMOND_SIZE - 8
  if spec.badge ~= nil then labelWidth = labelWidth - theme.arrowWidth - 8 end

  ui.pushStyleColor(ui.StyleColor.Text,
    spec.present == false and theme.absent or theme.label)
  -- vec2(0, 0.5): hard left, and centred on the line. The scalar form only
  -- says where to put it horizontally and leaves the text at the top.
  ui.textAligned(spec.label, vec2(0, 0.5),
    vec2(math.max(labelWidth, 10), theme.labelHeight))
  ui.popStyleColor()

  if spec.badge ~= nil then
    -- On FOCUS POINT this is Autofocus, a row of its own in CamTool 2 that
    -- has to fit in a corner here.
    ui.sameLine(0, 2)
    ui.pushStyleColor(ui.StyleColor.Button, rgbm(0, 0, 0, 0))
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, column.pillHover)
    ui.pushStyleColor(ui.StyleColor.ButtonActive, column.pill)
    ui.pushStyleColor(ui.StyleColor.Text,
      spec.badgeOn and column.accent or theme.absent)
    if ui.button(spec.badge .. '###' .. id .. 'badge',
        vec2(theme.arrowWidth + 6, theme.labelHeight)) then
      action = 'badge'
    end
    ui.popStyleColor(4)
  end

  ------------------------------------------------------------------
  -- Arrows and value
  ------------------------------------------------------------------
  -- An animated parameter has to be findable without reading every diamond in
  -- the column: the field itself carries a slightly lifted tint. The diamond
  -- still says WHERE the keyframe is; this only says that the camera moves
  -- this parameter at all.
  local animated = spec.keyframe == 'here' or spec.keyframe == 'elsewhere'
  local pill = animated and (column.pillAnimated or column.pill) or column.pill

  ui.pushStyleColor(ui.StyleColor.Button, pill)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, column.pillHover)
  ui.pushStyleColor(ui.StyleColor.ButtonActive, column.pillHover)
  -- A live reading is not this camera's value yet, and says so by being
  -- dimmer. Pinning it with the diamond is what makes it one.
  ui.pushStyleColor(ui.StyleColor.Text,
    (spec.present == false and theme.absent)
      or (spec.live and theme.muted)
      or theme.text)

  -- Held arrows repeat, as they do in CamTool 2.
  ui.pushButtonRepeat(true)
  if ui.arrowButton('##' .. id .. 'dec', ui.Direction.Left,
      vec2(theme.arrowWidth, theme.rowHeight)) then
    action = 'decrement'
  end
  ui.popButtonRepeat()

  ui.sameLine(0, 1)

  local valueWidth = width - 2 * theme.arrowWidth - 2
  local payload = nil

  if editing == id then
    ------------------------------------------------------------------
    -- Typing
    ------------------------------------------------------------------
    ui.setNextItemWidth(valueWidth)
    -- CharsDecimal keeps letters out; AutoSelectAll means the first keystroke
    -- replaces the old value instead of appending to it.
    local text, _, entered = ui.inputText('##' .. id .. 'entry', buffer,
      ui.InputTextFlags.CharsDecimal + ui.InputTextFlags.AutoSelectAll)
    buffer = text or buffer

    if entered then
      action, payload = 'commit', tonumber(buffer)
      editing, editingWasActive = nil, false
    elseif ui.itemActive() then
      editingWasActive = true
    elseif editingWasActive then
      -- Clicked away: abandon rather than commit half a number.
      editing, editingWasActive = nil, false
    end
  else
    ------------------------------------------------------------------
    -- Dragging, and the double click that opens the field
    ------------------------------------------------------------------
    -- ### and not ##: ImGui hashes the WHOLE label for a widget's
    -- identity, and only ### makes the part after it the identity on its
    -- own. The visible part here IS the value, so with ## the button was
    -- a different widget the instant it changed -- ImGui dropped the
    -- active item, and a drag moved the value exactly once before dying.
    ui.button((spec.text or '--') .. '###' .. id .. 'val',
      vec2(valueWidth, theme.rowHeight))

    local live = spec.present ~= false and not spec.noTyping

    -- The cursor is what makes the gesture discoverable, and it does it
    -- better than any line of help text under the panel.
    if ui.itemHovered() then
      noteHover(id, spec)
      if live then ui.setMouseCursor(ui.MouseCursor.ResizeEW) end
    end

    -- Horizontal only. A vertical drag would mean the same thing as scrolling
    -- the panel, and the mouse would have to choose.
    --
    -- The wheel deliberately does NOT do this. It is the same gesture whether
    -- you meant to scroll the panel or change a number -- only the pointer
    -- tells them apart, and nobody looks at the pointer while scrolling. Worse,
    -- if the panel scrolls at the same time, the rows travel under the pointer
    -- and one roll touches several parameters with nothing to show for it. For
    -- work whose mistakes only surface in the edit, that is the worst case
    -- there is.
    if live and ui.itemActive() then
      if dragId ~= id then dragId, dragState = id, 'holding' end

      -- Threshold zero: the dead zone is ours, measured on the axis that
      -- matters, rather than ImGui's which counts both.
      local delta = ui.mouseDragDelta(0, 0)
      local dx = delta ~= nil and delta.x or 0

      if dragState == 'holding' then
        if math.abs(dx) >= DEAD_ZONE_PX then
          dragState, dragToken = 'armed', dragToken + 1
          ui.resetMouseDragDelta(0)
        end
      elseif dragState == 'armed' then
        if ui.mouseClicked(ui.MouseButton.Right) then
          -- Right click to abandon, not Escape.
          --
          -- Escape is Assetto Corsa's key for leaving the replay. Holding the
          -- keyboard while a gesture is running stops it reaching the game --
          -- but it also teaches the hand to reach for Escape in an app where,
          -- a moment later with no field open, that same key ends the session
          -- and takes every unsaved camera with it. A cancel is not worth
          -- training that.
          --
          -- Right click is Blender's, it means nothing else during a drag,
          -- and pressing it by mistake costs one abandoned gesture.
          action, dragState = 'dragCancel', 'cancelled'
        elseif dx ~= 0 then
          action, payload = 'drag', dx / PIXELS_PER_STEP
          -- Reset so the next frame reports the movement since this one; the
          -- drag is then a stream of small steps rather than one growing jump.
          ui.resetMouseDragDelta(0)
        end
      end
    elseif dragId == id then
      dragId, dragState = nil, 'idle'
    end

    if not spec.noTyping and ui.itemHovered() and ui.mouseDoubleClicked(0) then
      editing, editingWasActive = id, false
      buffer = spec.raw or ''
    end
  end

  ui.sameLine(0, 1)

  ui.pushButtonRepeat(true)
  if ui.arrowButton('##' .. id .. 'inc', ui.Direction.Right,
      vec2(theme.arrowWidth, theme.rowHeight)) then
    action = 'increment'
  end
  ui.popButtonRepeat()

  ui.popStyleColor(4)
  ui.endGroup()

  return action, payload
end

---Which gesture is dragging, or nil when none is.
---
---The caller uses it to keep one drag to one undo entry: while this answers
---the same number, the edits it produces are all the same gesture stretching.
---@return number|nil
function parameter.draggingGesture()
  return dragState == 'armed' and dragToken or nil
end

---Give up any field being typed into. Called when the panel switches to
---another camera or keyframe, so a half-typed number cannot land somewhere
---it was never meant for.
function parameter.cancelEditing()
  editing, editingWasActive = nil, false
end

---An empty cell the height of a row, so columns of different lengths still
---line up with one another.
function parameter.blank(width)
  ui.dummy(vec2(width, theme.labelHeight + theme.rowHeight + 2))
end

return parameter
