--[[
  One parameter row of the ATR panel: a label, and a value between two arrows.

      FOCUS POINT  AF
     ‹   69.40 m    ›

  Presentation only. It is handed a formatted string and a colour, and hands
  back which part was clicked; deciding what a click means is the caller's job.
  Keeping it that way is what lets the panel be drawn in a test without a
  camera, a file or a running game behind it.

  Three things the caller has to know, all of them from CamTool 2 by way of
  docs/ui-inventory.md:

  The value is red when a keyframe sits at the playhead. That is not styling,
  it is the state of the parameter, and clicking the value is what toggles it.

  The arrows and the value are three separate targets. CamTool 2 has the same
  three, which is why the quick keyboard entry ATR asked for cannot be a plain
  click -- that gesture is taken.

  Nothing here is wired to anything yet: the panel reads a camera file and
  shows it. The actions are returned so the wiring has somewhere to land.
]]

local theme = require('ui/theme')

local parameter = {}

---@alias ParameterAction
---| '"decrement"' @the left arrow
---| '"increment"' @the right arrow
---| '"toggle"' @the value itself: create or remove the keyframe here
---| '"badge"' @the small marker on the label, where there is one

---Draw one row.
---
---@param id string @unique within the window, for ImGui
---@param spec table
---  label      what to write above the value
---  text       the value, already formatted, units included
---  column     one of theme.columns
---  keyframed  true when a keyframe sits at the playhead
---  present    false when there is nothing to show; the row greys out
---  badge      a short marker beside the label, such as 'AF'
---  badgeOn    whether that marker is lit
---  width      the row's width in pixels
---@return ParameterAction|nil
function parameter.draw(id, spec)
  local width = spec.width or 100
  local column = spec.column or theme.columns.camera
  local action = nil

  ui.beginGroup(width)

  ------------------------------------------------------------------
  -- Label
  ------------------------------------------------------------------
  local labelColour = spec.present == false and theme.absent or theme.label
  ui.pushStyleColor(ui.StyleColor.Text, labelColour)
  ui.textAligned(spec.label, ui.Alignment.Center, vec2(width, theme.labelHeight))
  ui.popStyleColor()

  if spec.badge ~= nil then
    -- The badge sits on the label line, right-aligned, and is its own target:
    -- on FOCUS POINT it is the Autofocus toggle, which in CamTool 2 is a row
    -- of its own and here has to fit in the corner.
    ui.sameLine(0, 0)
    ui.offsetCursorX(-theme.arrowWidth - 2)
    ui.pushStyleColor(ui.StyleColor.Button, rgbm(0, 0, 0, 0))
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, column.pillHover)
    ui.pushStyleColor(ui.StyleColor.ButtonActive, column.pill)
    ui.pushStyleColor(ui.StyleColor.Text,
      spec.badgeOn and theme.keyframed or theme.absent)
    if ui.button(spec.badge .. '##' .. id .. 'badge',
        vec2(theme.arrowWidth + 6, theme.labelHeight)) then
      action = 'badge'
    end
    ui.popStyleColor(4)
  end

  ------------------------------------------------------------------
  -- Arrows and value
  ------------------------------------------------------------------
  local pill = spec.keyframed and theme.keyframed or column.pill
  local pillHover = spec.keyframed and theme.keyframedHover or column.pillHover

  ui.pushStyleColor(ui.StyleColor.Button, column.pill)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, column.pillHover)
  ui.pushStyleColor(ui.StyleColor.ButtonActive, pillHover)
  ui.pushStyleColor(ui.StyleColor.Text, theme.text)

  -- Held arrows repeat, as they do in CamTool 2. arrowButton rather than a
  -- '<' in a button: a drawn triangle sizes itself to the row and stays quiet
  -- next to the coloured pill, where the text glyph did not.
  ui.pushButtonRepeat(true)
  if ui.arrowButton('##' .. id .. 'dec', ui.Direction.Left,
      vec2(theme.arrowWidth, theme.rowHeight)) then
    action = 'decrement'
  end
  ui.popButtonRepeat()

  ui.sameLine(0, 1)

  local valueWidth = width - 2 * theme.arrowWidth - 2
  ui.popStyleColor(4)

  ui.pushStyleColor(ui.StyleColor.Button, pill)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, pillHover)
  ui.pushStyleColor(ui.StyleColor.ButtonActive, pillHover)
  ui.pushStyleColor(ui.StyleColor.Text,
    spec.present == false and theme.absent or theme.text)
  if ui.button((spec.text or '--') .. '##' .. id .. 'val',
      vec2(valueWidth, theme.rowHeight)) then
    action = 'toggle'
  end
  ui.popStyleColor(4)

  ui.sameLine(0, 1)

  ui.pushStyleColor(ui.StyleColor.Button, column.pill)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, column.pillHover)
  ui.pushStyleColor(ui.StyleColor.ButtonActive, pillHover)
  ui.pushStyleColor(ui.StyleColor.Text, theme.text)
  ui.pushButtonRepeat(true)
  if ui.arrowButton('##' .. id .. 'inc', ui.Direction.Right,
      vec2(theme.arrowWidth, theme.rowHeight)) then
    action = 'increment'
  end
  ui.popButtonRepeat()
  ui.popStyleColor(4)

  ui.endGroup()

  return action
end

return parameter
