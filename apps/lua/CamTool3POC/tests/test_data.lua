--[[
  Tests for core/data.lua, run against a real CamTool 2 camera file
  (ks_red_bull_ring_layout_gp-init.json, trimmed to two cameras per mode).

  The hard requirement in CLAUDE.md is that existing user files stay loadable,
  so the fixture is real data rather than something invented to pass.
]]

local runner = require('tests/runner')
local data = require('core/data')
local fov = require('core/fov')
local rawFile = require('tests/fixtures/camera_file_v0')

local test, eq, near = runner.test, runner.eq, runner.near

---Collect every keyframe camera_fov in a document, in walk order.
local function collectFov(doc)
  local out = {}
  for _, listName in ipairs({ 'time', 'pos' }) do
    local list = doc[listName]
    if type(list) == 'table' then
      for c = 1, #list do
        local keyframes = list[c].keyframes
        if type(keyframes) == 'table' then
          for k = 1, #keyframes do
            local interp = keyframes[k].interpolation
            if interp and type(interp.camera_fov) == 'number' then
              out[#out + 1] = interp.camera_fov
            end
          end
        end
      end
    end
  end
  return out
end

test('a CamTool 2 file reports as version 0', function()
  eq(data.versionOf(rawFile), 0)
  eq(rawFile.version, nil, 'the fixture must not already carry a version')
end)

test('the fixture is a real camera file, not a stub', function()
  eq(type(rawFile.pos), 'table')
  eq(type(rawFile.track_spline), 'table')
  if data.cameraCount(rawFile) < 2 then
    error('expected at least 2 cameras in the fixture', 2)
  end
  if #collectFov(rawFile) < 2 then
    error('expected at least 2 keyframed FOV values in the fixture', 2)
  end
end)

test('loading stamps version 1 and the legacy interpolation mode', function()
  local doc = data.load(rawFile)
  eq(doc.version, 1)
  -- The whole point: new encoding, old maths. Anything else would change
  -- footage that has already been cut.
  eq(doc.interpolation_mode, data.MODE_LEGACY)
end)

test('camera_fov is decoded to degrees, everything else passes through', function()
  local before = collectFov(rawFile)
  local doc = data.load(rawFile)
  local after = collectFov(doc)

  eq(#after, #before, 'migration must not add or drop keyframes')

  for i = 1, #before do
    near(after[i], fov.decode(before[i]), 1e-12,
      'fov #' .. i .. ' must match the legacy decode exactly')
    -- Sanity: a plausible lens, not a stored ratio. Across all 32 reference
    -- files these land between 0.5 and 55.4 degrees.
    if after[i] <= 0 or after[i] > 180 then
      error(string.format('fov #%d decoded to %g degrees, which is not a lens',
        i, after[i]), 2)
    end
  end

  -- A non-encoded field must be untouched.
  eq(doc.pos[1].camera_in, rawFile.pos[1].camera_in)
  eq(doc.pos[1].keyframes[1].interpolation.loc_x,
    rawFile.pos[1].keyframes[1].interpolation.loc_x)
end)

test('loading never mutates the caller\'s table', function()
  local before = collectFov(rawFile)
  data.load(rawFile)
  data.load(rawFile)
  local after = collectFov(rawFile)

  eq(rawFile.version, nil, 'the input must not gain a version field')
  for i = 1, #before do
    eq(after[i], before[i], 'input fov #' .. i .. ' must be untouched')
  end
end)

test('loading an already migrated document does not decode twice', function()
  -- The failure this guards is nasty and silent: a second decode turns a
  -- sensible lens into nonsense, and nothing would complain.
  local once = data.load(rawFile)
  local twice = data.load(once)

  local a, b = collectFov(once), collectFov(twice)
  eq(#a, #b)
  for i = 1, #a do
    eq(b[i], a[i], 'fov #' .. i .. ' must survive a second load unchanged')
  end
  eq(twice.interpolation_mode, data.MODE_LEGACY, 'mode must be carried through')
end)

test('a version 1 file with no mode gets the corrected maths', function()
  local doc = data.load({ version = 1, pos = {}, time = {} })
  eq(doc.interpolation_mode, data.MODE_FIXED)
end)

test('an explicit mode is preserved, not overwritten', function()
  local doc = data.load({ version = 1, interpolation_mode = 'legacy', pos = {}, time = {} })
  eq(doc.interpolation_mode, data.MODE_LEGACY)
end)

test('a file from a newer build is refused rather than guessed at', function()
  local ok = pcall(data.load, { version = 99 })
  eq(ok, false, 'loading version 99 must raise')
end)

test('a non-table input is refused', function()
  eq(pcall(data.load, 'not a document'), false)
  eq(pcall(data.load, nil), false)
end)
