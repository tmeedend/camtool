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

test('loading stamps the current version and the legacy interpolation mode', function()
  local doc = data.load(rawFile)
  eq(doc.version, data.CURRENT_VERSION)
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

test('a flag stored as a number is read the way Python read it', function()
  -- CamTool 2 writes camera_use_tracking_point as 0 or 1, not as a boolean,
  -- and Lua calls 0 true where Python calls it false. Reading it with a plain
  -- `if` turned autofocus on for all 589 reference cameras instead of the 565
  -- that asked for it. Same family as the division by zero in CLAUDE.md.
  eq(data.isOn(0), false, 'the whole point')
  eq(data.isOn(1), true)
  eq(data.isOn(nil), false)
  eq(data.isOn(false), false)
  eq(data.isOn(true), true)
  eq(data.isOn(0.0), false, 'a float zero is still off')
  eq(data.isOn(-1), true, 'camera_use_specific_cam uses -1 for "no", so only '
    .. 'ask this about flags that mean 0 or 1')
end)

--------------------------------------------------------------------------
-- Version 2: a camera that keeps its identity
--------------------------------------------------------------------------

test('every camera of a migrated file comes out with an id', function()
  local doc = data.load(rawFile)
  eq(doc.version, 2)

  local seen = {}
  for _, listName in ipairs({ 'pos', 'time' }) do
    for i, camera in ipairs(doc[listName] or {}) do
      eq(type(camera.id), 'number', listName .. ' camera ' .. i .. ' has no id')
      eq(seen[camera.id], nil, 'id ' .. tostring(camera.id) .. ' handed out twice')
      seen[camera.id] = true
    end
  end
end)

test('the document remembers which id comes next', function()
  local doc = data.load(rawFile)
  eq(type(doc.next_camera_id), 'number')

  for _, listName in ipairs({ 'pos', 'time' }) do
    for _, camera in ipairs(doc[listName] or {}) do
      eq(camera.id < doc.next_camera_id, true, 'the counter is past every id')
    end
  end
end)

test('an id already in the file is kept, not reassigned', function()
  local doc = data.load({
    version = 1, interpolation_mode = 'fixed',
    pos = { { id = 9, camera_in = 0, keyframes = {} },
            { camera_in = 0.5, keyframes = {} } },
    time = {},
  })
  eq(doc.pos[1].id, 9)
  eq(doc.pos[2].id ~= 9, true, 'and the one without gets a free one')
  eq(doc.next_camera_id > 9, true)
end)

test('claiming an id moves the counter on', function()
  local doc = { next_camera_id = 7 }
  eq(data.claimCameraId(doc), 7)
  eq(data.claimCameraId(doc), 8)
  eq(doc.next_camera_id, 9)
end)

test('the counter does not go back when the last camera is deleted', function()
  -- The whole reason it lives on the document. Working the next id out from
  -- the cameras in hand would hand the deleted one's id to the next camera,
  -- and anything pointing at the old one would quietly follow the new.
  local doc = data.load({
    version = 1, interpolation_mode = 'fixed',
    pos = { { camera_in = 0, keyframes = {} }, { camera_in = 0.5, keyframes = {} } },
    time = {},
  })
  local highest = doc.pos[2].id
  table.remove(doc.pos, 2)

  eq(data.claimCameraId(doc) > highest, true, 'the id is not handed out again')
end)

test('claiming from nothing still answers a number', function()
  eq(data.claimCameraId(nil), 1)
  eq(data.claimCameraId({}), 1)
end)

test('a version 2 file missing ids is repaired rather than trusted', function()
  local doc = data.load({
    version = 2, interpolation_mode = 'fixed',
    pos = { { camera_in = 0, keyframes = {} } }, time = {},
  })
  eq(type(doc.pos[1].id), 'number')
end)

test('a camera shows its name, or its rank when it has none', function()
  -- The rank stays the fallback rather than being replaced: it is what a
  -- hotkey reaches for and what two people say to each other about a bug.
  eq(data.cameraLabel({ name = 'Eau Rouge' }, 14), 'Eau Rouge')
  eq(data.cameraLabel({}, 14), '14')
  eq(data.cameraLabel({ name = '' }, 14), '14', 'an empty name is no name')
  eq(data.cameraLabel(nil, 3), '3')
end)

test('a name survives being loaded and does not become anything else', function()
  local doc = data.load({
    version = 2, interpolation_mode = 'fixed',
    pos = { { id = 1, name = 'Bus Stop', camera_in = 0, keyframes = {} } },
    time = {},
  })
  eq(doc.pos[1].name, 'Bus Stop')
end)
