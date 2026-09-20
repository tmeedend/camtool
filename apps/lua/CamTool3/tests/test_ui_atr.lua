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
local trackBand = require('ui/band')
local data = require('core/data')
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

test('the panel never writes a note about its own construction', function()
  -- It used to list what CamTool 2 has and this does not, right there in the
  -- window. docs/ui-interactions.md forbids it: that list belongs in the
  -- repo, and a user reading "not implemented yet" learns nothing about the
  -- shot they are cutting. The list now lives in docs/etat.md.
  local handle = fakes.install({})
  parameter.cancelEditing()

  atr.draw({
    cameraCount = 0, keyframeCount = 0, listName = 'pos',
    trackPos = 0, trackLength = 1000, showMap = false,
  })

  local banned = { 'not here yet', 'not implemented', 'coming soon', 'TODO' }
  for i = 1, #handle.drawn do
    local call = handle.drawn[i]
    if call.op == 'text' then
      for _, phrase in ipairs(banned) do
        eq(tostring(call.text):lower():find(phrase:lower(), 1, true), nil,
          'the panel said: ' .. tostring(call.text))
      end
    end
  end

  handle.restoreIo()
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
    -- Through handle.tick, which advances the render frame. Calling
    -- script.update directly in a loop runs the app's work exactly ONCE: it
    -- guards against its two entry points firing in the same frame, and with
    -- the counter standing still every call after the first is that guard
    -- doing its job. Thirty frames of nothing, and no way to tell.
    handle.tick(0.016)
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
      ['no file###fileName'] = true,
      -- The list marks where a file came from, so the label carries it.
      ['fake_track_-cameras.json   [CamTool 2]###fileName'] = true,
      ['Take camera###hold'] = true,
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
  --
  -- Two draws: the first frame arms the gesture past the dead zone, the
  -- second is the drag proper. That is the shape of the real thing too.
  local handle = fakes.install({
    itemActive = true, mouseDragDelta = { x = 16, y = 0 },
  })
  parameter.cancelEditing()

  local spec = { label = 'MIX', text = '50%', width = 140 }
  parameter.draw('drag1', spec)
  local action, amount = parameter.draw('drag1', spec)
  eq(action, 'drag')
  runner.near(amount, 2, 1e-12)

  handle.restoreIo()
end)

test('dragging leftwards moves the other way', function()
  local handle = fakes.install({
    itemActive = true, mouseDragDelta = { x = -8, y = 0 },
  })
  parameter.cancelEditing()

  local spec = { label = 'MIX', text = '50%', width = 140 }
  parameter.draw('drag2', spec)
  local _, amount = parameter.draw('drag2', spec)
  runner.near(amount, -1, 1e-12)

  handle.restoreIo()
end)

--------------------------------------------------------------------------
-- What makes the drag safe
--------------------------------------------------------------------------

test('a click that slips a pixel or two moves nothing', function()
  -- The dead zone. Without it, pressing a value to read it more closely is
  -- enough to change it, and the change only shows up in the edit.
  local handle = fakes.install({
    itemActive = true, mouseDragDelta = { x = 2, y = 0 },
  })
  parameter.cancelEditing()

  local spec = { label = 'MIX', text = '50%', width = 140 }
  eq(parameter.draw('slip', spec), nil)
  eq(parameter.draw('slip', spec), nil, 'and it does not creep in later either')

  handle.restoreIo()
end)

test('a drag is horizontal: moving up and down changes nothing', function()
  -- Vertical would mean the same thing as scrolling the panel, and the mouse
  -- would have to choose between them.
  local handle = fakes.install({
    itemActive = true, mouseDragDelta = { x = 0, y = 60 },
  })
  parameter.cancelEditing()

  local spec = { label = 'MIX', text = '50%', width = 140 }
  parameter.draw('vert', spec)
  eq(parameter.draw('vert', spec), nil)

  handle.restoreIo()
end)

test('the pointer says the value can be dragged', function()
  -- Discoverability, and the only hint the panel gives.
  local handle = fakes.install({ itemHovered = true })
  parameter.cancelEditing()

  parameter.draw('cursor1', { label = 'MIX', text = '50%', width = 140 })
  eq(handle.cursor, ui.MouseCursor.ResizeEW)

  handle.restoreIo()
end)

test('a value with nothing behind it does not offer the cursor', function()
  local handle = fakes.install({ itemHovered = true })
  parameter.cancelEditing()

  parameter.draw('cursor2', {
    label = 'FOCUS POINT', text = nil, present = false, width = 140,
  })
  eq(handle.cursor, nil, 'nothing to drag, so nothing promised')

  handle.restoreIo()
end)

