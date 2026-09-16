--[[
  Tests for core/evaluate.lua: parameter-to-interpolator mapping, series
  building, and active camera selection.

  The mapping assertions are deliberately literal. They were extracted from
  InterpolateFrame.py, and a future "tidy-up" that makes them consistent would
  change how every existing camera moves.
]]

local runner = require('tests/runner')
local evaluate = require('core/evaluate')
local interpolation = require('core/interpolation')
local data = require('core/data')
local rawFile = require('tests/fixtures/camera_file_v0')

local test, eq, near = runner.test, runner.eq, runner.near

test('position and rotation go through the bezier', function()
  for _, p in ipairs({ 'loc_x', 'loc_y', 'loc_z', 'rot_x', 'rot_y', 'rot_z' }) do
    eq(evaluate.interpolatorFor(p), evaluate.BEZIER, p)
  end
end)

test('FOV and shake go through the sine', function()
  eq(evaluate.interpolatorFor('camera_fov'), evaluate.SIN)
  eq(evaluate.interpolatorFor('camera_shake_strength'), evaluate.SIN)
end)

test('the tracking offsets split between the two interpolators', function()
  -- The asymmetry CLAUDE.md's summary glosses over. Straight from the legacy.
  eq(evaluate.interpolatorFor('tracking_offset'), evaluate.BEZIER,
    'the plain offset uses the bezier')
  eq(evaluate.interpolatorFor('tracking_offset_heading'), evaluate.SIN)
  eq(evaluate.interpolatorFor('tracking_offset_pitch'), evaluate.SIN)
end)

test('four parameters are stored but never interpolated', function()
  -- camera_offset_shake_strength being camera-level while camera_shake_strength
  -- is keyframed is concrete evidence for issue #25.
  eq(evaluate.interpolatorFor('camera_offset_shake_strength'), evaluate.CAMERA_LEVEL)
  eq(evaluate.interpolatorFor('camera_shake_strength'), evaluate.SIN,
    'the plain shake IS keyframable, unlike the offset shake')
  eq(evaluate.interpolatorFor('spline_affect_pitch'), evaluate.CAMERA_LEVEL)
  eq(evaluate.interpolatorFor('spline_affect_roll'), evaluate.CAMERA_LEVEL)
  eq(evaluate.interpolatorFor('spline_affect_heading'), evaluate.CAMERA_LEVEL)
end)

test('an unknown parameter has no interpolator', function()
  eq(evaluate.interpolatorFor('not_a_real_parameter'), nil)
end)

