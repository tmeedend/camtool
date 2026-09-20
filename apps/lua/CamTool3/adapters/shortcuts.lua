--[[
  Keyboard shortcuts -- the only place that reads the keyboard.

  Through ac.ControlButton, and that choice is the whole point of this file.
  CamTool 2 installed a global keyboard hook and issue #34 is what that cost:
  latency on the game's own keys, felt by people who were not even using the
  app. ControlButton asks Assetto Corsa to tell us when a binding fires
  instead of watching the keyboard ourselves, so there is nothing to be slow.

  THE BINDINGS ARE DEFAULTS, NEVER FIXED. Each one lives in controls.ini under
  its own name, the user rebinds it in the panel with :control(), and what it
  is bound to is read back with :boundTo(). Nothing here assumes a key.

  THE TRAP, and it is the one worth reading twice: while a field has the
  keyboard -- a value being typed, a camera being named -- Space must write a
  space and the arrows must move the caret. Not one shortcut fires then. The
  check is wantCaptureKeyboard and it is made ONCE, here, for all of them,
  rather than by each caller remembering. CamTool 2 kept its own flags for
  this and got it wrong in places.
]]

local shortcuts = {}

---The buttons, created once and kept. ac.ControlButton only reads its
---defaults the first time it is called in a session, so creating them per
---frame would quietly ignore every default after the first.
local buttons = nil

---What each shortcut is for, in the order the settings panel shows them.
---
---FOUR, NOT EIGHT. There were Shift variants that stepped without moving the
---replay -- the keyboard's half of a Shift+click on the ribbon. The ribbon no
---longer moves the replay on a click, so there is nothing left for them to
---abstain from: an arrow moves the playhead, the way the jump-to-edit-point
---keys do in Premiere and Resolve, and that is all an arrow does.
---
---Anyone who had them bound keeps four dead entries in controls.ini. Harmless,
---and cheaper than carrying a shortcut that does what the plain key does.
shortcuts.DEFINITIONS = {
  { id = 'keyframeNext', label = 'Next keyframe',
    key = 'Right' },
  { id = 'keyframePrevious', label = 'Previous keyframe',
    key = 'Left' },
  { id = 'cameraNext', label = 'Next camera',
    key = 'Down' },
  { id = 'cameraPrevious', label = 'Previous camera',
    key = 'Up' },
}

---How long a held arrow waits before repeating, in seconds. Read from
---controls.ini as REPEAT_PERIOD once a user changes it.
shortcuts.REPEAT_PERIOD = 0.18

---Create the buttons, once.
---
---Safe to call again: it does nothing the second time, which matters because
---the defaults of a second call would be thrown away anyway.
function shortcuts.install()
  if buttons ~= nil then return end
  if ac.ControlButton == nil then return end

  buttons = {}

  for _, definition in ipairs(shortcuts.DEFINITIONS) do
    local keyIndex = ui.KeyIndex ~= nil and ui.KeyIndex[definition.key] or nil
    local ok, button = pcall(ac.ControlButton,
      'camtool3/' .. definition.label,
      {
        keyboard = keyIndex ~= nil
          and { key = keyIndex, shift = definition.shift == true } or nil,
        period = shortcuts.REPEAT_PERIOD,
      })
    if ok then buttons[definition.id] = button end
  end
end

---Has anything been pressed this frame?
---
---Answers one id at most, and nothing at all while a field owns the keyboard.
---@return string|nil @an id from DEFINITIONS
function shortcuts.pressed()
  if buttons == nil then return nil end

  -- THE GUARD. Typing a value or naming a camera means Space is a space and
  -- the arrows move the caret. One check, here, for every shortcut there will
  -- ever be.
  local uiState = ac.getUI ~= nil and ac.getUI() or nil
  if uiState ~= nil and uiState.wantCaptureKeyboard then return nil end

  for _, definition in ipairs(shortcuts.DEFINITIONS) do
    local button = buttons[definition.id]
    if button ~= nil then
      local ok, fired = pcall(button.pressed, button)
      if ok and fired then return definition.id end
    end
  end

  return nil
end

---What a shortcut is bound to right now, for a tooltip or a settings row.
---@param id string
---@return string @empty when unbound or unavailable
function shortcuts.boundTo(id)
  local button = buttons ~= nil and buttons[id] or nil
  if button == nil then return '' end
  local ok, label = pcall(button.boundTo, button)
  return (ok and type(label) == 'string') and label or ''
end

---Draw the rebinding widget for one shortcut. The panel owns the layout; this
---owns nothing but the call.
---@param id string
---@return boolean @whether there was a widget to draw
function shortcuts.control(id, width)
  local button = buttons ~= nil and buttons[id] or nil
  if button == nil then return false end
  local ok = pcall(button.control, button, width)
  return ok
end

---Forget the buttons. For tests only: a session creates them once.
function shortcuts.reset()
  buttons = nil
end

return shortcuts
