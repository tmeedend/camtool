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
---| '"commit"' @a number was typed; the payload is that number
---| '"badge"' @the marker beside the label, where there is one

---@alias KeyframeState '"none"'|'"elsewhere"'|'"here"'

local DIAMOND_SIZE = 9

---How far the mouse travels for one step of the parameter. Eight pixels is
---about a comfortable nudge per centimetre of movement, and Ctrl and Shift
---still divide and multiply it because the drag goes through the same entry
---point as the arrows.
local PIXELS_PER_STEP = 8

-- Which row is being typed into, and what is in the field. One at a time,
-- so this is a plain pair rather than a table: opening a second field closes
-- the first, which is what anyone would expect.
local editing = nil
local buffer = ''
local editingWasActive = false

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
function parameter.draw(id, spec)
  local width = spec.width or 100
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
    if ui.button(spec.badge .. '##' .. id .. 'badge',
        vec2(theme.arrowWidth + 6, theme.labelHeight)) then
      action = 'badge'
    end
    ui.popStyleColor(4)
  end

  ------------------------------------------------------------------
  -- Arrows and value
  ------------------------------------------------------------------
  ui.pushStyleColor(ui.StyleColor.Button, column.pill)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, column.pillHover)
  ui.pushStyleColor(ui.StyleColor.ButtonActive, column.pillHover)
  ui.pushStyleColor(ui.StyleColor.Text,
    spec.present == false and theme.absent or theme.text)

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
    ui.button((spec.text or '--') .. '##' .. id .. 'val',
      vec2(valueWidth, theme.rowHeight))

    if spec.present ~= false and not spec.noTyping and ui.itemActive() then
      local delta = ui.mouseDragDelta(0)
      if delta ~= nil and delta.x ~= 0 then
        action, payload = 'drag', delta.x / PIXELS_PER_STEP
        -- Reset so the next frame reports the movement since this one; the
        -- drag is then a stream of small steps rather than one growing jump.
        ui.resetMouseDragDelta(0)
      end
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
