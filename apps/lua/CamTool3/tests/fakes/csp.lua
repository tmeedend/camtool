--[[
  Fake CSP environment, enough to load and drive the app out of game.

  This is the tests/fakes layer CLAUDE.md asks for. It does not pretend to
  simulate Assetto Corsa; it exists so that loading the app, running a frame and
  drawing the window are things a test can do. That catches the whole class of
  failures that otherwise costs a game launch to discover: an unresolved
  require, a function over Lua's 60-upvalue limit, a nil reaching string.format
  inside the window function.

  What it cannot tell you: whether anything looks right on screen.
]]

local fakes = {}

local function vec3fake(x, y, z)
  return { x = x or 0, y = y or 0, z = z or 0 }
end

---The handful of globals CSP defines before any app code runs.
---
---A module is entitled to call rgbm at load time -- ui/theme.lua builds its
---palette there -- so these cannot wait for fakes.install, which happens
---inside a test after the requires at the top of the file have run.
function fakes.installGlobals()
  _G.vec3 = vec3fake
  _G.vec2 = function(x, y) return { x = x or 0, y = y or 0 } end
  _G.rgbm = function(r, g, b, m) return { r = r, g = g, b = b, mult = m } end
end

---Install fake globals. Returns a handle whose fields record what the app did.
---@param opts table|nil @{ cameraFile = <parsed camera document>, replay = boolean }
function fakes.install(opts)
  opts = opts or {}

  local handle = {
    logs = {},
    grabbed = false,
    disposed = false,
    replayPositions = {},
    cameraCalls = {},
    audioWrites = {},
    transform = {
      position = { x = 0, y = 0, z = 0 },
      look = { x = 0, y = 0, z = 1 },
      up = { x = 0, y = 1, z = 0 },
    },
  }

  fakes.installGlobals()

  local sim = {
    isReplayActive = opts.replay ~= false,
    isReplayOnlyMode = true,
    replayFrames = 5000,
    replayCurrentFrame = 100,
    replayFrameMs = 16.6,
    replayPlaybackRate = 1,
    focusedCar = 0,
    carsCount = 1,
    dt = 0.016,
    -- Render frame index, used by the app to run its per-frame work once even
    -- when both entry points fire.
    frame = 0,
  }

  -- The focused car, mutable so a test can drive it frame by frame. getCar
  -- hands this very table back, so writing to it is what moving the car means.
  handle.car = {
    splinePosition = opts.splinePosition or 0.5,
    index = 0,
    -- AC world position, Y-up. Needed for the tracking path.
    position = opts.carPosition or vec3fake(-170, 5, 450),
  }

  local grabbedCamera = {
    transform = handle.transform,
    transformOriginal = {
      position = vec3fake(10, 2, 30),
      look = vec3fake(0, 0, 1),
      up = vec3fake(0, 1, 0),
    },
    fov = 40, fovOriginal = 40,
    dofDistance = 20, dofDistanceOriginal = 20,
    dofFactor = 0, dofFactorOriginal = 0,
    exposure = 1, exposureOriginal = 1,
    ownShare = 1,
  }
  function grabbedCamera:active() return not handle.disposed end
  function grabbedCamera:dispose() handle.disposed = true end

  _G.ac = {
    getSim = function() return sim end,
    getUI = function() return { dt = 0.016, mouseDelta = { x = 0, y = 0 }, mousePos = { x = 0, y = 0 } } end,
    log = function(m) handle.logs[#handle.logs + 1] = tostring(m) end,
    warn = function() end,
    error = function() end,
    onRelease = function(fn) handle.releaseCallback = fn end,

    grabCamera = function()
      handle.grabbed = true
      handle.disposed = false
      return grabbedCamera
    end,

    getCameraPosition = function() return vec3fake(1, 2, 3) end,
    getCameraForward = function() return vec3fake(0, 0, 1) end,
    getCameraUp = function() return vec3fake(0, 1, 0) end,
    getCameraFOV = function() return 45 end,

    getCar = function(i)
      if i ~= 0 then return nil end
      return handle.car
    end,

    setReplayPosition = function(frame, counter)
      handle.replayPositions[#handle.replayPositions + 1] = { frame, counter }
    end,
    getAudioVolume = function() return 1 end,
    setAudioVolume = function(ch, v) handle.audioWrites[#handle.audioWrites + 1] = { ch, v } end,

    isKeyDown = function() return false end,

    -- Handing the view to one of Assetto Corsa's own cameras. CamTool 2 had
    -- to press F1 the right number of times; these are what CSP added.
    CameraMode = {
      Cockpit = 0, Car = 1, Drivable = 2, Track = 3, Helicopter = 4,
      OnBoardFree = 5, Free = 6,
    },
    setCurrentCamera = function(mode)
      handle.cameraMode = mode
      handle.cameraCalls[#handle.cameraCalls + 1] = { 'mode', mode }
    end,
    setCurrentDrivableCamera = function(mode)
      handle.drivableCamera = mode
      handle.cameraCalls[#handle.cameraCalls + 1] = { 'drivable', mode }
    end,
    setCurrentCarCamera = function(index)
      handle.carCamera = index
      handle.cameraCalls[#handle.cameraCalls + 1] = { 'car', index }
    end,

    -- Track identity, used to build the camera-file prefix.
    getTrackID = function() return opts.trackID or 'fake_track' end,
    getTrackLayout = function() return opts.trackLayout or '' end,
    getTrackName = function() return 'Fake Track' end,
    AudioChannel = { Main = 'main' },
    KeyIndex = { Shift = 16, Control = 17, Menu = 18 },
  }

  -- ImGui: every call is a no-op that reports "not clicked". Widgets that hand
  -- a value back must return it unchanged, or the app would see its sliders
  -- reset to nil every frame.
  -- opts.clicks maps a widget label to true, so a test can drive the app
  -- through its own UI instead of reaching into its internals.
  local clicks = opts.clicks or {}
  local function clicked(label) return clicks[label] == true end

  _G.ui = setmetatable({
    -- Enough of the layout and styling API for the ATR panel to be drawn.
    -- These have to be real values rather than the catch-all below: the panel
    -- does arithmetic on the width, and indexing a function would raise.
    StyleColor = { Text = 0, Button = 21, ButtonHovered = 22, ButtonActive = 23 },
    Alignment = { Start = -1, Center = 0, End = 1 },
    Direction = { None = -1, Left = 0, Right = 1, Up = 2, Down = 3 },
    arrowButton = function(label) return clicked(label) end,
    invisibleButton = function(label) return clicked(label) end,
    keyboardButtonPressed = function(key) return opts.keyPressed == key end,
    KeyIndex = { Control = 17, Shift = 16, Y = 89, Z = 90 },

    -- The pointer, for the drag and the double click. These answer the same
    -- for every widget, so a test that wants to be sure which one reacted
    -- draws a single row rather than the whole panel.
    itemActive = function() return opts.itemActive == true end,
    itemHovered = function() return opts.itemHovered == true end,
    mouseDoubleClicked = function() return opts.mouseDoubleClicked == true end,
    mouseDragDelta = function() return opts.mouseDragDelta end,
    resetMouseDragDelta = function() end,
    setNextItemWidth = function() end,

    InputTextFlags = { CharsDecimal = 1, AutoSelectAll = 16 },
    inputText = function(label, str)
      -- text, changed, enter pressed
      return opts.typed or str, opts.typed ~= nil, opts.enterPressed == true
    end,
    availableSpaceX = function() return opts.panelWidth or 360 end,
    windowWidth = function() return opts.panelWidth or 360 end,
    getCursor = function() return { x = 0, y = 0 } end,
    itemRectMin = function() return { x = 0, y = 0 } end,
    itemRectMax = function() return { x = 10, y = 10 } end,
    measureText = function(t) return { x = #tostring(t) * 7, y = 14 } end,

    slider = function(_, value) return value, false end,
    checkbox = function(label) return clicked(label) end,
    radioButton = function(label) return clicked(label) end,
    button = function(label) return clicked(label) end,
    hotkeyCtrl = function() return false end,
    hotkeyAlt = function() return false end,
    hotkeyShift = function() return false end,
  }, {
    __index = function() return function() return nil end end,
  })

  -- Filesystem: one file, whose contents JSON.parse hands back as the document
  -- the caller supplied.
  -- Every one of these is captured BEFORE restoreIo closes over it. Declared
  -- after, they would resolve to globals and restoring would set io.save to
  -- nil instead of putting it back.
  local originalScanDir = io.scanDir
  local originalLoad = io.load
  local originalSave = io.save
  local originalExists = io.exists
  local originalCopy = io.copyFile

  handle.restoreIo = function()
    io.scanDir = originalScanDir
    io.load = originalLoad
    io.save = originalSave
    io.exists = originalExists
    io.copyFile = originalCopy
  end

  handle.written = {}
  handle.copied = {}

  io.save = function(name, text)
    handle.written[name] = text
    return opts.saveFails ~= true
  end
  io.exists = function(name)
    if opts.existing == nil then return false end
    return opts.existing[name] == true
  end
  io.copyFile = function(from, to)
    handle.copied[#handle.copied + 1] = { from, to }
    return true
  end

  io.scanDir = function(dir)
    -- CamTool 3's own folder is empty unless a test says otherwise, so the
    -- default listing is the CamTool 2 one it always was.
    if dir == 'apps/lua/CamTool3/data' then return opts.ownFiles or {} end
    return opts.files or { 'fake_track_-cameras.json', 'settings.json', 'other_track_-x.json' }
  end
  io.createDir = function() return true end
  io.load = function() return '{"fake":true}' end
  _G.JSON = { parse = function() return opts.cameraFile end, stringify = function() return '{}' end }

  _G.script = {}

  handle.sim = sim
  handle.camera = grabbedCamera
  return handle
end

return fakes
