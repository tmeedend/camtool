--[[
  Recording a path -- pure logic, no ac/CSP dependency.

  Ported from Camera.record_spline. Three kinds, as in CamTool 2:

  - camera  the path of the camera, for one camera of the file: fly the free
            camera while the replay plays, and the camera will follow the
            same path later (core/spline plays it back).
  - track   a lap of the camera along the racing line: what core/pitlane
            and the map fall back on.
  - pit     the same through the pit lane.

  Every one records a sample per SECOND OF REPLAY TIME, not per frame, so the
  density along the lap does not depend on the replay speed. A sample is the
  camera's position and angles, and the car's track position as the_x.

  Two details that matter for playback:
  - Crossing the start line, the_x keeps counting past 1 rather than falling
    back to 0 (camera and pit kinds). That is where the the_x > 1 of the
    reference files come from, and what spline.queryPosition unwraps.
  - The heading is unwound against the previous sample, so the stored values
    are continuous across +/- pi and interpolate directly.

  The track kind starts once the car is in the first half of the lap and
  stops by itself when it comes back round to the line -- CamTool 2's two
  flags, kept as they are. Started in the first half, it records from there;
  the lap before that point is closed by the cyclic interpolation.

  One departure: a paused replay records nothing. CamTool 2 counted real time
  scaled by the replay speed setting, which goes on while paused, so a pause
  wrote the same point once a second.
]]

local angles = require('core/angles')

local recorder = {}

---Seconds of replay time between samples.
recorder.PERIOD = 1

local FIELDS = { 'the_x', 'loc_x', 'loc_y', 'loc_z', 'rot_x', 'rot_y', 'rot_z' }

---An empty path, in the shape the files carry.
function recorder.emptySpline()
  local spline = {}
  for _, field in ipairs(FIELDS) do spline[field] = {} end
  return spline
end

---How many points a path has, 0 for none or not a path.
function recorder.count(spline)
  if type(spline) ~= 'table' or type(spline.the_x) ~= 'table' then return 0 end
  return #spline.the_x
end

---@param kind string @'camera', 'track' or 'pit'
---@param alongReplay boolean|nil @the time list: the_x is a replay frame,
---  which never wraps, so a camera path does not run on past a line
function recorder.new(kind, alongReplay)
  return { kind = kind, clock = 0, started = false, pastHalf = false, done = false,
    alongReplay = alongReplay == true }
end

---Append one sample.
local function append(spline, x, sample)
  local n = #spline.the_x
  local heading = sample.heading
  if n > 0 then heading = angles.normalize(spline.rot_z[n], heading) end
  spline.the_x[n + 1] = x
  spline.loc_x[n + 1] = sample.x
  spline.loc_y[n + 1] = sample.y
  spline.loc_z[n + 1] = sample.z
  spline.rot_x[n + 1] = sample.pitch
  spline.rot_y[n + 1] = sample.roll
  spline.rot_z[n + 1] = heading
end

---One frame of recording.
---@param state table @from recorder.new
---@param spline table @the path being written, from recorder.emptySpline
---@param sample table @{ trackPos, x, y, z (CamTool space), pitch, roll, heading }
---@param replayDt number @seconds of replay time this frame; 0 while paused
---@return boolean @true once the recording has finished by itself (track)
function recorder.feed(state, spline, sample, replayDt)
  if state.done then return true end
  if type(replayDt) ~= 'number' or replayDt <= 0 then return false end

  state.clock = state.clock + replayDt
  if state.clock <= recorder.PERIOD then return false end
  state.clock = 0

  local x = sample.trackPos
  if type(x) ~= 'number' then return false end

  if state.kind == 'track' then
    if x < 0.5 and not state.started then
      state.started, state.pastHalf = true, false
    end
    if x < 0.5 and state.started and state.pastHalf then
      state.done = true
      return true
    end
    if state.started then
      if x > 0.5 then state.pastHalf = true end
      append(spline, x, sample)
    end
    return false
  end

  -- Camera and pit paths run on across the line.
  local n = #spline.the_x
  if n > 0 and not state.alongReplay then
    local previous = spline.the_x[n]
    if math.abs(x - previous) > math.abs(x + 1 - previous) then x = x + 1 end
  end
  append(spline, x, sample)
  return false
end

return recorder
