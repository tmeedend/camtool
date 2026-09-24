--[[
  Tests for core/cutfade.lua: the sound coming back after a cut.
]]

local runner = require('tests/runner')
local cutfade = require('core/cutfade')

local test, eq, near = runner.test, runner.eq, runner.near

test('nothing fades while the shot stays the same', function()
  local state = cutfade.new()
  for _ = 1, 10 do eq(cutfade.update(state, 1 / 60, 3, 0), 1) end
end)

test('taking the camera is not a cut', function()
  eq(cutfade.update(cutfade.new(), 1 / 60, 3, 0), 1)
end)

test('a new camera silences the frame of the cut, then comes back in half a second', function()
  local state = cutfade.new()
  cutfade.update(state, 1 / 60, 3, 0)
  eq(cutfade.update(state, 1 / 60, 4, 0), 0, 'the cut itself is silent')

  local at = {}
  for i = 1, 30 do at[i] = cutfade.update(state, 1 / 60, 4, 0) end
  near(at[15], (15 / 30) ^ 2, 1e-9, 'a square curve: a quarter at half time')
  near(at[30], 1, 1e-9, 'all back after half a second')
end)

test('a different followed car is a cut too', function()
  local state = cutfade.new()
  cutfade.update(state, 1 / 60, 3, 0)
  eq(cutfade.update(state, 1 / 60, 3, 1), 0)
end)

test('the fade does not depend on the frame rate', function()
  local function after(fps, seconds)
    local state = cutfade.new()
    cutfade.update(state, 1 / fps, 3, 0)
    cutfade.update(state, 1 / fps, 4, 0)
    local m
    for _ = 1, math.floor(seconds * fps + 0.5) do m = cutfade.update(state, 1 / fps, 4, 0) end
    return m
  end
  near(after(144, 0.25), after(60, 0.25), 0.02)
end)

test('reset makes the next frame a first one', function()
  local state = cutfade.new()
  cutfade.update(state, 1 / 60, 3, 0)
  cutfade.reset(state)
  eq(cutfade.update(state, 1 / 60, 9, 2), 1)
end)

--------------------------------------------------------------------------------
-- Through the app
--------------------------------------------------------------------------------

local fakes = require('tests/fakes/csp')

test('a cut in a held camera silences the game and brings it back', function()
  local function camera(at, x)
    return { camera_in = at, camera_pit = false, camera_use_tracking_point = 0,
      tracking_strength_heading = 1, tracking_strength_pitch = 1,
      tracking_offset = 0, tracking_mix = 0,
      keyframes = { { keyframe = at, interpolation = { loc_x = x, loc_y = 0, loc_z = 5 } } } }
  end
  local opts = {
    cameraFile = { interpolation_mode = 'fixed', version = 2, time = {},
      pos = { camera(0, 60), camera(0.5, -60) } },
    splinePosition = 0.4, carPosition = vec3(160, 5, 0),
    clicks = {
      ['no file###fileName'] = true,
      ['cameras   [CamTool 2]###fileName'] = true,
      ['Take camera###hold'] = true,
    },
  }
  local handle = fakes.install(opts)
  require('ui/band').reset()
  assert(loadfile('CamTool3.lua'))()
  for _ = 1, 6 do
    pcall(_G.script.windowAtr, 0.016)
    handle.tick(0.016)
  end
  for label in pairs(opts.clicks) do opts.clicks[label] = nil end
  eq(handle.grabbed, true, 'the camera was taken')
  eq(handle.audioMultiplier == nil or handle.audioMultiplier == 1, true,
    'taking the camera is not a cut')

  handle.car.splinePosition = 0.6
  handle.tick(0.016)
  eq(handle.audioMultiplier, 0, 'the cut is silent')
  for _ = 1, 40 do handle.tick(0.016) end
  eq(handle.audioMultiplier, 1, 'and the sound is back half a second later')

  handle.car.splinePosition = 0.3
  handle.tick(0.016)
  eq(handle.audioMultiplier, 0)
  opts.clicks['Release camera###hold'] = true
  pcall(_G.script.windowAtr, 0.016)
  opts.clicks['Release camera###hold'] = nil
  handle.tick(0.016)
  eq(handle.audioMultiplier, 1, 'letting go of the camera gives the sound back at once')

  handle.restoreIo()
end)
