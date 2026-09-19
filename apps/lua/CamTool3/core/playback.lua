--[[
  One frame of playback: a camera file plus where the car is, turned into where
  the camera should be and what it should look at.

  Pure logic, no ac/CSP dependency. Everything the game knows arrives as plain
  numbers in the input table, and everything the game must do leaves as plain
  numbers in the output table. Coordinates in and out are CamTool's own, Z up;
  converting to AC's Y-up world is the caller's job, as is turning the angles
  into whatever the camera API wants.

  This used to live inside CamTool3.lua, between a grabbed camera and a
  transform. Moving it out is what lets a whole lap be replayed out of game --
  see tests/lap.lua and the golden master it feeds.

  State that has to survive from one frame to the next -- the car history, the
  aim the camera is holding, the shake window -- lives in the state object
  playback.new returns, not in upvalues. One state object drives one camera.
]]

local dataModule = require('core/data')
local evaluate = require('core/evaluate')
local angles = require('core/angles')
local tracking = require('core/tracking')
local spline = require('core/spline')
local shake = require('core/shake')
local focus = require('core/focus')

local playback = {}

---The switches the panel exposes. Defaults are what the app starts with, which
---for the two legacy ones means reproducing CamTool 2, bug included.
playback.DEFAULTS = {
  ---Which of the two camera lists a file carries.
  listName = 'pos',
  applyTracking = true,
  applyRoll = true,
  applySpline = true,
  applyShake = true,
  applyFocus = true,
  ---Forces tracking_offset to 0, so the camera aims straight at the car with
  ---no lead. An A/B switch: 76% of the reference cameras use exactly -0.1, and
  ---on the long lenses these files favour, that lead is a visible part of the
  ---frame.
  ignoreLead = false,
  ---Below zero means "use the strength from the file".
  trackingOverride = -1,
  ---The last camera spans the start line, so its keyframes are read a lap
  ---back. The legacy does that whenever the camera is last, whether or not the
  ---keyframes are stored wrapped, which freezes cameras like le_lancone's last
  ---one on their first keyframe. That is issue #23; leave this on to
  ---reproduce it.
  legacyLastCamera = true,
  ---Reproduce issue #16, the car history starting full of zeroes.
  legacyZeroFill = false,
}

---Set the legacy switches from a document's interpolation_mode.
---
---These two are not preferences, they are a property of the file. A CamTool 2
---file is loaded as 'legacy' and has to behave as CamTool 2 did, quirks
---included, or footage already cut would change. A file authored in CamTool 3
---is 'fixed' and gets the corrected maths. core/data writes that field on
---load and carries it through saves; this is what acts on it.
---
---Leaving them as loose checkboxes made it possible to play a legacy file
---with the corrected curves without meaning to, which is the one thing the
---two-axis design in core/data exists to prevent.
---@param state table
---@param mode string|nil @'legacy' or 'fixed'
function playback.applyMode(state, mode)
  local legacy = mode ~= 'fixed'
  state.options.legacyLastCamera = legacy
  state.options.legacyZeroFill = legacy
  playback.resetHistory(state)
end

---Rebuild the per-frame history: the rolling record of the tracked car that
---feeds the lead/lag aim point, and the heading window the shake reads as pan
---speed. Called on a fresh grab, and whenever the zero fill switch changes,
---since that changes how the history starts.
function playback.resetHistory(state)
  state.carHistory = tracking.new(nil, state.options.legacyZeroFill)
  state.headingHistory = {}
  state.haveAim = false
  state.shakeMomentum = 0
end

---@param options table|nil @overrides for playback.DEFAULTS
---@return table @state, to be passed back to playback.frame every frame
function playback.new(options)
  local state = { options = {}, out = {} }
  for key, value in pairs(playback.DEFAULTS) do state.options[key] = value end
  for key, value in pairs(options or {}) do state.options[key] = value end
  playback.resetHistory(state)
  state.focusDistance = 0
  return state
end

---Pick the keyframed value, else the camera-level one, else a default.
local function pick(keyframed, cameraLevel, fallback)
  if keyframed ~= nil then return keyframed end
  if cameraLevel ~= nil then return cameraLevel end
  return fallback
end

---Keep the last N headings, most recent first, for the pan-speed measure.
local function pushHeading(state, value)
  table.insert(state.headingHistory, 1, value)
  while #state.headingHistory > shake.DEFAULT_MOMENTUM_WINDOW do
    table.remove(state.headingHistory)
  end
end

