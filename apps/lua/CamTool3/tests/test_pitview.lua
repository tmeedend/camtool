--[[
  The pit view: the ribbon and the map showing the pit lane cameras, so they
  can be selected and edited at all.
]]

local runner = require('tests/runner')
local fakes = require('tests/fakes/csp')
local edit = require('core/edit')

local test, eq = runner.test, runner.eq

test('a camera added in the pit view is a pit lane camera', function()
  local cameras = { { id = 1, camera_in = 0, camera_pit = false, keyframes = {} } }
  edit.addCamera(cameras, 0.5, 2, true)
  edit.addCamera(cameras, 0.7, 3)
  eq(cameras[2].camera_pit, true)
  eq(cameras[3].camera_pit, false, 'and without it, a track camera as before')
end)

local function camera(id, at, pit)
  return { id = id, camera_in = at, camera_pit = pit, camera_use_tracking_point = 0,
    tracking_strength_heading = 1, tracking_strength_pitch = 1, tracking_offset = 0,
    keyframes = { { keyframe = at, interpolation = { loc_x = 0, loc_y = 0, loc_z = 5 } } } }
end

local function start()
  local opts = {
    clicks = {},
    splinePosition = 0.1,
    cameraFile = { interpolation_mode = 'fixed', version = 2, time = {},
      next_camera_id = 4,
      pos = { camera(1, 0, false), camera(2, 0.3, true), camera(3, 0.6, false) } },
  }
  local handle = fakes.install(opts)
  require('ui/atr').cancelEditing()
  require('ui/band').reset()
  assert(loadfile('CamTool3.lua'))()
  pcall(_G.script.windowAtr, 0.016)

  local app = { handle = handle, opts = opts }
  function app.click(label)
    opts.clicks[label] = true
    pcall(_G.script.windowAtr, 0.016)
    opts.clicks[label] = nil
  end
  function app.label(suffix)
    handle.buttons = {}
    pcall(_G.script.windowAtr, 0.016)
    for i = 1, #handle.buttons do
      local text = tostring(handle.buttons[i])
      if text:sub(-#suffix) == suffix then return text end
    end
    return nil
  end
  function app.pitView() return app.label('###pitView') == '[pit]###pitView' end
  function app.selectedIsPit()
    local text = app.label('camera_pitval')
    return text ~= nil and text:find('^yes') ~= nil
  end
  return app
end

test('the pit button shows the pit cameras and selects the first of them', function()
  local app = start()
  eq(app.pitView(), false, 'the track cameras to begin with')
  app.click(' pit ###pitView')
  eq(app.pitView(), true)
  eq(app.selectedIsPit(), true, 'the fields are about a pit camera now')
  app.click('[pit]###pitView')
  eq(app.pitView(), false)
  eq(app.selectedIsPit(), false, 'and back on a track camera')
  app.handle.restoreIo()
end)

test('ticking PIT ONLY takes the ribbon with the camera', function()
  local app = start()
  -- Select a track camera: over to the pit view and back picks the first.
  app.click(' pit ###pitView')
  app.click('[pit]###pitView')
  eq(app.pitView(), false)
  eq(app.selectedIsPit(), false)
  app.click('##cameracamera_pitinc')
  eq(app.selectedIsPit(), true, 'the camera is a pit camera now')
  eq(app.pitView(), true, 'and the ribbon shows it, so it did not vanish')
  app.handle.restoreIo()
end)
