--[[
  Where the replay is, between two of its frames -- pure logic, no ac/CSP
  dependency.

  The position the `time` list plays on. CamTool 2 stores its keyframes and
  camera_in there in REPLAY FRAMES, and reads the replay position through
  Replay.get_interpolated_replay_pos: the current frame plus how far the
  replay has gone since that frame began, so a camera does not step at the
  frame rate of the recording (a replay recorded at 16 Hz would otherwise
  move the camera sixteen times a second).

  Ported from Replay.refresh, with one simplification CSP allows: CamTool 2
  measured the frame duration itself, over a second of replay at speed 1,
  rounded to one of five values -- the "Synchronizing..." button. CSP says it
  outright (sim.replayFrameMs), so there is nothing to synchronise and the
  value is exact.
]]

local replaytime = {}

---A jump further than this, in frames, starts afresh: a seek, not playback.
replaytime.JUMP = 10

function replaytime.new()
  return { frame = nil, since = 0 }
end

---One frame.
---@param state table @from replaytime.new
---@param frame number @the replay's current frame
---@param frameMs number @how long a replay frame lasts, milliseconds
---@param replayDt number @seconds of replay time this frame; 0 while paused
---@return number @the replay position in frames, with its fraction
function replaytime.update(state, frame, frameMs, replayDt)
  if type(frame) ~= 'number' then return 0 end
  if type(frameMs) ~= 'number' or frameMs <= 0 then return frame end

  if state.frame == nil or math.abs(frame - state.frame) >= replaytime.JUMP then
    state.frame, state.since = frame, 0
    return frame
  end

  state.since = state.since + (replayDt or 0) * 1000
  if frame ~= state.frame then
    -- The time the new frames account for is time already counted.
    state.since = state.since - frameMs * (frame - state.frame)
    state.frame = frame
  end
  if state.since < 0 then state.since = 0 end

  local fraction = state.since / frameMs
  if fraction > 1 then fraction = 1 end
  return frame + fraction
end

---Seconds for a number of replay frames, for the panel.
function replaytime.seconds(frames, frameMs)
  return (frames or 0) * (frameMs or 0) / 1000
end

---Replay frames for a number of seconds, for what the panel is given.
function replaytime.frames(seconds, frameMs)
  if type(frameMs) ~= 'number' or frameMs <= 0 then return 0 end
  return (seconds or 0) * 1000 / frameMs
end

return replaytime
