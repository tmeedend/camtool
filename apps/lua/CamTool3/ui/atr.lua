--[[
  The ATR panel: every parameter of the selected camera on one screen.

  Drawn from the mockup at the top of apps/python/CamTool_2/atr-new-ui.png.
  The point of it, in ATR's words, is that changing tabs costs time: CamTool 2
  puts Camera, Transform and Tracking behind three tabs, and this puts them
  side by side in the three colours those tabs already use.

  This module reads a camera document and draws it. It does not change one --
  the arrows and the values report what was clicked and the caller decides,
  and for now the caller does nothing with it. What is on screen is real
  though: the camera you selected, the values on the keyframe you selected,
  and a diamond per parameter saying whether that keyframe carries it.

  ISO FONCTIONNEL. docs/ui-inventory.md is the list of everything CamTool 2
  can do, and nothing on it may quietly vanish in the move to one screen. The
  mockup does leave things out, so they are gathered at the bottom under
  "elsewhere in CamTool 2" rather than forgotten: that section is a debt
  list, and it shrinks as each one finds its place.
]]

local theme = require('ui/theme')
local parameter = require('ui/parameter')
local evaluate = require('core/evaluate')

local atr = {}

--------------------------------------------------------------------------------
-- What each column holds
--------------------------------------------------------------------------------

---How a value is shown, and how what someone types comes back.
---
---The stored form is rarely the readable one: angles are radians, strengths
---are 0..1, and a track position is a fraction of a lap.
---docs/ui-inventory.md records this as a rule of the old UI and it carries
---over -- but only the old UI ever had to go one way. Typing 45 into a field
---labelled deg has to arrive as 0.785, so every unit owns both directions and
---a test walks each one there and back.
local UNITS = {
  metres = {
    show = function(v) return string.format('%.2f m', v) end,
    read = function(v) return v end,
  },
  degrees = {
    show = function(v) return string.format('%.2f deg', math.deg(v)) end,
    read = function(v) return math.rad(v) end,
  },
  plainDegrees = {
    show = function(v) return string.format('%.2f deg', v) end,
    read = function(v) return v end,
  },
  percent = {
    show = function(v) return string.format('%.0f%%', v * 100) end,
    read = function(v) return v / 100 end,
  },
  ratio = {
    show = function(v) return string.format('%.2f', v) end,
    read = function(v) return v end,
  },
  car = {
    show = function(v) return 'car ' .. tostring(math.floor(v)) end,
    read = function(v) return math.floor(v) end,
  },
  flag = {
    show = function(v) return v == true and 'yes' or 'no' end,
    read = function(v) return v end,
  },
  specificCam = {
    -- Minus one means CamTool drives. Anything else hands the view to one of
    -- Assetto Corsa's own cameras, and CamTool 2 then skips its whole
    -- interpolation -- which the port does not do yet.
    show = function(v)
      if v == nil or v < 0 then return 'CamTool' end
      return 'AC cam ' .. tostring(math.floor(v))
    end,
    read = function(v) return v end,
  },
}

atr.UNITS = UNITS

---@param key string @the field in a keyframe or on the camera
---@param label string @as the mockup writes it
---@param unit table @one of UNITS
local function row(key, label, unit, badge)
  return { key = key, label = label, unit = unit, badge = badge }
end

---A row whose value is not in the camera file at all.
---
---The tracked cars are the case, and it is worth stating plainly: CamTool 2
---keeps them in Camera.__init__, changes them with set_tracked_car, and never
---writes them anywhere. They are session state, reset to car 0 every time
---Assetto Corsa starts, and no camera remembers which car it was framing.
---Making them part of a camera would be a new feature, not a port.
local function runtimeRow(key, label, unit)
  return { key = key, label = label, unit = unit, runtime = true }
end

---A row for something that lives on the camera and cannot be keyframed, so
---it has no diamond and nothing to type into: Pit only and Specific cam.
---Both are in docs/ui-inventory.md and neither is in ATR's mockup, which is
---what the debt list at the bottom of the panel was for.
local function plainRow(key, label, unit)
  return { key = key, label = label, unit = unit, plain = true }
