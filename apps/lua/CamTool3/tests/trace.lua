--[[
  Replay a CamTool 2 recording through core/playback and measure the gap.

  The golden master says the port has not changed. The lap sweep says it is not
  broken. Neither can say it agrees with CamTool 2, because only CamTool 2
  knows what CamTool 2 does. A trace is that answer, recorded once in game and
  replayed here for ever after -- see apps/python/CamTool_2/classes/trace.py
  for the recording end and tools/trace_to_lua.py for the conversion.

  What is compared, per frame, is what each side asked of the camera: position
  in CamTool's own axes, pitch, roll, heading, field of view, focus distance.
  Both sides are recorded at the setter, so this is like for like.

  Two things this deliberately does not do.

  It does not compare frames where the mouse look blend was active. CamTool 2
  mixes its result with wherever the camera already was, weighted by
  strength_inv; core/playback does not model that at all, so those frames say
  nothing about the port. They are counted and skipped.

  It does not seed the held aim from the camera's real orientation, because the
  recording does not carry it: reading the heading before the frame would have
  filled ctt's per-frame cache earlier than the game does, and a recorder that
  can change what it records is worthless. The first frame is seeded from its
  own recorded result instead, which makes frame one agree by construction; the
  aim is carried forward from then on, as in the game.
]]

local playbackCore = require('core/playback')
local dataModule = require('core/data')

local trace = {}

---Shortest signed difference between two angles, in radians.
---
---The plain difference is returned untouched when it is already the short way
---round. Going through the modulo regardless would turn a difference of 1e-17
---into one of 2e-15, and a comparison that cannot report an exact zero cannot
---be tested against one.
local function angleDelta(a, b)
  local d = a - b
  if d >= -math.pi and d <= math.pi then return d end
  d = d % (2 * math.pi)
  if d > math.pi then d = d - 2 * math.pi end
  return d
end

---The clock the shake runs on, rebuilt the way CamTool 2 built it.
---
---Two ways, and the recording says which was in force. With a synced replay it
---is the interpolated replay position in seconds, deterministic and the same
---on every re-render. Without one -- get_refresh_rate returns -1 -- CamTool 2
---falls back to adding up dt, which makes the shake depend on the frame rate
---of the session that produced it, and resets to zero whenever the replay is
---paused.
---
---CamTool 3 always uses the deterministic clock, on purpose. That is a chosen
---difference, already known, and feeding it here would shake every camera out
---of phase and drown out everything else this comparison is for. So the
---legacy clock is reconstructed instead, and the question of which clock to
---keep stays where it belongs -- in the port, not in the measurement.
---@param state table @carries the running total between frames
---@return number @seconds
local function clockOf(state, row)
  local rate = row.rrate
  local synced = row.status == 1 and type(rate) == 'number' and rate > 0

  if synced and type(row.rpos) == 'number' then
    state.clock = row.rpos / (1000 / rate)
  elseif type(row.rtm) == 'number' and row.rtm ~= 0 then
    state.clock = state.clock + (row.dt or 0) * row.rtm
  else
    state.clock = 0
  end

  return state.clock
end

---What the trace says the camera was asked for, in the core's own terms.
---@return table|nil
local function recordedOf(row)
  if row.pos == nil or row.rot == nil then return nil end
  return {
    x = row.pos[1], y = row.pos[2], z = row.pos[3],
    pitch = row.rot[1], roll = row.rot[2], heading = row.rot[3],
    fov = row.fov,
    focus = row.focus,
  }
end

