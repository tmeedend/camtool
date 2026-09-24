--[[
  Tests for adapters/settings.lua and Load on startup.
]]

local runner = require('tests/runner')
local fakes = require('tests/fakes/csp')
local settings = require('adapters/settings')

local test, eq = runner.test, runner.eq

test('ac.storage is called even though it is a table', function()
  -- The SDK declares it as a table with a call: type() says table, and a
  -- check for 'function' would keep every setting for the session only.
  local handle = fakes.install({})
  local real = ac.storage
  local calls = 0
  ac.storage = setmetatable({}, { __call = function(_, key, default)
    calls = calls + 1
    return real(key, default)
  end })
  settings.set('loadOnStartup', false)
  eq(calls > 0, true)
  eq(handle.stored['camtool3.loadOnStartup'], false)
  handle.restoreIo()
end)

test('Load on startup is on by default, as in CamTool 2', function()
  local handle = fakes.install({})
  eq(settings.loadOnStartup(), true)
  handle.restoreIo()
end)

test('the last file is remembered per track and found again in the list', function()
  local handle = fakes.install({})
  local files = {
    { name = 'a.json', own = false }, { name = 'b.json', own = true },
    { name = 'b.json', own = false },
  }
  settings.setLastFile('spa_-', files[3])
  eq(settings.findFile(files, settings.lastFile('spa_-')), 3, 'the CamTool 2 one')
  settings.setLastFile('spa_-', files[2])
  eq(settings.findFile(files, settings.lastFile('spa_-')), 2, 'the CamTool 3 one')
  eq(settings.lastFile('monza_-'), nil, 'another track has its own')
  eq(settings.findFile(files, 'own:gone.json'), nil)
  handle.restoreIo()
end)

---Open the ATR window once on a fresh app, with one real file for the track.
local function openPanel(opts)
  opts.cameraFile = opts.cameraFile or require('tests/fixtures/camera_file_v0')
  local handle = fakes.install(opts)
  require('ui/atr').cancelEditing()
  require('ui/band').reset()
  assert(loadfile('CamTool3.lua'))()
  pcall(_G.script.windowAtr, 0.016)
  return handle
end

---Did the app load a file? It says so in its log.
local function loaded(handle)
  for i = 1, #handle.logs do
    if handle.logs[i]:find('] loaded ', 1, true) then return true end
  end
  return false
end

test('the first time the panel opens on a track, a file is loaded', function()
  local handle = openPanel({})
  eq(loaded(handle), true, 'a file is open without clicking anything')
  handle.restoreIo()
end)

test('with Load on startup off, nothing is opened', function()
  local handle = openPanel({ stored = { ['camtool3.loadOnStartup'] = false } })
  eq(loaded(handle), false)
  handle.restoreIo()
end)

test('it happens once: closing a file does not bring it back', function()
  local handle = openPanel({})
  local count = 0
  for _ = 1, 5 do pcall(_G.script.windowAtr, 0.016) end
  for i = 1, #handle.logs do
    if handle.logs[i]:find('] loaded ', 1, true) then count = count + 1 end
  end
  eq(count, 1)
  handle.restoreIo()
end)

test('opening a file remembers it for the next session on this track', function()
  local handle = openPanel({})
  local remembered = handle.stored['camtool3.lastFile.fake_track_-']
  eq(type(remembered) == 'string' and remembered ~= '', true)
  handle.restoreIo()
end)

local LOAD_ON_STARTUP = 'Open the last file of the track when the app starts'
  .. '###loadOnStartup'

test('the keys panel turns Load on startup off, and it stays off', function()
  local opts = { clicks = {} }
  local handle = openPanel(opts)

  opts.clicks[' keys ###showKeys'] = true
  pcall(_G.script.windowAtr, 0.016)
  opts.clicks[' keys ###showKeys'] = nil

  opts.clicks[LOAD_ON_STARTUP] = true
  pcall(_G.script.windowAtr, 0.016)
  opts.clicks[LOAD_ON_STARTUP] = nil

  eq(handle.stored['camtool3.loadOnStartup'], false, 'written where CSP keeps it')
  handle.restoreIo()
end)

--------------------------------------------------------------------------------
-- Deleting a file
--------------------------------------------------------------------------------

local storage = require('adapters/storage')
local MINE = 'fake_track_-mine.json'
local MINE_PATH = storage.CAMTOOL3_DATA_DIR .. '/' .. MINE

test('only CamTool 3 files go to the Recycle Bin, and only by name', function()
  local handle = fakes.install({ existing = { [MINE_PATH] = true }, ownFiles = { MINE } })
  local ok = storage.deleteCameraFile({ name = 'fake_track_-cameras.json', own = false })
  eq(ok, false, 'a CamTool 2 file is never touched')
  eq(storage.deleteCameraFile({ name = '../x.json', own = true }), false, 'no paths')
  eq(storage.deleteCameraFile({ name = MINE, own = true }), true)
  eq(handle.recycled[1], MINE_PATH, 'recycled, not deleted')
  eq(#handle.recycled, 1)
  handle.restoreIo()
end)

test('Delete asks twice, then the file leaves the list', function()
  local opts = { clicks = {}, existing = { [MINE_PATH] = true }, ownFiles = { MINE } }
  local handle = openPanel(opts)

  local function offered()
    handle.buttons = {}
    pcall(_G.script.windowAtr, 0.016)
    for i = 1, #handle.buttons do
      if tostring(handle.buttons[i]):find('###deleteFile', 1, true) then return true end
    end
    return false
  end
  eq(offered(), true, 'on our own file')

  opts.clicks['Delete###deleteFile'] = true
  pcall(_G.script.windowAtr, 0.016)
  opts.clicks['Delete###deleteFile'] = nil
  eq(#handle.recycled, 0, 'the first click only arms it')

  opts.clicks['Delete?###deleteFile'] = true
  pcall(_G.script.windowAtr, 0.016)
  opts.clicks['Delete?###deleteFile'] = nil
  eq(handle.recycled[1], MINE_PATH, 'the second one recycles it')

  eq(offered(), false, 'and the arrows are now on a CamTool 2 file, which cannot go')
  handle.restoreIo()
end)
