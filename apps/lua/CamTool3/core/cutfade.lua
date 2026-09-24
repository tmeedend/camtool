--[[
  The sound coming back after a cut -- pure logic, no ac/CSP dependency.

  From CamTool_2.acUpdate (~116-132), where it sits unannounced: whenever the
  live camera or the followed car changes, the game's volume drops to nothing
  and comes back over half a second, on a square curve -- quiet for longer,
  then quickly back. A cut in the picture is a cut in the sound, as on
  television, instead of the engine note jumping from one microphone to the
  next.

  The first camera after the camera is taken is not a cut: CamTool 2 does not
  fade on activation, and neither does this.
]]

local cutfade = {}

---How long the sound takes to come back, seconds.
cutfade.DURATION = 0.5

function cutfade.new()
  return { clock = 1, camera = nil, car = nil, primed = false }
end

---Forget what was on screen: the next frame is a first frame, not a cut.
function cutfade.reset(state)
  state.clock, state.camera, state.car, state.primed = 1, nil, nil, false
end

---One frame.
---@param state table @from cutfade.new
---@param dt number @real seconds since the last frame
---@param camera any @the live camera, compared frame to frame
---@param car any @the followed car
---@return number @the volume multiplier, 0..1
function cutfade.update(state, dt, camera, car)
  if state.primed and (camera ~= state.camera or car ~= state.car) then
    state.clock = 0
  end
  state.primed = true
  state.camera, state.car = camera, car

  -- Read before it moves on, as CamTool 2 does: the frame of the cut is
  -- silent.
  local multiplier = state.clock * state.clock
  state.clock = math.min(1, state.clock + (dt or 0) / cutfade.DURATION)
  return multiplier
end

return cutfade
