--[[
  The ATR panel.

  Two kinds of check. The first is that the panel's idea of a camera matches a
  real camera: every parameter it offers to show has to be one that exists,
  under the name the files actually use. That test was written after the panel
  shipped two invented fields -- camera_tracked_car_a and _b, which no camera
  file has ever contained, because CamTool 2 keeps the tracked car in memory
  and never saves it. A label on screen with nothing behind it is the quietest
  way to get a UI wrong.

  The second is the smoke test that the rest of this suite already relies on:
  draw it against fake CSP globals and see that it survives. Cheap here, a
  game launch there.
]]

local runner = require('tests/runner')
local fakes = require('tests/fakes/csp')
local trackAdapter = require('adapters/track')
local trackMap = require('ui/map')
local theme = require('ui/theme')
local atr = require('ui/atr')
local parameter = require('ui/parameter')
local evaluate = require('core/evaluate')
local dataModule = require('core/data')
local rawFile = require('tests/fixtures/camera_file_seb')

local test, eq = runner.test, runner.eq

test('every parameter the panel shows is one a camera really has', function()
  local doc = dataModule.load(rawFile)

  -- Every field any camera of the file carries. One camera is not enough:
  -- camera_use_specific_cam is optional and only eleven of the 589 reference
  -- cameras set it, so checking a single one would call it invented.
  local known = {}
  for _, cam in ipairs(doc.pos) do
    for field in pairs(cam) do known[field] = true end
  end
  eq(known.camera_in, true, 'the reference file looks wrong')

  for _, column in ipairs(atr.COLUMNS) do
    for _, spec in ipairs(column.rows) do
      if not spec.runtime then
        local known = evaluate.interpolatorFor(spec.key) ~= nil
          or known[spec.key] == true
          or spec.key == 'camera_use_specific_cam'
        eq(known, true, string.format(
          '%s (%s) is neither an interpolated parameter nor a field of a real '
            .. 'camera -- check the name against a data file',
          spec.key, spec.label))
      end
    end
  end
end)