test('a right click during a drag asks for the value back', function()
  -- Not Escape. That key is Assetto Corsa's for leaving the replay, and an
  -- app that teaches the hand to reach for it is an app where one mistimed
  -- press ends the session with every unsaved camera in it.
  local handle = fakes.install({
    itemActive = true, mouseDragDelta = { x = 30, y = 0 },
    rightClicked = true,
  })
  parameter.cancelEditing()

  local spec = { label = 'MIX', text = '50%', width = 140 }
  parameter.draw('esc', spec)
  eq(parameter.draw('esc', spec), 'dragCancel')

  handle.restoreIo()
end)

test('Escape does nothing to a drag, and so never reaches the game as ours', function()
  local handle = fakes.install({
    itemActive = true, mouseDragDelta = { x = 30, y = 0 }, keyPressed = 27,
  })
  parameter.cancelEditing()

  local spec = { label = 'MIX', text = '50%', width = 140 }
  parameter.draw('escgone', spec)
  eq(parameter.draw('escgone', spec), 'drag', 'the drag simply carries on')

  handle.restoreIo()
end)

test('after cancelling, the same hold cannot start dragging again', function()
  -- The button is still down. Without this, letting go would rearm the
  -- gesture a few pixels later and quietly carry on.
  local handle = fakes.install({
    itemActive = true, mouseDragDelta = { x = 30, y = 0 },
    rightClicked = true,
  })
  parameter.cancelEditing()

  local spec = { label = 'MIX', text = '50%', width = 140 }
  parameter.draw('esc2', spec)
  eq(parameter.draw('esc2', spec), 'dragCancel')

  handle.restoreIo()

  -- Right button let go of, left one still held.
  handle = fakes.install({
    itemActive = true, mouseDragDelta = { x = 60, y = 0 },
  })
  eq(parameter.draw('esc2', spec), nil, 'still held, still not dragging')
  handle.restoreIo()
end)

