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
local trackMap = require('ui/map')
local trackBand = require('ui/band')
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
    -- The names are CamTool 2's own, which are the words already in the
    -- user's head: "steering wheel" is findable where "AC cam 0" is not.
    show = function(v) return require('core/cameramode').label(v) end,
    read = function(v) return v end,
  },
}

atr.UNITS = UNITS

---@param key string @the field in a keyframe or on the camera
---@param label string @as the mockup writes it
---@param unit table @one of UNITS
---@param help string @one sentence on what the parameter DOES, per
---  docs/ui-interactions.md. DRAFT: written from the code that implements
---  each one, awaiting ATR's corrections -- he is the one who uses them.
local function row(key, label, unit, help, badge)
  return { key = key, label = label, unit = unit, help = help, badge = badge }
end

---A row whose value is not in the camera file at all.
---
---The tracked cars are the case, and it is worth stating plainly: CamTool 2
---keeps them in Camera.__init__, changes them with set_tracked_car, and never
---writes them anywhere. They are session state, reset to car 0 every time
---Assetto Corsa starts, and no camera remembers which car it was framing.
---Making them part of a camera would be a new feature, not a port.
local function runtimeRow(key, label, unit, help)
  return { key = key, label = label, unit = unit, help = help, runtime = true }
end

---A row for something that lives on the camera and cannot be keyframed, so
---it has no diamond and nothing to type into: Pit only and Specific cam.
---Both are in docs/ui-inventory.md and neither is in ATR's mockup, which is
---what the debt list at the bottom of the panel was for.
local function plainRow(key, label, unit, help)
  return { key = key, label = label, unit = unit, help = help, plain = true }
end

---A number that lives on the camera and is never interpolated, however much
---it looks like the ones beside it. core/evaluate calls these CAMERA_LEVEL:
---they have a slot in every keyframe and the legacy reads straight past it.
---No diamond, then -- but the arrows and the keyboard work as usual.
local function levelRow(key, label, unit, help)
  return { key = key, label = label, unit = unit, help = help, cameraLevel = true }
end

atr.COLUMNS = {
  {
    colour = 'camera',
    rows = {
      -- camera_in is not a keyframed parameter: it is where the camera takes
      -- over, and it lives on the camera itself.
      row('camera_in', 'STARTING POINT', UNITS.metres,
        'Where this camera takes over, in metres from the start line. '
        .. "It holds the shot until the next camera's own starting point."),
      row('camera_focus_point', 'FOCUS POINT', UNITS.metres,
        'Focus distance for depth of field, in metres. Ignored while AF is '
        .. 'lit, which recomputes it from the tracked car every frame.', 'AF'),
      row('camera_fov', 'FOV', UNITS.plainDegrees,
        'Field of view, in degrees. Smaller is more zoomed in.'),
      row('camera_shake_strength', 'SHAKE CAMERA', UNITS.percent,
        'Shakes where the camera points. It grows with how fast the camera '
        .. 'is panning, so a still camera barely trembles.'),
      row('camera_offset_shake_strength', 'SHAKE TRACKING', UNITS.percent,
        "Wobbles the point being aimed at, along the car's path, rather than "
        .. 'the camera itself. Set per camera: it cannot be keyframed.'),
      plainRow('camera_pit', 'PIT ONLY', UNITS.flag,
        'This camera is only used while the car is in the pit lane.'),
      plainRow('camera_use_specific_cam', 'AC CAMERA', UNITS.specificCam,
        "Hands the view to one of Assetto Corsa's own cameras instead of "
        .. 'driving it. CamTool means CamTool keeps the shot.'),
    },
  },
  {
    colour = 'transform',
    rows = {
      row('loc_x', 'X', UNITS.metres,
        'Where the camera stands, along the world X axis.'),
      row('loc_y', 'Y', UNITS.metres,
        'Where the camera stands, along the world Y axis.'),
      row('loc_z', 'Z', UNITS.metres, 'How high the camera stands.'),
      row('transform_loc_strength', 'STRENGTH LO.', UNITS.percent,
        'How much of the keyframed position to use against where the camera '
        .. 'already is. NOT APPLIED YET: it is 100% on every reference '
        .. 'camera and never keyframed, so nothing has needed it.'),
      row('rot_x', 'PITCH', UNITS.degrees, 'Tilt up and down.'),
      row('rot_y', 'ROLL', UNITS.degrees, 'Roll: the horizon leaning over.'),
      row('rot_z', 'HEADING', UNITS.degrees, 'Which way the camera faces.'),
      row('transform_rot_strength', 'STRENGTH RO.', UNITS.percent,
        'How much of the keyframed angles to use against where the camera is '
        .. 'already pointing. At 0% it keeps its own aim, at 100% it takes '
        .. 'the keyframed one.'),
    },
  },
  {
    colour = 'tracking',
    rows = {
      runtimeRow('trackedCarA', 'ACTIVE CAR', UNITS.car,
        'The car being followed. Session state: no camera file remembers it, '
        .. 'and it goes back to car 0 every time Assetto Corsa starts.'),
      row('tracking_mix', 'MIX', UNITS.percent,
        'Blends the aim between the active car and the extra one. NOT APPLIED '
        .. 'TO THE AIM YET in CamTool 3 -- only autofocus reads it, to focus '
        .. 'on whichever car is nearer.'),
      runtimeRow('trackedCarB', 'EXTRA CAR', UNITS.car,
        'The second car, the one MIX blends with the active one.'),
      row('tracking_offset', 'OFF TRACKING', UNITS.ratio,
        'Aims ahead of the car or behind it. Negative leads, positive lags. '
        .. 'Scaled by replay speed, so a slowed replay keeps the same lead.'),
      row('tracking_offset_pitch', 'OFFSET PITCH', UNITS.degrees,
        'Nudges the aim up or down by a fixed angle, after the tracking.'),
      row('tracking_offset_heading', 'OFF HEADING', UNITS.degrees,
        'Nudges the aim left or right by a fixed angle, after the tracking.'),
      row('tracking_strength_pitch', 'STR PITCH', UNITS.percent,
        'How much the tracking drives the tilt. At 0% the camera does not '
        .. 'follow the car up or down.'),
      row('tracking_strength_heading', 'STR HEADING', UNITS.percent,
        'How much the tracking drives which way the camera faces. At 0% it '
        .. 'does not turn towards the car at all.'),
    },
  },
}

