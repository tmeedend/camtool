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

test('every shortcut is declared, and none of them claims a key', function()
  -- The bindings live in controls.ini under their own names, and what a fresh
  -- install starts with is NOTHING. Assetto Corsa's free camera moves on the
  -- arrows, and flying it is what you do between placing one shot and the
  -- next: a default that fights it costs a session to find and a session to
  -- diagnose.
  local handle = withShortcuts({})

  eq(#handle.controlButtons, #shortcuts.DEFINITIONS + #shortcuts.HOLDS)
  for i = 1, #shortcuts.DEFINITIONS do
    local created = handle.controlButtons[i]
    eq(created.id:find('camtool3/', 1, true), 1,
      'namespaced, so it cannot collide: ' .. created.id)
    eq(created.defaults.keyboard, nil,
      created.id .. ' claims a key of its own')
    eq(created.defaults.period ~= nil, not shortcuts.DEFINITIONS[i].once,
      created.id .. ': the steps repeat when held, the rest fire once')
  end

  handle.restoreIo()
  shortcuts.reset()
end)

test('no shortcut is named as it was while it took the arrows', function()
  -- ac.ControlButton keeps a binding under its NAME. Taking the default away
  -- does nothing for anyone who already has the old one saved -- which is
  -- exactly the person who reported the clash. A new name is a new entry, and
  -- a new entry is unbound.
  local handle = withShortcuts({})

  for _, created in ipairs(handle.controlButtons) do
    for _, gone in ipairs({
      'camtool3/Next keyframe', 'camtool3/Previous keyframe',
      'camtool3/Next camera', 'camtool3/Previous camera',
    }) do
      eq(created.id ~= gone, true,
        created.id .. ' would inherit an arrow somebody bound')
    end
  end

  handle.restoreIo()
  shortcuts.reset()
end)

test('a held key repeats', function()
  -- Walking a set of forty cameras one press at a time is not a gesture.
  local handle = withShortcuts({})
  for i = 1, #shortcuts.DEFINITIONS do
    if not shortcuts.DEFINITIONS[i].once then
      eq(handle.controlButtons[i].defaults.period, shortcuts.REPEAT_PERIOD)
    end
  end
  handle.restoreIo()
  shortcuts.reset()
end)

test('stepping moves the playhead, and there is no variant that does not', function()
  -- There were four Shift variants that stepped without moving the replay.
  -- They were the keyboard's half of Shift+click on the ribbon; a click no
  -- longer moves the replay, so they had nothing left to abstain from.
  local steps = 0
  for _, definition in ipairs(shortcuts.DEFINITIONS) do
    if not definition.once then steps = steps + 1 end
  end
  eq(steps, 4, 'four steps, four bindings')
  eq(shortcuts.QUIET, nil, 'and no table of quiet ones')
end)

test('a press is reported by name', function()
  local handle = withShortcuts({ pressedShortcut = 'Step to next camera' })
  eq(shortcuts.pressed(), 'cameraNext')
  handle.restoreIo()
  shortcuts.reset()
end)

test('nothing fires while a field has the keyboard', function()
  -- THE trap. Typing a value or naming a camera means Space is a space and
  -- the arrows move the caret. One check for every shortcut there will ever
  -- be, rather than each caller remembering.
  local handle = withShortcuts({
    pressedShortcut = 'Step to next camera', typingSomewhere = true,
  })
  eq(shortcuts.pressed(), nil)
  handle.restoreIo()
  shortcuts.reset()
end)

test('and they fire again the moment the field lets go', function()
  local handle = withShortcuts({
    pressedShortcut = 'Step to next camera', typingSomewhere = false,
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

test('mouse look keeps the keys CamTool 2 had, and they do not repeat', function()
  -- The one exception to "no key by default", decided with Theo: Alt, Shift
  -- and Ctrl are what anyone coming from CamTool 2 already presses, and the
  -- zoom keys only count while Alt is held.
  local handle = withShortcuts({})
  local wanted = { mouseLook = 'Menu', zoomIn = 'Shift', zoomOut = 'Control' }
  for i, hold in ipairs(shortcuts.HOLDS) do
    local created = handle.controlButtons[#shortcuts.DEFINITIONS + i]
    eq(created.id:find('camtool3/', 1, true), 1, created.id)
    eq(hold.key, wanted[hold.id], hold.id)
    eq(created.defaults.keyboard ~= nil and created.defaults.keyboard.key,
      ui.KeyIndex[wanted[hold.id]], hold.id .. ' bound by default')
    eq(created.defaults.period, nil, hold.id .. ' is held, not repeated')
  end
  handle.restoreIo()
  shortcuts.reset()
end)

test('a hold key is read while held, and never while a field types', function()
  local handle = withShortcuts({})
  eq(shortcuts.down('mouseLook'), false)
  handle.held['Mouse look (hold)'] = true
  eq(shortcuts.down('mouseLook'), true)
  eq(shortcuts.pressed(), nil, 'and it is not a step')
  handle.ui.wantCaptureKeyboard = true
  eq(shortcuts.down('mouseLook'), false, 'Shift typed into a value is not a zoom')
  handle.restoreIo()
  shortcuts.reset()
end)
