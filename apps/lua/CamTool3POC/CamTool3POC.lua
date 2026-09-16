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

-- CamTool stores Z-up; AC is Y-up. Confirmed twice: the track splines put all
-- the elevation in loc_z (Spa spans 102 m, which is Eau Rouge), and
-- CamToolTool.get_position maps CamTool axis 2 to CSP axis 1.
local function toWorld(x, y, z)
  return vec3(x, z, y)
end

-- The angle conventions are the one thing here that cannot be settled by
-- reading code: CamTool's heading zero and sign have to match AC's, and the
-- legacy went through the DLL for this. Rather than guess and iterate over
-- several sessions, expose the choices and let one in-game pass settle it.
local yawSign = 1
local pitchSign = 1
local yawOffsetDeg = 0
local applyRoll = true

-- Set by the playback branch each frame, cleared at the top of every update.
local playbackFov = nil

local function refreshFileList()
  files = storage.listCameraFiles()
  fileIndex = 0
  log(string.format('found %d CamTool 2 camera files', #files))
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

function script.update(dt)
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
    local pos = focusedTrackPosition()
    if pos ~= nil then
      trackPos = pos
      local cameras = doc[listName]
      activeCam = evaluate.activeCameraIndex(cameras, pos)

      if activeCam ~= nil then
        evaluated = evaluate.all(cameras[activeCam], pos)
        local v = evaluated

        if v.loc_x ~= nil and v.loc_y ~= nil and v.loc_z ~= nil then
          transform.position = toWorld(v.loc_x, v.loc_y, v.loc_z)
        end

        -- rot_x is pitch, rot_y is roll, rot_z is heading. Named explicitly in
        -- InterpolateFrame.py, so this part is not guesswork -- only the sign
        -- and zero of the angles are.
        local yaw = (v.rot_z or 0) * yawSign + yawOffsetDeg * math.pi / 180
        local pitch = (v.rot_x or 0) * pitchSign
        local cp = math.cos(pitch)
        local look = vec3(cp * math.sin(yaw), math.sin(pitch), cp * math.cos(yaw))
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

  if #files == 0 then
    if ui.button('Find CamTool 2 files') then refreshFileList() end
  else
    ui.text(string.format('%d files', #files))
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
    ui.text('Angle convention -- flip these until it matches CamTool 2')
    if ui.checkbox('invert heading', yawSign < 0) then yawSign = -yawSign end
    ui.sameLine()
    if ui.checkbox('invert pitch', pitchSign < 0) then pitchSign = -pitchSign end
    if ui.checkbox('apply roll', applyRoll) then applyRoll = not applyRoll end
    yawOffsetDeg = ui.slider('##yawOffset', yawOffsetDeg, -180, 180, 'heading offset %.0f deg')
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