---The Spline tab of CamTool 2, which the mockup leaves out entirely. These
---shape how a camera follows the path recorded for it, and without them a
---camera with a path can only be played, never adjusted.
---
---The three affect_ angles are camera level: they sit in every keyframe and
---the legacy never interpolates them, which core/evaluate records and
---docs/legacy.md explains.
atr.SPLINE = {
  row('spline_speed', 'SPEED', UNITS.ratio,
    'How fast the camera travels its recorded path against the car. 2 means '
    .. 'it covers the path twice as fast.'),
  row('spline_affect_loc_xy', 'AFFECT XY', UNITS.percent,
    'How much the recorded path drives the camera horizontally.'),
  row('spline_affect_loc_z', 'AFFECT Z', UNITS.percent,
    'How much the recorded path drives the height of the camera.'),
  levelRow('spline_affect_pitch', 'AFFECT PITCH', UNITS.percent,
    'How much the recorded path drives the tilt. Set per camera, never '
    .. 'keyframed.'),
  levelRow('spline_affect_roll', 'AFFECT ROLL', UNITS.percent,
    'How much the recorded path drives the roll. Set per camera, never '
    .. 'keyframed.'),
  levelRow('spline_affect_heading', 'AFFECT HEADING', UNITS.percent,
    'How much the recorded path drives which way the camera faces. Set per '
    .. 'camera, never keyframed.'),
  row('spline_offset_loc_x', 'OFFSET X', UNITS.metres,
    'Steps the camera sideways off the recorded path, across its direction '
    .. 'of travel.'),
  row('spline_offset_loc_z', 'OFFSET Z', UNITS.metres,
    'Raises or lowers the camera off the recorded path.'),
  row('spline_offset_pitch', 'OFFSET PITCH', UNITS.degrees,
    'Tilts the camera away from the angle the path recorded.'),
  row('spline_offset_heading', 'OFFSET HEADING', UNITS.degrees,
    'Turns the camera away from the direction the path recorded.'),
  row('spline_offset_spline', 'OFFSET ALONG', UNITS.ratio,
    'Reads the recorded path earlier or later than the car, so the camera '
    .. 'runs ahead of it or behind it along the same route.'),
}