---Replay a trace and compare it, frame by frame, with core/playback.
---
---@param recording table @a converted trace: { header = ..., frames = ... }
---@param cameraFile table @the raw camera document the recording was made with
---@param options table|nil @overrides for playback.DEFAULTS
---@return table @see the fields set at the end of this function
function trace.replay(recording, cameraFile, options)
  local rows = recording.frames
  local doc = dataModule.load(cameraFile)

  local settings = { listName = 'pos' }
  for key, value in pairs(options or {}) do settings[key] = value end
  -- A trace records which list the app was playing; the file cannot say.
  if rows[1] ~= nil and rows[1].mode ~= nil then
    settings.listName = rows[1].mode
  end

  local state = playbackCore.new()
  playbackCore.applyMode(state, doc.interpolation_mode)
  for key, value in pairs(settings) do state.options[key] = value end
  playbackCore.resetHistory(state)
  local input = {}
  local clock = { clock = 0 }

  local result = {
    compared = 0,
    skippedMouseLook = 0,
    skippedNoOutput = 0,
    worst = { position = 0, pitch = 0, roll = 0, heading = 0, fov = 0, focus = 0 },
    worstFrame = {},
    frames = {},
  }

  local seeded = false

  for i = 1, #rows do
    local row = rows[i]
    local recorded = recordedOf(row)

    if recorded == nil then
      result.skippedNoOutput = result.skippedNoOutput + 1
    else
      if not seeded then
        -- head0 and pitch0 exist only in a recording made from a lap. A real
        -- one cannot carry them, so its first frame is seeded from its own
        -- result and agrees by construction; see the head of this file.
        input.seedHeading = row.head0 or recorded.heading
        input.seedPitch = row.pitch0 or recorded.pitch
        -- What the camera was already focused on. Recordings carry it as
        -- focus0; the two made before that field existed do not, and for
        -- those the first frame's own result is the closest thing available.
        input.seedFocus = row.focus0 or recorded.focus
        seeded = true
      end

      input.trackPos = row.x
      input.replayRate = row.rtm
      input.clock = clockOf(clock, row)

      -- AC hands out (x, y, z) with y up; CamTool stores z up.
      local car = row.carpos0
      if car ~= nil then
        input.carX, input.carY, input.carZ = car[1], car[3], car[2]
      else
        input.carX, input.carY, input.carZ = nil, nil, nil
      end

      local out = playbackCore.frame(state, doc, input)

      local mouseLook = type(row.si) == 'number' and row.si > 0
      if mouseLook then
        result.skippedMouseLook = result.skippedMouseLook + 1
      elseif out.active and out.x ~= nil then
        local gap = {
          frame = row.f,
          trackPos = row.x,
          activeCam = out.activeCam,
          recordedCam = row.cam,
          position = math.sqrt(
            (out.x - recorded.x) ^ 2 +
            (out.y - recorded.y) ^ 2 +
            (out.z - recorded.z) ^ 2),
          pitch = math.abs(angleDelta(out.pitch, recorded.pitch)),
          roll = math.abs(angleDelta(out.roll or 0, recorded.roll)),
          heading = math.abs(angleDelta(out.heading, recorded.heading)),
        }

        if out.fov ~= nil and recorded.fov ~= nil then
          gap.fov = math.abs(out.fov - recorded.fov)
        end
        if out.dofDistance ~= nil and recorded.focus ~= nil then
          gap.focus = math.abs(out.dofDistance - recorded.focus)
        end

        result.compared = result.compared + 1
        result.frames[#result.frames + 1] = gap

        for _, field in ipairs({ 'position', 'pitch', 'roll', 'heading', 'fov', 'focus' }) do
          local value = gap[field]
          if value ~= nil and value == value and value > result.worst[field] then
            result.worst[field] = value
            result.worstFrame[field] = row.f
          end
        end
      end
    end
  end

  return result
end

---A one-line-per-measure summary, for a failure message or a report.
---@return string
function trace.summary(result)
  local lines = {}
  lines[#lines + 1] = string.format(
    '%d frames compared, %d skipped for mouse look, %d with no camera output',
    result.compared, result.skippedMouseLook, result.skippedNoOutput)

  local units = {
    position = 'm', pitch = 'rad', roll = 'rad',
    heading = 'rad', fov = 'deg', focus = 'm',
  }
  for _, field in ipairs({ 'position', 'heading', 'pitch', 'roll', 'fov', 'focus' }) do
    lines[#lines + 1] = string.format('worst %-8s %12.6g %-3s  at frame %s',
      field, result.worst[field], units[field],
      tostring(result.worstFrame[field]))
  end

  return table.concat(lines, '\n       ')
end

---Turn a lap run into a recording shaped exactly like a converted trace.
---
---Used to test the replay itself: a trace of the core's own output must
---replay against the core with no gap at all. Anything above zero there is a
---bug in the comparison, not in the port.
---@param rows table[] @frames from lap.runCore
---@param listName string|nil
---@return table
function trace.fromLap(rows, listName)
  local frames = {}
  local frameMs = 16.6

  for i = 1, #rows do
    local row = rows[i]
    if row.active and row.x ~= nil then
      frames[#frames + 1] = {
        f = i,
        dt = frameMs / 1000,
        x = row.position,
        mode = listName or 'pos',
        cam = row.activeCam,
        si = 0,
        rtm = 1,
        status = 1,
        -- clockOf reads these two back as a time in seconds, and the shake
        -- phase depends on the answer, so they have to give back exactly the
        -- clock the lap ran on -- not a value a hair away from it. A refresh
        -- rate of 1000 ms per replay frame makes the conversion a division by
        -- one, so the position can be carried in seconds and come back
        -- untouched. A real recording has a real rate and no such luxury.
        rpos = row.clock,
        rrate = 1000,
        focused = 0,
        car0 = 0,
        -- What the core was holding on the way into the frame. A recording
        -- made in game carries only focus0; the other two are what makes a
        -- lap replay onto itself exactly.
        focus0 = row.focusBefore,
        head0 = row.headingBefore,
        pitch0 = row.pitchBefore,
        -- Back to AC order, since that is what a recording holds.
        carpos0 = { row.carX, row.carZ, row.carY },
        pos = { row.x, row.y, row.z },
        rot = { row.pitch, row.roll or 0, row.heading },
        fov = row.fov,
        focus = row.dofDistance,
      }
    end
  end

  return { header = { type = 'header', version = 1, synthetic = true }, frames = frames }
end

return trace
