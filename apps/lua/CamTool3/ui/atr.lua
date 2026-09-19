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
  'onglet Spline', 'onglet Settings', 'Activate Free Camera',
}

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

---The value the panel shows for one parameter, and whether it is keyframed.
---
---Not the value at the playhead: the value on the SELECTED KEYFRAME. That is
---what CamTool 2 edits -- its panel reads keyframes[active_kf] and nothing
---else -- and getting it wrong would have made every edit land somewhere the
---user was not looking. Red means this keyframe carries the parameter; grey
---means it does not and the camera's own value applies across its whole span.
---
---With no keyframe selected there is only the camera-level value, which is
---the honest picture of a camera that animates nothing.
---@return number|nil value, boolean keyframed
local function valueOf(camera, key, keyframeIndex)
  if camera == nil then return nil, false end

  local keyframes = camera.keyframes
  if type(keyframes) == 'table' and keyframeIndex ~= nil then
    local kf = keyframes[keyframeIndex]
    local interp = type(kf) == 'table' and kf.interpolation or nil
    if interp ~= nil and type(interp[key]) == 'number' then
      return interp[key], true
    end
  end

  return camera[key], false
end

---Draw a row of numbered buttons with an add and a remove at the end.
---
---The left side of CamTool 2 is two such columns, cameras and keyframes. ATR's
---mockup turns the camera one on its side and drops the other; both are here,
---because losing the keyframe list would leave no way to make a camera move.
---@return number|nil picked, boolean added, boolean removed
local function strip(id, count, active, width, colour, live)
  local picked, added, removed = nil, false, false
  local perRow = 20
  local cell = math.floor((width - (perRow - 1)) / perRow)

  for i = 1, count do
    -- Two different things, and CamTool 2 keeps them apart too: the camera
    -- being edited (__active_cam) and the one the car's position has made
    -- live (data.active_cam). Red is the one you are editing; the paler tint
    -- is the one on screen.
    local fill = colour
    if i == live then fill = theme.stripLive end
    if i == active then fill = theme.stripActive end
    ui.pushStyleColor(ui.StyleColor.Button, fill)
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, theme.stripActive)
    ui.pushStyleColor(ui.StyleColor.ButtonActive, theme.stripActive)
    if ui.button(tostring(i) .. '##' .. id .. i, vec2(cell, 16)) then
      picked = i
    end
    ui.popStyleColor(3)
    if i % perRow ~= 0 then ui.sameLine(0, 1) end
  end

  ui.pushStyleColor(ui.StyleColor.Button, colour)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, theme.stripActive)
  ui.pushStyleColor(ui.StyleColor.ButtonActive, theme.stripActive)
  if ui.button('+##' .. id .. 'add', vec2(cell, 16)) then added = true end
  ui.sameLine(0, 1)
  if ui.button('-##' .. id .. 'del', vec2(cell, 16)) then removed = true end
  ui.popStyleColor(3)
  ui.newLine(2)

  return picked, added, removed
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
  actions.selectCamera, actions.addCamera, actions.removeCamera =
    strip('cam', state.cameraCount or 0, state.cameraIndex, width, theme.strip,
      state.liveCameraIndex)

  -- And the keyframes of that camera. This is the second column of CamTool 2's
  -- left side, which the mockup has no place for -- without it a camera can
  -- hold a pose but never move.
  actions.selectKeyframe, actions.addKeyframe, actions.removeKeyframe =
    strip('kf', state.keyframeCount or 0, state.keyframeIndex, width,
      theme.stripKeyframe)

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
        value, here = valueOf(state.camera, spec.key, state.keyframeIndex)
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
