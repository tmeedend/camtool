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

  -- The sine easing, but run over the stored form of the value rather than
  -- over degrees. See the camera_fov test further down for why.
  local fov = require('core/fov')
  near(evaluate.parameter(camera, 'camera_fov', 0.3),
    fov.decode(interpolation.interpolate_sin(0.3, x,
      { fov.encode(10), fov.encode(20), fov.encode(30) })), 1e-12)
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

--------------------------------------------------------------------------------
-- The camera that spans the start line -- issue #23
--------------------------------------------------------------------------------

test('isLastCamera finds the last of its kind', function()
  local cams = { { camera_in = 0 }, { camera_in = 0.5 }, { camera_in = 0.9 } }
  eq(evaluate.isLastCamera(cams, 3), true)
  eq(evaluate.isLastCamera(cams, 2), false)
  eq(evaluate.isLastCamera(cams, nil), false)

  -- A trailing pit camera must not steal the title from the last on-track one.
  local mixed = { { camera_in = 0 }, { camera_in = 0.9 }, { camera_in = 0.95, camera_pit = true } }
  eq(evaluate.isLastCamera(mixed, 2), true, 'last on track')
  eq(evaluate.isLastCamera(mixed, 3), false)
  eq(evaluate.isLastCamera(mixed, 3, true), true, 'last pit camera')
end)

test('wrapped keyframes are detected by their negative positions', function()
  -- Red Bull Ring's last camera, stored across the line.
  eq(evaluate.hasWrappedKeyframes({ keyframes = {
    { keyframe = -0.096 }, { keyframe = 0.002 }, { keyframe = 0.08 },
  } }), true)

  -- le_lancone's last camera, which does not cross it.
  eq(evaluate.hasWrappedKeyframes({ keyframes = {
    { keyframe = 0.947 }, { keyframe = 0.962 }, { keyframe = 0.964 },
  } }), false)

  eq(evaluate.hasWrappedKeyframes({}), false)
  eq(evaluate.hasWrappedKeyframes(nil), false)
end)

test('only the last camera is ever wrapped', function()
  local wrapped = { keyframes = { { keyframe = -0.1 }, { keyframe = 0.05 } } }
  eq(evaluate.queryPosition(0.9, wrapped, false, 5, false), 0.9, 'not the last camera')
  eq(evaluate.queryPosition(0.9, wrapped, true, 1, false), 0.9, 'a lone camera never wraps')
  eq(evaluate.queryPosition(0.3, wrapped, true, 5, false), 0.3, 'below 0.5 stays put')
end)

test('a last camera with wrapped keyframes reads a lap back', function()
  local wrapped = { keyframes = { { keyframe = -0.096 }, { keyframe = 0.08 } } }
  near(evaluate.queryPosition(0.9, wrapped, true, 5, false), -0.1, 1e-12)
  near(evaluate.queryPosition(0.9, wrapped, true, 5, true), -0.1, 1e-12,
    'legacy agrees when the keyframes really are wrapped')
end)

test('#23: legacy wraps a last camera whose keyframes are not stored wrapped', function()
  -- le_lancone's last camera. The legacy shifts regardless, so the query lands
  -- before every keyframe and interpolate returns the first one: the camera
  -- freezes for its whole span. Fixed mode leaves it alone.
  local plain = { keyframes = {
    { keyframe = 0.947 }, { keyframe = 0.962 }, { keyframe = 0.964 },
  } }

  near(evaluate.queryPosition(0.95, plain, true, 5, true), -0.05, 1e-12,
    'legacy shifts it out of range')
  near(evaluate.queryPosition(0.95, plain, true, 5, false), 0.95, 1e-12,
    'fixed mode keeps it where the keyframes are')
end)

test('#23: the frozen camera is visible end to end', function()
  -- Not just the query: what the camera actually does. In legacy mode every
  -- position across the span evaluates to the same value, which is the bug as
  -- it looks on screen.
  local camera = {
    camera_in = 0.9466,
    keyframes = {
      { keyframe = 0.947, interpolation = { loc_x = 100 } },
      { keyframe = 0.962, interpolation = { loc_x = 200 } },
      { keyframe = 0.964, interpolation = { loc_x = 300 } },
    },
  }

  local legacyValues, fixedValues = {}, {}
  for _, at in ipairs({ 0.948, 0.955, 0.960, 0.963 }) do
    legacyValues[#legacyValues + 1] =
      evaluate.parameter(camera, 'loc_x', evaluate.queryPosition(at, camera, true, 5, true))
    fixedValues[#fixedValues + 1] =
      evaluate.parameter(camera, 'loc_x', evaluate.queryPosition(at, camera, true, 5, false))
  end

  for i = 2, #legacyValues do
    eq(legacyValues[i], legacyValues[1], 'legacy is stuck on one value')
  end
  eq(legacyValues[1], 100, 'and that value is the first keyframe')

  local moved = false
  for i = 2, #fixedValues do
    if math.abs(fixedValues[i] - fixedValues[1]) > 1e-9 then moved = true end
  end
  eq(moved, true, 'fixed mode actually moves the camera')
end)

test('camera_fov is interpolated in the space the file stores it in', function()
  -- CamTool 2 runs the interpolator over 1/(fov+15) and converts the result to
  -- degrees. Migration converts at load time, so evaluate has to undo that and
  -- redo it, or every zoom follows a different curve -- equal at the
  -- keyframes and up to 3.6 degrees apart between them, measured against a
  -- recorded Silverstone lap.
  local fov = require('core/fov')
  local interpolation = require('core/interpolation')

  local a, b = 7.5, 2.0
  local camera = {
    keyframes = {
      { keyframe = 0.2, interpolation = { camera_fov = a } },
      { keyframe = 0.4, interpolation = { camera_fov = b } },
    },
  }

  local at = 0.3
  local got = evaluate.parameter(camera, 'camera_fov', at)

  local legacy = fov.decode(interpolation.interpolate_sin(
    at, { 0.2, 0.4 }, { fov.encode(a), fov.encode(b) }))
  local naive = interpolation.interpolate_sin(at, { 0.2, 0.4 }, { a, b })

  near(got, legacy, 1e-12, 'must follow the legacy curve')
  eq(math.abs(got - naive) > 0.1, true, string.format(
    'and must differ from interpolating degrees, which gives %.4f against %.4f',
    naive, got))

  -- The keyframes themselves are where the two agree, so they prove nothing
  -- on their own -- but a conversion done twice would show up here.
  near(evaluate.parameter(camera, 'camera_fov', 0.2), a, 1e-12)
  near(evaluate.parameter(camera, 'camera_fov', 0.4), b, 1e-12)
end)
