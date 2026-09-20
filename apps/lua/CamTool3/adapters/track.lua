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

local sectionsCore = require('core/sections')

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

---Why an outline could not be built, in words the panel can show.
---
---Four reasons rather than one, and the split is the point: "no outline" on a
---circuit that plainly has one sends whoever reads it to the source. These
---say which of the four it was, and the log says it with the numbers.
track.NO_SPLINE_API = 'this CSP build has no ac.hasTrackSpline'
track.NO_SPLINE = 'the game reports no AI spline here'
track.NO_LENGTH = 'the game reports no track length'
track.NO_POINTS = 'the AI spline returned nothing usable'

---Can this be called?
---
---NOT `type(v) == 'function'`. CSP binds a good part of the `ac` namespace
---through LuaJIT's FFI, and a C function pointer is `cdata`: perfectly
---callable, but `type` says otherwise. Checking for 'function' declared every
---such call missing and turned a normal circuit into "no track outline for
---this circuit" -- which is exactly what it did on Spa.
---
---So: anything that is there might be callable, and pcall settles it.
local function callable(v)
  return v ~= nil
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

---What stands between us and an AI spline, if anything.
---@return string|nil @nil when there is one to draw
local function splineTrouble()
  local probe = ac.hasTrackSpline
  if not callable(probe) then return track.NO_SPLINE_API end

  local ok, answer = pcall(probe)
  if not ok then return track.NO_SPLINE_API end
  if answer ~= true then return track.NO_SPLINE end
  return nil
end

---Does this track have an AI spline to draw?
---@return boolean
function track.hasOutline()
  return splineTrouble() == nil
end

---Sample the AI spline into an outline.
---
---Coordinates come out in CamTool space (Z-up), so `x` and `y` are the
---horizontal pair: the same space the cameras store their own positions in,
---and the same mapping the app already uses for the car
---(`position.x, position.z, position.y`).
---
---Each way of failing says which one it was. A map that only knows how to say
---"no track" sends whoever reads it to the source instead, which is what
---happened the first time this ran on a normal circuit.
---@param spacingM number|nil @metres between samples, default DEFAULT_SPACING_M
---@return table|nil @{ points = { { x, y, p, halfLeft, halfRight } }, closed, lengthM, source }
---@return string|nil @why, when there is no outline
function track.outline(spacingM)
  local trouble = splineTrouble()
  if trouble ~= nil then return nil, trouble end

  local sim = ac.getSim()
  local lengthM = sim ~= nil and sim.trackLengthM or nil
  if not isFinite(lengthM) or lengthM <= 0 then return nil, track.NO_LENGTH end

  spacingM = isFinite(spacingM) and spacingM or track.DEFAULT_SPACING_M
  if spacingM <= 0 then spacingM = track.DEFAULT_SPACING_M end

  local count = math.floor(lengthM / spacingM + 0.5)
  if count < MIN_SAMPLES then count = MIN_SAMPLES end
  if count > MAX_SAMPLES then count = MAX_SAMPLES end

  local hasSides = callable(ac.getTrackAISplineSides)

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

  if #points < 2 then return nil, track.NO_POINTS end

  return {
    points = points,
    -- An A-B track must not have its two ends joined by a line across the map.
    closed = sim.isTrackOpen ~= true,
    lengthM = lengthM,
    source = 'ai-spline',
  }
end

---How many calls to wait before trying a failed track again. At one draw a
---frame that is about a second.
local RETRY_EVERY = 60