end

atr.COLUMNS = {
  {
    colour = 'camera',
    rows = {
      -- camera_in is not a keyframed parameter: it is where the camera takes
      -- over, and it lives on the camera itself.
      row('camera_in', 'STARTING POINT', UNITS.metres),
      row('camera_focus_point', 'FOCUS POINT', UNITS.metres, 'AF'),
      row('camera_fov', 'FOV', UNITS.plainDegrees),
      row('camera_shake_strength', 'SHAKE CAMERA', UNITS.percent),
      row('camera_offset_shake_strength', 'SHAKE TRACKING', UNITS.percent),
      plainRow('camera_pit', 'PIT ONLY', UNITS.flag),
      plainRow('camera_use_specific_cam', 'SPECIFIC CAM', UNITS.specificCam),
    },
  },
  {
    colour = 'transform',
    rows = {
      row('loc_x', 'X', UNITS.metres),
      row('loc_y', 'Y', UNITS.metres),
      row('loc_z', 'Z', UNITS.metres),
      row('transform_loc_strength', 'STRENGTH LO.', UNITS.percent),
      row('rot_x', 'PITCH', UNITS.degrees),
      row('rot_y', 'ROLL', UNITS.degrees),
      row('rot_z', 'HEADING', UNITS.degrees),
      row('transform_rot_strength', 'STRENGTH RO.', UNITS.percent),
    },
  },
  {
    colour = 'tracking',
    rows = {
      runtimeRow('trackedCarA', 'ACTIVE CAR', UNITS.car),
      row('tracking_mix', 'MIX', UNITS.percent),
      runtimeRow('trackedCarB', 'EXTRA CAR', UNITS.car),
      row('tracking_offset', 'OFF TRACKING', UNITS.ratio),
      row('tracking_offset_pitch', 'OFFSET PITCH', UNITS.degrees),
      row('tracking_offset_heading', 'OFF HEADING', UNITS.degrees),
      row('tracking_strength_pitch', 'STR PITCH', UNITS.percent),
      row('tracking_strength_heading', 'STR HEADING', UNITS.percent),
    },
  },
}

---Everything docs/ui-inventory.md lists that the mockup has no place for.
---Drawn, so that it is impossible to ship without noticing, and so the
---conversation about where each one goes happens over something visible.
atr.MISSING = {
  'Spline tab', 'Settings tab', 'Activate Free Camera',
}

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

