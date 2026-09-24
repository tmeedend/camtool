--[[
  Mouse look -- pure logic, no ac/CSP dependency.

  Ported from classes/MouseLook.py and the few lines of CamTool_2.acUpdate that
  drive it. Holding the mouse look key hands the camera to the mouse:

  - Left button held, mouse moving: the camera turns. Not by the raw movement
    but by how far the pointer is from the AVERAGE of its last 60 positions,
    so a flick keeps turning the camera for about a second while the average
    catches up. That is where the smoothness comes from.
  - Left button released: the camera coasts on the last turn and slows down
    by 5% a tick.
  - Zoom in / zoom out keys: the field of view eases in and out of a steady
    change over a quarter of a second.
  - The weight: while the key is held the camera file lets go over a second,
    and when it is released it takes back over two. The playback reads it to
    blend the keyframed camera with the one the mouse is steering.

  ONE DELIBERATE DEPARTURE, decided with Theo: CamTool 2 counts in frames.
  Its 60 samples are a second at 60 fps and 0.4 s at 150, its 5% slowdown is
  per frame, and its turn is applied per frame -- so the same gesture turned
  the camera two and a half times as far on a fast machine. Everything here
  runs on a fixed 60 Hz tick instead: the samples are taken on it, the
  slowdown is 0.95 per tick, and the turn is scaled by dt * 60. At 60 fps it
  is CamTool 2 exactly; at any other rate it is what CamTool 2 was at 60.

  And one bug not reproduced: CamTool 2 starts its zoom easing at "just
  released", so the first quarter second after the app loads zooms the free
  camera in by several degrees. Here it starts at rest.
]]

local fov = require('core/fov')

local mouselook = {}

---How many samples the average runs over, and how often one is taken.
mouselook.SAMPLES = 60
mouselook.TICK = 1 / 60

---Per tick, while coasting.
mouselook.COAST = 0.95

---The zoom step, in the stored FOV unit per second at full ease, and the
---limits CamTool 2 clamps to.
mouselook.ZOOM_RATE = 0.015
mouselook.FOV_MIN = 1
mouselook.FOV_MAX = 90

---Where the camera file stands for focus while the mouse has the camera.
mouselook.FOCUS_DISTANCE = 300

function mouselook.new()
  local state = {
    -- The pointer, rebuilt from the deltas: CSP hands out movement, CamTool 2
    -- read absolute positions. Only differences of it are ever used.
    px = 0, py = 0,
    xs = {}, ys = {}, head = 1,
    tickClock = 0,
    momentumX = 0, momentumY = 0,
    -- 0..1 before the ease: rises while the key is held, falls at half speed.
    weightClock = 0,
    -- The camera the gesture started on, so a cut during the hand-back
    -- snaps back rather than easing into a different shot.
    startCamera = nil,
    -- 1 is at rest. CamTool 2 starts at 0, see the note above.
    zoomClock = 1,
    zoomDirection = 1,
  }
  mouselook.forget(state)
  return state
end

---Fill every sample with where the pointer is now, and stop turning.
function mouselook.forget(state)
  for i = 1, mouselook.SAMPLES do
    state.xs[i], state.ys[i] = state.px, state.py
  end
  state.head = 1
  state.momentumX, state.momentumY = 0, 0
end

---Every sample to the current pointer, keeping the momentum: what a released
---button does, so the next press starts from here rather than from a jump.
local function resample(state)
  for i = 1, mouselook.SAMPLES do
    state.xs[i], state.ys[i] = state.px, state.py
  end
end

---The eased weight the playback blends by: 0 is the camera file, 1 the mouse.
function mouselook.weight(state)
  return math.sin(state.weightClock * math.pi / 2)
end

---One frame.
---@param state table @from mouselook.new
---@param input table
---  dt           seconds since the last frame
---  held         the mouse look key is down
---  steering     the left button is down, and not on one of our windows
---  dx, dy       pointer movement this frame, pixels
---  screenW/H    the game window, pixels; the turn is measured against it
---  fov          the camera's field of view now, degrees
---  zoomIn/Out   the zoom keys are down
---  camera       which camera of the file is live, for the snap back
---@return table @{ heading = , pitch = , fov = , weight = }: the turn to add
---  this frame, in radians, the new field of view, and the blend weight
function mouselook.update(state, input)
  local dt = input.dt or 0
  if dt < 0 then dt = 0 end
  local ticks = dt / mouselook.TICK

  state.px = state.px + (input.dx or 0)
  state.py = state.py + (input.dy or 0)

  local result = { heading = 0, pitch = 0, fov = input.fov, weight = 0 }

  if input.held then
    state.weightClock = math.min(1, state.weightClock + dt)
    if state.startCamera == nil then state.startCamera = input.camera end

    -- The turn from the momentum as it stood, then the momentum moves on: the
    -- order CamTool 2 runs them in. Sensitivity follows the lens, so a long
    -- lens is not a twitchy one.
    local sensitivity = (input.fov or 50) / 50
    result.heading = math.rad(state.momentumX * sensitivity) * ticks
    result.pitch = math.rad(state.momentumY * sensitivity) * ticks

    if input.steering then
      state.tickClock = state.tickClock + dt
      while state.tickClock >= mouselook.TICK do
        state.tickClock = state.tickClock - mouselook.TICK
        state.head = state.head % mouselook.SAMPLES + 1
        state.xs[state.head], state.ys[state.head] = state.px, state.py
      end

      local sx, sy = 0, 0
      for i = 1, mouselook.SAMPLES do sx, sy = sx + state.xs[i], sy + state.ys[i] end
      local avgX, avgY = sx / mouselook.SAMPLES, sy / mouselook.SAMPLES

      local w = (input.screenW or 1920) / 10
      local h = (input.screenH or 1080) / 10
      state.momentumX = (avgX - state.px) / w
      state.momentumY = (avgY - state.py) / h
    else
      local keep = mouselook.COAST ^ ticks
      state.momentumX = state.momentumX * keep
      state.momentumY = state.momentumY * keep
      resample(state)
      state.tickClock = 0
    end
  else
    state.weightClock = math.max(0, state.weightClock - dt / 2)
    -- A different camera took over during the hand-back: no easing from one
    -- shot into another.
    if state.weightClock > 0 and state.startCamera ~= nil
        and input.camera ~= state.startCamera then
      state.weightClock = 0
    end
    if state.weightClock == 0 then state.startCamera = nil end
    mouselook.forget(state)
    state.tickClock = 0
  end

  -- The zoom keys only count while the camera is the mouse's, as in CamTool 2.
  local zoomIn = input.held and input.zoomIn
  local zoomOut = input.held and input.zoomOut
  local factor
  if zoomIn or zoomOut then
    state.zoomClock = math.max(0, state.zoomClock - dt * 4)
    factor = math.sin((1 - state.zoomClock) * math.pi / 2)
    state.zoomDirection = zoomIn and 1 or -1
    if zoomIn and zoomOut then state.zoomDirection = 0 end
  else
    state.zoomClock = math.min(1, state.zoomClock + dt * 4)
    factor = 1 - math.sin(state.zoomClock * math.pi / 2)
  end

  if factor > 0 and state.zoomDirection ~= 0 and type(input.fov) == 'number'
      and input.fov > 0 then
    local stored = fov.encode(input.fov)
      + state.zoomDirection * mouselook.ZOOM_RATE * dt * factor
    if stored > 0 then
      local zoomed = fov.decode(stored)
      result.fov = math.max(mouselook.FOV_MIN, math.min(mouselook.FOV_MAX, zoomed))
    end
  end

  result.weight = mouselook.weight(state)
  return result
end

return mouselook
