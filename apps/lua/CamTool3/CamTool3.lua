--[[
  CamTool 3 -- cinematic replay camera for Assetto Corsa, on CSP Lua.

  Reads the camera files CamTool 2 wrote, migrates them, and plays them back:
  the camera the car's track position selects, every keyframed parameter through
  the ported interpolators, tracking with lead, and recorded splines.

  The playback itself is in core/playback.lua, which knows nothing of CSP. What
  is left here is the part that has to talk to the game: grabbing the camera,
  reading the sim, drawing the panel. That line is what lets a whole lap be
  replayed out of game -- see tests/lap.lua.

  The numbered probes further down are diagnostics kept from the port. Each maps
  to a row of the DLL table in CLAUDE.md or to a known issue, and they stay
  because they are how a camera problem gets pinned down without guessing.

  Still read only: this app writes no camera file and never touches
  apps/python/CamTool_2. The only global state it changes is the grabbed camera
  and, optionally, the main audio volume, both restored on unload.
]]

local storage = require('adapters/storage')
local trackAdapter = require('adapters/track')
local atrPanel = require('ui/atr')
local cameramode = require('core/cameramode')
local edit = require('core/edit')
local atrParameter = require('ui/parameter')
local angles = require('core/angles')
local spline = require('core/spline')
local seek = require('core/seek')
local filenames = require('core/filename')
local navigate = require('core/navigate')
local playstate = require('core/playstate')
local shortcuts = require('adapters/shortcuts')
local settings = require('adapters/settings')
local playbackCore = require('core/playback')
local pitlane = require('core/pitlane')
local carsCore = require('core/cars')
local mouselookCore = require('core/mouselook')
local cutfadeCore = require('core/cutfade')
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
  ac.log('[CamTool3] ' .. message)
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

-- The playback chain itself lives in core/playback: one state object, one input
-- table refilled each frame, one output table the panel reads back.
local pb = playbackCore.new()
local pbIn = {}
local pbOut = pb.out

-- CamTool stores Z-up; AC is Y-up. Confirmed twice: the track splines put all
-- the elevation in loc_z (Spa spans 102 m, which is Eau Rouge), and
-- CamToolTool.get_position maps CamTool axis 2 to CSP axis 1.
local function toWorld(x, y, z)
  return vec3(x, z, y)
end

-- Aim. The heading and pitch conventions are no longer guessed: they come from
-- Camera.calculate_cam_rot_to_tracking_car via core/angles.lua. The switches
-- below all live in pb.options now; the panel flips them there.
--
-- The shake clock is the replay position in seconds, never wall time, so the
-- same footage shakes identically on every render.
local shakeClockReadout = 0

-- Which Assetto Corsa camera the view has been handed to, or nil while
-- CamTool is driving. Kept so the switch happens on change rather than every
-- frame, which would fight anyone pressing F1 themselves.
local handedTo = nil

-- Set by playback each frame, cleared at the top of every update. Without this,
-- the manual DOF probe below runs afterwards and clobbers the played-back focus
-- with the camera's original factor -- the same trap playbackFov already avoids.
local playbackDofDistance = nil
local playbackDofFactor = nil

---Replay position in seconds. Deterministic on purpose: re-rendering the same
---footage must shake identically, which a wall clock would not give.
local function shakeClock()
  local ms = sim.replayFrameMs
  if type(ms) ~= 'number' or ms <= 0 then return 0 end
  return (sim.replayCurrentFrame or 0) * ms / 1000
end

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

-- Scan for this track's files without being asked, so the list is already there
-- when the panel opens. Driven from the window rather than from load: reading a
-- directory has no business in the per-frame path, and the app stays loaded
-- across a session change, so the track has to be rechecked rather than scanned
-- once and trusted.
local scannedPrefix = nil

local function ensureFileList()
  local prefix = storage.trackPrefix()
  if scannedPrefix == prefix then return end
  scannedPrefix = prefix
  refreshFileList()
end

local function loadSelectedFile()
  if fileIndex < 1 or fileIndex > #files then return end
  local entry = files[fileIndex]
  local name = entry.name
  local loaded, err = storage.loadCameraFile(entry)

  if loaded == nil then
    doc, docError, docName = nil, err, name
    log('load FAILED: ' .. tostring(err))
    return
  end

  doc, docError, docName = loaded, nil, name
  -- Remembered per track, for the next time the app sees this one.
  settings.setLastFile(storage.trackPrefix(), entry)
  -- The file says which maths it wants; see core/playback.applyMode.
  playbackCore.applyMode(pb, loaded.interpolation_mode)
  log(string.format('loaded %s -- %d cameras, version %s, mode %s',
    name, dataModule.cameraCount(loaded), tostring(loaded.version),
    tostring(loaded.interpolation_mode)))

  -- Loading a file is a statement of intent, so select playback here too, not
  -- only on grab. The grab section sits above this one in the window, so
  -- switching on grab alone would depend on which the user clicked first.
  mode = MODE_PLAYBACK
  log('mode: playback')
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

---Is the car the replay is following in the pit lane? The file's own track
---and pit splines decide when it has both, the game otherwise: see
---core/pitlane.
local function focusedCarInPitlane(trackPos, carX, carY)
  local index = sim.focusedCar
  local car = index ~= nil and index >= 0 and ac.getCar(index) or nil
  local gameSays = car ~= nil and car.isInPitlane == true
  return pitlane.isCarInPitlane(doc, trackPos, carX, carY, gameSays)
end

-- The extra car MIX aims towards. Session state, as in CamTool 2: no camera
-- file remembers it. Unlike CamTool 2 it starts as none rather than car 0,
-- which is so often the car being followed that MIX did nothing without
-- saying why.
local extraCar = nil

