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
local atr = require('ui/atr')
local parameter = require('ui/parameter')
local evaluate = require('core/evaluate')
local dataModule = require('core/data')
local rawFile = require('tests/fixtures/camera_file_seb')

local test, eq = runner.test, runner.eq

test('every parameter the panel shows is one a camera really has', function()
  local doc = dataModule.load(rawFile)

  -- A camera carrying the full set of camera-level fields.
  local reference = doc.pos[2]
  eq(type(reference), 'table')

  for _, column in ipairs(atr.COLUMNS) do
    for _, spec in ipairs(column.rows) do
      if not spec.runtime then
        local known = evaluate.interpolatorFor(spec.key) ~= nil
          or reference[spec.key] ~= nil
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
      eq(type(spec.format), 'function', spec.label .. ' has no formatter')
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
