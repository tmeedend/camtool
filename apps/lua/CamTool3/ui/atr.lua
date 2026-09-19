--[[
  The ATR panel: every parameter of the selected camera on one screen.

  Drawn from the mockup at the top of apps/python/CamTool_2/atr-new-ui.png.
  The point of it, in ATR's words, is that changing tabs costs time: CamTool 2
  puts Camera, Transform and Tracking behind three tabs, and this puts them
  side by side in the three colours those tabs already use.

  This module reads a camera document and draws it. It does not change one --
  the arrows and the values report what was clicked and the caller decides,
  and for now the caller does nothing with it. What is on screen is real
  though: the camera the car's position selected, the values in force at the
  playhead, and which of them are keyframed here.

  ISO FONCTIONNEL. docs/ui-inventory.md is the list of everything CamTool 2
  can do, and nothing on it may quietly vanish in the move to one screen. The
  mockup does leave things out, so they are gathered at the bottom under
  "ailleurs dans CamTool 2" rather than forgotten: that section is a debt
  list, and it shrinks as each one finds its place.
]]

local theme = require('ui/theme')
local parameter = require('ui/parameter')
local evaluate = require('core/evaluate')

local atr = {}

--------------------------------------------------------------------------------
-- What each column holds
--------------------------------------------------------------------------------

---How a value is turned into what the panel shows. The stored form is rarely
---the readable one: angles are radians, strengths are 0..1, and a track
---position is a fraction of a lap. docs/ui-inventory.md calls this out as a
---rule of the old UI, and it carries over unchanged.
local FORMAT = {
  metres = function(v) return string.format('%.2f m', v) end,
  degrees = function(v) return string.format('%.2f deg', math.deg(v)) end,
  plainDegrees = function(v) return string.format('%.2f deg', v) end,
  percent = function(v) return string.format('%.0f%%', v * 100) end,
  ratio = function(v) return string.format('%.2f', v) end,
  car = function(v) return 'car ' .. tostring(math.floor(v)) end,
}

---@param key string @the field in a keyframe or on the camera
---@param label string @as the mockup writes it
---@param format function
local function row(key, label, format, badge)
  return { key = key, label = label, format = format, badge = badge }
end

---A row whose value is not in the camera file at all.
---
---The tracked cars are the case, and it is worth stating plainly: CamTool 2
---keeps them in Camera.__init__, changes them with set_tracked_car, and never
---writes them anywhere. They are session state, reset to car 0 every time
---Assetto Corsa starts, and no camera remembers which car it was framing.
---Making them part of a camera would be a new feature, not a port.
local function runtimeRow(key, label, format)
  return { key = key, label = label, format = format, runtime = true }
end

atr.COLUMNS = {
  {
    colour = 'camera',
    rows = {
      -- camera_in is not a keyframed parameter: it is where the camera takes
      -- over, and it lives on the camera itself.
      row('camera_in', 'STARTING POINT', FORMAT.metres),
      row('camera_focus_point', 'FOCUS POINT', FORMAT.metres, 'AF'),
      row('camera_fov', 'FOV', FORMAT.plainDegrees),
      row('camera_shake_strength', 'SHAKE CAMERA', FORMAT.percent),
      row('camera_offset_shake_strength', 'SHAKE TRACKING', FORMAT.percent),
    },
  },
  {
    colour = 'transform',
    rows = {
      row('loc_x', 'X', FORMAT.metres),
      row('loc_y', 'Y', FORMAT.metres),
      row('loc_z', 'Z', FORMAT.metres),
      row('transform_loc_strength', 'STRENGTH LO.', FORMAT.percent),
      row('rot_x', 'PITCH', FORMAT.degrees),
      row('rot_y', 'ROLL', FORMAT.degrees),
      row('rot_z', 'HEADING', FORMAT.degrees),
      row('transform_rot_strength', 'STRENGTH RO.', FORMAT.percent),
    },
  },
  {
    colour = 'tracking',
    rows = {
      runtimeRow('trackedCarA', 'ACTIVE CAR', FORMAT.car),
      row('tracking_mix', 'MIX', FORMAT.percent),
      runtimeRow('trackedCarB', 'EXTRA CAR', FORMAT.car),
      row('tracking_offset', 'OFF TRACKING', FORMAT.ratio),
      row('tracking_offset_pitch', 'OFFSET PITCH', FORMAT.degrees),
      row('tracking_offset_heading', 'OFF HEADING', FORMAT.degrees),
      row('tracking_strength_pitch', 'STR PITCH', FORMAT.percent),
      row('tracking_strength_heading', 'STR HEADING', FORMAT.percent),
    },
  },
}

---Everything docs/ui-inventory.md lists that the mockup has no place for.
---Drawn, so that it is impossible to ship without noticing, and so the
---conversation about where each one goes happens over something visible.
atr.MISSING = {
  'Pit only', 'Specific cam', 'mode position / temps',
  'onglet Spline', 'onglet Settings',
  'ajouter / supprimer une camera', 'Activate Free Camera',
}

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

