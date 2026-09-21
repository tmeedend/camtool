--[[
  Tests for core/filename.lua.

  The field these go through accepts anything, and the thing it produces is a
  file on disk. Every case below is something a person could reasonably type
  into a box asking for a name -- including, first among them, the whole file
  name they had been looking at a second earlier.
]]

local runner = require('tests/runner')
local filename = require('core/filename')

local test, eq = runner.test, runner.eq

local SPA = 'spa_-'
local LANCONE = 'le_lancone_-'

--------------------------------------------------------------------------
-- Taking it apart
--------------------------------------------------------------------------

test('the name is what is left once the machine has had its share', function()
  eq(filename.display('spa_-theo.json', SPA), 'theo')
  eq(filename.display('le_lancone_-lancia.json', LANCONE), 'lancia')
end)

test('a file from another track keeps its prefix, which is the point', function()
  -- Shown while listing every track's files. Stripping a prefix that is not
  -- this track's would turn two files into the same name on screen. The
  -- extension still goes: that is noise whoever the file belongs to.
  eq(filename.display('monza_-lesmo.json', SPA), 'monza_-lesmo')
end)

test('only a trailing .json is an extension', function()
  eq(filename.display('spa_-notes.json backup.json', SPA), 'notes.json backup')
end)

test('a name that is all prefix comes back empty rather than wrong', function()
  eq(filename.display('spa_-.json', SPA), '')
end)

test('nothing in, nothing out', function()
  eq(filename.display(nil, SPA), '')
  eq(filename.display('theo.json', nil), 'theo')
end)

--------------------------------------------------------------------------
-- Putting it back together
--------------------------------------------------------------------------

test('a plain name becomes a file of this track', function()
  eq(filename.build('theo', SPA), 'spa_-theo.json')
end)

test('space either side is not part of a name', function()
  eq(filename.build('   theo  ', SPA), 'spa_-theo.json')
end)

test('a name typed out in full is the same file, not a doubled one', function()
  -- The old field showed the whole thing, so this is what anyone who had
  -- looked at it would type back.
  eq(filename.build('spa_-theo.json', SPA), 'spa_-theo.json')
  eq(filename.build('spa_-theo', SPA), 'spa_-theo.json')
  eq(filename.build('theo.json', SPA), 'spa_-theo.json')
end)

test('a prefix typed twice is still one prefix', function()
  eq(filename.build('spa_-spa_-theo', SPA), 'spa_-theo.json')
end)

test('an extension typed twice is still one extension', function()
  eq(filename.build('theo.json.json', SPA), 'spa_-theo.json')
end)

test('a character no file name may hold is dropped, not refused', function()
  -- A stray slash is a typo, and refusing the whole name over one costs more
  -- than quietly leaving it out.
  eq(filename.build('spa/theo', SPA), 'spa_-spatheo.json')
  eq(filename.build('a:b*c?d"e<f>g|h', SPA), 'spa_-abcdefgh.json')
end)

test('a name cannot climb out of its folder', function()
  eq(filename.build('../../secret', SPA), 'spa_-....secret.json')
  eq(filename.build('..\\..\\secret', SPA), 'spa_-....secret.json')
end)

test('a trailing dot is not kept', function()
  -- Windows strips it when it creates the file, so the app would write one
  -- name and then look for another.
  eq(filename.build('theo.', SPA), 'spa_-theo.json')
  eq(filename.build('theo...', SPA), 'spa_-theo.json')
end)

test('a name with nothing in it is refused, with a reason', function()
  local name, why = filename.build('', SPA)
  eq(name, nil)
  eq(type(why), 'string')

  eq(filename.build('   ', SPA), nil)
  eq(filename.build('.json', SPA), nil, 'an extension is not a name')
  eq(filename.build('spa_-', SPA), nil, 'nor is a prefix')
  eq(filename.build('spa_-.json', SPA), nil, 'nor both together')
  eq(filename.build('///', SPA), nil)
  eq(filename.build(nil, SPA), nil)
end)

test('a name keeps the dots and dashes inside it', function()
  eq(filename.build('spa 2024 - v2.1', SPA), 'spa_-spa 2024 - v2.1.json')
end)

test('what is built comes back out as what was typed', function()
  for _, typed in ipairs({ 'theo', 'Eau Rouge', 'set 2', 'a-b-c' }) do
    eq(filename.display(filename.build(typed, SPA), SPA), typed,
      'the round trip changed ' .. typed)
  end
end)
