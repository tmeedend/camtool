--[[
  Tests for adapters/shortcuts.lua.

  The binding itself cannot be checked out of game -- whether Assetto Corsa
  really calls back when Right is pressed is the in-game checklist's job. What
  can be checked here is everything around it, and one of those things matters
  more than the rest: while a field has the keyboard, not one shortcut fires.
]]

local runner = require('tests/runner')
local fakes = require('tests/fakes/csp')
local shortcuts = require('adapters/shortcuts')

local test, eq = runner.test, runner.eq

local function withShortcuts(opts)
  local handle = fakes.install(opts or {})
  shortcuts.reset()
  shortcuts.install()
  return handle
end

test('every shortcut is declared with a default, and none is fixed', function()
  -- The bindings live in controls.ini under their own names. Nothing here
  -- assumes a key; these are only what a fresh install starts with.
  local handle = withShortcuts({})

  eq(#handle.controlButtons, #shortcuts.DEFINITIONS)
  for _, created in ipairs(handle.controlButtons) do
    eq(created.id:find('camtool3/', 1, true), 1,
      'namespaced, so it cannot collide: ' .. created.id)
    eq(type(created.defaults.keyboard.key), 'number', 'a default key')
    eq(created.defaults.period ~= nil, true, 'and a repeat period')
  end

  handle.restoreIo()
  shortcuts.reset()
end)

test('a held arrow repeats', function()
  -- Walking a set of forty cameras one press at a time is not a gesture.
  local handle = withShortcuts({})
  for _, created in ipairs(handle.controlButtons) do
    eq(created.defaults.period, shortcuts.REPEAT_PERIOD)
  end
  handle.restoreIo()
  shortcuts.reset()
end)

test('the quiet variants are their own bindings, with Shift as the default', function()
  -- A binding matches its modifiers, so Shift+Left is not Left with a flag
  -- set. Declaring them plainly also means they can be rebound or unbound.
  local handle = withShortcuts({})

  local shifted = 0
  for _, created in ipairs(handle.controlButtons) do
    if created.defaults.keyboard.shift then shifted = shifted + 1 end
  end
  eq(shifted, 4, 'one quiet variant per direction')

  handle.restoreIo()
  shortcuts.reset()
end)

test('a press is reported by name', function()
  local handle = withShortcuts({ pressedShortcut = 'Next camera' })
  eq(shortcuts.pressed(), 'cameraNext')
  handle.restoreIo()
  shortcuts.reset()
end)

test('nothing fires while a field has the keyboard', function()
  -- THE trap. Typing a value or naming a camera means Space is a space and
  -- the arrows move the caret. One check for every shortcut there will ever
  -- be, rather than each caller remembering.
  local handle = withShortcuts({
    pressedShortcut = 'Next camera', typingSomewhere = true,
  })
  eq(shortcuts.pressed(), nil)
  handle.restoreIo()
  shortcuts.reset()
end)

test('and they fire again the moment the field lets go', function()
  local handle = withShortcuts({
    pressedShortcut = 'Next camera', typingSomewhere = false,
  })
  eq(shortcuts.pressed(), 'cameraNext')
  handle.restoreIo()
  shortcuts.reset()
end)

test('the buttons are created once, whatever asks', function()
  -- ac.ControlButton only reads its defaults the first time it is called in a
  -- session, so creating them again would quietly throw the rest away.
  local handle = withShortcuts({})
  local created = #handle.controlButtons

  shortcuts.install()
  shortcuts.install()
  eq(#handle.controlButtons, created)

  handle.restoreIo()
  shortcuts.reset()
end)

test('what a shortcut is bound to can be read back, for a tooltip', function()
  local handle = withShortcuts({ boundTo = 'Right Arrow' })
  eq(shortcuts.boundTo('cameraNext'), 'Right Arrow')
  eq(shortcuts.boundTo('nonesuch'), '', 'and an unknown one says nothing')
  handle.restoreIo()
  shortcuts.reset()
end)

test('a build without ControlButton simply has no shortcuts', function()
  local handle = fakes.install({})
  shortcuts.reset()
  ac.ControlButton = nil
  shortcuts.install()

  eq(shortcuts.pressed(), nil)
  eq(shortcuts.boundTo('cameraNext'), '')

  handle.restoreIo()
  shortcuts.reset()
end)