test('the panel labels are unique and the columns are the three tabs', function()
  local seen = {}
  local colours = {}

  for _, column in ipairs(atr.COLUMNS) do
    colours[#colours + 1] = column.colour
    for _, spec in ipairs(column.rows) do
      eq(type(spec.label), 'string')
      eq(#spec.label > 0, true)
      eq(seen[spec.label], nil, 'two rows are labelled ' .. spec.label)
      seen[spec.label] = true
      eq(type(spec.unit), 'table', spec.label .. ' has no unit')
      eq(type(spec.unit.show), 'function', spec.label .. ' cannot be shown')
      eq(type(spec.unit.read), 'function', spec.label .. ' cannot be typed')
    end
  end

  eq(#colours, 3)
  eq(colours[1], 'camera')
  eq(colours[2], 'transform')
  eq(colours[3], 'tracking')
end)

test('the debt list is not empty until everything has a place', function()
  -- The mockup leaves parts of CamTool 2 out. While that is still true the
  -- panel says so on screen, and this is the reminder that the list is meant
  -- to shrink to nothing rather than be deleted.
  eq(#atr.MISSING > 0, true)
end)

test('a parameter row draws and reports which part was clicked', function()
  local handle = fakes.install({ clicks = { ['##testdec'] = true } })

  local action = parameter.draw('test', {
    label = 'FOCUS POINT', text = '69.40 m', width = 120,
  })
  eq(action, 'decrement')

  handle.restoreIo()
end)

test('a keyframed row and an absent one both draw', function()
  local handle = fakes.install({})

  eq(parameter.draw('kf', {
    label = 'FOV', text = '8.70 deg', width = 120, keyframed = true,
  }), nil)

  -- No value at all: the row still has to draw, greyed out, rather than pass
  -- nil to string.format and take the whole window down with it.
  eq(parameter.draw('none', {
    label = 'FOV', text = nil, width = 120, present = false,
  }), nil)

  handle.restoreIo()
end)

test('the panel draws with a real camera, and with nothing at all', function()
  local handle = fakes.install({})
  local doc = dataModule.load(rawFile)

  local ok, err = pcall(atr.draw, {
    doc = doc,
    camera = doc.pos[2],
    cameraIndex = 2,
    cameraCount = #doc.pos,
    trackPos = 0.02,
    trackLength = 5802,
    trackedCarA = 0,
  })
  eq(ok, true, ok and '' or ('the panel raised: ' .. tostring(err)))

  -- Before a file is loaded there is no camera, no count and no position.
  ok, err = pcall(atr.draw, {})
  eq(ok, true, ok and '' or ('the empty panel raised: ' .. tostring(err)))

  handle.restoreIo()
end)

test('the ATR window exists and survives many frames', function()
  local handle = fakes.install({
    cameraFile = rawFile,
    splinePosition = 0.02,
    clicks = {
      ['Find CamTool 2 files'] = true,
      ['Load this file'] = true,
      ['Grab camera'] = true,
      ['Play CamTool 2 file (12)'] = true,
    },
  })

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  eq(type(_G.script.windowAtr), 'function', 'the manifest declares windowAtr')

  for _ = 1, 30 do
    local ok, err = pcall(_G.script.windowMain, 0.016)
    if not ok then error('windowMain raised: ' .. tostring(err), 2) end
    ok, err = pcall(_G.script.update, 0.016)
    if not ok then error('update raised: ' .. tostring(err), 2) end
    ok, err = pcall(_G.script.windowAtr, 0.016)
    if not ok then error('windowAtr raised: ' .. tostring(err), 2) end
  end

  handle.restoreIo()
end)

test('the ATR window draws before any file is loaded', function()
  -- The order the windows are opened in is the user's, not ours.
  local handle = fakes.install({ cameraFile = rawFile })

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  local ok, err = pcall(_G.script.windowAtr, 0.016)
  eq(ok, true, ok and '' or ('windowAtr raised with no file: ' .. tostring(err)))

  handle.restoreIo()
end)

test('the panel shows the selected keyframe, not the playhead', function()
  -- CamTool 2's panel reads keyframes[active_kf] and nothing else. Getting
  -- this wrong would put every edit somewhere the user is not looking.
  local handle = fakes.install({})

  local camera = {
    camera_in = 0.1,
    tracking_mix = 0.25,
    keyframes = {
      { keyframe = 0.10, interpolation = { tracking_mix = 0.5 } },
      { keyframe = 0.90, interpolation = {} },
    },
  }

  -- Keyframe 1 carries tracking_mix, keyframe 2 does not, and the camera has
  -- its own value. The panel has to show three different things.
  local ok = pcall(atr.draw, {
    camera = camera, cameraIndex = 1, cameraCount = 1,
    keyframeIndex = 1, keyframeCount = 2, trackPos = 0.5, trackLength = 1000,
  })
  eq(ok, true)

  ok = pcall(atr.draw, {
    camera = camera, cameraIndex = 1, cameraCount = 1,
    keyframeIndex = 2, keyframeCount = 2, trackPos = 0.5, trackLength = 1000,
  })
  eq(ok, true)

  -- And with no keyframe selected at all, which is a camera that animates
  -- nothing rather than an error.
  ok = pcall(atr.draw, {
    camera = camera, cameraIndex = 1, cameraCount = 1,
    keyframeCount = 0, trackPos = 0.5, trackLength = 1000,
  })
  eq(ok, true)

  handle.restoreIo()
end)

test('picking a camera in the panel does not move the live one', function()
  local handle = fakes.install({
    cameraFile = rawFile,
    splinePosition = 0.02,
    clicks = {
      ['Find CamTool 2 files'] = true, ['Load this file'] = true,
      ['Grab camera'] = true, ['Play CamTool 2 file (12)'] = true,
      -- The fourth camera in the strip.
      ['4##cam4'] = true,
    },
  })

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  for _ = 1, 5 do
    _G.script.windowMain(0.016)
    _G.script.update(0.016)
    local ok, err = pcall(_G.script.windowAtr, 0.016)
    if not ok then error('windowAtr raised: ' .. tostring(err), 2) end
  end

  -- The car still drives which camera is live; the panel selection is only
  -- about what is being looked at.
  eq(handle.grabbed, true)

  handle.restoreIo()
end)

test('the diamond tells the three keyframe states apart', function()
  -- Empty, hollow, filled. Getting these confused is what made CamTool 2's
  -- red ambiguous: it could not say "animated, but not here".
  local handle = fakes.install({})

  for _, state in ipairs({ 'none', 'elsewhere', 'here' }) do
    eq(parameter.draw('d' .. state, {
      label = 'FOV', text = '8.70 deg', width = 140, keyframe = state,
    }), nil)
  end

  handle.restoreIo()
end)

test('the session bar can load a file and take the camera', function()
  -- Theo's ask: starting work must not require opening the probe panel.
  local handle = fakes.install({
    cameraFile = rawFile,
    splinePosition = 0.02,
    clicks = {
      ['no file##fileName'] = true,
      -- The list marks where a file came from, so the label carries it.
      ['fake_track_-cameras.json   [CamTool 2]##fileName'] = true,
      ['Take camera##hold'] = true,
    },
  })

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  -- Only the ATR window is ever drawn here: no probe panel, no diagnostic
  -- buttons. It has to be enough on its own.
  for _ = 1, 6 do
    local ok, err = pcall(_G.script.windowAtr, 0.016)
    if not ok then error('windowAtr raised: ' .. tostring(err), 2) end
    _G.script.update(0.016)
  end

  eq(handle.grabbed, true, 'the camera was never taken from the ATR panel')

  handle.restoreIo()
end)

test('the panel reports an arrow press as an action', function()
  -- The link the test above cannot see directly: the panel turns a click on
  -- an arrow into an action keyed by parameter, which is what the app feeds
  -- to core/edit.
  local handle = fakes.install({
    clicks = { ['##trackingtracking_mixinc'] = true },
  })
  local doc = dataModule.load(rawFile)

  local actions = atr.draw({
    camera = doc.pos[2], cameraIndex = 2, cameraCount = #doc.pos,
    keyframeIndex = 1, keyframeCount = #(doc.pos[2].keyframes or {}),
    trackPos = 0.02, trackLength = 5802,
  })

  eq(actions.tracking_mix.op, 'increment')

  handle.restoreIo()
end)

test('the panel reports a diamond click, and the edit round trips', function()
  local edit = require('core/edit')
  local handle = fakes.install({
    clicks = { ['##transformloc_xkf'] = true },
  })
  local doc = dataModule.load(rawFile)
  local camera = doc.pos[2]

  local actions = atr.draw({
    camera = camera, cameraIndex = 2, cameraCount = #doc.pos,
    keyframeIndex = 1, keyframeCount = #(camera.keyframes or {}),
    trackPos = 0.02, trackLength = 5802,
  })
  eq(actions.loc_x.op, 'keyframe')

  local before = camera.keyframes[1].interpolation.loc_x
  local change = edit.apply({
    camera = camera, keyframeIndex = 1, key = 'loc_x',
    op = 'toggleKeyframe', live = 12.5,
  })
  eq(change ~= nil, true)
  edit.revert(change)
  eq(camera.keyframes[1].interpolation.loc_x, before, 'undo put it back')

  handle.restoreIo()
end)

--------------------------------------------------------------------------------
-- The two gestures that are not a click
--------------------------------------------------------------------------------

test('dragging a value reports how many steps it moved', function()
  -- Sixteen pixels at eight pixels a step is two steps, and the sign follows
  -- the direction of travel. core/edit then applies the parameter's own step
  -- and the modifiers, so a drag and an arrow can never disagree.
  local handle = fakes.install({
    itemActive = true, mouseDragDelta = { x = 16, y = 0 },
  })
  parameter.cancelEditing()

  local action, amount = parameter.draw('drag1', {
    label = 'MIX', text = '50%', width = 140,
  })
  eq(action, 'drag')
  runner.near(amount, 2, 1e-12)

  handle.restoreIo()
end)

test('dragging leftwards moves the other way', function()
  local handle = fakes.install({
    itemActive = true, mouseDragDelta = { x = -8, y = 0 },
  })
  parameter.cancelEditing()

  local _, amount = parameter.draw('drag2', { label = 'MIX', text = '50%', width = 140 })
  runner.near(amount, -1, 1e-12)

  handle.restoreIo()
end)

test('a value with nothing behind it cannot be dragged', function()
  local handle = fakes.install({
    itemActive = true, mouseDragDelta = { x = 40, y = 0 },
  })
  parameter.cancelEditing()

  local action = parameter.draw('drag3', {
    label = 'FOCUS POINT', text = nil, present = false, width = 140,
  })
  eq(action, nil, 'there is no value to move yet')

  handle.restoreIo()
end)

test('a double click opens the field, and Enter commits the number', function()
  local handle = fakes.install({ itemHovered = true, mouseDoubleClicked = true })
  parameter.cancelEditing()

  -- First draw: the double click lands, and the field opens for next frame.
  local action = parameter.draw('type1', {
    label = 'FOV', text = '29.43 deg', raw = '29.43', width = 140,
  })
  eq(action, nil, 'opening the field is not itself an edit')
  handle.restoreIo()

  -- Next frame, with something typed and Enter pressed.
  handle = fakes.install({ typed = '45', enterPressed = true })
  local commit, value = parameter.draw('type1', {
    label = 'FOV', text = '29.43 deg', raw = '29.43', width = 140,
  })
  eq(commit, 'commit')
  runner.near(value, 45, 1e-12)

  handle.restoreIo()
  parameter.cancelEditing()
end)

test('a number typed in degrees is stored in radians', function()
  -- The panel shows degrees and the file holds radians, so the conversion
  -- that displays a value has to run backwards on the way in. Getting this
  -- wrong would put 45 radians into a camera and point it at the sky.
  local degrees = atr.UNITS.degrees
  runner.near(degrees.read(45), math.pi / 4, 1e-12)
  runner.near(degrees.read(tonumber(degrees.show(math.pi / 3):match('[-%d.]+'))),
    math.pi / 3, 1e-4, 'there and back')

  local percent = atr.UNITS.percent
  runner.near(percent.read(50), 0.5, 1e-12)
  runner.near(percent.read(tonumber(percent.show(0.25):match('[-%d.]+'))),
    0.25, 1e-9, 'there and back')

  -- Metres and plain ratios are stored as shown.
  runner.near(atr.UNITS.metres.read(12.5), 12.5, 1e-12)
  runner.near(atr.UNITS.ratio.read(-0.1), -0.1, 1e-12)
end)

test('every unit can go both ways', function()
  for name, unit in pairs(atr.UNITS) do
    eq(type(unit.show), 'function', name)
    eq(type(unit.read), 'function', name)
  end
end)

test('the strips offer add and remove, and the keyframe row its position', function()
  local handle = fakes.install({ clicks = { ['+##kfadd'] = true } })
  local doc = dataModule.load(rawFile)

  local actions = atr.draw({
    camera = doc.pos[2], cameraIndex = 2, cameraCount = #doc.pos,
    keyframeIndex = 1, keyframeCount = #(doc.pos[2].keyframes or {}),
    keyframePosition = doc.pos[2].keyframes[1].keyframe,
    trackPos = 0.02, trackLength = 5802,
  })
  eq(actions.addKeyframe, true)

  handle.restoreIo()
end)

test('the keyframe position row only appears with a keyframe selected', function()
  local handle = fakes.install({ clicks = { ['##keyframePositioninc'] = true } })
  local doc = dataModule.load(rawFile)

  -- With one selected, the row is there and its arrow reports.
  local actions = atr.draw({
    camera = doc.pos[2], cameraIndex = 2, cameraCount = #doc.pos,
    keyframeIndex = 1, keyframeCount = 2,
    keyframePosition = 0.25,
    trackPos = 0.02, trackLength = 5802,
  })
  eq(actions.keyframePosition.op, 'increment')

  -- With none, there is nothing to move and no row to move it with.
  actions = atr.draw({
    camera = doc.pos[2], cameraIndex = 2, cameraCount = #doc.pos,
    keyframeCount = 0, trackPos = 0.02, trackLength = 5802,
  })
  eq(actions.keyframePosition, nil)

  handle.restoreIo()
end)

test('the panel can save the file it loaded, and says so', function()
  local storage = require('adapters/storage')
  local handle = fakes.install({
    cameraFile = rawFile,
    splinePosition = 0.02,
    clicks = {
      ['no file##fileName'] = true,
      -- The list marks where a file came from, so the label carries it.
      ['fake_track_-cameras.json   [CamTool 2]##fileName'] = true,
      ['Save##save'] = true,
      ['Save *##save'] = true,
    },
  })

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  for _ = 1, 4 do
    local ok, err = pcall(_G.script.windowAtr, 0.016)
    if not ok then error('windowAtr raised: ' .. tostring(err), 2) end
  end

  -- Written into CamTool 3's folder, never over the CamTool 2 original.
  local path = storage.CAMTOOL3_DATA_DIR .. '/fake_track_-cameras.json'
  eq(type(handle.written[path]), 'string', 'the panel never wrote the file')
  eq(handle.written[storage.CAMTOOL2_DATA_DIR .. '/fake_track_-cameras.json'],
    nil, 'the CamTool 2 file must not be touched')
  eq(handle.written[path]:find('"version": 1', 1, true) ~= nil, true)

  handle.restoreIo()
end)

test('saving with nothing loaded is refused, not crashed', function()
  local handle = fakes.install({ clicks = { ['Save##save'] = true } })

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  local ok, err = pcall(_G.script.windowAtr, 0.016)
  eq(ok, true, ok and '' or tostring(err))
  eq(next(handle.written), nil, 'nothing should have been written')

  handle.restoreIo()
end)

test('Reset asks before it clears anything', function()
  -- The one button in CamTool 2 that can throw away an afternoon in a single
  -- click. Here the first press only warns.
  local handle = fakes.install({
    cameraFile = rawFile,
    clicks = {
      ['no file##fileName'] = true,
      -- The list marks where a file came from, so the label carries it.
      ['fake_track_-cameras.json   [CamTool 2]##fileName'] = true,
      ['Reset##reset'] = true,
    },
  })

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  -- Draw twice: the first Reset warns, the second goes through. Both have to
  -- survive, and neither may write anything to disk.
  for _ = 1, 3 do
    local ok, err = pcall(_G.script.windowAtr, 0.016)
    if not ok then error('windowAtr raised: ' .. tostring(err), 2) end
  end
  eq(next(handle.written), nil, 'Reset must not touch the file')

  handle.restoreIo()
end)

test('the undo and redo buttons are both offered', function()
  local handle = fakes.install({ clicks = { ['Redo (0)##redo'] = true } })
  local doc = dataModule.load(rawFile)

  local actions = atr.draw({
    camera = doc.pos[2], cameraIndex = 2, cameraCount = #doc.pos,
    keyframeIndex = 1, keyframeCount = 2,
    trackPos = 0.02, trackLength = 5802, undoDepth = 3, redoDepth = 0,
  })
  eq(actions.redo, true)

  handle.restoreIo()
end)

test('the spline section appears only for a camera that has a path', function()
  local handle = fakes.install({})
  local splineFile = require('tests/fixtures/camera_file_splines')
  local doc = dataModule.load(splineFile)

  -- The Silverstone set is driven by recorded paths, so one of its cameras
  -- has points and the section is worth drawing.
  local withPath = nil
  for _, cam in ipairs(doc.pos) do
    if cam.spline ~= nil and #(cam.spline.the_x or {}) > 0 then withPath = cam end
  end
  eq(withPath ~= nil, true, 'the fixture should have a recorded path')

  local ok, err = pcall(atr.draw, {
    camera = withPath, cameraIndex = 1, cameraCount = #doc.pos,
    keyframeIndex = 1, keyframeCount = #(withPath.keyframes or {}),
    trackPos = 0.1, trackLength = 5802,
  })
  eq(ok, true, ok and '' or tostring(err))

  -- And a camera with no path must not raise either.
  ok, err = pcall(atr.draw, {
    camera = { camera_in = 0, keyframes = {} }, cameraIndex = 1,
    cameraCount = 1, keyframeCount = 0, trackPos = 0.1, trackLength = 5802,
  })
  eq(ok, true, ok and '' or tostring(err))

  handle.restoreIo()
end)

test('every spline parameter is real, and the camera-level ones have no diamond', function()
  -- The three affect_ angles sit in every keyframe and the legacy never
  -- interpolates them, so offering to keyframe them would be a lie. The
  -- expectation comes from core/evaluate rather than a list written here:
  -- the first version of this test carried its own list, and the list
  -- happily agreed with a mistake -- spline_speed marked camera level when
  -- core interpolates it.
  for _, spec in ipairs(atr.SPLINE) do
    eq(type(spec.unit), 'table', spec.label .. ' has no unit')
    local interp = evaluate.interpolatorFor(spec.key)
    eq(interp ~= nil, true, spec.key .. ' is not a parameter core knows')

    local neverInterpolated = interp == evaluate.CAMERA_LEVEL
    eq(spec.cameraLevel == true, neverInterpolated, string.format(
      '%s: core says %s, the panel says %s',
      spec.key, neverInterpolated and 'camera level' or 'keyframable',
      spec.cameraLevel and 'camera level' or 'keyframable'))
  end
end)

--------------------------------------------------------------------------------
-- Handing the view to Assetto Corsa
--------------------------------------------------------------------------------

test('a camera with an AC camera set hands the view over', function()
  -- Eleven of the reference cameras do this, and Le Lancone's camera 5 asks
  -- for the steering wheel view. Until now the port drove straight through
  -- them and nothing happened, which is what Theo saw.
  --
  -- A document of one camera, so which one is live is not in question.
  local doc = {
    pos = { {
      camera_in = 0,
      camera_use_specific_cam = 0,       -- steering wheel
      camera_use_tracking_point = 0,
      keyframes = { { keyframe = 0, interpolation = { loc_x = 0, loc_y = 0, loc_z = 5 } } },
    } },
    time = {},
  }

  local handle = fakes.install({
    cameraFile = doc,
    splinePosition = 0.5,
    clicks = {
      ['no file##fileName'] = true,
      ['fake_track_-cameras.json   [CamTool 2]##fileName'] = true,
      ['Take camera##hold'] = true,
    },
  })

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  for _ = 1, 6 do
    _G.script.windowAtr(0.016)
    _G.script.update(0.016)
  end

  eq(handle.cameraMode, 2, 'Drivable is the mode the steering wheel view needs')
  eq(handle.drivableCamera, 5, 'and the steering wheel is number five of it')

  -- Asked for once, not every frame: doing it every frame would fight
  -- anyone pressing F1 themselves.
  local modeCalls = 0
  for _, call in ipairs(handle.cameraCalls) do
    if call[1] == 'mode' then modeCalls = modeCalls + 1 end
  end
  eq(modeCalls, 1, 'the switch has to happen on change, not every frame')

  handle.restoreIo()
end)

test('a camera that drives itself takes the view back', function()
  local doc = {
    pos = {
      { camera_in = 0, camera_use_specific_cam = 0,
        keyframes = { { keyframe = 0, interpolation = { loc_x = 0, loc_y = 0, loc_z = 5 } } } },
      { camera_in = 0.4, camera_use_specific_cam = -1,
        keyframes = { { keyframe = 0.4, interpolation = { loc_x = 9, loc_y = 9, loc_z = 9 } } } },
    },
    time = {},
  }

  local handle = fakes.install({
    cameraFile = doc,
    splinePosition = 0.1,
    clicks = {
      ['no file##fileName'] = true,
      ['fake_track_-cameras.json   [CamTool 2]##fileName'] = true,
      ['Take camera##hold'] = true,
    },
  })

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  -- sim.frame has to move: the app does its per-frame work once per render
  -- frame and returns early otherwise, so a loop that never advances it runs
  -- the first frame four times.
  for _ = 1, 4 do
    handle.sim.frame = handle.sim.frame + 1
    _G.script.windowAtr(0.016)
    _G.script.update(0.016)
  end
  eq(handle.cameraMode, 2, 'handed over on the first camera')

  -- Drive on to the second camera, which drives itself.
  handle.car.splinePosition = 0.6
  for _ = 1, 4 do
    handle.sim.frame = handle.sim.frame + 1
    _G.script.update(0.016)
  end

  eq(handle.cameraMode, 6, 'Free is CamTool driving again')

  handle.restoreIo()
end)

test('the names come from CamTool 2, not from numbers', function()
  local cameramode = require('core/cameramode')

  eq(cameramode.label(-1), 'CamTool')
  eq(cameramode.label(nil), 'CamTool')
  eq(cameramode.label(0), 'steering wheel', 'Le Lancone camera 5 asks for this')
  eq(cameramode.label(8), 'behind')
  eq(cameramode.label(13), 'cockpit')

  -- Every value CamTool 2 could store has a name.
  for value = cameramode.MIN + 1, cameramode.MAX do
    local entry = cameramode.find(value)
    eq(entry ~= nil, true, 'no entry for ' .. value)
    eq(#entry.label > 0, true)
    eq(type(entry.mode), 'string')
  end
end)

test('the F1 family asks for a named camera rather than counting presses', function()
  -- The whole point of doing this in Lua. CamTool 2 pressed F1 the right
  -- number of times from a remembered offset, so the user had to line the
  -- view up by hand first; CSP takes the camera by name.
  local cameramode = require('core/cameramode')

  local wheel = cameramode.find(0)
  eq(wheel.mode, 'Drivable')
  eq(wheel.drivable, 5, 'asked for directly, not counted to')

  local behind = cameramode.find(8)
  eq(behind.mode, 'Car')
  eq(behind.carCamera, 5)

  local helicopter = cameramode.find(2)
  eq(helicopter.mode, 'Helicopter')
  eq(helicopter.drivable, nil)
  eq(helicopter.carCamera, nil)
end)

test('cycling walks the whole list and wraps', function()
  local cameramode = require('core/cameramode')
  eq(cameramode.cycle(-1, 1), 0)
  eq(cameramode.cycle(13, 1), -1, 'wraps at the top')
  eq(cameramode.cycle(-1, -1), 13, 'and at the bottom')
  eq(cameramode.cycle(nil, 1), 0, 'a camera that never set it starts here')
end)

test('the panel draws at the narrowest size the manifest allows', function()
  -- MIN_SIZE is 420 wide. The session bar used to reserve a fixed 160 for
  -- everything beside the file name, the row grew past it, and four buttons
  -- ended up off the edge where nothing could click them -- which is how
  -- Theo came to ask for undo buttons that were already there.
  local doc = dataModule.load(rawFile)

  for _, panelWidth in ipairs({ 420, 560, 1200 }) do
    local handle = fakes.install({ panelWidth = panelWidth })
    local ok, err = pcall(atr.draw, {
      camera = doc.pos[2], cameraIndex = 2, cameraCount = #doc.pos,
      keyframeIndex = 1, keyframeCount = 2,
      keyframePosition = 0.25, trackPos = 0.02, trackLength = 5802,
      loadedName = 'something.json', undoDepth = 2, redoDepth = 1,
    })
    eq(ok, true, ok and '' or (panelWidth .. ' wide: ' .. tostring(err)))
    handle.restoreIo()
  end
end)

test('the panel draws the map of the track, wired all the way to the game', function()
  -- The whole chain in one go: the adapter samples the fake track, the panel
  -- passes the outline down, the widget strokes it. Each piece has its own
  -- tests; this is the one that fails if they stop being connected.
  local handle = fakes.install({ cameraFile = rawFile })
  trackAdapter.clearCache()
  trackMap.reset()

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  local ok, err = pcall(_G.script.windowAtr, 0.016)
  eq(ok, true, ok and '' or ('windowAtr raised: ' .. tostring(err)))

  local strokes = 0
  for i = 1, #handle.drawn do
    if handle.drawn[i].op == 'pathStroke' then strokes = strokes + 1 end
  end
  eq(strokes > 0, true, 'the track reached the panel')

  handle.restoreIo()
end)

test('a track with no AI spline does not stop the panel drawing', function()
  -- A drift or gymkhana layout. The map says so and the rest of the panel
  -- carries on, because the cameras are still there to be edited.
  local handle = fakes.install({ cameraFile = rawFile, noTrackSpline = true })
  trackAdapter.clearCache()
  trackMap.reset()

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  local ok, err = pcall(_G.script.windowAtr, 0.016)
  eq(ok, true, ok and '' or ('windowAtr raised without a track spline: ' .. tostring(err)))

  handle.restoreIo()
end)

test('a track with no map says why, in the log the panel shows', function()
  -- The first run on Spa said "no track outline for this circuit" and nothing
  -- else, so the only way to find out what the adapter had actually decided
  -- was to read the source. The reason now goes through the app's own log,
  -- which the probe panel lists.
  local handle = fakes.install({ cameraFile = rawFile, noTrackSpline = true })
  trackAdapter.clearCache()
  trackMap.reset()

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()
  pcall(_G.script.windowAtr, 0.016)

  local said = nil
  for i = 1, #handle.logs do
    if handle.logs[i]:find('no track map', 1, true) then said = handle.logs[i] end
  end
  eq(said ~= nil, true, 'the panel explained itself in the log')

  handle.restoreIo()
end)

test('the map never takes more than its share of a small window', function()
  -- The default panel is 460 px tall. A map allowed its full ceiling would
  -- take two thirds of it and push the parameters off the bottom.
  local handle = fakes.install({ cameraFile = rawFile, panelHeight = 460 })
  trackAdapter.clearCache()
  trackMap.reset()

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()
  pcall(_G.script.windowAtr, 0.016)

  local tallest = 0
  for i = 1, #handle.drawn do
    local call = handle.drawn[i]
    if call.op == 'drawRectFilled' and call.y2 ~= nil then
      local tall = call.y2 - call.y
      if tall > tallest then tallest = tall end
    end
  end

  eq(tallest <= 460 * 0.35 + 1, true,
    'the map fits its share, got ' .. tostring(tallest))
  eq(tallest > 0, true, 'and it is still drawn')

  handle.restoreIo()
end)

test('a window dragged out tall gets a bigger map, up to the ceiling', function()
  local handle = fakes.install({ cameraFile = rawFile, panelHeight = 1600 })
  trackAdapter.clearCache()
  trackMap.reset()

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()
  pcall(_G.script.windowAtr, 0.016)

  local tallest = 0
  for i = 1, #handle.drawn do
    local call = handle.drawn[i]
    if call.op == 'drawRectFilled' and call.y2 ~= nil then
      local tall = call.y2 - call.y
      if tall > tallest then tallest = tall end
    end
  end

  eq(tallest <= theme.mapHeightMax, true, 'never past the ceiling')

  handle.restoreIo()
end)

--------------------------------------------------------------------------
-- The wheel
--------------------------------------------------------------------------

test('rolling the wheel over a value moves it one step a notch', function()
  -- The gesture that needs no aim: hover and roll, no value running away
  -- under the pointer. It goes through the same entry point as the arrows and
  -- the drag, so Ctrl and Shift still divide and multiply it.
  local handle = fakes.install({ itemHovered = true, mouseWheel = 1 })
  parameter.cancelEditing()

  local action, amount = parameter.draw('wheel1', {
    label = 'MIX', text = '50%', width = 140,
  })
  eq(action, 'drag')
  runner.near(amount, 1, 1e-12)

  handle.restoreIo()
end)

test('rolling the other way moves the other way', function()
  local handle = fakes.install({ itemHovered = true, mouseWheel = -2 })
  parameter.cancelEditing()

  local _, amount = parameter.draw('wheel2', {
    label = 'MIX', text = '50%', width = 140,
  })
  runner.near(amount, -2, 1e-12)

  handle.restoreIo()
end)

test('the wheel does nothing unless the pointer is on the value', function()
  local handle = fakes.install({ itemHovered = false, mouseWheel = 3 })
  parameter.cancelEditing()

  local action = parameter.draw('wheel3', {
    label = 'MIX', text = '50%', width = 140,
  })
  eq(action, nil)

  handle.restoreIo()
end)

test('a value with nothing behind it cannot be wheeled either', function()
  local handle = fakes.install({ itemHovered = true, mouseWheel = 3 })
  parameter.cancelEditing()

  local action = parameter.draw('wheel4', {
    label = 'FOCUS POINT', text = nil, present = false, width = 140,
  })
  eq(action, nil)

  handle.restoreIo()
end)

test('a wheel nudged mid-drag does not fight the hand already moving it', function()
  -- Both would be reported in the same frame, and the two would disagree
  -- about how far the value should go.
  local handle = fakes.install({
    itemActive = true, itemHovered = true,
    mouseDragDelta = { x = 16, y = 0 }, mouseWheel = 5,
  })
  parameter.cancelEditing()

  local _, amount = parameter.draw('wheel5', {
    label = 'MIX', text = '50%', width = 140,
  })
  runner.near(amount, 2, 1e-12, 'the drag, not the wheel')

  handle.restoreIo()
end)

test('a readout cannot be wheeled -- there is nothing to set', function()
  local handle = fakes.install({ itemHovered = true, mouseWheel = 1 })
  parameter.cancelEditing()

  local action = parameter.draw('wheel6', {
    label = 'ACTIVE CAR', text = 'car 0', runtime = true,
    noTyping = true, width = 140,
  })
  eq(action, nil)

  handle.restoreIo()
end)

--------------------------------------------------------------------------
-- Hiding the map
--------------------------------------------------------------------------

test('the map can be put away, and the panel still works without it', function()
  local handle = fakes.install({ cameraFile = rawFile })
  trackAdapter.clearCache()
  trackMap.reset()

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  local function strokes()
    local n = 0
    for i = 1, #handle.drawn do
      if handle.drawn[i].op == 'pathStroke' then n = n + 1 end
    end
    return n
  end

  pcall(_G.script.windowAtr, 0.016)
  eq(strokes() > 0, true, 'shown to begin with')

  -- Now a session where the toggle is being clicked.
  handle.restoreIo()

  handle = fakes.install({
    cameraFile = rawFile,
    clicks = { [' map ##showMap'] = true, ['[map]##showMap'] = true },
  })
  trackAdapter.clearCache()
  trackMap.reset()
  chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  pcall(_G.script.windowAtr, 0.016)
  local before = #handle.drawn
  pcall(_G.script.windowAtr, 0.016)

  local after = 0
  for i = before + 1, #handle.drawn do
    if handle.drawn[i].op == 'pathStroke' then after = after + 1 end
  end
  eq(after, 0, 'the second draw has no map in it')

  handle.restoreIo()
end)
