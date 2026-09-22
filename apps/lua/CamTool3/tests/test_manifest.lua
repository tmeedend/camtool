--[[
  Tests for core/manifest.lua.

  This runs once per release and its output is what people download, so the
  interesting cases are the ones where it would take out the wrong thing and
  nobody would look: a comment that belongs to the next section, a window that
  is last in the file, an ID that appears in a section which is not a window.
]]

local runner = require('tests/runner')
local manifest = require('core/manifest')

local test, eq = runner.test, runner.eq

---The shape of CamTool 3's own manifest, CRLF and all.
local function sample(eol)
  eol = eol or '\r\n'
  return table.concat({
    '[ABOUT]',
    'NAME = CamTool 3',
    'VERSION = 0.1',
    '',
    '[CORE]',
    '; a note about laziness',
    'LAZY = PARTIAL',
    '',
    '[WINDOW_...]',
    'ID = main',
    'NAME = CamTool 3',
    'ICON = icon.png',
    'FUNCTION_MAIN = windowMain',
    'SIZE = 360, 620',
    '',
    '; The panel ATR asked for: every parameter on one screen.',
    '; Its own window rather than a mode of the one above.',
    '[WINDOW_...]',
    'ID = atr',
    'NAME = CamTool 3 -- ATR',
    'FUNCTION_MAIN = windowAtr',
    '',
    '; Drives the camera every frame.',
    '[SIM_CALLBACKS]',
    'WORLD_UPDATE = simUpdate',
    '',
  }, eol)
end

test('the named window goes', function()
  local out, removed = manifest.withoutWindow(sample(), 'main')

  eq(removed, true)
  eq(out:find('windowMain', 1, true), nil, 'the probe window is still declared')
  eq(out:find('ID = main', 1, true), nil)
end)

test('and nothing else does', function()
  local out = manifest.withoutWindow(sample(), 'main')

  for _, kept in ipairs({
    '[ABOUT]', 'VERSION = 0.1', 'LAZY = PARTIAL',
    'ID = atr', 'windowAtr', 'WORLD_UPDATE = simUpdate',
  }) do
    eq(out:find(kept, 1, true) ~= nil, true, 'it took ' .. kept .. ' with it')
  end
end)

test('the comment above the NEXT section survives', function()
  -- The one that would go wrong quietly. An INI section has no end marker, so
  -- the paragraph introducing the ATR panel sits between the probe window's
  -- last line and the ATR header -- and a naive cut takes it.
  local out = manifest.withoutWindow(sample(), 'main')

  eq(out:find('The panel ATR asked for', 1, true) ~= nil, true,
    "the ATR window lost the paragraph explaining what it is for")
  eq(out:find('Its own window rather than', 1, true) ~= nil, true)
end)

test("a window's own comments go with it", function()
  local text = table.concat({
    '[CORE]',
    'LAZY = PARTIAL',
    '',
    '; these probes are not for players',
    '; and this line explains why',
    '[WINDOW_...]',
    'ID = probes',
    'FUNCTION_MAIN = windowProbes',
    '',
    '[SIM_CALLBACKS]',
    'WORLD_UPDATE = simUpdate',
  }, '\r\n')

  local out, removed = manifest.withoutWindow(text, 'probes')
  eq(removed, true)
  eq(out:find('not for players', 1, true), nil, 'an orphan comment was left')
  eq(out:find('WORLD_UPDATE', 1, true) ~= nil, true)
end)

test('a window at the end of the file goes too', function()
  local text = table.concat({
    '[ABOUT]',
    'NAME = CamTool 3',
    '',
    '[WINDOW_...]',
    'ID = probes',
    'FUNCTION_MAIN = windowProbes',
  }, '\r\n')

  local out, removed = manifest.withoutWindow(text, 'probes')
  eq(removed, true)
  eq(out:find('windowProbes', 1, true), nil)
  eq(out:find('NAME = CamTool 3', 1, true) ~= nil, true)
end)

test('a name nobody declared is reported, not shrugged off', function()
  -- The release must stop rather than ship the panel it was told to take out.
  local out, removed = manifest.withoutWindow(sample(), 'nosuchwindow')
  eq(removed, false)
  eq(out, sample(), 'and it changed nothing on the way')
end)

test('an ID outside a window section is left alone', function()
  local text = table.concat({
    '[SOMETHING_ELSE]',
    'ID = main',
    'VALUE = 3',
    '',
    '[WINDOW_...]',
    'ID = atr',
    'FUNCTION_MAIN = windowAtr',
  }, '\r\n')

  local out, removed = manifest.withoutWindow(text, 'main')
  eq(removed, false)
  eq(out:find('[SOMETHING_ELSE]', 1, true) ~= nil, true)
end)

test('the line endings come back as they went in', function()
  -- Assetto Corsa reads either, but a diff that rewrites every line of a file
  -- hides the one line that changed.
  local out = manifest.withoutWindow(sample('\r\n'), 'main')
  eq(out:find('\n') ~= nil, true)
  eq(out:gsub('\r\n', ''):find('\n'), nil, 'a bare newline crept in')

  local unix = manifest.withoutWindow(sample('\n'), 'main')
  eq(unix:find('\r'), nil, 'a carriage return crept in')
end)

test('spacing around the ID is not part of the name', function()
  for _, line in ipairs({ 'ID=main', 'ID   =   main', 'id = main' }) do
    local text = table.concat({
      '[WINDOW_...]', line, 'FUNCTION_MAIN = windowMain',
    }, '\r\n')
    local _, removed = manifest.withoutWindow(text, 'main')
    eq(removed, true, 'missed ' .. line)
  end
end)

test('nothing at all is not a crash', function()
  eq(select(2, manifest.withoutWindow(nil, 'main')), false)
  eq(select(2, manifest.withoutWindow('', 'main')), false)
  eq(select(2, manifest.withoutWindow(sample(), '')), false)
end)

test('the real manifest still declares both windows', function()
  -- Fails the day the probe window is renamed, which is the day the release
  -- would start shipping it.
  local file = io.open('manifest.ini', 'r')
  eq(file ~= nil, true, 'no manifest.ini beside the app')
  local text = file:read('*a')
  file:close()

  local _, removed = manifest.withoutWindow(text, 'main')
  eq(removed, true, "the release cannot find the probe window to remove")

  local rest = manifest.withoutWindow(text, 'main')
  eq(rest:find('windowAtr', 1, true) ~= nil, true, 'and the panel must stay')
  eq(rest:find('ICON = icon.png', 1, true) ~= nil, true,
    'along with its icon, or the app list goes generic again')
end)