---The value the panel shows for one parameter, and the state of its diamond.
---
---Not the value at the playhead: the value on the SELECTED KEYFRAME. That is
---what CamTool 2 edits -- its panel reads keyframes[active_kf] and nothing
---else -- and getting it wrong would have made every edit land somewhere the
---user was not looking.
---
---The diamond then says which of three situations you are in: the keyframe
---you selected carries this parameter, another keyframe of this camera does,
---or the camera never animates it at all and its own value holds across the
---whole span.
---@return number|nil value, KeyframeState
local function valueOf(camera, key, keyframeIndex)
  if camera == nil then return nil, 'none' end

  local keyframes = camera.keyframes
  local anywhere = false

  if type(keyframes) == 'table' then
    for i = 1, #keyframes do
      local kf = keyframes[i]
      local interp = type(kf) == 'table' and kf.interpolation or nil
      if interp ~= nil and type(interp[key]) == 'number' then
        if i == keyframeIndex then return interp[key], 'here' end
        anywhere = true
      end
    end
  end

  return camera[key], anywhere and 'elsewhere' or 'none'
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
  -- Session: pick a file, take the camera
  ------------------------------------------------------------------
  -- Here rather than in the diagnostic window, because needing the probe
  -- panel to start work made the probes part of the tool. They are not.
  ui.pushStyleColor(ui.StyleColor.Button, theme.strip)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, theme.stripLive)
  ui.pushStyleColor(ui.StyleColor.ButtonActive, theme.stripActive)

  if ui.arrowButton('##filePrev', ui.Direction.Left, vec2(18, 18)) then
    actions.prevFile = true
  end
  ui.sameLine(0, 2)
  if ui.button((state.fileName or 'no file') .. '##fileName',
      vec2(width - 160, 18)) then
    actions.loadFile = true
  end
  ui.sameLine(0, 2)
  if ui.arrowButton('##fileNext', ui.Direction.Right, vec2(18, 18)) then
    actions.nextFile = true
  end
  ui.sameLine(0, 6)
  if ui.button((state.held and 'Release camera' or 'Take camera') .. '##hold',
      vec2(110, 18)) then
    if state.held then actions.release = true else actions.grab = true end
  end
  ui.sameLine(0, 4)
  local depth = state.undoDepth or 0
  if ui.button(string.format('Undo (%d)##undo', depth), vec2(74, 18)) then
    actions.undo = true
  end
  ui.sameLine(0, 4)
  if ui.button(string.format('Redo (%d)##redo', state.redoDepth or 0),
      vec2(70, 18)) then
    actions.redo = true
  end
  ui.sameLine(0, 4)
  -- The star is the only thing saying there is work not on disk yet.
  if ui.button((depth > 0 and 'Save *' or 'Save') .. '##save', vec2(60, 18)) then
    actions.save = true
  end
  ui.sameLine(0, 4)
  if ui.button('Reset##reset', vec2(56, 18)) then
    actions.reset = true
  end
  ui.popStyleColor(3)

  -- Position or time. CamTool 2 puts this in the header as two icons; the
  -- two camera lists it switches between are a property of the file, and a
  -- file made in one mode is meaningless in the other.
  ui.pushStyleColor(ui.StyleColor.Button, theme.strip)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, theme.stripLive)
  ui.pushStyleColor(ui.StyleColor.ButtonActive, theme.stripActive)
  if ui.button((state.listName == 'pos' and '[position]' or ' position ')
      .. '##modePos', vec2(78, 18)) then
    actions.listName = 'pos'
  end
  ui.sameLine(0, 2)
  if ui.button((state.listName == 'time' and '[time]' or ' time ')
      .. '##modeTime', vec2(64, 18)) then
    actions.listName = 'time'
  end
  ui.popStyleColor(3)
  ui.sameLine(0, 8)

  ui.pushStyleColor(ui.StyleColor.Text, theme.absent)
  ui.text(state.status
    or (state.loadedName ~= nil
      and ('loaded: ' .. state.loadedName)
      or 'no file loaded -- click the name above to load it'))
  ui.popStyleColor()

  ------------------------------------------------------------------
  -- Header
  ------------------------------------------------------------------
  ui.pushStyleColor(ui.StyleColor.Text, theme.text)
  ui.textAligned('CAMTOOL 3', vec2(0, 0.5), vec2(width * 0.5, 20))
  ui.sameLine(0, 0)
  local metres = (state.trackPos or 0) * (state.trackLength or 0)
  ui.textAligned(string.format('%.0f m', metres), vec2(1, 0.5),
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

  -- Where the selected keyframe sits on the track.
  --
  -- This is the red band of ATR's mockup, and it turns out not to be
  -- navigation: in CamTool 2 a new keyframe is created with no position at
  -- all and this is the only thing that gives it one. Reading the source for
  -- it is what made that clear. Here a keyframe is born at the playhead
  -- instead, so the row moves one rather than placing it -- but it is the
  -- same field, and without it a keyframe could never be moved.
  if state.keyframeIndex ~= nil and state.keyframePosition ~= nil then
    local metres = state.keyframePosition * (state.trackLength or 0)
    local op, payload = parameter.draw('keyframePosition', {
      label = 'KEYFRAME ' .. tostring(state.keyframeIndex),
      text = string.format('%.2f m', metres),
      raw = string.format('%.2f', metres),
      column = theme.columns.camera,
      keyframe = 'here',
      width = math.min(240, width),
    })
    if op ~= nil then actions.keyframePosition = { op = op, amount = payload } end
    ui.newLine(2)
  end

  ------------------------------------------------------------------
  -- The three columns
  ------------------------------------------------------------------
  -- Drawn row by row through ui.columns rather than as three stacks, so the
  -- rows line up across the columns. The Camera column is the short one, and
  -- the space it leaves at the bottom is where Pit only and Specific cam are
  -- going to live.
  local colWidth = columnWidth(width)
  local longest = 0
  for _, column in ipairs(atr.COLUMNS) do
    longest = math.max(longest, #column.rows)
  end

  ui.columns(#atr.COLUMNS, false, 'atrColumns')

  for index, column in ipairs(atr.COLUMNS) do
    ui.pushStyleColor(ui.StyleColor.Text, theme.columns[column.colour].accent)
    ui.textAligned(theme.columns[column.colour].title, vec2(0, 0.5),
      vec2(colWidth, 20))
    ui.popStyleColor()
    if index < #atr.COLUMNS then ui.nextColumn() end
  end
  ui.nextColumn()

  for r = 1, longest do
    for index, column in ipairs(atr.COLUMNS) do
      local spec = column.rows[r]
      local colour = theme.columns[column.colour]

      if spec == nil then
        parameter.blank(colWidth)
      else
        local value, keyframe
        if spec.runtime then
          value, keyframe = state[spec.key], 'none'
        elseif spec.plain then
          value = state.camera ~= nil and state.camera[spec.key] or nil
          keyframe = 'none'
        else
          value, keyframe = valueOf(state.camera, spec.key, state.keyframeIndex)
        end

        -- camera_in is a track position: stored as a fraction of a lap, shown
        -- in metres, exactly as CamTool 2 shows it.
        local shown = value
        if spec.key == 'camera_in' and type(shown) == 'number' then
          shown = shown * (state.trackLength or 0)
        end

        -- A flag has no number to format, and Specific cam reads as a name.
        local text = nil
        if spec.plain then
          text = spec.unit.show(shown)
        elseif type(shown) == 'number' then
          text = spec.unit.show(shown)
        end

        local action, payload = parameter.draw(column.colour .. spec.key, {
          label = spec.label,
          text = text,
          raw = type(shown) == 'number' and string.format('%.4g', shown) or '',
          noDiamond = spec.plain == true or spec.runtime == true,
          noTyping = spec.plain == true or spec.runtime == true,
          column = colour,
          keyframe = keyframe,
          present = value ~= nil or spec.plain == true,
          width = colWidth,
          badge = spec.badge,
          badgeOn = spec.badge ~= nil and state.camera ~= nil
            and state.camera.camera_use_tracking_point == 1,
        })
        if action ~= nil then
          -- A typed value arrives in the unit the field is labelled with, so
          -- it goes back through the same conversion that displayed it. The
          -- track position also has to lose its metres.
          if action == 'commit' and type(payload) == 'number' then
            payload = spec.unit.read(payload)
            if spec.key == 'camera_in' and (state.trackLength or 0) > 0 then
              payload = payload / state.trackLength
            end
          end
          actions[spec.key] = { op = action, amount = payload }
        end
      end

      if index < #atr.COLUMNS then ui.nextColumn() end
    end
    ui.nextColumn()
  end

  ui.columns(1)

  ui.newLine(4)

  ------------------------------------------------------------------
  -- What has not found a place yet
  ------------------------------------------------------------------
  ui.pushStyleColor(ui.StyleColor.Text, theme.absent)
  ui.text('Diamond: filled = keyframed here, hollow = keyframed elsewhere '
    .. 'in this camera, empty = never keyframed.')
  ui.text('Top strip: red = the camera being edited, pale = the camera on '
    .. 'screen.')
  ui.text('Elsewhere in CamTool 2, not here yet:')
  ui.text('  ' .. table.concat(atr.MISSING, ', '))
  ui.text('Diamond toggles the keyframe; arrows step; drag a value to scrub; '
    .. 'double click it to type. Ctrl quarters the step, Shift quadruples it.')
  ui.text('Save writes over the file it came from, keeping one copy of what '
    .. 'was there before CamTool 3 first touched it.')
  ui.text('Ctrl+Z undoes, Ctrl+Y redoes. Reset asks before it clears.')
  ui.popStyleColor()

  return actions
end

return atr
