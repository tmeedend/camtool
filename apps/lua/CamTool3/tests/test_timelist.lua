--[[
  The `time` list: cameras laid out along the replay rather than the lap, in
  replay frames, as CamTool 2 stores them.
]]

local runner = require('tests/runner')
local replaytime = require('core/replaytime')
local playback = require('core/playback')

local test, eq, near = runner.test, runner.eq, runner.near

--------------------------------------------------------------------------------
-- core/replaytime
--------------------------------------------------------------------------------

test('between two frames, the position moves on with replay time', function()
  local state = replaytime.new()
  eq(replaytime.update(state, 100, 50, 0.01), 100, 'the first reading is the frame')
  near(replaytime.update(state, 100, 50, 0.02), 100.4, 1e-9, '20 ms of a 50 ms frame')
  near(replaytime.update(state, 100, 50, 0.02), 100.8, 1e-9)
  near(replaytime.update(state, 101, 50, 0.02), 101.2, 1e-9,
    'the new frame takes over the time already counted')
end)

test('it never runs past the next frame, and stands still when paused', function()
  local state = replaytime.new()
  replaytime.update(state, 100, 50, 0)
  near(replaytime.update(state, 100, 50, 1), 101, 1e-9, 'held at the next frame')
  local a = replaytime.update(state, 100, 50, 0)
  eq(replaytime.update(state, 100, 50, 0), a, 'paused')
end)

test('a jump starts afresh', function()
  local state = replaytime.new()
  replaytime.update(state, 100, 50, 0)
  replaytime.update(state, 100, 50, 0.04)
  eq(replaytime.update(state, 900, 50, 0.01), 900)
end)

test('frames and seconds convert both ways', function()
  near(replaytime.seconds(60, 1000 / 60), 1, 1e-12)
  near(replaytime.frames(2, 50), 40, 1e-12)
  eq(replaytime.frames(2, 0), 0)
end)

--------------------------------------------------------------------------------
-- The playback reads the time list on the replay position
--------------------------------------------------------------------------------

local function camera(at, x, extra)
  local c = { camera_in = at, tracking_strength_heading = 0, tracking_strength_pitch = 0,
    keyframes = { { keyframe = at, interpolation = { loc_x = x, loc_y = 0, loc_z = 5 } } } }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

local function doc()
  return { interpolation_mode = 'fixed', pos = { camera(0, 999) },
    time = { camera(0, 1), camera(200, 2), camera(500, 3) } }
end

local function frameAt(replayPos, trackPos, d)
  local state = playback.new({ listName = 'time', applyShake = false })
  return playback.frame(state, d or doc(), { trackPos = trackPos or 0.9,
    replayPos = replayPos, frameMs = 50, replayRate = 1, clock = 0 })
end

test('the time list picks its camera by replay frame, not by track position', function()
  eq(frameAt(150).activeCam, 1)
  eq(frameAt(250).activeCam, 2)
  eq(frameAt(600).activeCam, 3)
  eq(frameAt(250, 0.1).activeCam, 2, 'wherever the car is on the lap')
  eq(frameAt(250).x, 2)
end)

test('keyframes of the time list are read in frames', function()
  local d = { interpolation_mode = 'fixed', pos = {}, time = { {
    camera_in = 0, tracking_strength_heading = 0, tracking_strength_pitch = 0,
    keyframes = {
      { keyframe = 100, interpolation = { loc_x = 0, loc_y = 0, loc_z = 5 } },
      { keyframe = 300, interpolation = { loc_x = 10, loc_y = 0, loc_z = 5 } },
    } } } }
  local a, b = frameAt(120, nil, d).x, frameAt(280, nil, d).x
  eq(a < b, true, 'the camera moves with the replay')
end)

test('the offset along a path is in seconds on the time list', function()
  -- CamTool 2 multiplies it by the frame rate: at 50 ms a frame, one second
  -- of offset reads the path twenty frames earlier.
  local path = { the_x = { 0, 100 }, loc_x = { 0, 100 }, loc_y = { 0, 0 },
    loc_z = { 5, 5 }, rot_x = { 0, 0 }, rot_y = { 0, 0 }, rot_z = { 0, 0 } }
  local d = { interpolation_mode = 'fixed', pos = {}, time = {
    camera(0, 0, { spline = path, spline_offset_spline = 1, spline_affect_loc_xy = 1 }) } }
  near(frameAt(50, nil, d).splineQuery, 30, 1e-9)
end)

test('the pos list is untouched by any of it', function()
  local state = playback.new({ applyShake = false })
  local out = playback.frame(state, doc(), { trackPos = 0.5, replayPos = 250,
    frameMs = 50, replayRate = 1, clock = 0 })
  eq(out.activeCam, 1)
  eq(out.x, 999)
end)

--------------------------------------------------------------------------------
-- Through the app
--------------------------------------------------------------------------------

local fakes = require('tests/fakes/csp')

test('the app plays the time list on the replay frame', function()
  local d = doc()
  d.version = 2
  for _, c in ipairs(d.time) do c.camera_pit = false end
  local opts = { clicks = {}, cameraFile = d, splinePosition = 0.9 }
  local handle = fakes.install(opts)
  require('ui/atr').cancelEditing()
  require('ui/band').reset()
  assert(loadfile('CamTool3.lua'))()
  local function click(label)
    opts.clicks[label] = true
    pcall(_G.script.windowAtr, 0.016)
    opts.clicks[label] = nil
  end
  pcall(_G.script.windowAtr, 0.016)
  click(' time ###modeTime')
  click('Take camera###hold')
  eq(handle.grabbed, true)

  handle.sim.replayFrameMs = 50
  for _, at in ipairs({ { 150, 1 }, { 250, 2 }, { 600, 3 } }) do
    handle.sim.replayCurrentFrame = at[1]
    handle.tick(0.016)
    handle.tick(0.016)
    eq(handle.transform.position.x, at[2], 'frame ' .. at[1])
  end
  handle.restoreIo()
end)
