--[[
  Load the app against fake CSP globals and drive it for a few frames.

  This exists because of what it already caught, before the app was ever opened
  in Assetto Corsa: script.windowMain had grown past Lua's 60-upvalue limit, so
  the file would not compile at all, and a nil sim field reaching string.format
  killed the window on its first draw. Both cost nothing to find here and a
  game launch to find there.

  It proves the app loads, resolves every require, survives a frame and draws.
  It says nothing about whether the picture is right.
]]

local runner = require('tests/runner')
local fakes = require('tests/fakes/csp')
local rawFile = require('tests/fixtures/camera_file_v0')

local test, eq = runner.test, runner.eq

---Load the app fresh with the given fake options, returning the fake handle.
local function loadApp(opts)
  local handle = fakes.install(opts)
  local chunk, err = loadfile('CamTool3POC.lua')
  if chunk == nil then
    error('app did not compile: ' .. tostring(err), 2)
  end
  chunk()
  return handle
end

test('the app compiles and both entry points exist', function()
  -- Guards the upvalue limit: over 60 and loadfile fails outright.
  local handle = loadApp({ cameraFile = rawFile })
  eq(type(_G.script.update), 'function')
  eq(type(_G.script.windowMain), 'function')
  handle.restoreIo()
end)

test('a frame runs and the window draws without raising', function()
  local handle = loadApp({ cameraFile = rawFile })

  local ok, err = pcall(_G.script.update, 0.016)
  eq(ok, true, ok and '' or ('script.update raised: ' .. tostring(err)))

  ok, err = pcall(_G.script.windowMain, 0.016)
  eq(ok, true, ok and '' or ('script.windowMain raised: ' .. tostring(err)))

  handle.restoreIo()
end)

test('it survives many frames while holding the camera', function()
  local handle = loadApp({ cameraFile = rawFile })

  -- Nothing here can click buttons, so reach past the UI and grab directly,
  -- then let the per-frame path run against a held camera.
  eq(type(_G.ac.grabCamera), 'function')

  for _ = 1, 120 do
    local ok, err = pcall(_G.script.update, 0.016)
    if not ok then error('update raised mid-run: ' .. tostring(err), 2) end
    ok, err = pcall(_G.script.windowMain, 0.016)
    if not ok then error('windowMain raised mid-run: ' .. tostring(err), 2) end
  end

  handle.restoreIo()
end)

test('the teardown hook releases cleanly', function()
  local handle = loadApp({ cameraFile = rawFile })
  eq(type(handle.releaseCallback), 'function', 'the app must register ac.onRelease')

  local ok, err = pcall(handle.releaseCallback)
  eq(ok, true, ok and '' or ('teardown raised: ' .. tostring(err)))

  handle.restoreIo()
end)

test('the storage adapter filters settings.json out of the file list', function()
  local handle = fakes.install({ cameraFile = rawFile })
  local storage = require('adapters/storage')

  local list = storage.listCameraFiles()
  eq(#list, 1, 'settings.json is not a camera file')
  eq(list[1], 'fake_track-cameras.json')

  handle.restoreIo()
end)

test('the storage adapter migrates what it reads', function()
  local handle = fakes.install({ cameraFile = rawFile })
  local storage = require('adapters/storage')

  local doc, err = storage.loadCameraFile('fake_track-cameras.json')
  eq(err, nil)
  eq(doc.version, 1)
  eq(doc.interpolation_mode, 'legacy')

  handle.restoreIo()
end)

test('the storage adapter reports bad JSON instead of raising', function()
  -- JSON.parse does not raise on damaged input, it returns something
  -- unpredictable, so the adapter has to check rather than trust.
  local handle = fakes.install({ cameraFile = nil })
  local storage = require('adapters/storage')

  local doc, err = storage.loadCameraFile('whatever.json')
  eq(doc, nil)
  eq(type(err), 'string')

  handle.restoreIo()
end)
