--[[
  Is the replay actually running? -- pure logic, no ac/CSP dependency.

  The question sounds trivial and is not, because the panel can be wrong about
  it in a way that is worse than saying nothing: when the car is crawling or
  the camera is fixed, nothing on screen moves, and an icon claiming the
  replay is playing when it is paused is a lie the user has no way to check.

  Assetto Corsa answers it directly. ac.getGameDeltaT is documented as
  "values are zero if sim OR REPLAY are paused" -- so a pause is a pause
  whoever caused it: the replay bar, another app, the game's own menu. There
  is no state to track and none is tracked here.

  What this adds is steadiness. A single frame reading zero is not worth
  flipping an icon over -- a stutter, a load, a frame the game skipped -- and
  an icon that blinks is the same lie told faster. So a run of agreeing frames
  is required before the answer changes.
]]

local playstate = {}

---How many frames in a row must agree before the answer changes.
---
---At sixty frames a second that is a twentieth of a second: fast enough that
---pressing pause looks instant, slow enough that one odd frame changes
---nothing.
playstate.STEADY_FRAMES = 3

---@return table
function playstate.new()
  return { paused = false, agreeing = 0, saw = nil }
end

---Take one frame's reading.
---@param state table
---@param gameDeltaT number|nil @from ac.getGameDeltaT
---@return boolean @whether the replay is paused, steadily
function playstate.update(state, gameDeltaT)
  if type(state) ~= 'table' then return false end

  -- No reading at all is not a pause. A build without the call, or a frame
  -- where it answered nothing, should leave the icon where it was rather than
  -- announce something that was never measured.
  if type(gameDeltaT) ~= 'number' or gameDeltaT ~= gameDeltaT then
    state.agreeing = 0
    state.saw = nil
    return state.paused
  end

  local looksPaused = gameDeltaT <= 0

  if looksPaused ~= state.saw then
    state.saw = looksPaused
    state.agreeing = 1
  else
    state.agreeing = state.agreeing + 1
  end

  if looksPaused ~= state.paused and state.agreeing >= playstate.STEADY_FRAMES then
    state.paused = looksPaused
  end

  return state.paused
end

return playstate