---The value in force, and whether a keyframe sits at the playhead.
---
---Same order of preference as playback: the keyframed value first, then the
---one on the camera. Kept here rather than shared with core/playback because
---this one is about what to show, not about where to put the camera -- and
---the day they disagree, the panel must follow the camera, not the other way
---round.
---@return number|nil value, boolean keyframedHere
local function valueOf(camera, key, trackPos)
  if camera == nil then return nil, false end

  local here = evaluate.keyframeAt(camera, key, trackPos) ~= nil
  local keyframed = evaluate.parameter(camera, key, trackPos)
  if keyframed ~= nil then return keyframed, here end

  return camera[key], here
end

local function columnWidth(total)
  return math.floor((total - 2 * theme.columnGap - 2 * theme.padding) / 3)
end

---@param state table
---  doc          the migrated document, or nil
---  camera       the selected camera, or nil
---  cameraIndex  its 1-based index
---  cameraCount  how many cameras the list holds
---  trackPos     the playhead, 0..1
---  trackLength  metres, for the header readout
---@return table @actions raised this frame: { key = <ParameterAction> }
function atr.draw(state)
  local actions = {}
  local width = ui.availableSpaceX()

  ------------------------------------------------------------------
  -- Header
  ------------------------------------------------------------------
  ui.pushStyleColor(ui.StyleColor.Text, theme.text)
  ui.textAligned('CAMTOOL 3', ui.Alignment.Start, vec2(width * 0.5, 20))
  ui.sameLine(0, 0)
  local metres = (state.trackPos or 0) * (state.trackLength or 0)
  ui.textAligned(string.format('%.0f m', metres), ui.Alignment.End,
    vec2(width * 0.5, 20))
  ui.popStyleColor()

  ------------------------------------------------------------------
  -- The camera strip
  ------------------------------------------------------------------
  -- One button per camera, the live one in red. CamTool 2 only offers
  -- previous and next, and ATR's mockup replaces that with the whole set at
  -- a glance -- on a 48-camera file that is the difference between a click
  -- and forty.
  local count = state.cameraCount or 0
  if count > 0 then
    local perRow = 20
    local cellWidth = math.floor((width - (perRow - 1)) / perRow)
    for i = 1, count do
      local active = i == state.cameraIndex
      ui.pushStyleColor(ui.StyleColor.Button,
        active and theme.stripActive or theme.strip)
      ui.pushStyleColor(ui.StyleColor.ButtonHovered, theme.stripActive)
      ui.pushStyleColor(ui.StyleColor.ButtonActive, theme.stripActive)
      if ui.button(tostring(i) .. '##cam' .. i, vec2(cellWidth, 16)) then
        actions.selectCamera = i
      end
      ui.popStyleColor(3)
      if i % perRow ~= 0 and i < count then ui.sameLine(0, 1) end
    end
    ui.newLine(2)
  end

  ------------------------------------------------------------------
  -- The three columns
  ------------------------------------------------------------------
  local colWidth = columnWidth(width)

  for index, column in ipairs(atr.COLUMNS) do
    local colour = theme.columns[column.colour]

    ui.beginGroup(colWidth)
    ui.pushStyleColor(ui.StyleColor.Text, theme.text)
    ui.textAligned(colour.title, ui.Alignment.Center, vec2(colWidth, 18))
    ui.popStyleColor()

    for _, spec in ipairs(column.rows) do
      local value, here
      if spec.runtime then
        value, here = state[spec.key], false
      else
        value, here = valueOf(state.camera, spec.key, state.trackPos)
      end

      -- camera_in is a track position: stored as a fraction of a lap, shown
      -- in metres, exactly as CamTool 2 shows it.
      local shown = value
      if spec.key == 'camera_in' and shown ~= nil then
        shown = shown * (state.trackLength or 0)
      end

      local action = parameter.draw(column.colour .. spec.key, {
        label = spec.label,
        text = type(shown) == 'number' and spec.format(shown) or nil,
        column = colour,
        keyframed = here,
        present = value ~= nil,
        width = colWidth,
        badge = spec.badge,
        badgeOn = spec.badge ~= nil and state.camera ~= nil
          and state.camera.camera_use_tracking_point == 1,
      })
      if action ~= nil then actions[spec.key] = action end
    end

    ui.endGroup()
    if index < #atr.COLUMNS then ui.sameLine(0, theme.columnGap) end
  end

  ui.newLine(4)

  ------------------------------------------------------------------
  -- What has not found a place yet
  ------------------------------------------------------------------
  ui.pushStyleColor(ui.StyleColor.Text, theme.absent)
  ui.text('Ailleurs dans CamTool 2, pas encore ici :')
  ui.text('  ' .. table.concat(atr.MISSING, ', '))
  ui.text('Lecture seule : les fleches et les valeurs ne modifient rien.')
  ui.popStyleColor()

  return actions
end

return atr
