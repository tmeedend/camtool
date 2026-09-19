--[[
  Tests for core/serialise.lua.

  This is the code that overwrites files nobody can get back -- data/ is not
  in git and some of those camera sets are years old -- so the cases below
  are deliberately picky about shape rather than just checking it produces
  something JSON-shaped.
]]

local runner = require('tests/runner')
local serialise = require('core/serialise')

local test, eq = runner.test, runner.eq

---Strip the layout out, so a test can say what it means without counting
---spaces. Shape is what matters here; formatting is checked once, separately.
local function dense(text)
  return (text:gsub('%s+', ''))
end

test('the simple types come out as themselves', function()
  eq(dense(serialise.toJson({ a = 1 })), '{"a":1}')
  eq(dense(serialise.toJson({ a = true, b = false })), '{"a":true,"b":false}')
  eq(dense(serialise.toJson({ a = 'hi' })), '{"a":"hi"}')
end)

test('keys come out sorted, so two saves of one file match', function()
  -- Lua gives no order at all, so without this a save would shuffle the file
  -- and every diff would be unreadable.
  local text = dense(serialise.toJson({ zebra = 1, apple = 2, mango = 3 }))
  eq(text, '{"apple":2,"mango":3,"zebra":1}')
end)

test('an empty camera list stays a list, and an empty keyframe an object', function()
  -- Lua spells both {}. Getting this wrong writes a file whose shape is
  -- wrong in a way nothing notices until it is loaded back.
  eq(dense(serialise.toJson({ pos = {}, time = {} })), '{"pos":[],"time":[]}')
  eq(dense(serialise.toJson({ interpolation = {} })), '{"interpolation":{}}')
  eq(dense(serialise.toJson({ keyframes = {} })), '{"keyframes":[]}')
  eq(dense(serialise.toJson({ the_x = {}, loc_x = {} })),
    '{"loc_x":[],"the_x":[]}')
end)

test('a list with things in it is a list whatever it is called', function()
  eq(dense(serialise.toJson({ whatever = { 1, 2, 3 } })),
    '{"whatever":[1,2,3]}')
end)

test('a keyframe writes only what it sets', function()
  -- Absent, not null. CamTool 2 filters its nils out on save for the same
  -- reason, which is why real files look sparse.
  local kf = { keyframe = 0.5, interpolation = { camera_fov = 30 } }
  eq(dense(serialise.toJson(kf)),
    '{"interpolation":{"camera_fov":30},"keyframe":0.5}')
end)

test('numbers survive the trip', function()
  -- A position written short is a camera that has quietly moved.
  local text = serialise.toJson({ x = 1 / 3 })
  eq(text:find('0.3333333333333333', 1, true) ~= nil, true, text)

  -- Whole numbers stay whole, the way CamTool 2 wrote slots and indices.
  eq(dense(serialise.toJson({ slot = 3 })), '{"slot":3}')
  eq(dense(serialise.toJson({ x = -0.1 })), '{"x":-0.10000000000000001}')
end)

test('a value that cannot be written stops the save', function()
  -- Lua answers a division by zero with inf instead of raising, so an
  -- infinity can reach here from a calculation. Writing it would produce a
  -- file no parser accepts -- better to refuse than to corrupt.
  local ok = pcall(serialise.toJson, { x = 1 / 0 })
  eq(ok, false)
  ok = pcall(serialise.toJson, { x = 0 / 0 })
  eq(ok, false)
end)

test('quotes and backslashes in a name do not break the file', function()
  local text = serialise.toJson({ name = 'a "quoted" \\ name' })
  eq(text:find('\\"quoted\\"', 1, true) ~= nil, true, text)
  eq(text:find('\\\\', 1, true) ~= nil, true, text)
end)

test('the output is indented and ends with a newline', function()
  local text = serialise.toJson({ pos = { { camera_in = 0.5 } } })
  eq(text:sub(-1), '\n')
  eq(text:find('\n  "pos"', 1, true) ~= nil, true, text)
end)

