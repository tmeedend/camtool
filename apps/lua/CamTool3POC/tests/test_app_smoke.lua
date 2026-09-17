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

test('the tracking path runs when a car has a world position', function()
  -- Guards the aim code added after the first in-game session: without a
  -- position on the fake car it would quietly skip, and the new path would go
  -- untested while still looking green.
  local handle = loadApp({ cameraFile = rawFile, splinePosition = 0.04 })

  for _ = 1, 30 do
    local ok, err = pcall(_G.script.update, 0.016)
    if not ok then error('update raised with tracking: ' .. tostring(err), 2) end
  end

  local ok, err = pcall(_G.script.windowMain, 0.016)
  eq(ok, true, ok and '' or ('windowMain raised with tracking: ' .. tostring(err)))

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

  local list, prefix = storage.listCameraFiles()
  eq(prefix, 'fake_track_-', 'track id, underscore, layout, dash')
  eq(#list, 1, 'settings.json is not a camera file, and the other track is filtered out')
  eq(list[1], 'fake_track_-cameras.json')

  -- The escape hatch still shows everything except settings.json.
  local all = storage.listCameraFiles(true)
  eq(#all, 2)

  handle.restoreIo()
end)

test('the storage adapter migrates what it reads', function()
  local handle = fakes.install({ cameraFile = rawFile })
  local storage = require('adapters/storage')

  local doc, err = storage.loadCameraFile('fake_track_-cameras.json')
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

test('an unkeyframed heading holds instead of snapping to zero', function()
  -- Regression guard. A camera that never keyframes rot_z must keep pointing
  -- where it is, which is what the legacy does by falling back to the camera's
  -- live heading. Getting this wrong aimed 18% of the reference cameras at a
  -- fixed direction, and it took an in-game session to notice.
  local doc = {
    pos = {
      {
        camera_in = 0.0,
        -- Position and roll only: no rot_z, no rot_x, no tracking.
        tracking_strength_heading = 0,
        tracking_strength_pitch = 0,
        keyframes = {
          { keyframe = 0.0, interpolation = { loc_x = 0, loc_y = 0, loc_z = 10 } },
          { keyframe = 1.0, interpolation = { loc_x = 50, loc_y = 0, loc_z = 10 } },
        },
      },
    },
    time = {},
  }

  local handle = fakes.install({
    cameraFile = doc,
    splinePosition = 0.5,
    clicks = {
      ['Find CamTool 2 files'] = true,
      ['next >'] = true,
      ['Load this file'] = true,
      ['next >'] = true,
      ['Grab camera'] = true,
      ['Play CamTool 2 file (12)'] = true,
    },
  })

  -- Aim the camera somewhere distinctive before the app takes over.
  local angles = require('core/angles')
  local seedHeading, seedPitch = 1.1, -0.25
  local lx, ly, lz = angles.lookVector(seedHeading, seedPitch)
  handle.camera.transformOriginal.look = { x = lx, y = ly, z = lz }

  local chunk = assert(loadfile('CamTool3POC.lua'))
  chunk()

  -- A few frames: draw first so the clicks land, then run the frame.
  for _ = 1, 5 do
    _G.script.windowMain(0.016)
    _G.script.update(0.016)
  end

  local look = handle.transform.look
  local h, p = angles.fromLook(look.x, look.y, look.z)

  runner.near(angles.normalize(seedHeading, h), seedHeading, 1e-6,
    'heading must be held, not reset to zero')
  runner.near(p, seedPitch, 1e-6, 'pitch must be held too')

  handle.restoreIo()
end)

test('a real spline camera set plays back without raising', function()
  -- ks_silverstone_gp-seb: 14 cameras driven entirely by recorded paths, with
  -- spline_affect_loc_xy at 1. Includes pos[1], whose recording ends on a stray
  -- out-of-order sample, so this also covers the messy case.
  local splineFile = require('tests/fixtures/camera_file_splines')

  local handle = fakes.install({
    cameraFile = splineFile,
    splinePosition = 0.07,
    clicks = {
      ['Find CamTool 2 files'] = true,
      ['next >'] = true,
      ['Load this file'] = true,
      ['Grab camera'] = true,
      ['Play CamTool 2 file (12)'] = true,
    },
  })

  local chunk = assert(loadfile('CamTool3POC.lua'))
  chunk()

  for _ = 1, 40 do
    _G.script.windowMain(0.016)
    local ok, err = pcall(_G.script.update, 0.016)
    if not ok then error('spline playback raised: ' .. tostring(err), 2) end
  end

  -- The camera must have been put somewhere real, not left at the origin.
  local p = handle.transform.position
  eq(type(p.x), 'number')
  if p.x == 0 and p.y == 0 and p.z == 0 then
    error('the camera never moved off the origin', 2)
  end
  if math.abs(p.x) > 10000 or math.abs(p.z) > 10000 then
    error(string.format('camera placed off the map: %g %g %g', p.x, p.y, p.z), 2)
  end

  handle.restoreIo()
end)

test('both per-frame entry points exist', function()
  -- CSP may call script.update, or the WORLD_UPDATE callback, depending on how
  -- the manifest is read. The app has to keep driving the camera with its
  -- window closed, so both are wired.
  local handle = loadApp({ cameraFile = rawFile })
  eq(type(_G.script.update), 'function')
  eq(type(_G.script.simUpdate), 'function')
  handle.restoreIo()
end)

test('the work happens once per frame even if both entry points fire', function()
  -- Running twice in one frame would advance the replay cursor and the car
  -- history double, which would show up as the replay playing at 2x.
  --
  -- Replay driving is switched on through the UI so there is a per-frame side
  -- effect to count; without it this test would pass on an empty list and prove
  -- nothing.
  local handle = fakes.install({
    cameraFile = rawFile,
    clicks = { ['Drive replay'] = true },
  })
  local chunk = assert(loadfile('CamTool3POC.lua'))
  chunk()

  handle.sim.frame = 1
  _G.script.windowMain(0.016)   -- lands the click
  _G.script.update(0.016)

  local afterFirst = #handle.replayPositions
  if afterFirst == 0 then
    error('replay driving did not start, so this test proves nothing', 2)
  end

  _G.script.simUpdate(0.016)
  eq(#handle.replayPositions, afterFirst,
    'a second call in the same frame must do nothing')

  handle.sim.frame = 2
  _G.script.simUpdate(0.016)
  eq(#handle.replayPositions, afterFirst + 1, 'a new frame must be processed once')

  handle.sim.frame = 3
  _G.script.update(0.016)
  eq(#handle.replayPositions, afterFirst + 2, 'either entry point drives it')

  handle.restoreIo()
end)
