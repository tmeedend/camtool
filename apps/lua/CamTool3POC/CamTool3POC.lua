--[[
  CamTool 3 POC -- CSP capability probe.

  Goal: find out whether a Lua/CSP rewrite of CamTool can drop every remaining
  call into CamTool_1-16.dll. Each probe below maps to one row of the DLL table
  in CLAUDE.md, or to a known GitHub issue.

  This app writes no file and never touches apps/python/CamTool_2. The only
  global state it changes is the grabbed camera and, optionally, the main audio
  volume -- both restored when the probe is stopped or the window is closed.
]]

local storage = require('adapters/storage')
local evaluate = require('core/evaluate')
local angles = require('core/angles')
local tracking = require('core/tracking')
local spline = require('core/spline')
local dataModule = require('core/data')

local sim = ac.getSim()
local uiState = ac.getUI()

local COLOR_OK = rgbm(0.45, 1, 0.45, 1)
local COLOR_BAD = rgbm(1, 0.5, 0.4, 1)
local COLOR_IDLE = rgbm(0.7, 0.7, 0.7, 1)

--------------------------------------------------------------------------------
-- Logging
--------------------------------------------------------------------------------

local LOG_KEPT = 12
local logLines = {}

local function log(message)
  logLines[#logLines + 1] = message
  while #logLines > LOG_KEPT do table.remove(logLines, 1) end
  ac.log('[CamTool3POC] ' .. message)
end

---Coerce a possibly-missing number for display. A nil reaching string.format
---raises, and an error inside the window function kills the whole panel every
---frame, so the app would show nothing at all.
local function num(v)
  return type(v) == 'number' and v or 0
end

local function fmtVec(v)
  if v == nil then return '<nil>' end
  return string.format('%.3f %.3f %.3f', v.x, v.y, v.z)
end

--------------------------------------------------------------------------------
-- Camera grab
-- Covers DLL rows GetPosition, GetHeading, GetRoll on the read side, and the
-- whole write side CamTool 2 currently goes through ctt for.
--------------------------------------------------------------------------------

local MODE_HOLD = 'hold'
local MODE_ORBIT = 'orbit'
local MODE_SNAPSHOT = 'snapshot'
local MODE_MOUSELOOK = 'mouselook'
local MODE_PLAYBACK = 'playback'

local cam = nil
local grabError = nil
local anchor = nil
local orbitTime = 0
local mode = MODE_HOLD

-- Read-back check: what we asked for last frame vs what AC reports this frame.
-- This is issue #20 territory -- the reason get_position_old still calls the DLL.
local requestedPos = nil
local readbackError = 0
local readbackErrorMax = 0

local ownShare = 1
local ownShareTarget = 1
local ownShareRampSpeed = 0

local applyFov = false
local fovDeg = 40
local applyDof = false
local dofFactor = 1
local dofDistance = 20

--------------------------------------------------------------------------------
-- Probe 10 -- read AC's live camera WITHOUT holding it.
-- This is the gap the first round found: CamTool works by aiming the view and
-- then keyframing it, but at ownShare = 1 AC lets go of the camera and
-- transformOriginal freezes. ac.getCamera* should keep reporting the live
-- camera while we are not holding it. A snapshot taken this way, then replayed
-- through a grab, is the whole keyframe round trip in miniature.
--------------------------------------------------------------------------------

local snapshot = nil

local function snapshotTake()
  local p = ac.getCameraPosition()
  local f = ac.getCameraForward()
  local u = ac.getCameraUp()
  -- Copy: these may return reused vectors that change next frame.
  snapshot = {
    pos = vec3(p.x, p.y, p.z),
    look = vec3(f.x, f.y, f.z),
    up = vec3(u.x, u.y, u.z),
    fov = ac.getCameraFOV(),
  }
  log(string.format('snapshot: pos %s look %s fov %.2f',
    fmtVec(snapshot.pos), fmtVec(snapshot.look), snapshot.fov))
end

--------------------------------------------------------------------------------
-- Probe 11 -- mouse look.
-- CamTool 2 gates mouse look behind Alt/Shift/Ctrl (DLL row IsAsyncKeyPressed),
-- so gate on Shift here too: it keeps the mouse usable for the AC UI the rest
-- of the time. uiState.mouseDelta is global, unlike ui.mouseDelta() which only
-- reports inside this window.
--------------------------------------------------------------------------------

local lookYaw = 0
local lookPitch = 0
local lookSensitivity = 0.4
local lookActive = false

--------------------------------------------------------------------------------
-- Probe 12 -- replay a real CamTool 2 camera.
-- The whole chain end to end: read the user's file, migrate it, pick the camera
-- the car's track position selects, evaluate every keyframed parameter through
-- the ported interpolators, and drive the grabbed camera with the result.
-- Read only: nothing is ever written back.
--------------------------------------------------------------------------------

local files = {}
local fileIndex = 0
local doc = nil
local docError = nil
local docName = ''

-- 'pos' and 'time' are the two camera lists every file carries.
local listName = 'pos'

-- Live readout, refreshed each frame while playing back.
local trackPos = 0
local activeCam = nil
local evaluated = {}

-- The legacy reads the camera's CURRENT heading every frame (ctt.get_heading())
-- and falls back to it whenever the heading is not keyframed, so an unkeyframed
-- camera holds its aim instead of snapping to a fixed direction. 18% of the
-- reference cameras never keyframe rot_z, so this is not an edge case. A
-- grabbed camera's transformOriginal freezes at ownShare = 1, so carry the
-- previous frame's value instead; it is the same quantity.
local haveLastAim = false

-- Readouts, refreshed each frame so the panel can show what the aim resolved to.
local appliedHeading, appliedPitch = 0, 0
local aimedHeading, aimedPitch, aimStrength = 0, 0, 0
local aimOffset = 0

-- CamTool stores Z-up; AC is Y-up. Confirmed twice: the track splines put all
-- the elevation in loc_z (Spa spans 102 m, which is Eau Rouge), and
-- CamToolTool.get_position maps CamTool axis 2 to CSP axis 1.
local function toWorld(x, y, z)
  return vec3(x, z, y)
end

-- Aim. The heading and pitch conventions are no longer guessed: they come from
-- Camera.calculate_cam_rot_to_tracking_car via core/angles.lua.
--
-- Tracking here is SIMPLIFIED and does not yet match CamTool 2. It aims at the
-- focused car's current position, where the legacy averages several frames of
-- history and extrapolates one step ahead to lead the car. Expect the aim to
-- lag in fast corners.
local applyTracking = true
local applyRoll = true
local trackingOverride = -1   -- -1 means use the file's own strength

-- Rolling history of the tracked car, for the lead/lag aim point.
local carHistory = tracking.new()
local legacyZeroFill = false

-- Forces tracking_offset to 0, so the camera aims straight at the car with no
-- lead. An A/B switch: 76% of the reference cameras use exactly -0.1, and on the
-- long lenses these files favour, that lead is a visible part of the frame.
local ignoreLead = false
local applySpline = true
local splineQuery = 0

-- CamTool 2 only offers the current track's files; do the same, with an escape
-- hatch for loading another track's file while testing.
local showAllTracks = false
local filePrefix = ''

-- Set by the playback branch each frame, cleared at the top of every update.
local playbackFov = nil

local function refreshFileList()
  files, filePrefix = storage.listCameraFiles(showAllTracks)
  fileIndex = 0
  if #files == 1 then fileIndex = 1 end
  log(string.format('found %d camera files for %s', #files, filePrefix))
end

local function loadSelectedFile()
  if fileIndex < 1 or fileIndex > #files then return end
  local name = files[fileIndex]
  local loaded, err = storage.loadCameraFile(name)

  if loaded == nil then
    doc, docError, docName = nil, err, name
    log('load FAILED: ' .. tostring(err))
    return
  end

  doc, docError, docName = loaded, nil, name
  log(string.format('loaded %s -- %d cameras, version %s, mode %s',
    name, dataModule.cameraCount(loaded), tostring(loaded.version),
    tostring(loaded.interpolation_mode)))
end

---Pick the keyframed value, else the camera-level one, else a default.
local function pick(keyframed, cameraLevel, fallback)
  if keyframed ~= nil then return keyframed end
  if cameraLevel ~= nil then return cameraLevel end
  return fallback
end

---World position of the focused car, converted to CamTool space (Z-up).
local function focusedCarPosition()
  local index = sim.focusedCar
  if index == nil or index < 0 then return nil end
  local car = ac.getCar(index)
  if car == nil or car.position == nil then return nil end
  return car.position.x, car.position.z, car.position.y
end

---Track position of the car the replay is following, 0..1.
local function focusedTrackPosition()
  local index = sim.focusedCar
  if index == nil or index < 0 then return nil end
  local car = ac.getCar(index)
  if car == nil then return nil end
  return car.splinePosition
end

local function cameraActive()
  return cam ~= nil and cam:active()
end

local function grabCamera()
  if cameraActive() then return true end
  local grabbed, err = ac.grabCamera('CamTool 3 POC')
  if grabbed == nil then
    grabError = tostring(err or 'no reason given')
    log('GRAB FAILED: ' .. grabError)
    return false
  end
  cam = grabbed
  grabError = nil
  local p = grabbed.transformOriginal.position
  anchor = vec3(p.x, p.y, p.z)
  orbitTime = 0
  haveLastAim = false
  carHistory = tracking.new(nil, legacyZeroFill)
  requestedPos = nil
  readbackError = 0
  readbackErrorMax = 0
  fovDeg = grabbed.fovOriginal
  log(string.format('grab OK -- anchor %s, original FOV %.2f deg',
    fmtVec(anchor), grabbed.fovOriginal))
  return true
end

local function releaseCamera()
  if cam ~= nil then
    cam:dispose()
    cam = nil
    log('camera released')
  end
end

--------------------------------------------------------------------------------
-- Audio -- DLL rows GetVolume / SetVolume.
-- ac.ext_*AudioVolume caused sound bugs in the Python build; this checks whether
-- the Lua side behaves.
--------------------------------------------------------------------------------

local audioProbeOn = false
local audioValue = 1
local audioOriginal = nil

local function audioStart()
  if audioOriginal == nil then
    audioOriginal = ac.getAudioVolume(ac.AudioChannel.Main, -1, 1)
    audioValue = audioOriginal
    log(string.format('audio: original main volume = %.3f', audioOriginal))
  end
  audioProbeOn = true
end

local function audioStop()
  audioProbeOn = false
  if audioOriginal ~= nil then
    ac.setAudioVolume(ac.AudioChannel.Main, audioOriginal)
    log(string.format('audio: restored main volume to %.3f', audioOriginal))
    audioOriginal = nil
  end
end

--------------------------------------------------------------------------------
-- Replay driving -- DLL row SetReplaySpeed.
-- This is the one call with no direct CSP equivalent: sim.replayPlaybackRate is
-- read-only. So instead of asking for a speed, we advance the replay cursor
-- ourselves every frame. If this is smooth, the DLL call is replaceable.
--------------------------------------------------------------------------------

local replayDriveOn = false
local replayRate = 1
local replayCursor = 0

local function replayStart()
  if not sim.isReplayActive then
    log('replay: not in replay mode, ignored')
    return
  end
  replayCursor = sim.replayCurrentFrame
  replayDriveOn = true
  log(string.format('replay: driving from frame %d / %d (%.2f ms per frame)',
    sim.replayCurrentFrame, sim.replayFrames, sim.replayFrameMs))
end

local function replayStop()
  replayDriveOn = false
  log('replay: released, AC controls playback again')
end

--------------------------------------------------------------------------------
-- Per-frame update
--------------------------------------------------------------------------------

--- Playback lives in its own function for a mundane reason: Lua caps a
--- function at 60 upvalues, and folding it into script.update went over.
local function runPlayback(transform)
  local pos = focusedTrackPosition()
  if pos ~= nil then
    trackPos = pos
    local cameras = doc[listName]
    activeCam = evaluate.activeCameraIndex(cameras, pos)

    if activeCam ~= nil then
      local camera = cameras[activeCam]
      evaluated = evaluate.all(camera, pos)
      local v = evaluated

      -- Where the legacy reads the camera's live angles: the previous frame's
      -- result, seeded from the real orientation the first time through.
      if not haveLastAim then
        local look = cam.transformOriginal.look
        appliedHeading, appliedPitch = angles.fromLook(look.x, look.y, look.z)
        haveLastAim = true
      end
      local currentHeading, currentPitch = appliedHeading, appliedPitch

      ------------------------------------------------------------------
      -- The recorded path, read at its own position
      ------------------------------------------------------------------
      local splinePoint = nil
      local affectXY, affectZ, affectHeading, affectPitch = 0, 0, 0, 0

      if applySpline and spline.exists(camera) then
        local query = spline.queryPosition(pos, camera.spline.the_x,
          pick(v.spline_speed, camera.spline_speed, 1),
          pick(v.spline_offset_spline, camera.spline_offset_spline, 0),
          listName)
        splineQuery = query

        splinePoint = spline.sample(camera, query,
          pick(v.spline_offset_loc_x, camera.spline_offset_loc_x, 0),
          pick(v.spline_offset_loc_z, camera.spline_offset_loc_z, 0))

        if splinePoint ~= nil then
          affectXY = pick(v.spline_affect_loc_xy, camera.spline_affect_loc_xy, 0)
          affectZ = pick(v.spline_affect_loc_z, camera.spline_affect_loc_z, 0)
          -- These two are camera level only: they have a slot in a keyframe
          -- but the legacy never interpolates them.
          affectHeading = camera.spline_affect_heading or 0
          affectPitch = camera.spline_affect_pitch or 0

          local headingOffset = pick(v.spline_offset_heading, camera.spline_offset_heading, 0)
          if splinePoint.heading ~= nil then
            splinePoint.heading = splinePoint.heading + headingOffset
          end
          if splinePoint.pitch ~= nil then
            -- The legacy scales pitch by sin(offset + pi/2), so turning the
            -- path away from its recorded heading flattens it.
            splinePoint.pitch = splinePoint.pitch * math.sin(headingOffset + math.pi / 2)
              + pick(v.spline_offset_pitch, camera.spline_offset_pitch, 0)
          end
        end
      end

      ------------------------------------------------------------------
      -- Position: keyframes mixed with the path
      ------------------------------------------------------------------
      local px, py, pz = v.loc_x, v.loc_y, v.loc_z

      if splinePoint ~= nil then
        px = spline.mix(px, splinePoint.x, affectXY)
        py = spline.mix(py, splinePoint.y, affectXY)
        pz = spline.mix(pz, splinePoint.z, affectZ)
      end

      if px ~= nil and py ~= nil and pz ~= nil then
        transform.position = toWorld(px, py, pz)
      end

      ------------------------------------------------------------------
      -- Aim: keyframes, the tracked car, and the path
      ------------------------------------------------------------------
      -- rot_x is pitch, rot_y is roll, rot_z is heading, named explicitly in
      -- InterpolateFrame.py.
      local rotStrength = pick(v.transform_rot_strength, camera.transform_rot_strength, 1)

      local transformHeading, transformPitch = nil, nil
      if v.rot_z ~= nil then
        transformHeading = angles.blend(currentHeading, v.rot_z, rotStrength)
      end
      if v.rot_x ~= nil then
        transformPitch = angles.blend(currentPitch, v.rot_x, rotStrength)
      end

      local aimHeading, aimPitch = nil, nil
      local pitchStrength = 0
      aimStrength = 0

      if applyTracking and px ~= nil and py ~= nil and pz ~= nil then
        local carX, carY, carZ = focusedCarPosition()
        if carX ~= nil then
          tracking.push(carHistory, carX, carY, carZ)

          -- Aim where the car is heading, or where it has been, rather than
          -- at the car itself. tracking_offset picks which and by how much;
          -- the replay speed stretches it so a slowed replay keeps the same
          -- lead in wall-clock terms.
          local offset = pick(v.tracking_offset, camera.tracking_offset, 0)
          if ignoreLead then offset = 0 end
          aimOffset = offset

          local targetX, targetY, targetZ =
            tracking.target(carHistory, offset, sim.replayPlaybackRate, 0)

          aimHeading, aimPitch = angles.aimAt(px, py, pz, targetX, targetY, targetZ)
          aimHeading = aimHeading + pick(v.tracking_offset_heading, camera.tracking_offset_heading, 0)
          aimPitch = aimPitch + pick(v.tracking_offset_pitch, camera.tracking_offset_pitch, 0)

          aimStrength = pick(v.tracking_strength_heading, camera.tracking_strength_heading, 0)
          pitchStrength = pick(v.tracking_strength_pitch, camera.tracking_strength_pitch, 0)
          if trackingOverride >= 0 then
            aimStrength, pitchStrength = trackingOverride, trackingOverride
          end

          aimedHeading, aimedPitch = aimHeading, aimPitch
        end
      end

      local heading = angles.combine(currentHeading, transformHeading,
        aimHeading, aimStrength,
        splinePoint and splinePoint.heading or nil, affectHeading)

      local pitch = angles.combine(currentPitch, transformPitch,
        aimPitch, pitchStrength,
        splinePoint and splinePoint.pitch or nil, affectPitch)

      appliedHeading, appliedPitch = heading, pitch

      local lx, ly, lz = angles.lookVector(heading, pitch)
      local look = vec3(lx, ly, lz)
      transform.look = look

      if applyRoll and v.rot_y ~= nil and v.rot_y ~= 0 then
        -- Roll turns the up vector around the look axis. Built by hand rather
        -- than with vector helpers so the convention stays visible.
        -- side = cross(look, worldUp) with worldUp = (0, 1, 0).
        local sx, sy, sz = -look.z, 0, look.x
        local sl = math.sqrt(sx * sx + sy * sy + sz * sz)
        if sl > 1e-6 then
          sx, sy, sz = sx / sl, sy / sl, sz / sl
          local ux = sy * look.z - sz * look.y
          local uy = sz * look.x - sx * look.z
          local uz = sx * look.y - sy * look.x
          local c, s = math.cos(v.rot_y), math.sin(v.rot_y)
          transform.up = vec3(ux * c + sx * s, uy * c + sy * s, uz * c + sz * s)
        else
          transform.up = vec3(0, 1, 0)
        end
      else
        transform.up = vec3(0, 1, 0)
      end

      -- Post-migration this is plain degrees, so it goes straight in.
      if v.camera_fov ~= nil and v.camera_fov > 0 and v.camera_fov < 180 then
        playbackFov = v.camera_fov
      end
    end
  end
end

-- Both entry points below can fire in the same render frame depending on how
-- CSP is configured, and the work must happen exactly once: running twice would
-- advance the replay cursor and the car history double.
local lastFrame = -1

local function perFrame(dt)
  local frame = sim.frame
  if frame ~= nil then
    if frame == lastFrame then return end
    lastFrame = frame
  end

  -- Real-time dt. sim.dt is scaled by replay speed and would feed back into the
  -- replay driving below.
  local rt = uiState.dt

  -- Stale values must not survive a frame where playback produced nothing.
  playbackFov = nil

  if replayDriveOn and sim.isReplayActive and sim.replayFrames > 1 then
    local framesPerSecond = 1000 / math.max(sim.replayFrameMs, 0.001)
    replayCursor = replayCursor + rt * framesPerSecond * replayRate
    if replayCursor < 0 then replayCursor = 0 end
    if replayCursor > sim.replayFrames - 1 then replayCursor = sim.replayFrames - 1 end
    local frame = math.floor(replayCursor)
    ac.setReplayPosition(frame, replayCursor - frame)
  end

  if audioProbeOn then
    ac.setAudioVolume(ac.AudioChannel.Main, audioValue)
  end

  if not cameraActive() then return end

  -- ownShare ramp -- candidate fix for issue #16 (camera jump on activation).
  if ownShareRampSpeed ~= 0 then
    local delta = ownShareTarget - ownShare
    local step = ownShareRampSpeed * rt
    if math.abs(delta) <= step then
      ownShare = ownShareTarget
      ownShareRampSpeed = 0
      log(string.format('ownShare ramp done -> %.2f', ownShare))
    elseif delta > 0 then
      ownShare = ownShare + step
    else
      ownShare = ownShare - step
    end
  end
  cam.ownShare = ownShare

  -- Compare what AC reports now against what we asked for last frame.
  if requestedPos ~= nil then
    local actual = cam.transformOriginal.position
    local dx = actual.x - requestedPos.x
    local dy = actual.y - requestedPos.y
    local dz = actual.z - requestedPos.z
    readbackError = math.sqrt(dx * dx + dy * dy + dz * dz)
    if readbackError > readbackErrorMax then readbackErrorMax = readbackError end
  end

  local transform = cam.transform

  if mode == MODE_ORBIT and anchor ~= nil then
    -- Constant-speed orbit: any stutter is obvious to the eye.
    orbitTime = orbitTime + rt
    local radius = 8
    local x = anchor.x + math.cos(orbitTime * 0.4) * radius
    local y = anchor.y + 2
    local z = anchor.z + math.sin(orbitTime * 0.4) * radius
    transform.position = vec3(x, y, z)
    -- AC convention: Y is vertical.
    local dir = vec3(anchor.x - x, anchor.y - y, anchor.z - z)
    dir:normalize()
    transform.look = dir
    transform.up = vec3(0, 1, 0)
  elseif mode == MODE_SNAPSHOT and snapshot ~= nil then
    -- Replay a pose captured while AC still owned the camera. Feed copies: the
    -- matrix gets normalized after this, which could otherwise edit the stored
    -- snapshot in place and let it drift frame after frame.
    local sp, sl, su = snapshot.pos, snapshot.look, snapshot.up
    transform.position = vec3(sp.x, sp.y, sp.z)
    transform.look = vec3(sl.x, sl.y, sl.z)
    transform.up = vec3(su.x, su.y, su.z)
  elseif mode == MODE_PLAYBACK and doc ~= nil then
    runPlayback(transform)

  elseif mode == MODE_MOUSELOOK and anchor ~= nil then
    lookActive = ac.isKeyDown(ac.KeyIndex.Shift)
    if lookActive then
      local delta = uiState.mouseDelta
      lookYaw = lookYaw - delta.x * lookSensitivity * 0.01
      lookPitch = lookPitch - delta.y * lookSensitivity * 0.01
      -- Stop just short of straight up/down, where yaw becomes meaningless.
      if lookPitch > 1.5 then lookPitch = 1.5 end
      if lookPitch < -1.5 then lookPitch = -1.5 end
    end
    local cp = math.cos(lookPitch)
    transform.position = vec3(anchor.x, anchor.y, anchor.z)
    transform.look = vec3(cp * math.sin(lookYaw), math.sin(lookPitch), cp * math.cos(lookYaw))
    transform.up = vec3(0, 1, 0)
  else
    -- MODE_HOLD: re-apply AC's own transform. With ownShare = 1 the view must
    -- stay visually identical to AC. If it does not, the grab itself is lossy.
    local original = cam.transformOriginal
    transform.position = original.position
    transform.look = original.look
    transform.up = original.up
  end

  local p = transform.position
  requestedPos = vec3(p.x, p.y, p.z)

  if playbackFov ~= nil then
    cam.fov = playbackFov
  elseif applyFov then
    cam.fov = fovDeg
  else
    cam.fov = cam.fovOriginal
  end

  if applyDof then
    cam.dofFactor = dofFactor
    cam.dofDistance = dofDistance
  else
    cam.dofFactor = cam.dofFactorOriginal
  end
end

-- The app has to keep working with its window closed: watching a replay means
-- not having a panel on screen. LAZY = PARTIAL keeps the script loaded, and
-- WORLD_UPDATE drives it per frame regardless of the window. script.update is
-- kept as well, since which of the two CSP calls is not something that can be
-- settled by reading the SDK -- the shipped apps disagree. The frame guard
-- above makes running both harmless.
function script.update(dt)
  perFrame(dt)
end

function script.simUpdate(dt)
  perFrame(dt)
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

local function keyState(label, keyIndex)
  local down = ac.isKeyDown(keyIndex)
  ui.text(label .. ':')
  ui.sameLine()
  ui.textColored(down and 'DOWN' or 'up', down and COLOR_OK or COLOR_IDLE)
end

local function drawContext()
  ui.header('Context')
  ui.text(string.format('replay active: %s   frames: %d',
    tostring(sim.isReplayActive), num(sim.replayFrames)))
  ui.text(string.format('frame %d   playbackRate %.2f (read-only)',
    num(sim.replayCurrentFrame), num(sim.replayPlaybackRate)))

end

local function drawLiveCamera()
  ui.separator()
  ui.header('10. AC live camera (read without holding)')
  ui.text('pos:  ' .. fmtVec(ac.getCameraPosition()))
  ui.text('fwd:  ' .. fmtVec(ac.getCameraForward()))
  ui.text('up:   ' .. fmtVec(ac.getCameraUp()))
  ui.text(string.format('fov:  %.2f deg', num(ac.getCameraFOV())))
  if cameraActive() then
    ui.textColored('camera is held -- these may be frozen, release to test', COLOR_BAD)
  end
  if ui.button('Take snapshot') then snapshotTake() end
  if snapshot ~= nil then
    ui.text('snapshot pos: ' .. fmtVec(snapshot.pos))
  else
    ui.textColored('no snapshot yet', COLOR_IDLE)
  end

end

local function drawGrab()
  ui.separator()
  ui.header('1-2. Camera grab and read-back')
  if cameraActive() then
    ui.textColored('camera HELD by this app', COLOR_OK)
    if ui.button('Release camera') then releaseCamera() end
  else
    ui.textColored('camera not held', COLOR_IDLE)
    if ui.button('Grab camera') then grabCamera() end
    if grabError ~= nil then ui.textColored(grabError, COLOR_BAD) end
  end

  if cameraActive() then
    ui.text('anchor: ' .. fmtVec(anchor))
    ui.text('reported now: ' .. fmtVec(cam.transformOriginal.position))
    ui.text('look: ' .. fmtVec(cam.transform.look))
    ui.text('up:   ' .. fmtVec(cam.transform.up))
    ui.textColored(string.format('read-back error: %.4f m (max %.4f)',
      readbackError, readbackErrorMax),
      readbackErrorMax < 0.01 and COLOR_OK or COLOR_BAD)

    ui.separator()
    ui.header('3. Motion -- stutter test (#20)')
    if ui.radioButton('Hold (mirror AC)', mode == MODE_HOLD) then mode = MODE_HOLD end
    if ui.radioButton('Orbit anchor', mode == MODE_ORBIT) then mode = MODE_ORBIT end
    if ui.radioButton('Restore snapshot (10)', mode == MODE_SNAPSHOT) then mode = MODE_SNAPSHOT end
    if snapshot == nil and mode == MODE_SNAPSHOT then
      ui.textColored('take a snapshot first, before grabbing', COLOR_BAD)
    end
    if ui.radioButton('Mouse look (11)', mode == MODE_MOUSELOOK) then mode = MODE_MOUSELOOK end
    if ui.radioButton('Play CamTool 2 file (12)', mode == MODE_PLAYBACK) then mode = MODE_PLAYBACK end
    if mode == MODE_PLAYBACK and doc == nil then
      ui.textColored('load a file below first', COLOR_BAD)
    end

    if mode == MODE_MOUSELOOK then
      ui.textColored(lookActive and 'LOOKING (Shift held)' or 'hold Shift to look around',
        lookActive and COLOR_OK or COLOR_IDLE)
      lookSensitivity = ui.slider('##lookSens', lookSensitivity, 0.05, 2, 'sensitivity %.2f')
      ui.text(string.format('yaw %.2f rad   pitch %.2f rad', lookYaw, lookPitch))
    end

    ui.separator()
    ui.header('4. ownShare ramp (#16)')
    ownShare = ui.slider('##ownShare', ownShare, 0, 1, 'ownShare %.2f')
    if ui.button('Ramp 0 -> 1 over 1s') then
      ownShare = 0
      ownShareTarget = 1
      ownShareRampSpeed = 1
      log('ownShare ramp 0 -> 1 started')
    end
    ui.sameLine()
    if ui.button('Ramp 1 -> 0 over 1s') then
      ownShare = 1
      ownShareTarget = 0
      ownShareRampSpeed = 1
      log('ownShare ramp 1 -> 0 started')
    end

    ui.separator()
    ui.header('5. FOV -- near clipping (#38)')
    if ui.checkbox('Apply FOV', applyFov) then applyFov = not applyFov end
    fovDeg = ui.slider('##fov', fovDeg, 2, 90, 'FOV %.1f deg')
    ui.text(string.format('AC original FOV: %.2f deg', num(cam.fovOriginal)))

    ui.separator()
    ui.header('6. DOF')
    if ui.checkbox('Apply DOF', applyDof) then applyDof = not applyDof end
    dofFactor = ui.slider('##dofFactor', dofFactor, 0, 1, 'factor %.2f')
    dofDistance = ui.slider('##dofDistance', dofDistance, 0.5, 200, 'distance %.1f m', 2)
  end

end

local function drawPlayback()
  ui.separator()
  ui.header('12. Play a real CamTool 2 camera')

  if ui.checkbox('list every track', showAllTracks) then
    showAllTracks = not showAllTracks
    refreshFileList()
  end

  if #files == 0 then
    if ui.button('Find CamTool 2 files') then refreshFileList() end
    if filePrefix ~= '' then
      ui.textColored('none matching ' .. filePrefix, COLOR_IDLE)
    end
  else
    ui.text(string.format('%d files for %s', #files, filePrefix))
    ui.sameLine()
    if ui.button('Rescan') then refreshFileList() end

    local label = fileIndex >= 1 and files[fileIndex] or '(pick a file)'
    if ui.button('< prev') then
      fileIndex = fileIndex - 1
      if fileIndex < 1 then fileIndex = #files end
    end
    ui.sameLine()
    if ui.button('next >') then
      fileIndex = fileIndex + 1
      if fileIndex > #files then fileIndex = 1 end
    end
    ui.text(label)

    if ui.button('Load this file') then loadSelectedFile() end
  end

  if docError ~= nil then
    ui.textColored(docError, COLOR_BAD)
  end

  if doc ~= nil then
    ui.textColored(string.format('%s -- %d cameras, %s',
      docName, dataModule.cameraCount(doc), tostring(doc.interpolation_mode)), COLOR_OK)

    if ui.radioButton('pos list', listName == 'pos') then listName = 'pos' end
    ui.sameLine()
    if ui.radioButton('time list', listName == 'time') then listName = 'time' end
    ui.text(string.format('%d cameras in this list', #(doc[listName] or {})))

    ui.text(string.format('track pos %.5f   active camera %s',
      trackPos, tostring(activeCam)))

    local v = evaluated
    if v.loc_x ~= nil then
      ui.text(string.format('loc  %.2f %.2f %.2f', v.loc_x, v.loc_y or 0, v.loc_z or 0))
    end
    if v.camera_fov ~= nil then
      ui.text(string.format('fov  %.2f deg', v.camera_fov))
    end
    ui.text(string.format('rot  pitch %.3f  roll %.3f  head %.3f',
      v.rot_x or 0, v.rot_y or 0, v.rot_z or 0))

    ui.separator()
    ui.text('Aim')
    if ui.checkbox('track the car', applyTracking) then applyTracking = not applyTracking end
    ui.sameLine()
    if ui.checkbox('apply roll', applyRoll) then applyRoll = not applyRoll end

    ui.text(string.format('heading applied %.3f  (keyframed %s, aim %.3f)',
      num(appliedHeading),
      v.rot_z and string.format('%.3f', v.rot_z) or 'none -- holds',
      num(aimedHeading)))
    ui.text(string.format('pitch   applied %.3f  (keyframed %s, aim %.3f)',
      num(appliedPitch),
      v.rot_x and string.format('%.3f', v.rot_x) or 'none -- holds',
      num(aimedPitch)))
    ui.textColored(string.format('tracking strength in use: %.2f', num(aimStrength)),
      aimStrength > 0 and COLOR_OK or COLOR_IDLE)
    ui.text(string.format('tracking offset %.3f  (%s)', num(aimOffset),
      aimOffset < 0 and 'leads the car' or (aimOffset > 0 and 'trails it' or 'aims at it')))
    if ui.checkbox('follow the recorded spline', applySpline) then
      applySpline = not applySpline
    end
    if doc ~= nil and activeCam ~= nil and doc[listName] ~= nil then
      local c = doc[listName][activeCam]
      if c ~= nil and spline.exists(c) then
        ui.textColored(string.format('spline: %d points, read at %.4f',
          #c.spline.the_x, splineQuery), COLOR_OK)
        ui.text(string.format('  affect xy %.2f  z %.2f  heading %.2f',
          num(c.spline_affect_loc_xy), num(c.spline_affect_loc_z),
          num(c.spline_affect_heading)))
      else
        ui.textColored('this camera has no recorded spline', COLOR_IDLE)
      end
    end

    if ui.checkbox('aim straight at the car (no lead)', ignoreLead) then
      ignoreLead = not ignoreLead
    end
    if ui.checkbox('legacy startup transient (#16)', legacyZeroFill) then
      legacyZeroFill = not legacyZeroFill
      carHistory = tracking.new(nil, legacyZeroFill)
      log('car history reset, legacy zero fill = ' .. tostring(legacyZeroFill))
    end

    -- Forcing the strength is a diagnostic: it tells apart "tracking is wrong"
    -- from "this camera barely tracks".
    trackingOverride = ui.slider('##trackOverride', trackingOverride, -1, 1,
      trackingOverride < 0 and 'strength: from file' or 'strength forced to %.2f')
  end

end

local function drawReplay()
  ui.separator()
  ui.header('7. Replay driving (SetReplaySpeed)')
  replayRate = ui.slider('##replayRate', replayRate, -2, 2, 'rate %.2fx')
  if replayDriveOn then
    ui.textColored(string.format('driving, cursor %.2f', replayCursor), COLOR_OK)
    if ui.button('Stop driving replay') then replayStop() end
  else
    if ui.button('Drive replay') then replayStart() end
  end

end

local function drawAudio()
  ui.separator()
  ui.header('8. Audio (GetVolume / SetVolume)')
  if audioProbeOn then
    ui.textColored('overriding main volume', COLOR_OK)
    audioValue = ui.slider('##audio', audioValue, 0, 1, 'volume %.2f')
    if ui.button('Stop and restore') then audioStop() end
  else
    if ui.button('Take over main volume') then audioStart() end
  end

end

local function drawKeys()
  ui.separator()
  ui.header('9. Modifier keys (IsAsyncKeyPressed)')
  keyState('Shift', ac.KeyIndex.Shift)
  ui.sameLine()
  keyState('Ctrl', ac.KeyIndex.Control)
  ui.sameLine()
  keyState('Alt', ac.KeyIndex.Menu)
  ui.text(string.format('ui.hotkey: ctrl %s  alt %s  shift %s',
    tostring(ui.hotkeyCtrl()), tostring(ui.hotkeyAlt()), tostring(ui.hotkeyShift())))

end

local function drawLog()
  ui.separator()
  ui.header('Log')
  for i = 1, #logLines do
    ui.text(logLines[i])
  end
end

function script.windowMain(dt)
  drawContext()
  drawLiveCamera()
  drawGrab()
  drawPlayback()
  drawReplay()
  drawAudio()
  drawKeys()
  drawLog()
end


--------------------------------------------------------------------------------
-- Teardown. LAZY = FULL unloads the app once its window is closed; ac.onRelease
-- fires then, so no probe can outlive the app and leave the camera grabbed or
-- the main volume turned down.
--------------------------------------------------------------------------------

ac.onRelease(function()
  releaseCamera()
  replayStop()
  audioStop()
end)
