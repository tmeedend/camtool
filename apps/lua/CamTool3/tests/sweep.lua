--[[
  What to look for in a lap.

  tests/lap.lua produces the frames; this decides which of them are wrong. The
  checks below are the ones that used to need a pair of eyes and a running game:
  a camera that teleports mid-shot, a value that has gone to infinity, a lens
  at a nonsense focal length, a camera in the file that can never be selected.

  None of them says the shot is good. They say it is not broken.

  Thresholds are relative wherever they can be. How far a camera moves in one
  frame depends on how finely the lap is sampled and on how fast that particular
  shot was meant to travel -- one of the reference cameras covers 120 m in two
  percent of a lap, on purpose. What does not depend on either is the ratio
  between one step and the shot's usual step: a dolly is smooth at any speed,
  and a teleport stands out at any sampling rate. Across the reference files,
  sampled anywhere between 600 and 10800 frames per lap, the worst honest ratio
  is 5, and it barely moves between rates.
]]

local sweep = {}

---How much larger than a shot's usual step a single step may be before it
---counts as a jump rather than as movement.
sweep.JUMP_RATIO = 10

---Steps below this are never jumps, whatever the ratio says. Without a floor
---the ratio turns microscopic on a nearly static shot and reports a ten
---thousandth of a millimetre as a teleport. Metres.
sweep.POSITION_FLOOR = 0.02

---The most the lens may change in one frame. This one is absolute, not a
---ratio: a whip zoom over a tenth of a second is something these files really
---do -- two FOV keyframes a thousandth of a lap apart -- and no ratio can tell
---it from a cut. What is not intentional is the lens changing by a quarter of
---its range between two frames. Degrees, at the sampling rate below.
sweep.FOV_STEP_LIMIT = 12

---Frames per lap the checks assume: a 90 second lap at 60 frames per second.
---The FOV limit is in those terms, so a sweep run at another rate has to pass
---its own limit.
sweep.FRAMES_PER_LAP = 5400

---Tolerance on the length of the look vector.
sweep.UNIT_TOLERANCE = 1e-9