test('a whole migrated document comes back out', function()
  local dataModule = require('core/data')
  local doc = dataModule.load(require('tests/fixtures/camera_file_lap'))
  local text = serialise.toJson(doc)

  -- The things that have to be there for it to be loadable again.
  eq(text:find('"version": 1', 1, true) ~= nil, true)
  eq(text:find('"interpolation_mode"', 1, true) ~= nil, true)
  eq(text:find('"pos": [', 1, true) ~= nil, true)
  eq(text:find('"keyframes"', 1, true) ~= nil, true)
  eq(text:find('"track_spline"', 1, true) ~= nil, true)
  eq(#text > 10000, true, 'a real file is not a few hundred bytes')

  -- And nothing Lua-shaped leaked through.
  eq(text:find('nil', 1, true), nil)
  eq(text:find('inf', 1, true), nil)
end)

--------------------------------------------------------------------------------
-- Writing the file
--------------------------------------------------------------------------------

local fakes = require('tests/fakes/csp')
local storage = require('adapters/storage')

test('saving writes the document where the file came from', function()
  local handle = fakes.install({})
  local doc = require('core/data').load(require('tests/fixtures/camera_file_lap'))

  local ok, err = storage.saveCameraFile('fake_track_-cameras.json', doc)
  eq(ok, true, tostring(err))

  local written = handle.written['apps/lua/CamTool3/data/fake_track_-cameras.json']
  eq(type(written), 'string', 'nothing was written')
  eq(written:find('"pos": [', 1, true) ~= nil, true)

  handle.restoreIo()
end)

test('the first overwrite keeps a copy of what was there', function()
  -- data/ is not in git and some of those files are years old, so the state
  -- before CamTool 3 ever touched them is worth one copy.
  local path = 'apps/lua/CamTool3/data/fake_track_-cameras.json'
  local handle = fakes.install({ existing = { [path] = true } })
  local doc = require('core/data').load(require('tests/fixtures/camera_file_lap'))

  storage.saveCameraFile('fake_track_-cameras.json', doc)
  eq(#handle.copied, 1, 'no backup was taken')
  eq(handle.copied[1][2], path .. storage.BACKUP_SUFFIX)

  handle.restoreIo()
end)

test('a second save does not overwrite the first backup', function()
  local path = 'apps/lua/CamTool3/data/fake_track_-cameras.json'
  local handle = fakes.install({
    existing = { [path] = true, [path .. storage.BACKUP_SUFFIX] = true },
  })
  local doc = require('core/data').load(require('tests/fixtures/camera_file_lap'))

  storage.saveCameraFile('fake_track_-cameras.json', doc)
  eq(#handle.copied, 0, 'the copy is of what was there first, not last')

  handle.restoreIo()
end)

test('a document with an infinity in it is refused, not written', function()
  -- Lua answers a division by zero with inf where Python raised, so one can
  -- reach a camera through a calculation. Writing it makes a file no parser
  -- reads; refusing keeps the last good one on disk.
  local handle = fakes.install({})
  local doc = require('core/data').load(require('tests/fixtures/camera_file_lap'))
  doc.pos[1].camera_in = 1 / 0

  local ok, err = storage.saveCameraFile('fake_track_-cameras.json', doc)
  eq(ok, false)
  eq(type(err), 'string')
  eq(next(handle.written), nil, 'nothing should have been written at all')

  handle.restoreIo()
end)

test('a failed write is reported rather than assumed', function()
  local handle = fakes.install({ saveFails = true })
  local doc = require('core/data').load(require('tests/fixtures/camera_file_lap'))

  local ok, err = storage.saveCameraFile('fake_track_-cameras.json', doc)
  eq(ok, false)
  eq(type(err), 'string')

  handle.restoreIo()
end)

test('restoring the fake really puts the filesystem back', function()
  -- It did not, for a while: restoreIo closed over locals declared after it,
  -- so it set io.save to nil. Nothing noticed because no test wrote a file
  -- after restoring one.
  local before = io.save
  local handle = fakes.install({})
  handle.restoreIo()
  eq(io.save, before)
end)

test('saving never writes into CamTool 2 folder', function()
  -- The whole reason there are two folders. A CamTool 2 file opened here and
  -- saved becomes a copy in ours; the original stays exactly as CamTool 2
  -- left it, and CamTool 2 never sees a file its loader would choke on.
  local handle = fakes.install({})
  local doc = require('core/data').load(require('tests/fixtures/camera_file_lap'))

  storage.saveCameraFile('anything.json', doc)

  for path in pairs(handle.written) do
    eq(path:sub(1, #storage.CAMTOOL3_DATA_DIR), storage.CAMTOOL3_DATA_DIR,
      'wrote outside CamTool 3: ' .. path)
  end
  eq(next(handle.written) ~= nil, true, 'nothing was written at all')

  handle.restoreIo()
end)

test('both folders are listed, ours first', function()
  local handle = fakes.install({
    ownFiles = { 'fake_track_-mine.json' },
    files = { 'fake_track_-cameras.json' },
  })

  local list = storage.listCameraFiles()
  eq(#list, 2)
  eq(list[1].name, 'fake_track_-mine.json')
  eq(list[1].own, true, 'a file we saved comes first')
  eq(list[2].own, false)

  handle.restoreIo()
end)