---The legend the ? button shows. Everything the panel means, in one place,
---which docs/ui-interactions.md asks for -- and the only place help is
---exhaustive. Tooltips answer about one field; this answers about the panel.
atr.LEGEND = {
  'Diamond   filled = keyframed here, hollow = keyframed elsewhere in this ' ..
    'camera, empty = never keyframed. A tinted field is animated.',
  'Camera strip   red = the camera being edited, pale = the camera on screen.',
  'Values   arrows step, drag scrubs, double click types. Right click during ' ..
    'a drag abandons it; click away to abandon a typed one. Ctrl quarters ' ..
    'the step, Shift quadruples it. The wheel never edits, and Escape is the ' ..
    "game's own key for leaving the replay.",
  'Ribbon   the lap from the start line to the finish, tinted by camera, ' ..
    "with this camera's keyframes above it and the car as a white line.",
  'Ribbon   click to select that camera AND bring the car there. ' ..
    'Shift+click selects without moving the replay.',
  'Ribbon   drag the red handle to move where a camera takes over. ' ..
    'Double click a segment to name it. Right click for more.',
  'Map   the same cameras on the circuit. Click and Shift+click do what they ' ..
    'do on the ribbon; the handle drags there too.',
  'Undo   Ctrl+Z and Ctrl+Y, or the buttons. A whole drag is one entry, and ' ..
    'moving the replay is not an edit at all.',
  'Save   writes over the file it came from, keeping one copy of what was ' ..
    'there before CamTool 3 first touched it. Reset asks first.',
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

---Decide where a row of buttons has to break.
---
---Pure arithmetic, so the one thing that actually goes wrong here -- a button
---landing past the edge of the window where nothing can click it -- is
---something a test can catch. The panel is resizable and this row has grown
---twice already.
---@param items table[] @{ width = , gap = } each, in order
---@param available number @the width the row has
---@param startX number|nil @how much of the first line is already taken
---@return boolean[] @whether each item begins a new line
function atr.wrapRow(items, available, startX)
  local breaks = {}
  local x = startX or 0

  for i, item in ipairs(items) do
    local gap = (i == 1 and startX ~= nil and startX > 0) and (item.gap or 3)
      or (i == 1 and 0 or item.gap or 3)

    if x + gap + item.width > available and (i > 1 or x > 0) then
      breaks[i] = true
      x = item.width
    else
      breaks[i] = false
      x = x + gap + item.width
    end
  end

  return breaks
end

---Draw one parameter, whichever section it belongs to.
---
---Every kind of row goes through here: keyframable, camera level, the two
---plain fields and the runtime readouts. One place, so a gesture or a unit
---added later reaches all of them.
local function drawCell(spec, colour, colWidth, state, actions, section)
  local value, keyframe

  if spec.runtime then
    value, keyframe = state[spec.key], 'none'
  elseif spec.plain or spec.cameraLevel then
    value = state.camera ~= nil and state.camera[spec.key] or nil
    keyframe = 'none'
  else
    value, keyframe = valueOf(state.camera, spec.key, state.keyframeIndex)
  end

  -- camera_in is a track position: stored as a fraction of a lap, shown in
  -- metres, exactly as CamTool 2 shows it.
  local shown = value
  if spec.key == 'camera_in' and type(shown) == 'number' then
    shown = shown * (state.trackLength or 0)
  end

  -- A flag has no number to format, and Specific cam reads as a name.
  local text = nil
  if spec.plain or type(shown) == 'number' then
    text = spec.unit.show(shown)
  end

  local action, payload = parameter.draw(section .. spec.key, {
    label = spec.label,
    text = text,
    -- The sentence, and what kind of row this is so the gestures offered
    -- match what the row actually allows. Both were missing: the help was
    -- written into atr.COLUMNS and stopped here, so not one tooltip ever
    -- appeared. Each half was tested and the join between them was not.
    help = spec.help,
    runtime = spec.runtime,
    raw = type(shown) == 'number' and string.format('%.4g', shown) or '',
    noDiamond = spec.plain == true or spec.runtime == true
      or spec.cameraLevel == true,
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
    -- A typed value arrives in the unit the field is labelled with, so it
    -- goes back through the same conversion that displayed it. The track
    -- position also has to lose its metres.
    if action == 'commit' and type(payload) == 'number' then
      payload = spec.unit.read(payload)
      if spec.key == 'camera_in' and (state.trackLength or 0) > 0 then
        payload = payload / state.trackLength
      end
    end
    actions[spec.key] = { op = action, amount = payload }
  end
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

  -- The tooltip delay needs a clock, and CSP does not offer ImGui's.
  parameter.beginFrame(state.dt)

  ------------------------------------------------------------------
  -- Session: pick a file, take the camera
  ------------------------------------------------------------------
  -- Here rather than in the diagnostic window, because needing the probe
  -- panel to start work made the probes part of the tool. They are not.
  ui.pushStyleColor(ui.StyleColor.Button, theme.strip)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, theme.stripLive)
  ui.pushStyleColor(ui.StyleColor.ButtonActive, theme.stripActive)

  -- The name takes what the others leave, worked out from their own widths
  -- rather than from a number that has to be kept in step with them. It was
  -- a fixed 160, the row grew past it, and four buttons ended up off the
  -- edge of the window where nothing could click them.
  local HOLD_WIDTH = 110
  local arrow = theme.barHeight
  local nameWidth = math.max(60,
    width - arrow - 2 - 2 - arrow - 6 - HOLD_WIDTH)

  if ui.arrowButton('##filePrev', ui.Direction.Left, vec2(arrow, arrow)) then
    actions.prevFile = true
  end
  ui.sameLine(0, 2)
  if ui.button((state.fileName or 'no file') .. '###fileName',
      vec2(nameWidth, theme.barHeight)) then
    actions.loadFile = true
  end
  ui.sameLine(0, 2)
  if ui.arrowButton('##fileNext', ui.Direction.Right, vec2(arrow, arrow)) then
    actions.nextFile = true
  end
  ui.sameLine(0, 6)
  if ui.button((state.held and 'Release camera' or 'Take camera') .. '###hold',
      vec2(HOLD_WIDTH, theme.barHeight)) then
    if state.held then actions.release = true else actions.grab = true end
  end
  ui.popStyleColor(3)

  ui.pushStyleColor(ui.StyleColor.Text, theme.absent)
  ui.text(state.status
    or (state.loadedName ~= nil
      and ('loaded: ' .. state.loadedName)
      or 'no file loaded -- click the name above to load it'))
  ui.popStyleColor()

  ------------------------------------------------------------------
  -- Header
  ------------------------------------------------------------------
  -- Only the car's position. The name of the app is already on the window
  -- title bar, and saying it twice used a line that the panel would rather
  -- give to the cameras.
  ui.pushStyleColor(ui.StyleColor.Text, theme.text)
  local metres = (state.trackPos or 0) * (state.trackLength or 0)
  ui.textAligned(string.format('%.0f m', metres), vec2(1, 0.5), vec2(width, 20))
  ui.popStyleColor()

  ------------------------------------------------------------------
  -- The camera strip
  ------------------------------------------------------------------
  -- One button per camera, the live one in red. CamTool 2 only offers
  -- previous and next, and ATR's mockup replaces that with the whole set at
  -- a glance -- on a 48-camera file that is the difference between a click
  -- and forty.
  -- The two numbered strips that used to sit here are gone. They gave every
  -- camera a cell, twenty to a row, and the ribbon below does the same job at
  -- any size -- which is issue #6. They were put behind a temporary switch for
  -- a session of real work first, and were not missed.
  --
  -- Where what they carried went: selecting a camera or a keyframe is a click
  -- on the ribbon, adding and removing a camera is its right-click menu, and
  -- the keyframe pair moved into the row of actions below.
  local stripWidth = 0

  -- The actions sit to the right of the keyframe strip, which is where the
  -- room is: a camera rarely has twenty keyframes, and these were previously
  -- on the file line, where they ran off the end of the window and could not
  -- be clicked at all.
  --
  -- They WRAP now. Beside a long keyframe strip, or in a narrow window, the
  -- row used to run past the edge and the last buttons became unclickable --
  -- the same failure as before, moved one line down. Where it breaks is
  -- arithmetic, in atr.wrapRow, so a test catches it rather than an eye.
  ui.pushStyleColor(ui.StyleColor.Button, theme.strip)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, theme.stripLive)
  ui.pushStyleColor(ui.StyleColor.ButtonActive, theme.stripActive)

  local depth = state.undoDepth or 0
  local legacy = state.mode ~= 'fixed'

  -- Square brackets mean "on" throughout this row, for the map, the help, the
  -- list and the maths alike.
  local items = {
    { id = 'undo', width = 74, gap = 12,
      label = string.format('Undo (%d)###undo', depth) },
    { id = 'redo', width = 70,
      label = string.format('Redo (%d)###redo', state.redoDepth or 0) },
    -- The star is the only thing saying there is work not on disk yet.
    { id = 'save', width = 60,
      label = (depth > 0 and 'Save *' or 'Save') .. '###save' },
    -- Armed, the button says so itself. It used to warn only in the status
    -- line at the top of the panel, far from the thing that was clicked, so a
    -- first click read as nothing happening.
    { id = 'reset', width = 56,
      label = (state.confirmReset and 'Reset?' or 'Reset') .. '###reset' },
    { id = 'toggleMap', width = 52,
      label = (state.showMap and '[map]' or ' map ') .. '###showMap' },
    { id = 'toggleHelp', width = 30,
      label = (state.showHelp and '[?]' or ' ? ') .. '###showHelp' },
    -- The keyframe pair, which the strip used to carry. A keyframe is born at
    -- the playhead and belongs to the selected camera, so neither button
    -- needs somewhere to point at -- unlike a camera, which is added where
    -- the right click landed on the ribbon.
    { id = 'addKeyframe', width = 34, gap = 10, label = '+kf##kfadd' },
    { id = 'removeKeyframe', width = 34, label = '-kf##kfdel' },
    -- Position or time, and which curve maths the file gets. The second is
    -- not a preference: a CamTool 2 file is loaded as legacy and has to
    -- behave as CamTool 2 did, or footage already cut would change. Shown so
    -- it is never a surprise, switchable because a file can be moved across
    -- on purpose.
    { id = 'posList', width = 74, gap = 10,
      label = (state.listName == 'pos' and '[position]' or ' position ')
        .. '###modePos' },
    { id = 'timeList', width = 58,
      label = (state.listName == 'time' and '[time]' or ' time ')
        .. '###modeTime' },
  }

  if state.loadedName ~= nil then
    items[#items + 1] = { id = 'maths', width = 96, gap = 10,
      label = (legacy and 'maths: legacy' or 'maths: fixed') .. '###mode' }
  end

  local breaks = atr.wrapRow(items, width, stripWidth)
  local clicked = {}

  for i, item in ipairs(items) do
    if breaks[i] or (i == 1 and stripWidth <= 0) then
      -- The second half of that matters: with the strips hidden there is no
      -- keyframe strip beside this row, so there is no line to continue. The
      -- first version carried on regardless and put the first button after
      -- the full-width header -- the whole row landed off the right edge of
      -- the window, where nothing could click it, and the switch that had
      -- hidden the strips went with it.
      ui.newLine(2)
    else
      ui.sameLine(0, item.gap or 3)
    end
    if ui.button(item.label, vec2(item.width, theme.stripHeight)) then
      clicked[item.id] = true
    end
  end

  if clicked.undo then actions.undo = true end
  if clicked.redo then actions.redo = true end
  if clicked.save then actions.save = true end
  if clicked.reset then actions.reset = true end
  if clicked.toggleMap then actions.toggleMap = true end
  if clicked.toggleHelp then actions.toggleHelp = true end
  if clicked.addKeyframe then actions.addKeyframe = true end
  if clicked.removeKeyframe then actions.removeKeyframe = true end
  if clicked.posList then actions.listName = 'pos' end
  if clicked.timeList then actions.listName = 'time' end
  if clicked.maths then actions.mode = legacy and 'fixed' or 'legacy' end

  ui.popStyleColor(3)
  ui.newLine(2)

  ------------------------------------------------------------------
  -- The track band
  ------------------------------------------------------------------
  -- The lap as a ribbon: the same ownership the map draws, projected onto a
  -- line. It answers a different question -- how long each shot lasts, and
  -- where the relays fall in the lap -- and it scales where the numbered
  -- strip does not, which is issue #6.
  --
  -- The strips above are still there. What this replaces, and whether it
  -- replaces them at all, is ATR's call in front of a replay, not something
  -- to decide by deleting them first.
  ui.newLine(2)
  local band = trackBand.draw(state, width)
  if band.camera ~= nil then actions.selectCamera = band.camera end
  if band.keyframe ~= nil then actions.selectKeyframe = band.keyframe end
  if band.move ~= nil then actions.moveCameraIn = band.move end
  if band.rename ~= nil then actions.renameCamera = band.rename end
  if band.seekTo ~= nil then actions.seekTo = band.seekTo end
  if band.hint ~= nil then actions.hint = band.hint end
  if band.addCamera ~= nil then actions.addCameraAt = band.addCamera end
  if band.removeCamera ~= nil then actions.removeCameraAt = band.removeCamera end
  ui.newLine(2)

  ------------------------------------------------------------------
  -- The map
  ------------------------------------------------------------------
  -- The set seen from above: which camera covers which stretch of the lap.
  -- The strip above says the same thing in list order; this says it in the
  -- order you actually drive, which is the one the shot is cut in.
  --
  -- Placement is provisional, and only ATR can say whether the trade against
  -- the parameters is worth it in front of a replay. The map takes what its
  -- shape needs up to a ceiling rather than a fixed band, so a circuit that
  -- draws wide does not leave an empty strip under it.
  --
  -- The ceiling is the smaller of what the map is ever allowed and a share of
  -- this window. Without the second, the default 460 px panel would hand two
  -- thirds of itself to the map and push the parameters off the bottom, while
  -- a window dragged out wide gets a map worth having.
  if state.showMap ~= false then
    local ceiling = math.min(theme.mapHeightMax,
      math.max(theme.mapHeightMin,
        math.floor((ui.windowHeight() or 0) * theme.mapShareOfWindow)))
    local picked, mapMove, mapSeek, mapHint = trackMap.draw(state, width, ceiling)
    if picked ~= nil then actions.selectCamera = picked end
    if mapMove ~= nil then actions.moveCameraIn = mapMove end
    if mapSeek ~= nil then actions.seekTo = mapSeek end
    if mapHint ~= nil then actions.hint = mapHint end
  end
  ui.newLine(2)

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
        drawCell(spec, colour, colWidth, state, actions, column.colour)
      end

      if index < #atr.COLUMNS then ui.nextColumn() end
    end
    ui.nextColumn()
  end

  ui.columns(1)

  ui.newLine(4)

  ------------------------------------------------------------------
  -- The recorded path
  ------------------------------------------------------------------
  -- CamTool 2 keeps these behind a tab of their own. They only mean anything
  -- once a path has been recorded for the camera, so the section says when
  -- there is none rather than showing eleven numbers that do nothing.
  local path = state.camera ~= nil and state.camera.spline or nil
  local points = type(path) == 'table' and type(path.the_x) == 'table'
    and #path.the_x or 0

  ui.pushStyleColor(ui.StyleColor.Text, theme.columns.camera.accent)
  ui.textAligned(points > 0
    and string.format('SPLINE -- %d points recorded', points)
    or 'SPLINE -- nothing recorded for this camera', vec2(0, 0.5),
    vec2(width, 20))
  ui.popStyleColor()

  if points > 0 then
    local perRow = 3
    ui.columns(perRow, false, 'atrSpline')
    for _, spec in ipairs(atr.SPLINE) do
      drawCell(spec, theme.columns.camera, colWidth, state, actions, 'spline')
      ui.nextColumn()
    end
    ui.columns(1)
    ui.newLine(4)
  end

  ------------------------------------------------------------------
  -- Help: one line always, everything on request
  ------------------------------------------------------------------
  -- What used to sit here was a wall of text, and a list of what CamTool 2
  -- has that this does not. Both are gone: the list belongs in the repo, not
  -- in the window, and the wall was there whether or not anyone wanted it.
  --
  -- The status line is the one that makes the panel learnable, precisely
  -- because nobody has to know it is there. A tooltip has to be gone looking
  -- for; this is simply on screen.
  parameter.endFrame()

  if state.showHelp then
    ui.pushStyleColor(ui.StyleColor.Text, theme.absent)
    for _, line in ipairs(atr.LEGEND) do
      ui.text(line)
    end
    ui.popStyleColor()
  else
    -- Whatever the pointer is over: a parameter, or the ribbon, which has
    -- gestures of its own worth saying out loud.
    local label, help = parameter.hovered()
    ui.pushStyleColor(ui.StyleColor.Text, theme.statusLine)
    ui.text(label ~= nil and (label .. '  --  ' .. (help or ''))
      or actions.hint
      or 'Hover a value to read what it does.')
    ui.popStyleColor()
  end

  return actions
end

return atr