---Work out one frame.
---
---@param state table @from playback.new
---@param doc table @a migrated camera document
---@param input table
---  trackPos      the car's normalised track position, 0..1
---  carX/Y/Z      the car's world position in CamTool space, or nil
---  replayRate    replay playback rate, 1 at normal speed
---  clock         replay position in seconds, the shake clock
---  seedHeading   the camera's real heading, used once to seed the held aim
---  seedPitch     likewise for pitch
---  seedFocus     the camera's focus distance, likewise for the held focus
---@return table @the output table, reused between frames: copy what you keep
function playback.frame(state, doc, input)
  local out = state.out
  local options = state.options

  -- Nothing here may survive a frame that produced no camera.
  out.active = false
  out.activeCam = nil
  out.x, out.y, out.z = nil, nil, nil
  out.fov = nil
  out.dofDistance, out.dofFactor = nil, nil

  local pos = input.trackPos
  if pos == nil or doc == nil then return out end

  out.trackPos = pos

  local cameras = doc[options.listName]
  local activeCam = evaluate.activeCameraIndex(cameras, pos)
  out.activeCam = activeCam
  if activeCam == nil then return out end

  local camera = cameras[activeCam]

  -- Keyframes are read at a position of their own for the camera that spans
  -- the start line. See #23.
  local isLastCamera = evaluate.isLastCamera(cameras, activeCam)
  local keyframeQuery = evaluate.queryPosition(pos, camera, isLastCamera,
    #cameras, options.legacyLastCamera)
  out.isLastCamera = isLastCamera
  out.keyframeQuery = keyframeQuery

  local v = evaluate.all(camera, keyframeQuery)
  out.evaluated = v

  -- Where the legacy reads the camera's live angles: the previous frame's
  -- result, seeded from the real orientation the first time through.
  --
  -- The held focus is seeded the same way and for the same reason. The legacy
  -- holds it by reading the camera back, so on the frame it first holds, the
  -- value is whatever the camera already had. Starting from zero instead puts
  -- the focus plane on the lens until something writes a real distance.
  if not state.haveAim then
    state.heading = input.seedHeading or 0
    state.pitch = input.seedPitch or 0
    if type(input.seedFocus) == 'number' then
      state.focusDistance = input.seedFocus
    end
    state.haveAim = true
  end
  local currentHeading, currentPitch = state.heading, state.pitch

  ------------------------------------------------------------------
  -- The recorded path, read at its own position
  ------------------------------------------------------------------
  local splinePoint = nil
  local affectXY, affectZ, affectHeading, affectPitch = 0, 0, 0, 0

  if options.applySpline and spline.exists(camera) then
    local query = spline.queryPosition(pos, camera.spline.the_x,
      pick(v.spline_speed, camera.spline_speed, 1),
      pick(v.spline_offset_spline, camera.spline_offset_spline, 0),
      options.listName)
    out.splineQuery = query

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
    out.x, out.y, out.z = px, py, pz
  end

  ------------------------------------------------------------------
  -- Aim: keyframes, the tracked car, and the path
  ------------------------------------------------------------------
  -- Fetched once: the tracking aim and the autofocus both need it.
  local carPosX, carPosY, carPosZ = input.carX, input.carY, input.carZ

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
  -- The aim at the car before the offsets are added. The focus gate wants
  -- this one, not the offset aim the camera ends up using.
  local aimHeadingRaw = nil
  local pitchStrength = 0
  local aimStrength = 0

  if options.applyTracking and px ~= nil and py ~= nil and pz ~= nil then
    local carX, carY, carZ = carPosX, carPosY, carPosZ
    if carX ~= nil then
      tracking.push(state.carHistory, carX, carY, carZ)

      -- Aim where the car is heading, or where it has been, rather than
      -- at the car itself. tracking_offset picks which and by how much;
      -- the replay speed stretches it so a slowed replay keeps the same
      -- lead in wall-clock terms.
      local offset = pick(v.tracking_offset, camera.tracking_offset, 0)
      if options.ignoreLead then offset = 0 end
      out.aimOffset = offset

      -- The offset shake wobbles the aim point along the car's path rather
      -- than rotating the camera. It is added to the lead/lag weight, which
      -- is where the legacy puts it. The momentum it uses is the previous
      -- frame's: this runs before this frame's is measured.
      local offsetShake = 0
      if options.applyShake then
        offsetShake = shake.trackingOffset(
          camera.camera_offset_shake_strength or 0, input.clock, state.shakeMomentum)
      end

      local targetX, targetY, targetZ =
        tracking.target(state.carHistory, offset, input.replayRate, offsetShake)

      aimHeading, aimPitch = angles.aimAt(px, py, pz, targetX, targetY, targetZ)
      aimHeadingRaw = aimHeading
      aimHeading = aimHeading + pick(v.tracking_offset_heading, camera.tracking_offset_heading, 0)
      aimPitch = aimPitch + pick(v.tracking_offset_pitch, camera.tracking_offset_pitch, 0)

      aimStrength = pick(v.tracking_strength_heading, camera.tracking_strength_heading, 0)
      pitchStrength = pick(v.tracking_strength_pitch, camera.tracking_strength_pitch, 0)
      if options.trackingOverride >= 0 then
        aimStrength, pitchStrength = options.trackingOverride, options.trackingOverride
      end

      out.aimedHeading, out.aimedPitch = aimHeading, aimPitch
    end
  end
  out.aimStrength = aimStrength

  local heading = angles.combine(currentHeading, transformHeading,
    aimHeading, aimStrength,
    splinePoint and splinePoint.heading or nil, affectHeading)

  local pitch = angles.combine(currentPitch, transformPitch,
    aimPitch, pitchStrength,
    splinePoint and splinePoint.pitch or nil, affectPitch)

  -- Rotation shake rides on top of the combined aim. camera_shake_strength
  -- IS keyframable, unlike the offset shake above -- that asymmetry is
  -- issue #25.
  if options.applyShake then
    state.shakeMomentum = shake.momentum(state.headingHistory)
    local shakePitch, shakeHeading = shake.rotation(
      pick(v.camera_shake_strength, camera.camera_shake_strength, 0),
      input.clock, state.shakeMomentum, input.replayRate)
    heading = heading + shakeHeading
    pitch = pitch + shakePitch
  end
  out.shakeMomentum = state.shakeMomentum

  state.heading, state.pitch = heading, pitch
  pushHeading(state, heading)

  out.heading, out.pitch = heading, pitch

  local lx, ly, lz = angles.lookVector(heading, pitch)
  out.lookX, out.lookY, out.lookZ = lx, ly, lz

  -- The roll actually applied, for anything comparing against CamTool 2,
  -- which sets a roll angle where this builds an up vector from it.
  out.roll = 0

  if options.applyRoll and v.rot_y ~= nil and v.rot_y ~= 0 then
    out.roll = v.rot_y
    -- Roll turns the up vector around the look axis. Built by hand rather
    -- than with vector helpers so the convention stays visible.
    -- side = cross(look, worldUp) with worldUp = (0, 1, 0).
    local sx, sy, sz = -lz, 0, lx
    local sl = math.sqrt(sx * sx + sy * sy + sz * sz)
    if sl > 1e-6 then
      sx, sy, sz = sx / sl, sy / sl, sz / sl
      local ux = sy * lz - sz * ly
      local uy = sz * lx - sx * lz
      local uz = sx * ly - sy * lx
      local c, s = math.cos(v.rot_y), math.sin(v.rot_y)
      out.upX, out.upY, out.upZ = ux * c + sx * s, uy * c + sy * s, uz * c + sz * s
    else
      out.upX, out.upY, out.upZ = 0, 1, 0
    end
  else
    out.upX, out.upY, out.upZ = 0, 1, 0
  end

  -- Post-migration this is plain degrees, so it goes straight in.
  if v.camera_fov ~= nil and v.camera_fov > 0 and v.camera_fov < 180 then
    out.fov = v.camera_fov
  end

  ------------------------------------------------------------------
  -- Depth of field
  ------------------------------------------------------------------
  if options.applyFocus and px ~= nil and py ~= nil and pz ~= nil then
    local distance = nil

    -- camera_use_tracking_point is the Autofocus toggle, and it is stored as
    -- 0 or 1 rather than as a boolean -- hence data.isOn, since a plain `if`
    -- would read 0 as on.
    if dataModule.isOn(camera.camera_use_tracking_point) and carPosX ~= nil then
      -- currentHeading, not heading: the legacy's gate reads the camera's
      -- heading through ctt, which still holds the previous frame's value at
      -- this point in the frame.
      if aimHeadingRaw == nil or focus.shouldRefocus(currentHeading, aimHeadingRaw) then
        distance = focus.auto({ x = px, y = py, z = pz },
          { x = carPosX, y = carPosY, z = carPosZ }, nil, 0)
        state.focusDistance = distance
      else
        -- Aimed away from the car: hold the previous distance rather than
        -- pumping the focus onto something off screen.
        distance = state.focusDistance
      end
    elseif v.camera_focus_point ~= nil then
      distance = v.camera_focus_point
      state.focusDistance = distance
    end

    if distance ~= nil then
      out.dofDistance = distance
      out.dofFactor = focus.dofFactor(distance)
    end
  end
  out.focusDistance = state.focusDistance

  out.active = true
  return out
end

return playback