test('one gesture answers with one number, and the next with another', function()
  -- What keeps a drag to one undo entry, and two drags of the same row to
  -- two. The row id cannot tell them apart -- it is the same both times.
  local handle = fakes.install({
    itemActive = true, mouseDragDelta = { x = 16, y = 0 },
  })
  parameter.cancelEditing()

  local spec = { label = 'MIX', text = '50%', width = 140 }
  eq(parameter.draggingGesture(), nil, 'nothing yet')
  parameter.draw('g', spec)
  local first = parameter.draggingGesture()
  eq(type(first), 'number')
  parameter.draw('g', spec)
  eq(parameter.draggingGesture(), first, 'the same gesture, still going')
  handle.restoreIo()

  -- Let go, then drag the same row again.
  handle = fakes.install({ itemActive = false })
  parameter.draw('g', spec)
  eq(parameter.draggingGesture(), nil, 'let go')
  handle.restoreIo()

  handle = fakes.install({ itemActive = true, mouseDragDelta = { x = 16, y = 0 } })
  parameter.draw('g', spec)
  eq(parameter.draggingGesture() ~= first, true, 'a second gesture, not the first')
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

test('the keyframe pair sits in the action row now the strips have gone', function()
  -- The strips gave every camera and every keyframe a numbered cell. The
  -- ribbon does that at any size, so they went -- but a keyframe still has to
  -- be addable, and neither button needs somewhere to point at: a keyframe is
  -- born at the playhead, on the selected camera.
  local handle = fakes.install({ clicks = { ['+kf##kfadd'] = true } })
  parameter.cancelEditing()

  local actions = atr.draw({
    cameraCount = 3, cameraIndex = 1, keyframeCount = 2, keyframeIndex = 1,
    trackPos = 0.2, trackLength = 4300, listName = 'pos', showMap = false,
  })
  eq(actions.addKeyframe, true)
  handle.restoreIo()

  handle = fakes.install({ clicks = { ['-kf##kfdel'] = true } })
  actions = atr.draw({
    cameraCount = 3, cameraIndex = 1, keyframeCount = 2, keyframeIndex = 1,
    trackPos = 0.2, trackLength = 4300, listName = 'pos', showMap = false,
  })
  eq(actions.removeKeyframe, true)
  handle.restoreIo()
end)

test('no numbered cell is drawn anywhere any more', function()
  -- The strips are gone for good, not hidden. A cell coming back would mean
  -- two ways to pick a camera again, which is what the ribbon replaced.
  local handle = fakes.install({})
  parameter.cancelEditing()

  atr.draw({
    cameraCount = 22, cameraIndex = 1, keyframeCount = 3, keyframeIndex = 1,
    trackPos = 0.2, trackLength = 4300, listName = 'pos', showMap = false,
  })

  for i = 1, #handle.buttons do
    eq(tostring(handle.buttons[i]):find('###cam%d'), nil,
      'a numbered camera cell came back: ' .. tostring(handle.buttons[i]))
    eq(tostring(handle.buttons[i]):find('###kf%d'), nil,
      'a numbered keyframe cell came back: ' .. tostring(handle.buttons[i]))
  end
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
      ['no file###fileName'] = true,
      -- The list marks where a file came from, so the label carries it.
      ['fake_track_-cameras.json   [CamTool 2]###fileName'] = true,
      ['Save###save'] = true,
      ['Save *###save'] = true,
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
  eq(handle.written[path]:find('"version": ' .. data.CURRENT_VERSION, 1, true)
    ~= nil, true)

  handle.restoreIo()
end)

test('saving with nothing loaded is refused, not crashed', function()
  local handle = fakes.install({ clicks = { ['Save###save'] = true } })

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
      ['no file###fileName'] = true,
      -- The list marks where a file came from, so the label carries it.
      ['fake_track_-cameras.json   [CamTool 2]###fileName'] = true,
      ['Reset###reset'] = true,
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
  local handle = fakes.install({ clicks = { ['Redo (0)###redo'] = true } })
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
      ['no file###fileName'] = true,
      ['fake_track_-cameras.json   [CamTool 2]###fileName'] = true,
      ['Take camera###hold'] = true,
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
      ['no file###fileName'] = true,
      ['fake_track_-cameras.json   [CamTool 2]###fileName'] = true,
      ['Take camera###hold'] = true,
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
    clicks = { [' map ###showMap'] = true, ['[map]###showMap'] = true },
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

--------------------------------------------------------------------------
-- Widget identity: ### and not ##
--------------------------------------------------------------------------

---What ImGui would use as a widget's identity: the part after ###, or the
---whole label when there is no ###.
local function identityOf(label)
  local after = tostring(label):match('###(.*)$')
  return after or tostring(label)
end

test('a value keeps its identity when the value changes', function()
  -- ImGui hashes the WHOLE label, and only ### makes the part after it the
  -- identity on its own. The visible part of this widget IS the value, so
  -- with ## the button became a different widget the moment it moved: ImGui
  -- dropped the active item, and a drag changed the value exactly once and
  -- then died. That is the bug this pins.
  local handle = fakes.install({})
  parameter.cancelEditing()

  parameter.draw('row', { label = 'FOV', text = '40.00 deg', width = 140 })
  local first = {}
  for i = 1, #handle.buttons do first[#first + 1] = identityOf(handle.buttons[i]) end

  handle.buttons = {}
  parameter.draw('row', { label = 'FOV', text = '41.00 deg', width = 140 })
  local second = {}
  for i = 1, #handle.buttons do second[#second + 1] = identityOf(handle.buttons[i]) end

  eq(#first > 0, true)
  eq(#first, #second)
  for i = 1, #first do
    eq(first[i], second[i], 'widget ' .. i .. ' kept its identity')
  end

  handle.restoreIo()
end)

test('no widget in the panel changes identity when its text does', function()
  -- The same trap, swept across the whole panel rather than one row: draw it
  -- twice with everything the same except the words, and every identity has
  -- to match. A label built with ## and a changing prefix shows up here.
  local doc = data.load(rawFile)
  local base = {
    doc = doc, camera = doc.pos[1], cameraIndex = 1, cameraCount = #doc.pos,
    keyframeIndex = 1, keyframeCount = 2,
    trackPos = 0.3, trackLength = 4300,
    listName = 'pos', showMap = false,
  }

  local function identities(extra)
    local handle = fakes.install({})
    parameter.cancelEditing()

    local state = {}
    for k, v in pairs(base) do state[k] = v end
    for k, v in pairs(extra) do state[k] = v end
    atr.draw(state)

    local out = {}
    for i = 1, #handle.buttons do out[#out + 1] = identityOf(handle.buttons[i]) end
    handle.restoreIo()
    return out
  end

  local quiet = identities({
    fileName = 'a.json', held = false, undoDepth = 0, redoDepth = 0,
    mode = 'legacy',
  })
  local busy = identities({
    fileName = 'a much longer name.json', held = true, undoDepth = 7,
    redoDepth = 3, mode = 'fixed',
  })

  eq(#quiet > 10, true, 'the panel drew a good number of widgets')
  eq(#quiet, #busy, 'and the same number both times')
  for i = 1, #quiet do
    eq(quiet[i], busy[i], 'widget ' .. i .. ' (' .. tostring(quiet[i]) .. ')')
  end
end)

--------------------------------------------------------------------------
-- Did Assetto Corsa actually take the camera we asked for?
--------------------------------------------------------------------------

---Run the app with a file whose only camera asks for the steering wheel --
---the sixth of the F1 family, and the one in question.
local function runHandOver(opts)
  opts.cameraFile = {
    pos = { {
      camera_in = 0, camera_use_specific_cam = 0,
      keyframes = { { keyframe = 0, interpolation = { loc_x = 0, loc_y = 0, loc_z = 5 } } },
    } },
    time = {},
  }
  opts.splinePosition = 0.5
  opts.clicks = {
    ['no file###fileName'] = true,
    ['fake_track_-cameras.json   [CamTool 2]###fileName'] = true,
    ['Take camera###hold'] = true,
  }
  local handle = fakes.install(opts)
  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  for _ = 1, 6 do
    pcall(_G.script.windowAtr, 0.016)
    handle.tick(0.016)
  end
  return handle
end

test('a game that clamps the camera we asked for is caught saying so', function()
  -- The sixth of the F1 family: CamTool 2 walks that family modulo SIX, while
  -- CSP's enum names five. The real game takes the sixth -- confirmed, the
  -- enum is just incomplete -- but another build need not, and a camera
  -- quietly swapped for its neighbour is invisible from anywhere else. So the
  -- app asks, reads back, and says when the two disagree. Here the fake is
  -- the build that clamps.
  local handle = runHandOver({ drivableCeiling = 4 })

  local asked = false
  for i = 1, #handle.cameraCalls do
    if handle.cameraCalls[i][1] == 'drivable' and handle.cameraCalls[i][2] == 5 then
      asked = true
    end
  end

  eq(asked, true, 'the fixture does ask for the sixth camera')

  local warned = false
  for i = 1, #handle.logs do
    if tostring(handle.logs[i]):find('settled on', 1, true) then warned = true end
  end
  eq(warned, true, 'the log says what the game did with it')

  handle.restoreIo()
end)

test('a game that obeys says nothing', function()
  -- The bite test for the one above: a warning that fires whatever happens
  -- would be worth nothing.
  local handle = runHandOver({})

  for i = 1, #handle.logs do
    eq(tostring(handle.logs[i]):find('settled on', 1, true), nil,
      'no complaint when the camera is the one we asked for')
  end

  handle.restoreIo()
end)

--------------------------------------------------------------------------
-- The contract in docs/ui-interactions.md
--------------------------------------------------------------------------

test('clicking away drops what was being typed', function()
  -- The way out of a typed entry, now that Escape is left to the game.
  -- Nothing was applied until Enter, so there is nothing to put back, but the
  -- field has to close without committing half a number.
  local handle = fakes.install({
    itemHovered = true, mouseDoubleClicked = true,
  })
  parameter.cancelEditing()

  local spec = { label = 'FOV', text = '40.00 deg', raw = '40', width = 140 }
  parameter.draw('esc-type', spec)
  handle.restoreIo()

  -- Typing.
  handle = fakes.install({ typed = '35', itemActive = true })
  eq(parameter.draw('esc-type', spec), nil, 'nothing committed yet')
  handle.restoreIo()

  -- Clicked away: the field is no longer active. That frame still draws the
  -- field -- it was open when the drawing began -- and closes it at the end,
  -- so the value comes back on the one after.
  handle = fakes.install({})
  eq(parameter.draw('esc-type', spec), nil, 'and nothing committed on the way out')
  handle.restoreIo()

  handle = fakes.install({})
  parameter.draw('esc-type', spec)

  local sawValue = false
  for i = 1, #handle.buttons do
    if tostring(handle.buttons[i]):find('esc%-typeval') then sawValue = true end
  end
  eq(sawValue, true, 'back to a value, not a field being typed into')
  handle.restoreIo()
end)

test('an animated parameter is tinted, so a column can be swept', function()
  -- Without it, finding what a camera animates means reading twenty-one
  -- diamonds one by one.
  --
  -- Asked of the widget, not of the theme: what colour did the field get.
  local function fieldColour(keyframe)
    local handle = fakes.install({})
    parameter.cancelEditing()
    parameter.draw('tint-' .. keyframe, {
      label = 'FOV', text = '40.00 deg', width = 140,
      column = theme.columns.camera, keyframe = keyframe,
    })

    local colour = nil
    for i = 1, #handle.styles do
      if handle.styles[i].which == ui.StyleColor.Button then
        colour = handle.styles[i].colour
      end
    end
    handle.restoreIo()
    return colour
  end

  local plain = fieldColour('none')
  eq(rawequal(plain, theme.columns.camera.pill), true,
    'a parameter this camera never animates keeps the plain tint')

  eq(rawequal(fieldColour('here'), theme.columns.camera.pillAnimated), true,
    'keyframed on the selected keyframe')
  eq(rawequal(fieldColour('elsewhere'), theme.columns.camera.pillAnimated), true,
    'keyframed somewhere else in the camera -- still animated')
end)

--------------------------------------------------------------------------
-- The help layer
--------------------------------------------------------------------------

---Draw one row with the mouse on it, `frames` times, and return the fake.
local function hoverRow(frames, dt, spec)
  local handle = fakes.install({ itemHovered = true })
  parameter.cancelEditing()

  for _ = 1, frames do
    parameter.beginFrame(dt)
    parameter.draw('hovered', spec)
    parameter.endFrame()
  end
  return handle
end

test('a tooltip waits for the mouse to settle', function()
  -- Twenty-one fields packed together: with no delay, crossing the panel sets
  -- off a trail of bubbles. CSP has no DelayNormal flag, so the clock is ours
  -- and therefore has to be tested.
  local spec = { label = 'STR PITCH', text = '50%', width = 140,
    help = 'How much the tracking drives the tilt.' }

  local brief = hoverRow(1, 0.016, spec)
  eq(#brief.tooltips, 0, 'passing over shows nothing')
  brief.restoreIo()

  local settled = hoverRow(40, 0.016, spec)
  eq(#settled.tooltips > 0, true, 'resting on it does')
  settled.restoreIo()
end)

test('a tooltip says what the parameter does before how to change it', function()
  local settled = hoverRow(40, 0.016, { label = 'MIX', text = '0%', width = 140,
    help = 'Blends the aim between the active car and the extra one.' })

  local tip = settled.tooltips[1]
  eq(tip:find('Blends the aim', 1, true), 1, 'what it does comes first')
  eq(tip:find('Drag', 1, true) ~= nil, true, 'and the gestures follow')
  settled.restoreIo()
end)

test('a read-only row does not promise gestures it has not got', function()
  local settled = hoverRow(40, 0.016, {
    label = 'ACTIVE CAR', text = 'car 0', width = 140, runtime = true,
    noDiamond = true, noTyping = true,
    help = 'The car being followed.',
  })
  eq(settled.tooltips[1]:find('Read only', 1, true) ~= nil, true)
  eq(settled.tooltips[1]:find('Drag', 1, true), nil)
  settled.restoreIo()
end)

test('moving to another field restarts the wait', function()
  local handle = fakes.install({ itemHovered = true })
  parameter.cancelEditing()

  local a = { label = 'FOV', text = '40', width = 140, help = 'Field of view.' }
  local b = { label = 'PITCH', text = '0', width = 140, help = 'Tilt.' }

  for _ = 1, 40 do
    parameter.beginFrame(0.016)
    parameter.draw('rowA', a)
    parameter.endFrame()
  end
  local afterA = #handle.tooltips
  eq(afterA > 0, true)

  parameter.beginFrame(0.016)
  parameter.draw('rowB', b)
  parameter.endFrame()
  eq(#handle.tooltips, afterA, 'the new field starts its own wait')

  handle.restoreIo()
end)

test('the status line answers at once, with no delay at all', function()
  -- It is always on screen, so it can afford to. That is what makes the panel
  -- learnable without knowing there is anything to hover.
  local handle = fakes.install({ itemHovered = true })
  parameter.cancelEditing()

  parameter.beginFrame(0.016)
  parameter.draw('status', { label = 'OFF TRACKING', text = '0.00', width = 140,
    help = 'Aims ahead of the car or behind it.' })
  parameter.endFrame()

  local label, help = parameter.hovered()
  eq(label, 'OFF TRACKING')
  eq(help, 'Aims ahead of the car or behind it.')

  handle.restoreIo()
end)

test('the status line forgets once the mouse leaves the panel', function()
  local handle = fakes.install({ itemHovered = true })
  parameter.cancelEditing()

  parameter.beginFrame(0.016)
  parameter.draw('gone', { label = 'FOV', text = '40', width = 140, help = 'x' })
  parameter.endFrame()
  eq(parameter.hovered(), 'FOV')
  handle.restoreIo()

  -- A frame where no row claims the mouse: only beginFrame/endFrame can know.
  handle = fakes.install({ itemHovered = false })
  parameter.beginFrame(0.016)
  parameter.draw('gone', { label = 'FOV', text = '40', width = 140, help = 'x' })
  parameter.endFrame()
  eq(parameter.hovered(), nil)
  handle.restoreIo()
end)

test('the ? button shows the legend instead of the status line', function()
  local function textsWith(showHelp)
    local handle = fakes.install({})
    parameter.cancelEditing()
    atr.draw({
      cameraCount = 0, keyframeCount = 0, listName = 'pos',
      trackPos = 0, trackLength = 1000, showMap = false, showHelp = showHelp,
    })
    local joined = {}
    for i = 1, #handle.drawn do
      if handle.drawn[i].op == 'text' then joined[#joined + 1] = handle.drawn[i].text end
    end
    handle.restoreIo()
    return table.concat(joined, '\n')
  end

  local closed = textsWith(false)
  eq(closed:find('Hover a value', 1, true) ~= nil, true, 'the status line')
  eq(closed:find('never edits', 1, true), nil, 'and not the legend')

  local open = textsWith(true)
  eq(open:find('never edits', 1, true) ~= nil, true, 'the legend, in full')
  eq(open:find('Hover a value', 1, true), nil)
end)

test('every parameter of the panel carries a sentence', function()
  -- The contract asks for one per element, with priority on the cryptic
  -- names. A row added later without one fails here.
  local function check(spec)
    eq(type(spec.help), 'string', spec.label .. ' has no help')
    eq(#spec.help > 10, true, spec.label .. ' says too little')
    eq(spec.help:sub(-1), '.', spec.label .. ' is not a sentence')
  end

  for _, column in ipairs(atr.COLUMNS) do
    for _, spec in ipairs(column.rows) do check(spec) end
  end
  for _, spec in ipairs(atr.SPLINE) do check(spec) end
end)

--------------------------------------------------------------------------
-- The action row, which has run off the edge twice now
--------------------------------------------------------------------------

---Replay a layout and return where every item ends up.
---@return table[] @{ x = , right = , line = } per item
local function layout(items, available, startX)
  local breaks = atr.wrapRow(items, available, startX)
  local out = {}
  local x, line = startX or 0, 1

  for i, item in ipairs(items) do
    if breaks[i] then
      x, line = 0, line + 1
    elseif i > 1 or (startX or 0) > 0 then
      x = x + (item.gap or 3)
    end
    out[i] = { x = x, right = x + item.width, line = line }
    x = x + item.width
  end
  return out
end

local function widths(list)
  local items = {}
  for i, w in ipairs(list) do items[i] = { width = w, gap = 3 } end
  return items
end

test('a row that fits stays on one line', function()
  local placed = layout(widths({ 50, 50, 50 }), 400, 0)
  eq(placed[1].line, 1)
  eq(placed[3].line, 1)
end)

test('a button that would not fit starts the next line', function()
  local placed = layout(widths({ 50, 50, 50 }), 110, 0)
  eq(placed[1].line, 1)
  eq(placed[2].line, 1, '50 + 3 + 50 = 103, still inside 110')
  eq(placed[3].line, 2, 'the third would reach 156')
end)

test('a full keyframe strip pushes the whole row down', function()
  -- What Théo saw: the strip beside it had taken the width, and the buttons
  -- carried on off the edge of the window where nothing can click them.
  local placed = layout(widths({ 74, 70, 60 }), 300, 290)
  eq(placed[1].line, 2, 'no room left on the strip line at all')
  eq(placed[1].x, 0)
end)

test('no button of the real row ever lands past the edge', function()
  -- The row as the panel actually builds it, at every width from cramped to
  -- comfortable, with the keyframe strip taking anything from nothing to
  -- almost everything.
  local real = {
    { id = 'undo', width = 74, gap = 12 }, { id = 'redo', width = 70 },
    { id = 'save', width = 60 }, { id = 'reset', width = 56 },
    { id = 'map', width = 52 }, { id = 'help', width = 30 },
    { id = 'pos', width = 74, gap = 10 }, { id = 'time', width = 58 },
    { id = 'maths', width = 96, gap = 10 },
  }

  for available = 120, 900, 20 do
    for _, startX in ipairs({ 0, 60, available - 40, available }) do
      local placed = layout(real, available, startX)
      for i, at in ipairs(placed) do
        eq(at.right <= available or at.x == 0, true, string.format(
          'button %d reaches %d of %d (strip took %d)',
          i, at.right, available, startX))
      end
    end
  end
end)

test('a button wider than the panel gets its own line rather than a neighbour', function()
  -- It will still be clipped, and nothing can be done about that but make the
  -- window bigger. What matters is that it does not drag a second button off
  -- the edge with it.
  local placed = layout(widths({ 200, 50 }), 100, 0)
  eq(placed[1].line, 1)
  eq(placed[2].line, 2)
end)



--------------------------------------------------------------------------
-- Buttons that used to refuse in silence
--------------------------------------------------------------------------

---Load a file, click something, and report what the panel said and did.
local function clickInPanel(label, opts)
  opts = opts or {}
  opts.cameraFile = rawFile
  opts.clicks = {
    ['no file###fileName'] = true,
    ['fake_track_-cameras.json   [CamTool 2]###fileName'] = true,
  }
  if label ~= nil then opts.clicks[label] = true end
  for extra in pairs(opts.extraClicks or {}) do opts.clicks[extra] = true end
  local handle = fakes.install(opts)
  trackAdapter.clearCache()
  trackMap.reset()

  local chunk = assert(loadfile('CamTool3.lua'))
  chunk()

  -- Load on the first frame, then click on the next.
  pcall(_G.script.windowAtr, 0.016)
  handle.tick(0.016)
  opts.clicks['no file###fileName'] = nil
  opts.clicks['fake_track_-cameras.json   [CamTool 2]###fileName'] = nil
  pcall(_G.script.windowAtr, 0.016)

  -- More frames: the panel is drawn before the clicks it reported are acted
  -- on, so anything a click had to say appears the frame after -- and a click
  -- that first has to select something needs the one after that.
  for _ = 1, 3 do
    handle.tick(0.016)
    handle.drawn = {}
    pcall(_G.script.windowAtr, 0.016)
  end

  -- Everything the panel wrote: the status line sits near the top, well
  -- before the help line at the bottom.
  local said = {}
  for i = 1, #handle.drawn do
    if handle.drawn[i].op == 'text' then said[#said + 1] = handle.drawn[i].text end
  end
  handle.restoreIo()
  return table.concat(said, ' | '), handle
end

test('adding a keyframe works before the camera has been taken', function()
  -- The playhead came from the playback, and the playback only runs once the
  -- camera is held. Before that, every button needing a position refused in
  -- silence -- clicking + and watching nothing happen was exactly that.
  --
  -- Measured on the undo stack: a refused add leaves it empty. The camera is
  -- selected by clicking the ribbon, which is how one is selected now.
  local _, handle = clickInPanel(nil, {
    splinePosition = 0.42, itemHovered = true,
    mouseX = 17 + 100, mouseY = 23 + 10,
    extraClicks = { ['##trackBand'] = true, ['+kf##kfadd'] = true },
  })

  local depth = nil
  for i = #handle.buttons, 1, -1 do
    local n = tostring(handle.buttons[i]):match('^Undo %((%d+)%)')
    if n then depth = tonumber(n) break end
  end

  eq(depth ~= nil and depth >= 1, true,
    'something was added with no camera held, got ' .. tostring(depth))
  handle.restoreIo()
end)

test('a button that cannot act says why', function()
  -- No car at all: nothing to put a keyframe at, and the panel has to say so
  -- rather than swallow the click.
  local said = clickInPanel(nil, {
    noFocusedCar = true, itemHovered = true,
    mouseX = 17 + 100, mouseY = 23 + 10,
    extraClicks = { ['##trackBand'] = true, ['+kf##kfadd'] = true },
  })
  eq(said:find('no car', 1, true) ~= nil, true,
    'the panel said: ' .. tostring(said))
end)

test('Reset says on the button that it is armed', function()
  -- It warned only in the status line at the top, far from the thing that was
  -- clicked, so a first click read as nothing happening.
  local _, handle = clickInPanel('Reset###reset')

  local armed = false
  for i = 1, #handle.buttons do
    if tostring(handle.buttons[i]):find('Reset?###reset', 1, true) then
      armed = true
    end
  end
  eq(armed, true, 'the button asks the question itself')
  handle.restoreIo()
end)

--------------------------------------------------------------------------
-- Escape belongs to the game
--------------------------------------------------------------------------

test('nothing in the panel asks to hold the keyboard', function()
  -- It did, so Escape could cancel a gesture without Assetto Corsa taking it
  -- as "leave the replay". The capture worked; what made it wrong is that it
  -- taught the hand to reach for Escape in an app where the same key, a
  -- moment later with nothing open, ends the session and every unsaved camera
  -- with it.
  local doc = data.load(rawFile)
  local handle = fakes.install({ itemHovered = true, mouseDoubleClicked = true })
  parameter.cancelEditing()

  for _ = 1, 3 do
    atr.draw({
      doc = doc, camera = doc.pos[1], cameraIndex = 1, cameraCount = #doc.pos,
      cameras = doc.pos, keyframeIndex = 1, keyframeCount = 2,
      trackPos = 0.3, trackLength = 4300, listName = 'pos',
      showMap = false, dt = 0.016,
    })
  end

  eq(handle.keyboardHeld, nil, 'the game keeps its own keys')
  handle.restoreIo()
  parameter.cancelEditing()
end)





test('the legend covers every gesture the panel has', function()
  -- docs/ui-interactions.md: the ? button is the ONLY place help is
  -- exhaustive. A gesture that exists and is not in here is undiscoverable
  -- for anyone who did not watch it being built.
  local all = table.concat(atr.LEGEND, ' | '):lower()

  for _, gesture in ipairs({
    'shift+click', 'double click', 'right click', 'drag', 'escape',
    'ctrl+z', 'wheel', 'diamond', 'ribbon', 'map', 'click away',
  }) do
    eq(all:find(gesture, 1, true) ~= nil, true,
      'the legend never mentions ' .. gesture)
  end
end)

test('the legend says what a click on the ribbon does to the replay', function()
  -- The one Théo found missing: a click moves the replay, and nothing said so.
  local all = table.concat(atr.LEGEND, ' | '):lower()
  eq(all:find('bring the car', 1, true) ~= nil, true)
  eq(all:find('without moving the replay', 1, true) ~= nil, true)
end)

test('the panel hands the widget the sentence written for the row', function()
  -- Written after the tooltips turned out never to show at all. Both halves
  -- had tests -- the widget showed one when handed a sentence, the panel had
  -- a sentence for every parameter -- and the join between them did not: the
  -- panel rebuilt the row and dropped the sentence on the way. This is that
  -- join, and it is where the bug was.
  --
  -- The tooltip itself is checked at the widget, not here: the fake answers
  -- "hovered" for every row at once, so the delay resets on each and a panel
  -- drawn whole can never reach it. One row hovered is the real case.
  local doc = data.load(rawFile)
  local handle = fakes.install({ itemHovered = true })
  parameter.cancelEditing()

  atr.draw({
    doc = doc, camera = doc.pos[1], cameraIndex = 1, cameraCount = #doc.pos,
    cameras = doc.pos, keyframeIndex = 1, keyframeCount = 2,
    trackPos = 0.3, trackLength = 4300, listName = 'pos',
    showMap = false, dt = 0.016,
  })

  local label, help = parameter.hovered()
  eq(type(help), 'string', 'the sentence reached the widget')
  eq(#help > 10, true, 'and it is a sentence, not an empty slot')

  -- And that same sentence, given to the widget, does become a tooltip.
  handle.restoreIo()
  handle = fakes.install({ itemHovered = true })
  parameter.cancelEditing()
  for _ = 1, 40 do
    parameter.beginFrame(0.016)
    parameter.draw('join', { label = label, help = help, text = '1', width = 140 })
    parameter.endFrame()
  end
  eq(#handle.tooltips > 0, true, 'and the widget shows it')
  eq(handle.tooltips[1]:find(help, 1, true), 1)

  handle.restoreIo()
end)

test('the status line shows the sentence, not just the label', function()
  local doc = data.load(rawFile)
  local handle = fakes.install({ itemHovered = true })
  parameter.cancelEditing()

  atr.draw({
    doc = doc, camera = doc.pos[1], cameraIndex = 1, cameraCount = #doc.pos,
    cameras = doc.pos, keyframeIndex = 1, keyframeCount = 2,
    trackPos = 0.3, trackLength = 4300, listName = 'pos',
    showMap = false, dt = 0.016,
  })

  local label, help = parameter.hovered()
  eq(type(label), 'string')
  eq(type(help), 'string', 'the sentence reached the widget')

  handle.restoreIo()
end)