local function median(values)
  if #values == 0 then return 0 end
  local sorted = {}
  for i = 1, #values do sorted[i] = values[i] end
  table.sort(sorted)
  return sorted[math.ceil(#sorted / 2)]
end

local function isFinite(value)
  return type(value) == 'number' and value == value
    and value ~= math.huge and value ~= -math.huge
end

---Report the steps of one span that break out of the shot.
---
---A step is a jump when it is both worth seeing at all -- above the floor --
---and far larger than what this shot usually does. Both halves matter: the
---ratio alone flags dust on a static camera, and the floor alone would have to
---be tuned per shot, since one of the reference cameras covers 120 m in two
---percent of a lap on purpose.
---@param steps table[] @{ size = number, frame = number }
---@param found table @findings are appended here
local function reportJumps(steps, found, camera)
  local sizes = {}
  for i = 1, #steps do sizes[i] = steps[i].size end

  -- The median, zeros included: a shot that stands still has a median of zero,
  -- the floor takes over, and the twitch it was holding still through is a
  -- jump. Measuring only the moving frames would make the twitch the norm.
  local typical = median(sizes)
  local bar = math.max(typical, sweep.POSITION_FLOOR) * sweep.JUMP_RATIO

  for i = 1, #steps do
    local step = steps[i]
    if step.size > bar then
      found[#found + 1] = string.format(
        'camera %d, frame %d: the camera jumps %.4g m, past the %.4g m bar '
          .. 'this shot sets (it usually moves %.4g m a frame)',
        camera, step.frame, step.size, bar, typical)
    end
  end
end

---Every check, over one lap.
---
---@param doc table @the migrated document the lap was run against
---@param rows table[] @frames from lap.runCore
---@param spans table[] @from lap.spans
---@param listName string|nil @which camera list was played, default 'pos'
---@return string[] @findings, empty when the lap is clean
function sweep.findings(doc, rows, spans, listName)
  local found = {}
  local FIELDS = {
    'x', 'y', 'z', 'lookX', 'lookY', 'lookZ', 'upX', 'upY', 'upZ',
    'fov', 'dofDistance', 'dofFactor', 'heading', 'pitch',
  }

  ------------------------------------------------------------------
  -- Every number the camera is given has to be a number
  ------------------------------------------------------------------
  -- Lua answers a division by zero with inf rather than raising, so a camera
  -- that would have thrown in Python drives the view to infinity here instead.
  for i = 1, #rows do
    local row = rows[i]
    for _, field in ipairs(FIELDS) do
      local value = row[field]
      if value ~= nil and not isFinite(value) then
        found[#found + 1] = string.format('frame %d: %s is %s',
          i, field, tostring(value))
      end
    end
  end

  ------------------------------------------------------------------
  -- The look vector has to be a direction
  ------------------------------------------------------------------
  for i = 1, #rows do
    local row = rows[i]
    if row.lookX ~= nil and isFinite(row.lookX) then
      local length = math.sqrt(row.lookX ^ 2 + row.lookY ^ 2 + row.lookZ ^ 2)
      if math.abs(length - 1) > sweep.UNIT_TOLERANCE then
        found[#found + 1] = string.format(
          'frame %d: the look vector is %.12f long, not 1', i, length)
      end
    end
  end

  ------------------------------------------------------------------
  -- The lens has to be a lens
  ------------------------------------------------------------------
  for i = 1, #rows do
    local fov = rows[i].fov
    if fov ~= nil and (not isFinite(fov) or fov <= 0 or fov >= 180) then
      found[#found + 1] = string.format('frame %d: FOV is %s degrees',
        i, tostring(fov))
    end
    local distance = rows[i].dofDistance
    if distance ~= nil and (not isFinite(distance) or distance < 0) then
      found[#found + 1] = string.format('frame %d: focus distance is %s m',
        i, tostring(distance))
    end
  end

  ------------------------------------------------------------------
  -- A shot has to be continuous
  ------------------------------------------------------------------
  -- Only within a span: a cut between two cameras is CamTool doing its job.
  for _, span in ipairs(spans) do
    local position, fov = {}, {}

    for i = span.first + 1, span.last do
      local a, b = rows[i - 1], rows[i]
      if a.x ~= nil and b.x ~= nil and isFinite(a.x) and isFinite(b.x) then
        position[#position + 1] = {
          frame = i,
          size = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2),
        }
      end
      if a.fov ~= nil and b.fov ~= nil and isFinite(a.fov) and isFinite(b.fov) then
        fov[#fov + 1] = { frame = i, size = math.abs(b.fov - a.fov) }
      end
    end

    reportJumps(position, found, span.camera)

    local fovLimit = sweep.FOV_STEP_LIMIT * sweep.FRAMES_PER_LAP / #rows
    for i = 1, #fov do
      if fov[i].size > fovLimit then
        found[#found + 1] = string.format(
          'camera %d, frame %d: the FOV changes %.4g deg in one frame, past '
            .. 'the %.4g deg this sweep allows',
          span.camera, fov[i].frame, fov[i].size, fovLimit)
      end
    end
  end

  ------------------------------------------------------------------
  -- A camera in the file has to be reachable
  ------------------------------------------------------------------
  -- Cameras are selected by walking the list against the car's track position,
  -- so a camera whose start is not past the one before it can never win the
  -- walk. That is a property of the file, and CamTool 2 behaves the same way.
  -- Anything else that never fires is a selection bug.
  local cameras = doc[listName or 'pos'] or {}
  local seen = {}
  for i = 1, #rows do
    if rows[i].activeCam ~= nil then seen[rows[i].activeCam] = true end
  end

  for i = 1, #cameras do
    local camera = cameras[i]
    -- Pit cameras are a separate list that only plays in the pit lane, and a
    -- lap swept on the track never goes there, so their absence is expected.
    if not camera.camera_pit and not seen[i] then
      local shadowed = false
      for j = i + 1, #cameras do
        local other = cameras[j]
        if not other.camera_pit and (other.camera_in or 0) <= (camera.camera_in or 0) then
          shadowed = true
          break
        end
      end
      if not shadowed then
        found[#found + 1] = string.format(
          'camera %d starts at %.5f and is never selected, though no later '
            .. 'camera starts before it',
          i, camera.camera_in or 0)
      end
    end
  end

  return found
end

return sweep
