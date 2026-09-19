--[[
  Drive the app over a whole lap, out of game.

  The unit tests check one function at a time; the smoke test proves the app
  survives a frame. Neither answers the question that actually sends Theo back
  into Assetto Corsa: does the camera behave over a whole lap, across every
  camera switch. This drives exactly that, and deterministically -- the shake
  clock comes from the replay frame counter, so the same lap replays the same
  way every run.

  The car follows the track path recorded in the camera file itself. Two of the
  reference files carry one (a real lap, driven by a real user, recorded through
  CamTool 2's own spline recorder), so no invented trajectory is needed and the
  distances and angles the camera sees are the ones it would see in game.
]]

local fakes = require('tests/fakes/csp')
local playbackCore = require('core/playback')
local dataModule = require('core/data')

local lap = {}

---Sample a recorded track path at a normalised position.
---
---Returns CamTool coordinates (Z up), which is what the path stores. Positions
---outside the recorded range wrap between the last sample and the first, since
---a track path closes on itself.
---@param doc table @a migrated camera document
---@return function|nil @(position) -> x, y, z, or nil when the file records no path
function lap.trackSampler(doc)
  local path = doc and doc.track_spline
  local xs = path and path.the_x
  if type(xs) ~= 'table' or #xs < 2 then return nil end

  local n = #xs

  return function(position)
    -- Normalise into 0..1 first: a lap driven past the line must not run off
    -- the end of the table.
    local p = position % 1

    -- Before the first sample or after the last: interpolate across the line.
    if p <= xs[1] or p >= xs[n] then
      local span = (xs[1] + 1) - xs[n]
      local along = p > xs[n] and (p - xs[n]) or (p + 1 - xs[n])
      local t = span > 0 and (along / span) or 0
      return path.loc_x[n] + (path.loc_x[1] - path.loc_x[n]) * t,
             path.loc_y[n] + (path.loc_y[1] - path.loc_y[n]) * t,
             path.loc_z[n] + (path.loc_z[1] - path.loc_z[n]) * t
    end

    for i = 1, n - 1 do
      if p >= xs[i] and p <= xs[i + 1] then
        local span = xs[i + 1] - xs[i]
        local t = span > 0 and ((p - xs[i]) / span) or 0
        return path.loc_x[i] + (path.loc_x[i + 1] - path.loc_x[i]) * t,
               path.loc_y[i] + (path.loc_y[i + 1] - path.loc_y[i]) * t,
               path.loc_z[i] + (path.loc_z[i + 1] - path.loc_z[i]) * t
      end
    end

    return path.loc_x[n], path.loc_y[n], path.loc_z[n]
  end
end

---A path for files that record none: a circle wide enough to stand in for a
---track, tilted so the elevation changes too. Not realistic, but deterministic,
---and it keeps the car well clear of any camera, which is what matters for a
---run that only asks whether the numbers stay finite and continuous.
---@param radius number|nil
function lap.circleSampler(radius)
  radius = radius or 400
  return function(position)
    local a = position * 2 * math.pi
    return math.cos(a) * radius, math.sin(a) * radius, 10 + math.sin(a * 3) * 15
  end
end

local DEFAULT_CLICKS = {
  'Find CamTool 2 files',
  'Load this file',
  'Grab camera',
  'Play CamTool 2 file (12)',
}

---Run the app over a lap and record what it asked the camera to do.
---
---@param opts table
---  cameraFile  parsed camera document the fake filesystem hands back
---  frames      how many frames to run (default 600)
---  from, to    normalised track positions to sweep between (default 0 to 1)
---  sampler     (position) -> x, y, z in CamTool space; defaults to the file's
---              own recorded path, falling back to a circle
---  checkboxes  extra widget labels to click during setup, e.g. to switch a
---              legacy toggle off
---  frameMs     replay frame length, which drives the shake clock (default 16.6)
---@return table @{ frames = { <one row per frame> }, handle = <fake handle> }
function lap.run(opts)
  opts = opts or {}
  local frames = opts.frames or 600
  local from = opts.from or 0
  local to = opts.to or 1

  local clicks = {}
  for _, label in ipairs(DEFAULT_CLICKS) do clicks[label] = true end

  local handle = fakes.install({
    cameraFile = opts.cameraFile,
    clicks = clicks,
    splinePosition = from,
  })
  handle.sim.replayFrameMs = opts.frameMs or 16.6
  handle.sim.replayCurrentFrame = 0

  local chunk, err = loadfile('CamTool3.lua')
  if chunk == nil then error('app did not compile: ' .. tostring(err), 2) end
  chunk()

  -- Draw a few times so the setup clicks land: find the files, load one, grab
  -- the camera, select playback. Then stop clicking -- the click table is read
  -- on every draw, and a button held down would re-fire for the whole lap.
  for _ = 1, 4 do _G.script.windowMain(0.016) end
  for label in pairs(clicks) do clicks[label] = nil end

  -- A checkbox flips on every draw it is clicked in, so the toggles get a draw
  -- of their own. Buttons above are safe to hold down; these are not.
  if opts.checkboxes ~= nil and #opts.checkboxes > 0 then
    for _, label in ipairs(opts.checkboxes) do clicks[label] = true end
    _G.script.windowMain(0.016)
    for label in pairs(clicks) do clicks[label] = nil end
  end

  local sampler = opts.sampler
  if sampler == nil then
    -- The document the app loaded is the migrated one; the fixture is the raw
    -- one. The recorded path is untouched by migration, so either will do.
    sampler = lap.trackSampler(opts.cameraFile) or lap.circleSampler()
  end

  local rows = {}
  local dt = (opts.frameMs or 16.6) / 1000

  for i = 1, frames do
    local t = frames > 1 and ((i - 1) / (frames - 1)) or 0
    local position = from + (to - from) * t

    -- CamTool stores Z up, AC is Y up.
    local cx, cy, cz = sampler(position)
    handle.car.splinePosition = position
    handle.car.position = { x = cx, y = cz, z = cy }

    -- Both counters advance: sim.frame is the app's once-per-frame guard, and
    -- replayCurrentFrame is the shake clock.
    handle.sim.frame = handle.sim.frame + 1
    handle.sim.replayCurrentFrame = handle.sim.replayCurrentFrame + 1

    _G.script.update(dt)

    local p = handle.transform.position
    local l = handle.transform.look
    local u = handle.transform.up
    rows[i] = {
      frame = i,
      position = position,
      x = p.x, y = p.y, z = p.z,
      lx = l.x, ly = l.y, lz = l.z,
      ux = u.x, uy = u.y, uz = u.z,
      fov = handle.camera.fov,
      dofDistance = handle.camera.dofDistance,
      dofFactor = handle.camera.dofFactor,
    }
  end

  return { frames = rows, handle = handle }
end

---The fields a row carries, in the order the golden fixture stores them.
lap.FIELDS = {
  'x', 'y', 'z',
  'lx', 'ly', 'lz',
  'ux', 'uy', 'uz',
  'fov', 'dofDistance', 'dofFactor',
}

--------------------------------------------------------------------------------
-- The same lap, straight through the core
--------------------------------------------------------------------------------

---Fields a core row carries beyond the camera pose, for the checks that need
---to know which camera was live and where its keyframes were read.
lap.CORE_FIELDS = {
  'x', 'y', 'z',
  'lookX', 'lookY', 'lookZ',
  'upX', 'upY', 'upZ',
  'fov', 'dofDistance', 'dofFactor',
  'heading', 'pitch', 'roll',
}

---Run a lap through core/playback with no app and no fake CSP around it.
---
---Faster than lap.run, and it keeps the diagnostics the app only shows on
---screen: which camera was live, where its keyframes were read, how strongly
---it tracked. Those are what the invariant checks need.
---
---@param opts table
---  cameraFile  a raw camera document; it is migrated here
---  frames      how many frames to run (default 600)
---  from, to    normalised track positions to sweep between (default 0 to 1)
---  options     overrides for playback.DEFAULTS
---  sampler     (position) -> x, y, z in CamTool space
---  frameMs     replay frame length, which drives the shake clock
---  replayRate  replay playback rate (default 1)
---@return table @{ doc = <migrated>, frames = { <one row per frame> } }
function lap.runCore(opts)
  opts = opts or {}
  local frames = opts.frames or 600
  local from = opts.from or 0
  local to = opts.to or 1
  local frameMs = opts.frameMs or 16.6

  local doc = dataModule.load(opts.cameraFile)

  -- The file decides the legacy maths, exactly as the app does on load; an
  -- explicit option in the test then wins over it, which is how a sweep asks
  -- for the corrected curves on a legacy file.
  local state = playbackCore.new()
  playbackCore.applyMode(state, doc.interpolation_mode)
  for key, value in pairs(opts.options or {}) do state.options[key] = value end
  playbackCore.resetHistory(state)

  local sampler = opts.sampler or lap.trackSampler(doc) or lap.circleSampler()

  local input = {
    replayRate = opts.replayRate or 1,
    -- Seeded once, like a fresh grab of a camera pointing down the X axis.
    seedHeading = opts.seedHeading or 0,
    seedPitch = opts.seedPitch or 0,
  }

  local rows = {}
  for i = 1, frames do
    local t = frames > 1 and ((i - 1) / (frames - 1)) or 0
    local position = from + (to - from) * t

    input.trackPos = position
    input.carX, input.carY, input.carZ = sampler(position)
    input.clock = i * frameMs / 1000

    -- The aim and focus the core is holding on the way in. A real recording
    -- cannot carry the heading -- reading it in game would fill a cache the
    -- game fills later -- but a lap turned into a recording can, and the
    -- replay of such a recording has to start from exactly here to land on
    -- exactly the same frames.
    local headingBefore = state.heading or input.seedHeading
    local pitchBefore = state.pitch or input.seedPitch
    local focusBefore = state.focusDistance

    local out = playbackCore.frame(state, doc, input)

    -- The output table is reused frame to frame, so this has to be a copy.
    local row = {
      frame = i,
      position = position,
      active = out.active,
      activeCam = out.activeCam,
      isLastCamera = out.isLastCamera,
      keyframeQuery = out.keyframeQuery,
      aimStrength = out.aimStrength,
      -- The car goes in the row too: a trace carries its inputs, so a lap
      -- turned into one has to carry them as well.
      carX = input.carX, carY = input.carY, carZ = input.carZ,
      clock = input.clock,
      headingBefore = headingBefore,
      pitchBefore = pitchBefore,
      focusBefore = focusBefore,
    }
    for _, field in ipairs(lap.CORE_FIELDS) do row[field] = out[field] end
    rows[i] = row
  end

  return { doc = doc, frames = rows }
end

---Split a lap into the stretches during which one camera was live.
---
---A cut between two cameras is CamTool doing its job; a jump inside one is a
---bug. Every continuity check below is therefore per span, never across one.
---@return table[] @{ camera = <index>, first = <frame>, last = <frame> }
function lap.spans(rows)
  local spans = {}
  local current = nil

  for i = 1, #rows do
    local row = rows[i]
    local camera = row.active and row.activeCam or nil
    if camera ~= (current and current.camera) then
      current = camera and { camera = camera, first = i, last = i } or nil
      if current ~= nil then spans[#spans + 1] = current end
    elseif current ~= nil then
      current.last = i
    end
  end

  return spans
end

return lap
