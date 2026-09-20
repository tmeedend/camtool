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
    -- Every drawing call the panel made, in order. Enough for a test to ask
    -- what reached the screen: that no coordinate is inf or nan, that nothing
    -- was drawn outside its box, that the track was stroked once per run of
    -- colour. Not enough to say it looks right -- nothing here can.
    drawn = {},
    buttons = {},
    -- Style colours pushed, in order, so a test can ask what colour a widget
    -- was actually drawn in rather than what the theme merely offers.
    styles = {},
    tooltips = {},
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
    -- A 500 m circle is a hair over 3141 m round.
    trackLengthM = opts.trackLengthM or 3141.59,
    isTrackOpen = opts.isTrackOpen == true,
    -- What the game says its drivable camera actually is, which is not
    -- always what was asked for.
    driveableCameraMode = opts.driveableCameraMode,
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
      -- opts.drivableCeiling models a game that refuses what it was given
      -- and clamps: exactly the suspicion about the sixth F1 camera.
      if opts.drivableCeiling ~= nil and mode > opts.drivableCeiling then
        sim.driveableCameraMode = opts.drivableCeiling
      else
        sim.driveableCameraMode = mode
      end
    end,
    setCurrentCarCamera = function(index)
      handle.carCamera = index
      handle.cameraCalls[#handle.cameraCalls + 1] = { 'car', index }
    end,

    -- The track's shape, for the map. A circle of known radius, so a test can
    -- work out by hand where a point should land -- with opts.trackRadius at
    -- zero standing in for a track whose fast_lane is missing.
    --
    -- opts.noTrackSpline models the real case the map has to survive: drift
    -- and gymkhana layouts, parking-lot maps and the odd scenic mod ship
    -- without one.
    hasTrackSpline = function()
      return opts.noTrackSpline ~= true
    end,
    trackProgressToWorldCoordinate = function(p)
      local r = opts.trackRadius or 500
      local angle = p * 2 * math.pi
      -- AC is Y-up: the horizontal pair is x and z.
      return vec3fake(r * math.cos(angle), 0, r * math.sin(angle))
    end,
    getTrackAISplineSides = function(p)
      if opts.trackSides == nil then return { x = 6, y = 6 } end
      return opts.trackSides(p)
    end,

    -- Track identity, used to build the camera-file prefix.
    -- Named sections, the sections.ini question. nil by default: most of the
    -- tests have no opinion, and the probe has to survive that.
    getTrackSectorName = opts.sectorName,

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
    pushStyleColor = function(which, colour)
      handle.styles[#handle.styles + 1] = { which = which, colour = colour }
    end,
    Alignment = { Start = -1, Center = 0, End = 1 },
    Direction = { None = -1, Left = 0, Right = 1, Up = 2, Down = 3 },
    arrowButton = function(label) return clicked(label) end,
    invisibleButton = function(label) return clicked(label) end,
    keyboardButtonPressed = function(key) return opts.keyPressed == key end,
    KeyIndex = { Control = 17, Shift = 16, Y = 89, Z = 90, Escape = 27 },
    -- The pointer shape over a draggable value. A plain table because the
    -- catch-all below answers with a function, and indexing a function raises.
    MouseCursor = { Arrow = 0, ResizeEW = 6 },
    setMouseCursor = function(shape) handle.cursor = shape end,

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
    windowHeight = function() return opts.panelHeight or 620 end,
    -- Deliberately not the origin. A widget that draws at its own
    -- coordinates and forgets to add the cursor would land in exactly the
    -- right place if this were { 0, 0 }, and the test that checks it stays
    -- inside its box would never notice.
    getCursor = function() return { x = opts.cursorX or 17, y = opts.cursorY or 23 } end,
    itemRectMin = function() return { x = opts.itemX or 0, y = opts.itemY or 0 } end,
    -- Where the click landed. The map measures from itemRectMin, so these two
    -- are read together and a test sets both.
    mousePos = function()
      return { x = opts.mouseX or -1, y = opts.mouseY or -1 }
    end,
    -- The pointer in the window's own coordinates, which is the ruler
    -- ui.getCursor uses and therefore the one anything drawn has to be
    -- measured against.
    mouseLocalPos = function()
      return { x = opts.mouseX or -1, y = opts.mouseY or -1 }
    end,
    itemRectMax = function() return { x = 10, y = 10 } end,
    measureText = function(t) return { x = #tostring(t) * 7, y = 14 } end,

    -- Drawing. Recorded rather than ignored, so the map can be tested.
    pathLineTo = function(point)
      handle.drawn[#handle.drawn + 1] =
        { op = 'pathLineTo', x = point.x, y = point.y }
    end,
    pathStroke = function(colour, closed, thickness)
      handle.drawn[#handle.drawn + 1] =
        { op = 'pathStroke', colour = colour, closed = closed,
          thickness = thickness }
    end,
    drawLine = function(p1, p2, colour, thickness)
      handle.drawn[#handle.drawn + 1] =
        { op = 'drawLine', x = p1.x, y = p1.y, x2 = p2.x, y2 = p2.y,
          colour = colour, thickness = thickness }
    end,
    drawTextClipped = function(text, posMin, posMax, colour)
      handle.drawn[#handle.drawn + 1] = { op = 'label', text = tostring(text),
        x = posMin.x, y = posMin.y, x2 = posMax.x, y2 = posMax.y,
        colour = colour }
    end,
    drawQuadFilled = function(a, b, c, d, colour)
      -- Recorded by its centre, which is what a test wants to know: the four
      -- corners of a diamond are the same point plus a radius.
      handle.drawn[#handle.drawn + 1] = { op = 'drawQuadFilled',
        x = (a.x + c.x) / 2, y = (a.y + c.y) / 2, colour = colour }
    end,
    drawCircle = function(point, radius, colour)
      handle.drawn[#handle.drawn + 1] =
        { op = 'drawCircle', x = point.x, y = point.y, radius = radius,
          colour = colour }
    end,
    drawCircleFilled = function(point, radius, colour)
      handle.drawn[#handle.drawn + 1] =
        { op = 'drawCircleFilled', x = point.x, y = point.y, radius = radius,
          colour = colour }
    end,
    drawRectFilled = function(p1, p2, colour)
      handle.drawn[#handle.drawn + 1] =
        { op = 'drawRectFilled', x = p1.x, y = p1.y, x2 = p2.x, y2 = p2.y,
          colour = colour }
    end,
    textAligned = function(text)
      handle.drawn[#handle.drawn + 1] = { op = 'text', text = tostring(text) }
    end,
    -- Recorded so a test can see whether a widget was put beside the last one
    -- or under it, which is the difference between a clickable row and one
    -- drawn off the edge of the window.
    sameLine = function(offset, spacing)
      handle.drawn[#handle.drawn + 1] = { op = 'sameLine', spacing = spacing }
    end,
    newLine = function()
      handle.drawn[#handle.drawn + 1] = { op = 'newLine' }
    end,
    text = function(text)
      handle.drawn[#handle.drawn + 1] = { op = 'text', text = tostring(text) }
    end,
    setTooltip = function(text)
      handle.tooltips[#handle.tooltips + 1] = tostring(text)
    end,

    -- The context menu. Its contents are only drawn while it is open, so a
    -- test says so rather than the fake guessing.
    itemPopup = function(id, button, content)
      if opts.popupOpen and type(content) == 'function' then return content() end
      if opts.popupOpen and type(button) == 'function' then return button() end
    end,
    selectable = function(label) return clicked(label) end,
    mouseClicked = function(button)
      return opts.rightClicked == true and button == 1
    end,
    MouseButton = { Left = 0, Right = 1 },

    slider = function(_, value) return value, false end,
    checkbox = function(label) return clicked(label) end,
    radioButton = function(label) return clicked(label) end,
    -- Labels are recorded: several of the panel's readouts are written into
    -- them, the undo depth among them, and a test has no other way to see it.
    button = function(label)
      handle.buttons[#handle.buttons + 1] = label
      handle.drawn[#handle.drawn + 1] = { op = 'button', text = tostring(label) }
      return clicked(label)
    end,
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

  ---Advance one render frame and run the app's per-frame work.
  ---
  ---Bumping sim.frame is not a detail. The app runs its work once per render
  ---frame and guards against the two entry points firing in the same one, so
  ---with the counter left where it starts, a test that loops thirty times
  ---runs exactly one frame and cannot tell. Anything that needs the app to
  ---actually advance goes through here.
  ---@param dt number|nil
  function handle.tick(dt)
    sim.frame = sim.frame + 1
    if _G.script.update ~= nil then pcall(_G.script.update, dt or 0.016) end
  end

  return handle
end

return fakes