test('seriesFor pairs each value with its own keyframe position', function()
  local camera = {
    keyframes = {
      { keyframe = 0.10, interpolation = { loc_x = 1, camera_fov = 20 } },
      { keyframe = 0.20, interpolation = { camera_fov = 30 } },
      { keyframe = 0.30, interpolation = { loc_x = 3 } },
    },
  }

  -- loc_x is absent from the middle keyframe, so it must pair with 0.10 and
  -- 0.30 -- not with the first two positions.
  local x, y = evaluate.seriesFor(camera, 'loc_x')
  eq(#x, 2)
  eq(x[1], 0.10); eq(y[1], 1)
  eq(x[2], 0.30); eq(y[2], 3)

  local fx, fy = evaluate.seriesFor(camera, 'camera_fov')
  eq(#fx, 2)
  eq(fx[1], 0.10); eq(fy[1], 20)
  eq(fx[2], 0.20); eq(fy[2], 30)
end)

test('seriesFor returns nothing for a parameter the camera never keyframes', function()
  local camera = { keyframes = { { keyframe = 0.5, interpolation = { loc_x = 1 } } } }
  local x, y = evaluate.seriesFor(camera, 'rot_z')
  eq(#x, 0)
  eq(#y, 0)
end)

test('seriesFor survives a camera with no keyframes at all', function()
  eq(#(select(1, evaluate.seriesFor({}, 'loc_x'))), 0)
  eq(#(select(1, evaluate.seriesFor(nil, 'loc_x'))), 0)
end)

test('parameter routes through the interpolator the legacy uses', function()
  local camera = {
    keyframes = {
      { keyframe = 0.0, interpolation = { loc_x = 0, camera_fov = 10 } },
      { keyframe = 0.5, interpolation = { loc_x = 10, camera_fov = 20 } },
      { keyframe = 1.0, interpolation = { loc_x = -5, camera_fov = 30 } },
    },
  }
  local x = { 0.0, 0.5, 1.0 }

  near(evaluate.parameter(camera, 'loc_x', 0.3),
    interpolation.interpolate(0.3, x, { 0, 10, -5 }), 1e-12)

  near(evaluate.parameter(camera, 'camera_fov', 0.3),
    interpolation.interpolate_sin(0.3, x, { 10, 20, 30 }), 1e-12)
end)

test('parameter is nil when unkeyframed or camera-level', function()
  local camera = { keyframes = { { keyframe = 0.5, interpolation = { loc_x = 1 } } } }
  eq(evaluate.parameter(camera, 'rot_z', 0.5), nil, 'not keyframed here')
  eq(evaluate.parameter(camera, 'camera_offset_shake_strength', 0.5), nil,
    'camera-level parameters are never interpolated')
  eq(evaluate.parameter(camera, 'nonsense', 0.5), nil)
end)

test('all returns exactly the parameters the camera keyframes', function()
  local camera = {
    keyframes = {
      { keyframe = 0.0, interpolation = { loc_x = 0, camera_fov = 10 } },
      { keyframe = 1.0, interpolation = { loc_x = 10, camera_fov = 30 } },
    },
  }
  local values = evaluate.all(camera, 0.5)

  local count = 0
  for _ in pairs(values) do count = count + 1 end
  eq(count, 2)
  eq(type(values.loc_x), 'number')
  eq(type(values.camera_fov), 'number')
  eq(values.rot_z, nil)
end)

test('all works on a real migrated camera', function()
  local doc = data.load(rawFile)
  local camera = doc.pos[1]
  local values = evaluate.all(camera, camera.camera_in + 0.001)

  eq(type(values.loc_x), 'number', 'a real camera must yield a position')
  -- Post-migration the FOV is in degrees, so it must look like a lens.
  if values.camera_fov ~= nil and (values.camera_fov <= 0 or values.camera_fov > 180) then
    error('camera_fov evaluated to ' .. values.camera_fov .. ' degrees', 2)
  end
end)

--------------------------------------------------------------------------------
-- Active camera selection
--------------------------------------------------------------------------------

local function camerasAt(...)
  local out = {}
  for i, v in ipairs({ ... }) do out[i] = { camera_in = v } end
  return out
end

test('the active camera is the last one started', function()
  local cams = camerasAt(0.0, 0.25, 0.60)
  eq(evaluate.activeCameraIndex(cams, 0.0), 1)
  eq(evaluate.activeCameraIndex(cams, 0.10), 1)
  eq(evaluate.activeCameraIndex(cams, 0.25), 2)
  eq(evaluate.activeCameraIndex(cams, 0.59), 2)
  eq(evaluate.activeCameraIndex(cams, 0.60), 3)
  eq(evaluate.activeCameraIndex(cams, 0.99), 3)
end)

test('before the first camera you are still on the last one', function()
  -- The lap wrap: the camera covering the end of the lap stays live across the
  -- start line, until the first camera's activation point. This is the walk
  -- that issue #23 lives in.
  local cams = camerasAt(0.10, 0.50, 0.80)
  eq(evaluate.activeCameraIndex(cams, 0.05), 3)
  eq(evaluate.activeCameraIndex(cams, 0.0), 3)
end)

test('pit cameras are skipped unless asked for', function()
  local cams = {
    { camera_in = 0.0 },
    { camera_in = 0.30, camera_pit = true },
    { camera_in = 0.60 },
  }
  -- On track, the pit camera at 0.30 must not take over.
  eq(evaluate.activeCameraIndex(cams, 0.40), 1)
  eq(evaluate.activeCameraIndex(cams, 0.70), 3)
  -- Asking for pit cameras finds only the flagged one.
  eq(evaluate.activeCameraIndex(cams, 0.40, true), 2)
end)

test('selection copes with empty and all-pit lists', function()
  eq(evaluate.activeCameraIndex({}, 0.5), nil)
  eq(evaluate.activeCameraIndex(nil, 0.5), nil)
  eq(evaluate.activeCameraIndex({ { camera_in = 0.1, camera_pit = true } }, 0.5), nil,
    'no on-track camera exists')
end)

test('selection works on the real file', function()
  local doc = data.load(rawFile)
  local index = evaluate.activeCameraIndex(doc.pos, 0.5)
  eq(type(index), 'number')
  if index < 1 or index > #doc.pos then
    error('index ' .. index .. ' is out of range', 2)
  end
end)