---The outline of the track being driven, sampled once and kept.
---
---Keyed by track and layout, so the cache survives a session and reloads if
---the track ever changes underneath us.
---
---A SUCCESS is kept for good: sampling is far too slow for a frame and the
---track does not change shape while a session runs.
---
---A FAILURE is kept only for a second. The app loads when its window is first
---opened, which can be while the session is still coming up, and the first
---answer out of the game is not always the settled one. Caching that first
---"no" for good would leave the map empty for a whole session over a question
---that would have answered itself a second later. Retrying every frame is the
---other mistake -- that is the expensive case -- so it retries on a count.
---@param spacingM number|nil
---@return table|nil outline
---@return string|nil reason @why there is none
function track.currentOutline(spacingM)
  local key = ac.getTrackID() .. '/' .. ac.getTrackLayout()
    .. '/' .. tostring(spacingM or track.DEFAULT_SPACING_M)

  if cache ~= nil and cache.key == key then
    if cache.outline ~= nil then return cache.outline, nil end

    cache.waited = cache.waited + 1
    if cache.waited < RETRY_EVERY then return nil, cache.reason end
  end

  local outline, reason = track.outline(spacingM)
  local firstTry = cache == nil or cache.key ~= key
  cache = { key = key, outline = outline, reason = reason, waited = 0 }

  -- Once per track, and once more only if the reason changes. Never per
  -- frame. These are the numbers that would have said what was wrong the
  -- first time this ran on a circuit that plainly has an AI spline.
  if outline == nil and firstTry then
    local sim = ac.getSim()
    ac.log(string.format(
      'CamTool3: no track outline for %s -- %s ' ..
      '(hasTrackSpline is %s, trackLengthM is %s)',
      key, tostring(reason), type(ac.hasTrackSpline),
      tostring(sim ~= nil and sim.trackLengthM or nil)))
  end

  return outline, reason
end

---The named stretches of the lap, read once and kept. Keyed by track and
---layout, like the outline.
local sectionCache = nil

---Pull the raw IN / OUT / TEXT out of `sections.ini`.
---
---Everything here is behind pcall and the answers are handed to core/sections
---to be made sense of. A sections.ini is written by hand by the track author,
---and this app is not the place to find out what happens when one is not.
---@return table[] @{ { from, to, text } } in file order, possibly empty
local function readSections()
  local raw = {}

  local reader = ac.INIConfig ~= nil and ac.INIConfig.trackData or nil
  if not callable(reader) then return raw end

  local ok, config = pcall(reader, 'sections.ini')
  if not ok or type(config) ~= 'table' or not callable(config.iterate) then
    return raw
  end

  local read = pcall(function()
    for _, name in config:iterate('SECTION') do
      -- The default given decides the type that comes back, which is the
      -- whole reason IN and OUT are asked for with a number and TEXT with a
      -- string.
      raw[#raw + 1] = {
        from = config:get(name, 'IN', 0 / 0),
        to = config:get(name, 'OUT', 0 / 0),
        text = config:get(name, 'TEXT', ''),
      }
    end
  end)
  if not read then return {} end

  return raw
end

---What this part of the track is called, if it is called anything.
---
---Tracks carry a `sections.ini` giving IN / OUT / TEXT per section -- Spa has
---Kemmel Straight, Les Combes, Eau Rouge -- and ac.getTrackSectorName reads
---it. Confirmed in game rather than assumed, which was worth doing: a build
---answering "Sector 2" everywhere would have made this worse than useless as
---a suggested camera name.
---
---The sections do NOT cover the whole lap. Between them the answer is an
---empty string, which is why this hands back nil rather than a blank: a
---camera on a stretch nobody named should be offered nothing, not "".
---@param position number @0..1
---@return string|nil
function track.sectionNameAt(position)
  if not isFinite(position) then return nil end
  if not callable(ac.getTrackSectorName) then return nil end

  local ok, name = pcall(ac.getTrackSectorName, position)
  if not ok or type(name) ~= 'string' then return nil end

  name = name:gsub('^%s+', ''):gsub('%s+$', '')
  if name == '' then return nil end
  return name
end

---The named stretches of the lap, from the track's own `sections.ini`.
---
---WHY THE FILE AND NOT ac.getTrackSectorName. That call answers one position
---at a time. The ruler above the ribbon draws a name ACROSS the stretch it
---covers, so it needs the bounds, and finding them by probing would mean a
---thousand calls a frame to discover what the file states outright.
---
---The file is read once per track and kept. It is a handful of lines, but it
---is a file, and a file has no business being opened in a frame.
---
---An absent or unreadable file is an empty list, not an error: plenty of
---circuits name nothing, and the ruler then shows distances alone.
---@return table[] @{ { from, to, text, wrapped } }, possibly empty
function track.sections()
  local key = ac.getTrackID() .. '/' .. ac.getTrackLayout()

  if sectionCache ~= nil and sectionCache.key == key then
    return sectionCache.list
  end

  sectionCache = { key = key, list = sectionsCore.normalise(readSections()) }
  return sectionCache.list
end

---Forget what was sampled. For tests, and for a reload during development.
function track.clearCache()
  cache = nil
  sectionCache = nil
end

return track
