--[[
  Track adapter -- the only place that asks the game what the circuit looks
  like.

  It answers one question: give me an outline of the track I can draw. The
  shape it returns is what core/trackmap works on, so everything downstream
  stays testable out of game.

  The outline comes from the AI spline (`fast_lane.ai`), for one reason that
  decides it over the track's own map.png: every point of it IS a value of
  camera_in. Placing a camera on the map is then reading an index, not
  inverting a projection, and no map.ini scale and offset has to be decoded.

  Not every track has one. Drift and gymkhana layouts, parking-lot maps and
  the odd scenic mod ship without a fast_lane, and a secondary layout
  sometimes misses it too. The answer is then nil, and the caller says so
  rather than drawing a guess. Worth keeping in proportion: CamTool already
  picks its camera from car.splinePosition, which is that same spline, so a
  track without one is a track where the app does nothing anyway.

  Sampling happens once per track and is cached. It is far too slow for a
  frame, and the outline does not change while a session runs.
]]

local track = {}

---Metres between samples. Five puts about 1000 points on a 5 km circuit,
---which draws as a smooth line at any panel size we offer.
track.DEFAULT_SPACING_M = 5

---Sampling bounds. Too few points and a hairpin becomes a corner; too many
---and a long Nordschleife-sized outline costs more than it shows.
local MIN_SAMPLES = 64
local MAX_SAMPLES = 3000

---Half-width to fall back on when the track says nothing usable, in metres.
local DEFAULT_HALF_WIDTH_M = 5
---A fast_lane can be hand-made and careless. Anything outside this is not a
---racetrack edge, it is a bad number, and drawn at scale it would swamp the
---map.
local MIN_HALF_WIDTH_M = 1
local MAX_HALF_WIDTH_M = 30

local cache = nil

local function isFinite(v)
  return type(v) == 'number' and v == v and v - v == 0
end

---Clamp one side of the track to something that can be drawn.
---
---Lua does not raise on a bad division, it returns inf, and an inf half-width
---would stretch the ribbon off the panel. Anything not finite falls back.
local function usableHalfWidth(v)
  if not isFinite(v) then return DEFAULT_HALF_WIDTH_M end
  if v < MIN_HALF_WIDTH_M then return MIN_HALF_WIDTH_M end
  if v > MAX_HALF_WIDTH_M then return MAX_HALF_WIDTH_M end
  return v
end

---Does this track have an AI spline to draw?
---@return boolean
function track.hasOutline()
  if type(ac.hasTrackSpline) ~= 'function' then return false end
  local ok, answer = pcall(ac.hasTrackSpline)
  return ok and answer == true
end

---Sample the AI spline into an outline.
---
---Coordinates come out in CamTool space (Z-up), so `x` and `y` are the
---horizontal pair: the same space the cameras store their own positions in,
---and the same mapping the app already uses for the car
---(`position.x, position.z, position.y`).
---@param spacingM number|nil @metres between samples, default DEFAULT_SPACING_M
---@return table|nil @{ points = { { x, y, p, halfLeft, halfRight } }, closed, lengthM, source }
function track.outline(spacingM)
  if not track.hasOutline() then return nil end

  local sim = ac.getSim()
  local lengthM = sim ~= nil and sim.trackLengthM or nil
  if not isFinite(lengthM) or lengthM <= 0 then return nil end

  spacingM = isFinite(spacingM) and spacingM or track.DEFAULT_SPACING_M
  if spacingM <= 0 then spacingM = track.DEFAULT_SPACING_M end

  local count = math.floor(lengthM / spacingM + 0.5)
  if count < MIN_SAMPLES then count = MIN_SAMPLES end
  if count > MAX_SAMPLES then count = MAX_SAMPLES end

  local hasSides = type(ac.getTrackAISplineSides) == 'function'

  local points = {}
  for i = 0, count - 1 do
    local p = i / count
    local world = ac.trackProgressToWorldCoordinate(p)
    if world ~= nil then
      local halfLeft, halfRight = DEFAULT_HALF_WIDTH_M, DEFAULT_HALF_WIDTH_M
      if hasSides then
        local sides = ac.getTrackAISplineSides(p)
        if sides ~= nil then
          halfLeft = usableHalfWidth(sides.x)
          halfRight = usableHalfWidth(sides.y)
        end
      end

      points[#points + 1] = {
        -- AC is Y-up, CamTool is Z-up.
        x = world.x,
        y = world.z,
        p = p,
        halfLeft = halfLeft,
        halfRight = halfRight,
      }
    end
  end

  if #points < 2 then return nil end

  return {
    points = points,
    -- An A-B track must not have its two ends joined by a line across the map.
    closed = sim.isTrackOpen ~= true,
    lengthM = lengthM,
    source = 'ai-spline',
  }
end

---The outline of the track being driven, sampled once and kept.
---
---Keyed by track and layout, so the cache survives a session and reloads if
---the track ever changes underneath us.
---@param spacingM number|nil
---@return table|nil
function track.currentOutline(spacingM)
  local key = ac.getTrackID() .. '/' .. ac.getTrackLayout()
    .. '/' .. tostring(spacingM or track.DEFAULT_SPACING_M)

  if cache ~= nil and cache.key == key then return cache.outline end

  -- Cached even when it comes back nil: a track without a spline would
  -- otherwise be re-sampled on every draw, which is the expensive case.
  cache = { key = key, outline = track.outline(spacingM) }
  return cache.outline
end

---Forget what was sampled. For tests, and for a reload during development.
function track.clearCache()
  cache = nil
end

return track