---The connected cars and where they are on the track, for the arrows.
---Built on a click, not every frame.
local function connectedCars()
  local list = {}
  for i = 0, (sim.carsCount or 1) - 1 do
    local car = ac.getCar(i)
    if car ~= nil and car.isConnected ~= false and car.splinePosition ~= nil then
      list[#list + 1] = { index = i, pos = car.splinePosition }
    end
  end
  return list
end

---The extra car that counts: none when it is the followed car, or gone.
local function effectiveExtraCar()
  if extraCar == nil or extraCar == sim.focusedCar then return nil end
  local car = ac.getCar(extraCar)
  if car == nil or car.isConnected == false then return nil end
  return extraCar
end

---World position of the extra car, in CamTool space, or nil without one.
local function extraCarPosition()
  local index = effectiveExtraCar()
  if index == nil then return nil end
  local car = ac.getCar(index)
  if car.position == nil then return nil end
  return car.position.x, car.position.z, car.position.y
end

local function cameraActive()
  return cam ~= nil and cam:active()
end

local function grabCamera()
  if cameraActive() then return true end
  local grabbed, err = ac.grabCamera('CamTool 3')
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
  playbackCore.resetHistory(pb)
  requestedPos = nil
  readbackError = 0
  readbackErrorMax = 0
  fovDeg = grabbed.fovOriginal
  log(string.format('grab OK -- anchor %s, original FOV %.2f deg',
    fmtVec(anchor), grabbed.fovOriginal))

  -- Grabbing is nearly always a prelude to playing a file back. Switching only
  -- when a file is loaded matters: the playback branch does nothing without
  -- one, so the camera would sit frozen with no clue why.
  if doc ~= nil then
    mode = MODE_PLAYBACK
    log('mode: playback')
  end
  return true
end

local function releaseCamera()
  if cam ~= nil then
    cam:dispose()
    cam = nil
    log('camera released')
  end

  -- And everything the playback last decided goes with it. The per-frame loop
  -- returns early while the camera is not held, so nothing would clear these
  -- otherwise and they would go on reading as current: see
  -- playback.clearOutput for what that cost.
  playbackCore.clearOutput(pb)
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

--------------------------------------------------------------------------------
-- Bringing the car to a point of the track
--------------------------------------------------------------------------------
-- The ribbon says "here" and means a place on the track; a replay is
-- addressed by frame. core/seek holds the arithmetic and the index; what is
-- left here is everything that can only happen against a running game.
--
-- WHY THIS IS A STATE MACHINE AND NOT A LOOP. Moving the replay does not
-- report back until the next frame: ac.setReplayPosition is a request, and
-- where the car ended up can only be read once the game has drawn again. So a
-- correction is spread over frames, one probe each, and the whole thing lives
-- between them.

local seekIndex = nil
---What the index is an index OF. Frames mean nothing across a different
---replay or a different car, so the key changing empties it.
local seekKey = nil
---The seek in progress: target, how many probes are left, and the best
---landing so far.
local seekJob = nil
---Something for the panel to say once the seek is over. Kept here rather than
---written straight into the panel's status: that local is declared hundreds of
---lines below, and assigning it from here would quietly make a global that
---nothing ever reads.
local seekMessage = nil

---Whether the replay is running, steadily. Read, never set: Assetto Corsa has
---no call to pause a replay, so the panel says what is happening and does not
---pretend to decide it.
local playing = playstate.new()

---Set later, once the panel's own state exists to act on. A shortcut has to
---work with the window closed, so it is handled in the frame loop -- which is
---written above everything it needs.
local handleShortcuts = nil


---How close counts as arrived: half a bucket, which is a few metres.
local SEEK_TOLERANCE = 0.5 / seek.BUCKETS
---Probes before giving up and keeping the closest landing. Three to five was
---the estimate; five is the ceiling.
local SEEK_TRIES = 5

local function seekKeyNow()
  return string.format('%s/%s/%d/%d', ac.getTrackID(), ac.getTrackLayout(),
    sim.focusedCar or -1, sim.replayFrames or 0)
end

---Note where the car is, every frame, for nothing.
---
---This is the whole cost of the feature in the hot path: a key comparison, a
---multiply and a store. No allocation, and the index cannot grow.
local function seekRecord(position)
  if not sim.isReplayActive or position == nil then return end

  local key = seekKeyNow()
  if key ~= seekKey then
    seekKey = key
    if seekIndex == nil then seekIndex = seek.new() else seek.clear(seekIndex) end
  end

  seek.record(seekIndex, position, sim.replayCurrentFrame)
end

---Put the replay at a frame, and keep the app's own cursor with it.
---
---The diagnostic panel can drive the replay itself, advancing replayCursor a
---frame at a time. Leaving it behind would have it drag the replay straight
---back to where it was on the next frame.
local function seekGoTo(frame)
  if frame < 0 then frame = 0 end
  local last = math.max((sim.replayFrames or 1) - 1, 0)
  if frame > last then frame = last end

  local whole = math.floor(frame)
  replayCursor = frame
  ac.setReplayPosition(whole, frame - whole)
  return frame
end

---Where the car was last frame, so a teleport can be told from a drive.
local lastCarAt = nil

---How far round the lap the car may move in one frame and still have driven
---there. At 300 km/h a frame covers about 1.4 m, three hundredths of a
---percent of a 5 km circuit; two percent is a hundred metres, which leaves
---plenty of room for a replay running fast and still catches any jump worth
---noticing.
local JUMP_GAP = 0.02

---Whether the playhead is being dragged, and how long since the last jump of
---that drag. Declared up here, ahead of the muffling, because the quiet is
---the one thing a drag changes about an ordinary search.
local scrubbing = false
local scrubClock = 0

---What the volume was before we started jumping the replay about, or nil
---when we are not holding it.
---
---HERE RATHER THAN ON THE JOB, which is where it used to live. A job is one
---search, and the quiet has to last longer than one: dragging the playhead is
---a run of searches, and a volume restored between two of them would put the
---artefact back in the middle of the gesture -- once per jump, which is worse
---than the one it was avoiding.
local muffledVolume = nil

---Quieten the game while the replay is jumping about.
---
---CamTool 2 had audio artefacts on replay position changes. Skipped when the
---audio probe owns the volume: two things writing it would fight.
local function seekMuffle(on)
  if audioProbeOn then return end

  if on then
    if muffledVolume == nil then
      muffledVolume = ac.getAudioVolume(ac.AudioChannel.Main, -1, 1)
      ac.setAudioVolume(ac.AudioChannel.Main, 0)
    end
  elseif muffledVolume ~= nil and not scrubbing then
    -- A search that finishes in the middle of a drag does NOT give the sound
    -- back: the drag is still moving the replay, and the artefact would play
    -- once per jump instead of once per gesture.
    ac.setAudioVolume(ac.AudioChannel.Main, muffledVolume)
    muffledVolume = nil
  end
end

---Begin bringing the car to a lap position. Not an edit: nothing here touches
---camera data, so nothing here goes on the undo stack.
---@param target number @0..1
---@return string|nil @what to tell the user, when there is something to say
local function seekBegin(target)
  if not sim.isReplayActive then return 'no replay to move' end
  if type(target) ~= 'number' or target ~= target then return nil end
  if seekIndex == nil then seekIndex = seek.new() end

  local from = sim.replayCurrentFrame or 0
  local guess = seek.nearest(seekIndex, target, from, 8)

  -- Nothing recorded anywhere near: start from where we are and correct. The
  -- first probe is what makes the second one informed.
  if guess == nil then guess = from end

  seekJob = {
    target = target,
    tries = SEEK_TRIES,
    bestFrame = nil,
    bestGap = nil,
    lastFrame = nil,
    lastPosition = nil,
    pace = seek.framesPerLap(seekIndex),
  }
  seekMuffle(true)
  seekJob.lastFrame = seekGoTo(guess)
  return nil
end

---One probe: read where the last jump landed, and decide what to do about it.
local function seekStep(position)
  if seekJob == nil then return end

  if not sim.isReplayActive or position == nil then
    seekMuffle(false)
    seekJob = nil
    return
  end

  local gap = seek.gap(position, seekJob.target)

  -- Every landing teaches the index something, including the ones that missed.
  seek.record(seekIndex, position, sim.replayCurrentFrame)

  if seekJob.bestGap == nil or gap < seekJob.bestGap then
    seekJob.bestGap, seekJob.bestFrame = gap, sim.replayCurrentFrame
  end

  if gap <= SEEK_TOLERANCE then
    seekMuffle(false)
    seekJob = nil
    return
  end

  -- Two landings are a measurement of the lap, for a replay too short for the
  -- index to have measured one.
  if seekJob.pace == nil and seekJob.lastPosition ~= nil then
    seekJob.pace = seek.paceFrom(seekJob.lastFrame, seekJob.lastPosition,
      sim.replayCurrentFrame, position)
  end
  if seekJob.pace == nil then seekJob.pace = math.max(sim.replayFrames or 1, 1) end

  seekJob.tries = seekJob.tries - 1
  if seekJob.tries <= 0 then
    -- Out of tries: sit at the closest we managed and say so, rather than
    -- leave the replay wherever the last guess happened to land.
    if seekJob.bestFrame ~= nil then seekGoTo(seekJob.bestFrame) end
    seekMessage = string.format(
      'the car never passes there in this replay -- closest is %.0f m away',
      (seekJob.bestGap or 0) * (sim.trackLengthM or 0))
    seekMuffle(false)
    seekJob = nil
    return
  end

  seekJob.lastFrame, seekJob.lastPosition = sim.replayCurrentFrame, position
  local next_ = seek.refine(sim.replayCurrentFrame, position, seekJob.target,
    seekJob.pace, math.max((sim.replayFrames or 1) - 1, 0))
  if next_ == nil then
    seekMuffle(false)
    seekJob = nil
    return
  end
  seekGoTo(next_)
end

--------------------------------------------------------------------------------
-- Scrubbing
--------------------------------------------------------------------------------
-- Dragging the playhead along the ruler, which is a seek that has to keep up
-- with a hand rather than land exactly.
--
-- SO IT IS DELIBERATELY ROUGH. One jump every tenth of a second, one probe
-- each, no convergence: a drag crosses fifty positions in the time the full
-- five-probe search would settle on the first of them, and running that
-- search per frame would ask the game to reload the replay sixty times a
-- second. What the eye wants during a drag is the picture moving with the
-- hand, and a jump into the right corner is enough for that.
--
-- THE EXACT LANDING COMES ON RELEASE, once, by the ordinary search -- which
-- is also when being a few metres out would start to matter, because that is
-- when someone looks at the frame they landed on.

---How long between two jumps while a drag runs, in seconds.
---
---A tenth of a second. Fast enough to read as following the hand, slow enough
---that the game is asked to move the replay ten times a second and not sixty.
local SCRUB_INTERVAL = 0.1

---Follow a drag. Called every frame the playhead is being dragged.
---@param target number @0..1, where the pointer is now
---@param dt number @seconds since the last frame
local function scrubTo(target, dt)
  if not sim.isReplayActive then return end
  if type(target) ~= 'number' or target ~= target then return end
  if seekIndex == nil then seekIndex = seek.new() end

  -- A search left over from before the drag, or started by the one before
  -- this, would go on probing once a frame underneath it.
  seekJob = nil

  if not scrubbing then
    scrubbing = true
    -- The clock starts satisfied, so the first frame of the drag moves the
    -- replay at once. Waiting a tenth of a second to react to a press is the
    -- one delay anybody would notice.
    scrubClock = SCRUB_INTERVAL
    -- Quiet for the whole gesture, not for each jump: see muffledVolume.
    seekMuffle(true)
  end

  scrubClock = scrubClock + (type(dt) == 'number' and dt == dt and dt or 0)
  if scrubClock < SCRUB_INTERVAL then return end
  scrubClock = 0

  local from = sim.replayCurrentFrame or 0
  local guess = seek.nearest(seekIndex, target, from, 8)

  if guess ~= nil then
    seekGoTo(guess)
    return
  end

  -- Nowhere near anything recorded, which is every stretch the replay has not
  -- played yet. One step of the arithmetic then, and one only.
  --
  -- NOT the ordinary search, and this is the whole reason a drag has code of
  -- its own: that search probes once per FRAME until it converges, which is
  -- exactly the sixty-jumps-a-second this is here to avoid. Here a wrong
  -- landing is simply left standing until the next tick, a tenth of a second
  -- later -- by which time the frame loop has recorded where it landed, so
  -- the correction is better informed than a second probe would have been.
  -- Over a drag lasting a second that is ten corrections, which reads as
  -- following the hand.
  local here = focusedTrackPosition()
  if here == nil then return end

  -- A pace for a replay too short to have measured one: assume the whole of
  -- it is a lap. Wrong, and it is a first guess, which the next tick refines.
  local pace = seek.framesPerLap(seekIndex)
    or math.max(sim.replayFrames or 1, 1)

  local next_ = seek.refine(from, here, target, pace,
    math.max((sim.replayFrames or 1) - 1, 0))
  if next_ ~= nil then seekGoTo(next_) end
end

---Let go. The landing itself arrives as an ordinary seek, so all this has to
---do is stop following.
local function scrubStop()
  scrubbing = false
end


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

---Drive the grabbed camera from the camera file, for one frame.
---
---Everything below the surface is in core/playback: this reads the sim, hands
---it over as plain numbers, and writes the answer back to the transform. That
---split is what lets tests/lap.lua run a whole lap out of game.
--------------------------------------------------------------------------------
-- Mouse look, CamTool 2's Alt + mouse. The maths is core/mouselook; this is
-- where it meets the game.
--
-- Two cases, as in CamTool 2. With the camera held, the playback blends the
-- file with the mouse by the weight. On Assetto Corsa's free camera, with
-- nothing held, the free camera itself is steered -- the case people use to
-- aim a shot before pinning it.
--------------------------------------------------------------------------------

local look = mouselookCore.new()
local lookOut = { heading = 0, pitch = 0, fov = nil, weight = 0 }

---How far mouse look may tilt the free camera, radians. Same as the playback.
local LOOK_PITCH_LIMIT = 1.5

---Is the pointer on a window -- ours or any app's? A click there is meant for
---the window, not for the camera.
local function pointerOnWindow()
  if uiState.wantCaptureMouse then return true end
  if ui ~= nil and ui.mouseBusy ~= nil then
    local ok, busy = pcall(ui.mouseBusy)
    if ok and busy then return true end
  end
  return false
end

---The lens the mouse zooms from: the held camera's, or the free camera's.
local function currentLens()
  if cameraActive() then return cam.fov end
  if ac.getCameraFOV ~= nil then return ac.getCameraFOV() end
  return nil
end

---One step of mouse look. Every frame, held or not: the hand-back and the
---zoom easing run on their own clocks.
local function mouseLookFrame(rt)
  local held = shortcuts.down('mouseLook')
  local delta = uiState.mouseDelta
  local size = uiState.windowSize
  local lens = currentLens()

  lookOut = mouselookCore.update(look, {
    dt = rt,
    held = held,
    steering = held and uiState.isMouseLeftKeyDown == true and not pointerOnWindow(),
    dx = delta ~= nil and delta.x or 0,
    dy = delta ~= nil and delta.y or 0,
    screenW = size ~= nil and size.x or nil,
    screenH = size ~= nil and size.y or nil,
    fov = lens,
    zoomIn = held and shortcuts.down('zoomIn'),
    zoomOut = held and shortcuts.down('zoomOut'),
    camera = pbOut.activeCam,
  })

  -- The free camera, when nothing is held. CamTool 2 did this without
  -- asking, since its camera calls went through the free camera anyway.
  if cameraActive() or sim.cameraMode ~= ac.CameraMode.Free then return end

  if (lookOut.heading ~= 0 or lookOut.pitch ~= 0)
      and ac.getCameraForward ~= nil and ac.setCameraDirection ~= nil then
    local f = ac.getCameraForward()
    local heading, pitch = angles.fromLook(f.x, f.y, f.z)
    heading = heading + lookOut.heading
    pitch = math.max(-LOOK_PITCH_LIMIT, math.min(LOOK_PITCH_LIMIT, pitch + lookOut.pitch))
    local lx, ly, lz = angles.lookVector(heading, pitch)
    ac.setCameraDirection(vec3(lx, ly, lz))
  end

  if lookOut.fov ~= nil and lens ~= nil and lookOut.fov ~= lens
      and ac.setCameraFOV ~= nil then
    ac.setCameraFOV(lookOut.fov)
  end
end

--------------------------------------------------------------------------------
-- The sound after a cut, see core/cutfade. Through the master multiplier,
-- which CSP offers for exactly this and which touches neither the player's
-- own volume setting nor the channel the seek muffles.
--------------------------------------------------------------------------------

local cutFade = cutfadeCore.new()
local audioMultiplier = 1

local function setAudioMultiplier(value)
  if value == audioMultiplier or ac.setAudioVolumeMultiplier == nil then return end
  ac.setAudioVolumeMultiplier(value)
  audioMultiplier = value
end

local function runPlayback(transform)
  -- The legacy reads the camera's CURRENT heading every frame
  -- (ctt.get_heading()) and falls back to it whenever the heading is not
  -- keyframed, so an unkeyframed camera holds its aim instead of snapping to a
  -- fixed direction. 18% of the reference cameras never keyframe rot_z, so this
  -- is not an edge case. A grabbed camera's transformOriginal freezes at
  -- ownShare = 1, so playback carries the previous frame's value instead and
  -- only needs seeding once, on the first frame after a grab.
  if not pb.haveAim then
    local look = cam.transformOriginal.look
    pbIn.seedHeading, pbIn.seedPitch = angles.fromLook(look.x, look.y, look.z)
    -- Same for the focus the camera is already holding, so the first frame
    -- that holds rather than refocuses does not snap the plane to zero.
    pbIn.seedFocus = cam.dofDistanceOriginal
  end

  pbIn.trackPos = focusedTrackPosition()
  pbIn.carX, pbIn.carY, pbIn.carZ = focusedCarPosition()
  pbIn.inPitlane = focusedCarInPitlane(pbIn.trackPos, pbIn.carX, pbIn.carY)
  pbIn.extraCar = effectiveExtraCar()
  pbIn.extraX, pbIn.extraY, pbIn.extraZ = extraCarPosition()
  pbIn.manualWeight = lookOut.weight
  pbIn.manualHeading, pbIn.manualPitch = lookOut.heading, lookOut.pitch
  pbIn.manualFov = lookOut.fov
  pbIn.replayRate = sim.replayPlaybackRate
  pbIn.clock = shakeClock()
  shakeClockReadout = pbIn.clock

  local out = playbackCore.frame(pb, doc, pbIn)
  if not out.active then return end

  ------------------------------------------------------------------
  -- Cameras that hand the view to Assetto Corsa
  ------------------------------------------------------------------
  -- Eleven of the reference cameras do this, and until now the port drove
  -- its own camera straight through them. Handing over means two things:
  -- ask AC for the camera the file names, and stop writing the transform --
  -- ownShare at zero lets AC's own view through the grab we are still
  -- holding, so coming back is a matter of putting it back.
  -- Last frame's hand-over, read back now that AC has had a frame to obey it.
  if checkHandOver ~= nil then
    local asked = checkHandOver
    checkHandOver = nil
    if asked.drivable ~= nil and sim.driveableCameraMode ~= nil
        and sim.driveableCameraMode ~= asked.drivable then
      log(string.format(
        'WARNING %s asked for drivable camera %d, Assetto Corsa settled on %d',
        asked.label, asked.drivable, sim.driveableCameraMode))
    end
  end

  local handOver = cameramode.find(out.specificCam)
  if handOver ~= nil then
    if handedTo ~= handOver.value then
      handedTo = handOver.value
      ac.setCurrentCamera(ac.CameraMode[handOver.mode])
      -- CamTool 2 could not ask for these: for the F1 family it pressed F1
      -- the right number of times from a remembered offset, which is why it
      -- needed the user to line the view up first. These two calls are what
      -- CSP added, and what makes the manual sync unnecessary.
      if handOver.drivable ~= nil then
        ac.setCurrentDrivableCamera(handOver.drivable)
      end
      if handOver.carCamera ~= nil then
        ac.setCurrentCarCamera(handOver.carCamera)
      end
      log('camera ' .. tostring(out.activeCam) .. ' hands the view to '
        .. handOver.label)
      -- Check next frame that this is the camera the game actually took.
      --
      -- The sixth of the F1 family is the reason. CamTool 2 walks that family
      -- modulo SIX (CamMode.changeCamModeZero) so its cycle has six
      -- positions, while ac.DrivableCamera names five. Asking for the sixth
      -- could have landed back on the fifth, which would make "steering
      -- wheel" and "cockpit" the same view. It does not -- confirmed in game,
      -- the enum is simply incomplete.
      --
      -- The check stays anyway: another CSP build need not behave the same,
      -- and a camera quietly swapped for its neighbour is invisible from
      -- anywhere else.
      checkHandOver = handOver
    end
    cam.ownShare = 0
    return
  end

  if handedTo ~= nil then
    handedTo = nil
    ac.setCurrentCamera(ac.CameraMode.Free)
    cam.ownShare = ownShare
    log('taking the view back')
  end

  if out.x ~= nil then
    transform.position = toWorld(out.x, out.y, out.z)
  end
  transform.look = vec3(out.lookX, out.lookY, out.lookZ)
  transform.up = vec3(out.upX, out.upY, out.upZ)

  playbackFov = out.fov
  playbackDofDistance = out.dofDistance
  playbackDofFactor = out.dofFactor
end

-- Both entry points below can fire in the same render frame depending on how
-- CSP is configured, and the work must happen exactly once: running twice would
-- advance the replay cursor and the car history double.
local lastFrame = -1

---A hand-over asked for last frame, waiting to be checked against what
---Assetto Corsa actually did with it. See where it is set.
local checkHandOver = nil

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
  playbackDofDistance = nil
  playbackDofFactor = nil

  -- Is it running? One reading, and Assetto Corsa's own: getGameDeltaT is
  -- zero when the sim OR the replay is paused, whoever paused it.
  playstate.update(playing, ac.getGameDeltaT ~= nil and ac.getGameDeltaT() or nil)

  if handleShortcuts ~= nil then handleShortcuts() end

  -- Where the car is, noted for nothing, so the ribbon can ask later. Before
  -- the early return below: the index has to build whether or not the camera
  -- is held, since it is the watching that fills it in.
  local carAt = focusedTrackPosition()

  -- A JUMP, NOT A DRIVE. The aim is a blend of the car's last fifty
  -- positions, so the frame after a scrub they are all about a stretch of
  -- track the car has left, and the aim walks from there to here over the
  -- best part of a second. Throwing the history away is the whole of the fix,
  -- and the function that does it was already there for the grab.
  --
  -- Watched on the car's own position rather than on our own seeks, so that
  -- dragging Assetto Corsa's replay bar counts too -- which is what issue #16
  -- actually describes.
  --
  -- Worth keeping in proportion: measured, this is about a degree of drift
  -- decaying over fifty frames, and only when the car jumps ACROSS the line
  -- of sight. It is not the whole of #16.
  if carAt ~= nil and lastCarAt ~= nil then
    local moved = seek.gap(lastCarAt, carAt)
    if moved ~= nil and moved > JUMP_GAP then
      playbackCore.jumped(pb)
    end
  end
  lastCarAt = carAt

  seekRecord(carAt)

  -- And a seek in progress reads where its last jump landed. Also before the
  -- return: bringing the car somewhere has nothing to do with holding the
  -- camera.
  if seekJob ~= nil then seekStep(carAt) end

  if replayDriveOn and seekJob == nil
      and sim.isReplayActive and sim.replayFrames > 1 then
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

  mouseLookFrame(rt)

  -- Only a held camera cuts. CamTool 2 dipped the sound at every camera
  -- boundary even switched off, since it worked the live camera out anyway.
  if not cameraActive() then
    cutfadeCore.reset(cutFade)
    setAudioMultiplier(1)
    return
  end

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

  if mode == MODE_PLAYBACK then
    setAudioMultiplier(cutfadeCore.update(cutFade, rt,
      pbOut.active and pbOut.activeCam or nil, sim.focusedCar))
  else
    setAudioMultiplier(1)
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

  if playbackDofDistance ~= nil then
    cam.dofDistance = playbackDofDistance
    cam.dofFactor = playbackDofFactor
  elseif applyDof then
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

---Can Assetto Corsa tell us what this part of the track is called?
---
---A probe rather than a feature, and the question is narrow: `sections.ini`
---in a track's data folder defines IN / OUT / TEXT per section -- Théo's
---example is Imola's `TEXT=Tamburello` -- and CSP's ac.getTrackSectorName is
---very probably the accessor for exactly that file. Very probably is not good
---enough to wire a naming suggestion on, because if it answers "Sector 2"
---everywhere then suggesting it is worse than suggesting nothing.
---
---So: read it out loud, at the car and at eight points around the lap, and
---look. If the names are real, the rename field can offer one; if they are
---generic, nothing is lost but this panel.
local function drawSectionNames()
  ui.separator()
  ui.header('11. Track section names (sections.ini)')

  if type(ac.getTrackSectorName) ~= 'function'
      and ac.getTrackSectorName == nil then
    ui.textColored('ac.getTrackSectorName is not in this CSP build', COLOR_IDLE)
    return
  end

  local here = focusedTrackPosition()
  if here ~= nil then
    local ok, name = pcall(ac.getTrackSectorName, here)
    ui.text(string.format('at the car (%.3f): %s',
      here, ok and tostring(name) or ('raised: ' .. tostring(name))))
  end

  -- Eight points around the lap: one name repeated is a generic answer, eight
  -- different ones are real section names.
  local line = {}
  for i = 0, 7 do
    local at = i / 8
    local ok, name = pcall(ac.getTrackSectorName, at)
    line[#line + 1] = string.format('%.2f=%s', at,
      ok and tostring(name) or '?')
  end
  ui.text(table.concat(line, '  '))
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

  ensureFileList()

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

    if ui.radioButton('pos list', pb.options.listName == 'pos') then
      pb.options.listName = 'pos'
    end
    ui.sameLine()
    if ui.radioButton('time list', pb.options.listName == 'time') then
      pb.options.listName = 'time'
    end
    ui.text(string.format('%d cameras in this list',
      #(doc[pb.options.listName] or {})))

    -- Percent as well as the raw value: every keyframe position gets talked
    -- about in percent, so making the reader convert in their head is a good
    -- way to have them look at the wrong part of the lap.
    ui.text(string.format('track pos %6.2f%%  (%.5f)   active camera %s',
      num(pbOut.trackPos) * 100, num(pbOut.trackPos), tostring(pbOut.activeCam)))

    local v = pbOut.evaluated or {}
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
    if ui.checkbox('track the car', pb.options.applyTracking) then
      pb.options.applyTracking = not pb.options.applyTracking
    end
    ui.sameLine()
    if ui.checkbox('apply roll', pb.options.applyRoll) then
      pb.options.applyRoll = not pb.options.applyRoll
    end

    ui.text(string.format('heading applied %.3f  (keyframed %s, aim %.3f)',
      num(pbOut.heading),
      v.rot_z and string.format('%.3f', v.rot_z) or 'none -- holds',
      num(pbOut.aimedHeading)))
    ui.text(string.format('pitch   applied %.3f  (keyframed %s, aim %.3f)',
      num(pbOut.pitch),
      v.rot_x and string.format('%.3f', v.rot_x) or 'none -- holds',
      num(pbOut.aimedPitch)))
    local strength = num(pbOut.aimStrength)
    ui.textColored(string.format('tracking strength in use: %.2f', strength),
      strength > 0 and COLOR_OK or COLOR_IDLE)
    local offset = num(pbOut.aimOffset)
    ui.text(string.format('tracking offset %.3f  (%s)', offset,
      offset < 0 and 'leads the car' or (offset > 0 and 'trails it' or 'aims at it')))
    if ui.checkbox('follow the recorded spline', pb.options.applySpline) then
      pb.options.applySpline = not pb.options.applySpline
    end
    if ui.checkbox('apply shake', pb.options.applyShake) then
      pb.options.applyShake = not pb.options.applyShake
    end
    ui.sameLine()
    if ui.checkbox('apply depth of field', pb.options.applyFocus) then
      pb.options.applyFocus = not pb.options.applyFocus
    end
    ui.text(string.format('shake: pan %.3f  clock %.2f s   focus %.1f m',
      num(pbOut.shakeMomentum), num(shakeClockReadout), num(pbOut.focusDistance)))
    local list = doc[pb.options.listName]
    if pbOut.activeCam ~= nil and list ~= nil then
      local c = list[pbOut.activeCam]
      if c ~= nil and spline.exists(c) then
        ui.textColored(string.format('spline: %d points, read at %.4f',
          #c.spline.the_x, num(pbOut.splineQuery)), COLOR_OK)
        ui.text(string.format('  affect xy %.2f  z %.2f  heading %.2f',
          num(c.spline_affect_loc_xy), num(c.spline_affect_loc_z),
          num(c.spline_affect_heading)))
      else
        ui.textColored('this camera has no recorded spline', COLOR_IDLE)
      end
    end

    if ui.checkbox('aim straight at the car (no lead)', pb.options.ignoreLead) then
      pb.options.ignoreLead = not pb.options.ignoreLead
    end
    if pbOut.isLastCamera then
      -- Shown in the lap's own terms: a wrapped query is negative, which reads
      -- as the tail of the previous lap.
      ui.textColored(string.format('last camera: keyframes read at %6.2f%%%s',
        num(pbOut.keyframeQuery) * 100,
        pbOut.keyframeQuery ~= pbOut.trackPos and ' -- wrapped a lap back' or ''),
        COLOR_OK)
    end
    if ui.checkbox('legacy last-camera wrap (#23)', pb.options.legacyLastCamera) then
      pb.options.legacyLastCamera = not pb.options.legacyLastCamera
    end
    if ui.checkbox('legacy startup transient (#16)', pb.options.legacyZeroFill) then
      pb.options.legacyZeroFill = not pb.options.legacyZeroFill
      playbackCore.resetHistory(pb)
      log('car history reset, legacy zero fill = '
        .. tostring(pb.options.legacyZeroFill))
    end

    -- Forcing the strength is a diagnostic: it tells apart "tracking is wrong"
    -- from "this camera barely tracks".
    pb.options.trackingOverride = ui.slider('##trackOverride',
      pb.options.trackingOverride, -1, 1,
      pb.options.trackingOverride < 0 and 'strength: from file'
        or 'strength forced to %.2f')
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
  -- The same three through the bindings mouse look actually reads. If the row
  -- above says down and this one does not, ac.ControlButton is not taking a
  -- lone modifier, or not with another one held.
  ui.text(string.format('bindings: look %s  zoom in %s  zoom out %s  weight %.2f',
    tostring(shortcuts.down('mouseLook')), tostring(shortcuts.down('zoomIn')),
    tostring(shortcuts.down('zoomOut')), lookOut.weight or 0))
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

-- What the ATR panel is pointed at. Separate from the camera the car has made
-- live, exactly as CamTool 2 keeps __active_cam apart from data.active_cam:
-- you edit one camera while another is on screen.
local atrCamera = nil

-- The ribbon and the map show the track cameras, or the pit lane ones
-- (panel.pitView). It follows the selected camera: whenever what is selected
-- changes kind -- another camera picked, PIT ONLY ticked -- the view goes with
-- it, so the camera being edited is always on the ribbon.
local atrKeyframe = 1
---Start an empty set, if there is not one already.
---
---EVERY WAY IN USED TO GO THROUGH LOADING. A fresh session could only work on
---somebody else's file, and the first thing anyone does -- put a camera
---where the car is -- answered "no file yet, go and name one first". Naming a
---file is not what someone wants at that moment; it is a thing the machine
---needs, and it can be asked for later, when there is something worth keeping.
---@return boolean @true when this call is what made it
local function startNewDocument()
  if doc ~= nil then return false end

  doc, docError = dataModule.newDocument(), nil
  playbackCore.applyMode(pb, doc.interpolation_mode)
  atrCamera, atrKeyframe = nil, 1
  mode = MODE_PLAYBACK
  log('new camera file')
  return true
end

-- Every edit, newest last. edit.apply hands back a record that can be put
-- back, so undo is this stack and nothing more.
local undoStack = {}
local redoStack = {}

-- CamTool 2's Load on startup: the first time the app sees a track, open the
-- file last used on it, or the first one there is. Once per track, and never
-- over unsaved work -- the app outlives a session, so the next track can
-- arrive with changes still in hand.
local startupLoadedFor = nil

-- Small pieces of panel state, in one table rather than one local each:
-- script.windowAtr closes over most of this file, and LuaJIT allows a
-- function sixty upvalues.
--   loadOnStartup   read once and kept, the panel shows it every frame
--   pitView         the ribbon and the map show the pit lane cameras
--   selectedWasPit  the kind of camera selected last frame; see below
local panel = {
  loadOnStartup = settings.loadOnStartup(),
  pitView = false,
  selectedWasPit = nil,
}

local function startupLoad()
  local prefix = storage.trackPrefix()
  if startupLoadedFor == prefix then return end
  startupLoadedFor = prefix
  if not panel.loadOnStartup or #undoStack > 0 or #files == 0 then return end
  fileIndex = settings.findFile(files, settings.lastFile(prefix)) or 1
  loadSelectedFile()
end
local UNDO_KEPT = 200

-- What the session line says instead of the loaded file name, after a save.
local atrStatus = nil
---Whether the panel is showing the map. Not saved anywhere yet: CamTool 3
---has no settings file, so this lasts as long as the session.
local atrShowMap = true
---And whether it is showing the key bindings, which are on a button of their
---own rather than hanging off the end of the legend.
local atrShowKeys = false
---Whether the ? legend is open instead of the status line. Session state too.
local atrShowHelp = false
---The last reason the map had nothing to draw, so a change is said once
---rather than every frame.
local atrOutlineReason = nil

---What the arrow keys do, now that the panel's own state exists to move.
---
---In the frame loop rather than the panel, because a shortcut has to work
---with the window closed -- which is the whole point of LAZY = PARTIAL. The
---forward declaration above is what lets a function written here be called
---from a loop written above it.
---
---Nothing here is an edit: stepping through cameras changes what is selected
---and where the replay is, and neither belongs on the undo stack.
handleShortcuts = function()
  shortcuts.install()

  local fired = shortcuts.pressed()
  if fired == nil then return end

  local action = fired

  local cameras = doc ~= nil and doc[pb.options.listName] or nil
  if cameras == nil or #cameras == 0 then
    atrStatus = 'no cameras to step through'
    return
  end

  local camera = atrCamera ~= nil and cameras[atrCamera] or nil
  local target = nil

  if action == 'cameraNext' or action == 'cameraPrevious' then
    local next_ = action == 'cameraNext'
      and navigate.nextCamera(cameras, atrCamera)
      or navigate.previousCamera(cameras, atrCamera)

    -- Ends stop rather than wrap: see core/navigate for why.
    if next_ == nil then return end

    atrCamera, atrKeyframe = next_, 1
    atrParameter.cancelEditing()
    target = navigate.positionOf(cameras[next_], nil)
  else
    if camera == nil then
      atrStatus = 'pick a camera first'
      return
    end

    local count = type(camera.keyframes) == 'table' and #camera.keyframes or 0
    if count == 0 then
      atrStatus = 'this camera has no keyframes'
      return
    end

    local next_ = action == 'keyframeNext'
      and navigate.nextKeyframe(camera, atrKeyframe)
      or navigate.previousKeyframe(camera, atrKeyframe)
    if next_ == nil then return end

    atrKeyframe = next_
    atrParameter.cancelEditing()
    target = navigate.positionOf(camera, next_)
  end

  -- Stepping brings the car with it. That is what the jump-to-edit-point keys
  -- do in an editing suite, and it is the only thing that makes an arrow
  -- worth pressing: the point of going to the next keyframe is to see it.
  if target ~= nil then
    local why = seekBegin(target)
    if why ~= nil then atrStatus = why end
  end
end

-- The two buttons that can throw away an afternoon in a single click. Both
-- ask once, and what arms them is a click on the button itself.
local atrConfirmReset = false
local atrConfirmDelete = false
local atrConfirmLoad = false

---Did the user actually DO something this frame?
---
---Not `next(actions) ~= nil`, which was the old test and was wrong in a way
---nobody would guess: `hint` is an action, and it is set every frame the
---pointer is anywhere over the ribbon or the play indicator. So an armed
---confirmation disarmed itself the moment the mouse drifted across the panel
---on its way back to the button -- which is the path it takes.
---@param actions table
---@return boolean
local function actedOn(actions)
  for key in pairs(actions) do
    if key ~= 'hint' then return true end
  end
  return false
end

-- How far one press moves a keyframe along the track. CamTool 2 offers 1, 10
-- and 100 m on separate buttons; one row plus the modifiers covers the same
-- ground -- 2.5 m with Ctrl, 10 plain, 40 with Shift.
local KEYFRAME_STEP_M = 10

---What the camera is doing right now, for seeding a new keyframe. This is the
---gesture the whole tool is built on: put the view where you want it, then
---pin it.
---What the camera is doing right now.
---
---Two sources, and the second is the one that was missing. While CamTool is
---driving, pbOut is what it decided. While it is not -- free camera, cockpit,
---anything -- the camera still exists and can be read straight from the game,
---and THAT is the number someone flying a free camera around wants to see
---before pinning it.
---
---It is the gesture the whole tool is built on: put the view where you want
---it, then pin it. Without the reading, the panel showed `--` and you were
---pinning something you could not see.
local function liveValue(key)
  if key == 'loc_x' and pbOut.x ~= nil then return pbOut.x end
  if key == 'loc_y' and pbOut.y ~= nil then return pbOut.y end
  if key == 'loc_z' and pbOut.z ~= nil then return pbOut.z end
  if key == 'rot_x' and pbOut.pitch ~= nil then return pbOut.pitch end
  if key == 'rot_y' and pbOut.roll ~= nil then return pbOut.roll end
  if key == 'rot_z' and pbOut.heading ~= nil then return pbOut.heading end
  if key == 'camera_fov' and pbOut.fov ~= nil then return pbOut.fov end
  if key == 'camera_focus_point' and pbOut.dofDistance ~= nil then
    return pbOut.dofDistance
  end

  -- Nothing from the playback: read the game's own camera. Positions come
  -- back in AC space and CamTool stores Z-up, the same swap as everywhere
  -- else; the angles come from the look vector, through the same conversion
  -- the playback seeds itself with.
  if key == 'loc_x' or key == 'loc_y' or key == 'loc_z' then
    local p = ac.getCameraPosition and ac.getCameraPosition() or nil
    if p == nil then return nil end
    if key == 'loc_x' then return p.x end
    if key == 'loc_y' then return p.z end
    return p.y
  end

  if key == 'rot_x' or key == 'rot_z' then
    local look = ac.getCameraForward and ac.getCameraForward() or nil
    if look == nil then return nil end
    -- fromLook takes an AC look vector as it comes, Y-up, and answers in
    -- CamTool convention. No swapping here: doing it anyway gives angles that
    -- look plausible and are wrong, which is worse than showing nothing.
    local heading, pitch = angles.fromLook(look.x, look.y, look.z)
    return key == 'rot_x' and pitch or heading
  end

  if key == 'camera_fov' then
    return ac.getCameraFOV and ac.getCameraFOV() or nil
  end

  -- Roll and the focus distance have no reading of their own: AC gives a look
  -- vector rather than an angle, and nothing reports what the lens is focused
  -- on. Saying nothing is better than saying zero.
  return nil
end

---The undo entry a drag in progress is stretching, with the gesture it
---belongs to. See remember.
local openDrag = nil

---A gesture from the map or the band, for the frame it is reported on. The
---parameter rows have their own counter; these two need one too, or a drag
---across the map would land one undo entry per frame.
local externalGesture = nil

local function remember(change)
  if change == nil then return end

  -- A drag is one gesture and costs one undo, however many frames it takes.
  -- Recording every frame would bury the rest of the stack under a two-second
  -- drag, and undoing would then walk back through it a pixel at a time.
  -- Instead the entry already on the stack keeps the value from before the
  -- gesture started and grows a new end.
  local gesture = atrParameter.draggingGesture() or externalGesture
  if edit.continues(openDrag, change, gesture) then
    openDrag.change.after = change.after
    return
  end

  undoStack[#undoStack + 1] = change
  while #undoStack > UNDO_KEPT do table.remove(undoStack, 1) end
  -- A new edit is a new branch: what was undone is no longer ahead of us.
  redoStack = {}

  openDrag = gesture ~= nil and { gesture = gesture, change = change } or nil
end

---Escape during a drag: put the value back where the gesture found it.
---
---The open entry already holds that value, so this is the same revert undo
---would do -- minus the entry, which never became a thing the user did.
local function cancelDrag()
  if openDrag == nil then return end

  for i = #undoStack, 1, -1 do
    if undoStack[i] == openDrag.change then
      table.remove(undoStack, i)
      break
    end
  end

  edit.revert(openDrag.change)
  openDrag = nil
end

local function undoOnce()
  if #undoStack == 0 then return end
  local change = undoStack[#undoStack]
  table.remove(undoStack)
  edit.revert(change)
  redoStack[#redoStack + 1] = change
end

local function redoOnce()
  if #redoStack == 0 then return end
  local change = redoStack[#redoStack]
  table.remove(redoStack)
  edit.reapply(change)
  undoStack[#undoStack + 1] = change
end

---The ATR panel. Read only for now: it shows a camera and its keyframes, and
---reports clicks that nothing acts on yet.
function script.windowAtr(dt)
  ensureFileList()
  startupLoad()

  local cameras = doc ~= nil and doc[pb.options.listName] or nil
  local count = cameras ~= nil and #cameras or 0

  -- Follow the car until the user picks a camera to work on.
  if atrCamera == nil or atrCamera > count then atrCamera = pbOut.activeCam end

  do
    local selected = cameras ~= nil and atrCamera ~= nil and cameras[atrCamera] or nil
    local selectedPit = nil
    if selected ~= nil then selectedPit = selected.camera_pit == true end
    if selectedPit ~= nil and selectedPit ~= panel.selectedWasPit then
      panel.pitView = selectedPit
    end
    panel.selectedWasPit = selectedPit
  end
  local camera = cameras ~= nil and atrCamera ~= nil and cameras[atrCamera] or nil
  local keyframes = camera ~= nil and camera.keyframes or nil
  local keyframeCount = type(keyframes) == 'table' and #keyframes or 0
  if atrKeyframe > keyframeCount then atrKeyframe = keyframeCount end
  if atrKeyframe < 1 and keyframeCount > 0 then atrKeyframe = 1 end

  -- Sampled once per track and cached by the adapter, so asking for it on
  -- every draw costs one table comparison. The reason comes with it: a map
  -- that can only say "no track" is a map that sends you to read the source.
  local outline, outlineReason = trackAdapter.currentOutline()
  if outlineReason ~= atrOutlineReason then
    atrOutlineReason = outlineReason
    -- Into the app's own log, which the probe panel shows: a reason nobody
    -- can read without going to find a file is half a reason.
    if outlineReason ~= nil then log('no track map -- ' .. outlineReason) end
  end

  local actions = atrPanel.draw({
    doc = doc,
    -- Where the arrows are pointing, which after a load or a save is the file
    -- that is open. It used not to be after a save -- the browse position sat
    -- wherever it had last been left -- so a set you had just named looked as
    -- though it had not been made, and finding it meant walking the list.
    --
    -- The NAME only, without the track prefix or the extension: see
    -- core/filename for why the machine's half has no business in a box
    -- somebody types into.
    -- A set started with +cam and not yet named comes first. Not "no file":
    -- there IS one, it is the one being worked on. And not the browse
    -- position either -- showing somebody else's file name while you edit
    -- your own new set is a lie the arrows are not worth telling.
    fileName = (doc ~= nil and docName == '' and 'unsaved set')
      or (fileIndex >= 1 and files[fileIndex] ~= nil
        and (filenames.display(files[fileIndex].name, storage.trackPrefix())
          .. (files[fileIndex].own and '' or '   [CamTool 2]'))) or nil,
    undoDepth = #undoStack,
    redoDepth = #redoStack,
    status = atrStatus,
    mode = doc ~= nil and doc.interpolation_mode or nil,
    listName = pb.options.listName,
    loadedName = doc ~= nil
      and filenames.display(docName, storage.trackPrefix()) or nil,
    held = cameraActive(),
    camera = camera,
    cameraIndex = atrCamera,
    cameraCount = count,
    liveCameraIndex = pbOut.activeCam,
    keyframeIndex = keyframeCount > 0 and atrKeyframe or nil,
    keyframeCount = keyframeCount,
    keyframePosition = keyframeCount > 0 and keyframes[atrKeyframe] ~= nil
      and keyframes[atrKeyframe].keyframe or nil,
    -- The car, held camera or not: the ribbon, the map and the metre readout
    -- all showed zero until the camera was taken, which is not where the car
    -- was.
    trackPos = pbOut.trackPos or focusedTrackPosition(),
    trackLength = sim.trackLengthM,
    outline = outline,
    outlineReason = outlineReason,
    showMap = atrShowMap,
    showHelp = atrShowHelp,
    showKeys = atrShowKeys,
    confirmReset = atrConfirmReset,
    confirmDelete = atrConfirmDelete,
    canDeleteFile = files[fileIndex] ~= nil and files[fileIndex].own == true,
    deleteHint = files[fileIndex] ~= nil and ('Move ' .. files[fileIndex].name ..
      ' to the Recycle Bin. Click twice.') or nil,
    confirmLoad = atrConfirmLoad,
    paused = playing.paused,
    -- Offered when naming a camera that has none: see ui/band.
    sectionNameAt = trackAdapter.sectionNameAt,
    -- What the track calls its own stretches, for the ruler. Read once when
    -- the track loaded, so this is a lookup and not a file.
    sections = trackAdapter.sections(),
    dt = dt,
    cameras = cameras,
    -- Not from the file: CamTool 2 never saved which car a camera framed.
    -- What the camera is doing, for every field that has no value of its own.
    live = liveValue,
    loadOnStartup = panel.loadOnStartup,
    offerFreeCamera = not cameraActive() and ac.CameraMode ~= nil
      and sim.cameraMode ~= ac.CameraMode.Free,
    pitView = panel.pitView,
    trackedCarA = sim.focusedCar,
    trackedCarB = effectiveExtraCar(),
    carName = ac.getDriverName,
  })

  -- Only the selections are wired: they change nothing about the camera, they
  -- change what the panel is looking at.
  -- The two cars. Session state and not edits, as in CamTool 2: nothing
  -- reaches the camera file or the undo stack.
  local function carStep(request)
    if type(request) ~= 'table' then return nil end
    if request.op == 'increment' then return 1 end
    if request.op == 'decrement' then return -1 end
    return nil
  end

  local stepFollowed = carStep(actions.trackedCarA)
  if stepFollowed ~= nil and sim.focusedCar ~= nil and sim.focusedCar >= 0 then
    local list = connectedCars()
    local from = sim.focusedCar
    local to = carsCore.step(list, from, carsCore.positionOf(list, from), stepFollowed)
    if to ~= from then
      ac.focusCar(to)
      -- Followed and extra at once is no extra car. Forgotten rather than
      -- kept, so it does not come back when the followed car moves on.
      if extraCar == to then extraCar = nil end
    end
  end

  local stepExtra = carStep(actions.trackedCarB)
  if stepExtra ~= nil then
    extraCar = carsCore.stepExtra(connectedCars(), sim.focusedCar,
      effectiveExtraCar(), stepExtra)
  end

  -- Switching the view picks the first camera it shows, so the fields below
  -- are about a camera you can see. With none there, the selection stays and
  -- the view stays switched: the ribbon then offers to add one.
  if actions.togglePitView then
    panel.pitView = not panel.pitView
    local list = doc ~= nil and doc[pb.options.listName] or nil
    for i = 1, list ~= nil and #list or 0 do
      if (list[i].camera_pit == true) == panel.pitView then
        atrCamera, atrKeyframe = i, 1
        atrParameter.cancelEditing()
        break
      end
    end
    local selected = list ~= nil and atrCamera ~= nil and list[atrCamera] or nil
    panel.selectedWasPit = nil
    if selected ~= nil then panel.selectedWasPit = selected.camera_pit == true end
  end

  if actions.selectCamera ~= nil then
    atrCamera = actions.selectCamera
    atrKeyframe = 1
    atrParameter.cancelEditing()
  end
  ------------------------------------------------------------------
  -- Moving a camera's start from the map or the band
  ------------------------------------------------------------------
  -- The same edit the STARTING POINT row makes, so it lands on the undo stack
  -- the same way and stops at the neighbouring cameras the same way. The
  -- gesture token keeps a whole drag to one entry.
  if actions.moveCameraIn ~= nil and camera ~= nil then
    externalGesture = actions.moveCameraIn.gesture
    remember(edit.apply({
      camera = camera,
      cameras = cameras,
      cameraIndex = atrCamera,
      key = 'camera_in',
      op = 'set',
      value = actions.moveCameraIn.position,
    }))
    externalGesture = nil
  end

  -- Once nothing is being dragged, the entry is closed: the next edit starts
  -- a new one even on the same parameter.
  if atrParameter.draggingGesture() == nil and actions.moveCameraIn == nil then
    openDrag = nil
  end

  -- Dragging the playhead along the ruler. Rough and frequent while the drag
  -- runs; the exact landing arrives below, as an ordinary seek, on the frame
  -- the button comes up.
  --
  -- NOT an edit, no more than the seek below it is: it moves the replay,
  -- reaches no camera data, and never touches the undo stack.
  if actions.scrubTo ~= nil then
    scrubTo(actions.scrubTo, dt)
  else
    scrubStop()
  end

  -- Bringing the car to a point of the track. NOT an edit: it moves the
  -- replay, touches no camera data, and so never reaches the undo stack.
  if actions.seekTo ~= nil then
    local why = seekBegin(actions.seekTo)
    if why ~= nil then atrStatus = why end

    -- A search muffles on its way in and unmuffles when it finishes. If there
    -- was no search to start -- out of a replay, say -- nothing would ever
    -- unmuffle, and a drag that ended there would leave the game silent for
    -- good.
    if seekJob == nil then seekMuffle(false) end
  end

  -- Whatever the seek had to say once it finished, said here because the
  -- machine runs between frames and the panel is drawn in them.
  if seekMessage ~= nil then
    atrStatus = seekMessage
    seekMessage = nil
  end

  -- Adding and removing a camera from the ribbon's menu. Same edits as the
  -- strip's plus and minus, but the position comes from where the right click
  -- landed rather than from the playhead, and the removal names the camera
  -- under the pointer rather than whichever one happens to be selected.
  if actions.addCameraAt ~= nil and cameras ~= nil then
    remember(edit.addCamera(cameras, actions.addCameraAt,
      dataModule.claimCameraId(doc), panel.pitView))
  end

  if actions.removeCameraAt ~= nil and cameras ~= nil then
    remember(edit.removeCamera(cameras, actions.removeCameraAt))
    if atrCamera ~= nil and atrCamera > #cameras then atrCamera = #cameras end
  end

  -- A name goes on the undo stack like anything else, so a rename can be
  -- taken back and a camera can go back to being a number.
  if actions.renameCamera ~= nil and cameras ~= nil then
    local target = cameras[actions.renameCamera.index]
    if target ~= nil then
      remember(edit.renameCamera(target, actions.renameCamera.name))
    end
  end

  if actions.toggleMap then atrShowMap = not atrShowMap end
  if actions.toggleHelp then
    atrShowHelp = not atrShowHelp
    -- One panel at a time under the ribbon. Two open at once would push the
    -- map and the parameters off the bottom of any window.
    if atrShowHelp then atrShowKeys = false end
  end
  if actions.toggleKeys then
    atrShowKeys = not atrShowKeys
    if atrShowKeys then atrShowHelp = false end
  end
  if actions.selectKeyframe ~= nil then
    atrKeyframe = actions.selectKeyframe
    atrParameter.cancelEditing()
  end

  ------------------------------------------------------------------
  -- Edits
  ------------------------------------------------------------------
  -- Everything goes through core/edit, including the undo stack, so a gesture
  -- added later lands in one place rather than twenty-one.
  if camera ~= nil then
    local ctrl = ac.isKeyDown(ac.KeyIndex.Control)
    local shift = ac.isKeyDown(ac.KeyIndex.Shift)

    -- The two that are not numbers: a flag either way, and a cycle.
    local pit = actions.camera_pit
    if type(pit) == 'table' and (pit.op == 'increment' or pit.op == 'decrement') then
      remember(edit.toggleFlag(camera, 'camera_pit'))
    end
    local specific = actions.camera_use_specific_cam
    if type(specific) == 'table' then
      if specific.op == 'increment' then
        remember(edit.cycleSpecificCam(camera, 1))
      elseif specific.op == 'decrement' then
        remember(edit.cycleSpecificCam(camera, -1))
      end
    end

    for key, request in pairs(actions) do
      if edit.RULES[key] ~= nil and type(request) == 'table' then
        local op, direction, amount, value
        if request.op == 'keyframe' then
          op = 'toggleKeyframe'
        elseif request.op == 'decrement' then
          op, direction = 'nudge', -1
        elseif request.op == 'increment' then
          op, direction = 'nudge', 1
        elseif request.op == 'drag' then
          -- The drag carries its own size, signed, so one entry point serves
          -- both it and the arrows.
          op, direction, amount = 'nudge', 1, request.amount
        elseif request.op == 'commit' then
          op, value = 'set', request.amount
        end

        if request.op == 'dragCancel' then
          cancelDrag()
        elseif op ~= nil then
          remember(edit.apply({
            camera = camera,
            -- Moving a camera's start needs to see its neighbours, so it can
            -- stop at them instead of crossing one.
            cameras = cameras,
            cameraIndex = atrCamera,
            keyframeIndex = keyframeCount > 0 and atrKeyframe or nil,
            key = key,
            op = op,
            direction = direction,
            amount = amount,
            value = value,
            ctrl = ctrl,
            shift = shift,
            live = liveValue(key),
          }))
        end
      end
    end
  end

  ------------------------------------------------------------------
  -- Cameras and keyframes, added, removed and moved
  ------------------------------------------------------------------
  -- Where the car is, whether or not we are driving the camera.
  --
  -- pbOut.trackPos is filled by the playback, and the playback only runs once
  -- the camera is held. So before taking it, the playhead was nil and every
  -- button that needs one -- add a camera, add a keyframe -- refused silently.
  -- Clicking + and watching nothing happen is exactly what that looked like.
  -- The car's position needs no camera held, so it is the honest fallback.
  local playhead = pbOut.trackPos or focusedTrackPosition()

  -- A button that cannot act says so. Refusing in silence is what made these
  -- look broken.
  -- ADDING A CAMERA WITH NOTHING LOADED STARTS A SET. It used to refuse and
  -- send you off to name a file first, which is the machine's errand, not
  -- yours: the name can be asked for later, when there is something worth
  -- keeping. Done before `cameras` is read below, so the camera lands in the
  -- set this call just made.
  if actions.addCamera and doc == nil and playhead ~= nil then
    if startNewDocument() then
      cameras = doc[pb.options.listName]
      atrStatus = 'new set -- Save when you want to name it'
    end
  end

  if (actions.addCamera or actions.addKeyframe) and playhead == nil then
    atrStatus = 'no car to put it at -- start the replay first'
  elseif actions.removeCamera and atrCamera == nil then
    atrStatus = 'pick a camera before removing one'
  elseif actions.addKeyframe and camera == nil then
    atrStatus = 'pick a camera before adding a keyframe'
  end

  if actions.addKeyframe and camera ~= nil and playhead ~= nil then
    local change = edit.addKeyframe(camera, playhead)
    remember(change)
    if change ~= nil then
      -- Select what was just made, which is what anyone expects next.
      for i = 1, #camera.keyframes do
        if camera.keyframes[i].keyframe == playhead then atrKeyframe = i end
      end
    end
  end
  if actions.removeKeyframe and camera ~= nil then
    remember(edit.removeKeyframe(camera, atrKeyframe))
    if atrKeyframe > #camera.keyframes then atrKeyframe = #camera.keyframes end
  end
  if actions.addCamera and cameras ~= nil and playhead ~= nil then
    -- The document hands out the identity: see core/data.claimCameraId.
    remember(edit.addCamera(cameras, playhead, dataModule.claimCameraId(doc),
      panel.pitView))
  end
  if actions.removeCamera and cameras ~= nil and atrCamera ~= nil then
    remember(edit.removeCamera(cameras, atrCamera))
    if atrCamera > #cameras then atrCamera = #cameras end
    atrKeyframe = 1
  end

  -- Moving the selected keyframe along the track. The step is in metres, so
  -- the conversion happens here rather than in core/edit, which has no idea
  -- how long a lap is.
  local request = actions.keyframePosition
  if request ~= nil and camera ~= nil and keyframes ~= nil then
    local kf = keyframes[atrKeyframe]
    local length = sim.trackLengthM
    if kf ~= nil and type(length) == 'number' and length > 0 then
      local step = KEYFRAME_STEP_M
      if ac.isKeyDown(ac.KeyIndex.Control) then step = step / 4 end
      if ac.isKeyDown(ac.KeyIndex.Shift) then step = step * 4 end

      local metres = (kf.keyframe or 0) * length
      local target = nil
      if request.op == 'increment' then target = metres + step
      elseif request.op == 'decrement' then target = metres - step
      elseif request.op == 'drag' then target = metres + step * (request.amount or 0)
      elseif request.op == 'commit' then target = request.amount
      end

      if type(target) == 'number' then
        remember(edit.apply({
          camera = camera, holder = kf, key = 'keyframe',
          op = 'set', value = target / length,
        }))
        edit.sortKeyframes(camera)
        for i = 1, #camera.keyframes do
          if camera.keyframes[i] == kf then atrKeyframe = i end
        end
      end
    end
  end

  -- Ctrl+Z and Ctrl+Y, the shortcuts everyone reaches for first. Read here
  -- rather than as an app hotkey so they only fire while this window has the
  -- keyboard, and cannot fight whatever else is bound to them.
  local ctrlHeld = ac.isKeyDown(ac.KeyIndex.Control)
  if actions.undo or (ctrlHeld and ui.keyboardButtonPressed(ac.KeyIndex.Z)) then
    undoOnce()
  end
  if actions.redo or (ctrlHeld and ui.keyboardButtonPressed(ac.KeyIndex.Y)) then
    redoOnce()
  end

  -- The session controls, so that starting work no longer means opening the
  -- probe panel.
  if actions.listName ~= nil and actions.listName ~= pb.options.listName then
    pb.options.listName = actions.listName
    atrCamera, atrKeyframe = nil, 1
    atrParameter.cancelEditing()
  end
  if actions.prevFile and fileIndex > 1 then fileIndex = fileIndex - 1 end
  if actions.nextFile and fileIndex < #files then fileIndex = fileIndex + 1 end
  if actions.mode ~= nil and doc ~= nil and actions.mode ~= doc.interpolation_mode then
    -- Changing the maths of a file is an edit like any other, so it is
    -- undoable and the star appears until it is saved.
    remember(edit.apply({
      camera = doc, holder = doc, key = 'interpolation_mode',
      op = 'set', value = actions.mode,
    }))
    playbackCore.applyMode(pb, doc.interpolation_mode)
  end

  -- LOADING ASKS FIRST WHEN THERE IS WORK TO LOSE -- issue #26. Loading
  -- replaces the whole document and empties the undo stack, so there is no
  -- way back from it, and the thing that opens a file is the same button
  -- people click to read which one is open.
  --
  -- The undo depth is what counts as unsaved, which is the same signal the
  -- star on the Save button uses: the warning appears exactly when the star
  -- is showing, so the two never disagree.
  if actions.loadFile then
    local pending = #undoStack

    if pending > 0 and not atrConfirmLoad then
      atrConfirmLoad = true
      atrStatus = string.format(
        '%d unsaved change%s would be lost. Click again to load anyway.',
        pending, pending == 1 and '' or 's')
    else
      atrConfirmLoad = false
      loadSelectedFile()
      -- A name being typed was about the file that was in hand a moment ago.
      atrPanel.cancelEditing()
      atrStatus = nil
      undoStack, redoStack = {}, {}
    end
  elseif atrConfirmLoad and actedOn(actions) then
    -- Anything else done means they thought better of it.
    atrConfirmLoad = false
  end

  -- Reset. CamTool 2 wipes both camera lists and both track splines with no
  -- confirmation and no way back, which docs/ui-inventory.md flags as its
  -- most destructive button. Here it asks first, and what it does is undoable
  -- like everything else.
  if actions.reset and doc ~= nil then
    if atrConfirmReset then
      atrConfirmReset = false
      local list = doc[pb.options.listName]
      if type(list) == 'table' and #list > 0 then
        remember(edit.clearCameras(list))
        atrCamera, atrKeyframe = 1, 1
        atrStatus = 'reset -- undo puts it back'
      end
    else
      atrConfirmReset = true
      atrStatus = 'Reset clears every camera of this list. Click again.'
    end
  elseif atrConfirmReset and actedOn(actions) then
    -- Anything else done means they thought better of it.
    atrConfirmReset = false
  end

  -- Deleting a file: the one the arrows are on, into the Recycle Bin, after a
  -- second click. The cameras of a deleted file that is open stay open --
  -- Save would write them back.
  if actions.deleteFile then
    local entry = files[fileIndex]
    if entry ~= nil and entry.own then
      if atrConfirmDelete then
        atrConfirmDelete = false
        local ok, err = storage.deleteCameraFile(entry)
        if ok then
          log('recycled ' .. entry.name)
          atrStatus = entry.name .. ' is in the Recycle Bin'
            .. (entry.name == docName and ' -- its cameras stay open until you load another file' or '')
          refreshFileList()
        else
          atrStatus = 'DELETE FAILED: ' .. tostring(err)
          log(atrStatus)
        end
      else
        atrConfirmDelete = true
        atrStatus = 'Click Delete again to move ' .. entry.name .. ' to the Recycle Bin.'
      end
    end
  elseif atrConfirmDelete and actedOn(actions) then
    atrConfirmDelete = false
  end

  -- Saving under a name of your own. The file is written into CamTool 3's
  -- folder like every other save, so this never touches a CamTool 2 original
  -- whatever it is called.
  --
  if type(actions.saveAs) == 'string' then
    -- Everything about the file name that is not the name lives in
    -- core/filename: the prefix that belongs to this track, the extension,
    -- and taking back off whatever of either the user typed anyway.
    local name, why = filenames.build(actions.saveAs, storage.trackPrefix())
    if name == nil then
      atrStatus = why or 'a file needs a name'
    else
      startNewDocument()

      local saved, err = storage.saveCameraFile(name, doc)
      if saved then
        docName = name
        atrStatus = 'saved ' .. filenames.display(name, storage.trackPrefix())
        undoStack, redoStack = {}, {}

        -- The new file has to appear in the list, and the list is only
        -- rescanned when the track changes -- so rescan now rather than
        -- waiting for one.
        refreshFileList()

        -- AND THE ARROWS HAVE TO POINT AT IT. Saving under a name is how a
        -- set becomes yours; leaving the browse position on some other file
        -- meant stepping through the list to find what you had just written.
        for i = 1, #files do
          if files[i].own and files[i].name == name then
            fileIndex = i
            settings.setLastFile(storage.trackPrefix(), files[i])
          end
        end

        log('saved as ' .. name)
      else
        atrStatus = 'SAVE FAILED: ' .. tostring(err)
        log(atrStatus)
      end
    end
  end

  if actions.save then
    if doc ~= nil and docName == '' then
      -- A set made with +cam and never named. "Nothing loaded to save" was
      -- true and no use: what has to happen next is the name, so the field
      -- opens rather than being described.
      atrPanel.renameFile()
      atrStatus = 'give it a name, then press enter'
    elseif doc == nil then
      atrStatus = 'nothing loaded to save'
    else
      local saved, err = storage.saveCameraFile(docName, doc)
      if saved then
        atrStatus = 'saved ' .. filenames.display(docName, storage.trackPrefix())
        -- The stack is what says there is work not on disk; once it is on
        -- disk, there is not.
        undoStack, redoStack = {}, {}
        log('saved ' .. docName)
      else
        atrStatus = 'SAVE FAILED: ' .. tostring(err)
        log(atrStatus)
      end
    end
  end
  if actions.grab then grabCamera() end
  if actions.release then releaseCamera() end
  if actions.toggleLoadOnStartup then
    panel.loadOnStartup = not panel.loadOnStartup
    settings.set('loadOnStartup', panel.loadOnStartup)
  end
  if actions.freeCamera and ac.setCurrentCamera ~= nil then
    ac.setCurrentCamera(ac.CameraMode.Free)
  end
end

function script.windowMain(dt)
  drawContext()
  drawSectionNames()
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
  setAudioMultiplier(1)
end)
