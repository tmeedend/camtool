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
---NONE OF THEM IS BOUND TO ANYTHING BY DEFAULT, and that is the interesting
---part of this file now.
---
---They were the four arrows, which read well on paper -- an arrow steps to
---the next edit point, as in any editing suite. In this one it is wrong,
---because the thing you spend the session doing is FLYING THE FREE CAMERA to
---place a shot, and Assetto Corsa's free camera moves on the arrows. So every
---press meant to nudge the view also stepped the selection and took the
---replay with it. Théo found it while placing a second camera, which is about
---as early as anyone would.
---
---There is no obvious key left to move them to: the free camera has the
---arrows, WASD and the mouse, and guessing wrong costs another session. So
---they are declared, listed in the ? panel, and left for whoever wants them
---to choose a key. A shortcut nobody asked for is worth less than a free
---camera that behaves.
---
---THE NAMES CHANGED WITH THE DEFAULTS, and that is deliberate rather than
---tidy-mindedness. ac.ControlButton keeps a binding under its name in
---controls.ini; changing a default does nothing for anyone who already has
---the old one saved, so the arrows would have gone on firing for exactly the
---person who reported them. A new name is a new entry, unbound. The old ones
---stay in controls.ini doing nothing, like the Shift variants before them.
---
---CamTool 2's own keys come after the steps, unbound like them -- decided
---with Theo: F10 took the camera (and, pressed again, loaded the next file),
---and Y, U, I, O and P loaded the track's first five files. Nobody asked for
---a key here either, and a letter in a replay is easy to press by accident.
---Enable hotkeys, CamTool 2's switch for Y to P, has no equivalent: an
---unbound shortcut is a disabled one. These fire once per press (`once`),
---where the steps repeat while held.
shortcuts.DEFINITIONS = {
  { id = 'keyframeNext', label = 'Step to next keyframe' },
  { id = 'keyframePrevious', label = 'Step to previous keyframe' },
  { id = 'cameraNext', label = 'Step to next camera' },
  { id = 'cameraPrevious', label = 'Step to previous camera' },
  { id = 'takeCamera', label = 'Take the camera (held: next file)', once = true },
  { id = 'releaseCamera', label = 'Release the camera', once = true },
  { id = 'loadFile1', label = 'Load file 1 of this track', once = true },
  { id = 'loadFile2', label = 'Load file 2 of this track', once = true },
  { id = 'loadFile3', label = 'Load file 3 of this track', once = true },
  { id = 'loadFile4', label = 'Load file 4 of this track', once = true },
  { id = 'loadFile5', label = 'Load file 5 of this track', once = true },
}

---Keys that count while they are HELD rather than when they are pressed: the
---mouse look of CamTool 2 and its two zoom keys.
---
---THESE DO HAVE DEFAULTS, and it is a deliberate exception to the rule above,
---decided with Theo. They are CamTool 2's keys, Alt, Shift and Ctrl, which is
---what the hands of anyone coming from it already do. And they do not fight
---the free camera: the zoom keys only count while the mouse look key is held,
---and Alt on its own moves nothing in Assetto Corsa. Rebindable like the
---others, in the same panel.
---
---Whether ac.ControlButton takes a lone modifier as a binding, and whether it
---still reports Shift while Alt is down, is not written anywhere: the probe
---window shows the three states so the first session in game settles it.
shortcuts.HOLDS = {
  { id = 'mouseLook', label = 'Mouse look (hold)', key = 'Menu' },
  { id = 'zoomIn', label = 'Mouse look zoom in (hold)', key = 'Shift' },
  { id = 'zoomOut', label = 'Mouse look zoom out (hold)', key = 'Control' },
}

---How long a held key waits before repeating, in seconds. Read from
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
        period = not definition.once and shortcuts.REPEAT_PERIOD or nil,
      })
    if ok then buttons[definition.id] = button end
  end

  for _, definition in ipairs(shortcuts.HOLDS) do
    local keyIndex = ui.KeyIndex ~= nil and ui.KeyIndex[definition.key] or nil
    local ok, button = pcall(ac.ControlButton,
      'camtool3/' .. definition.label,
      { keyboard = keyIndex ~= nil and { key = keyIndex } or nil })
    if ok then buttons[definition.id] = button end
  end
end

---Every binding the panel lists, the steps and then the holds.
---@return table[]
function shortcuts.all()
  local list = {}
  for _, definition in ipairs(shortcuts.DEFINITIONS) do list[#list + 1] = definition end
  for _, definition in ipairs(shortcuts.HOLDS) do list[#list + 1] = definition end
  return list
end

---Is a hold key down right now? Never while a field has the keyboard, for the
---same reason as below: Shift typed into a value is not a zoom.
---@param id string @an id from HOLDS
---@return boolean
function shortcuts.down(id)
  local button = buttons ~= nil and buttons[id] or nil
  if button == nil then return false end
  local uiState = ac.getUI ~= nil and ac.getUI() or nil
  if uiState ~= nil and uiState.wantCaptureKeyboard then return false end
  local ok, held = pcall(button.down, button)
  return ok and held == true
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
