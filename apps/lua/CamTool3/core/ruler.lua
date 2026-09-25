--[[
  The graduations along the top of the ribbon -- pure logic, no ac/CSP
  dependency.

  A ribbon is one lap from the line to the line, and on its own it says
  nothing about distance: the same stretch of pixels is 200 metres at
  Brands Hatch and 900 at the Nordschleife. The ruler is what turns "a third
  of the way along" into "2.5 km", which is the unit everyone who has driven
  the track already thinks in.

  THE STEP IS CHOSEN, NEVER FIXED. A ruler wants a round number between its
  labels -- 100, 200, 500 metres, a kilometre -- and which of those fits
  depends on both the lap and the width of the panel. So the step comes off a
  1/2/5 ladder, taking the first rung whose spacing leaves room for a label.
  A fixed step would crowd into mush on a narrow window and leave a long
  circuit with three marks on it.

  NOTHING IS ALLOCATED PER FRAME. The panel draws this every frame and the
  answer only changes when the window is resized or the track is changed, so
  the last answer is kept and handed back as the same table. That is not an
  optimisation dressed up as a rule: `ui/band` draws inside a frame loop, and
  a table per frame there is a table per frame for the whole session.
]]

local ruler = {}

---Pixels a label needs to itself before the next one starts. Measured
---generously: the longest label the ladder produces is "10.5 km", and a
---ruler whose numbers touch is worse than one with fewer of them.
ruler.MIN_LABEL_PX = 54

---Pixels between the small unlabelled marks. Below this they stop reading as
---marks and start reading as a texture.
ruler.MIN_TICK_PX = 5

---The rungs, in metres. Ten metres is finer than anyone needs on a ribbon a
---few hundred pixels wide, and ten kilometres covers the Nordschleife.
local LADDER = { 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000 }

---The same ladder for a ribbon laid along the replay rather than the lap --
---the time list -- in seconds: from a second to half an hour.
local SECONDS_LADDER = { 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800 }

---A time as it should be written on the ruler: seconds under a minute,
---minutes and seconds above, as a replay counter reads.
---@param seconds number
---@return string
function ruler.timeLabel(seconds)
  if not (type(seconds) == 'number' and seconds == seconds and seconds - seconds == 0) then
    return ''
  end
  local whole = math.floor(seconds + 0.5)
  if whole < 60 then return string.format('%d s', whole) end
  return string.format('%d:%02d', math.floor(whole / 60), whole % 60)
end

local function isFinite(v)
  return type(v) == 'number' and v == v and v - v == 0
end

---A distance as it should be written on the ruler.
---
---Metres below a kilometre, kilometres above, and no trailing zero: "2 km"
---rather than "2.0 km", because the ruler is read at a glance and a decimal
---that says nothing still has to be read.
---@param metres number
---@return string
function ruler.label(metres)
  if not isFinite(metres) then return '' end

  if metres < 1000 then
    return string.format('%d m', math.floor(metres + 0.5))
  end

  local km = metres / 1000
  if math.abs(km - math.floor(km + 0.5)) < 0.001 then
    return string.format('%d km', math.floor(km + 0.5))
  end
  return string.format('%.1f km', km)
end

---The rung to put labels on, given how much room there is.
---
---The first one wide enough, and the widest one when none of them is: a
---panel squeezed to nothing gets one label rather than none, which at least
---says what the ribbon measures.
---@return number @metres
local function labelStep(lengthM, width, ladder)
  for i = 1, #ladder do
    if ladder[i] / lengthM * width >= ruler.MIN_LABEL_PX then return ladder[i] end
  end
  return ladder[#ladder]
end

---How finely to subdivide between two labels.
---
---Fifths where they fit, halves otherwise, nothing at all when even those
---would be a smear. Never a subdivision that is not a whole fraction of the
---step: marks that do not line up with the labels above them read as a
---second, contradicting ruler.
---@return number|nil @metres, or nil for no small marks
local function tickStep(step, lengthM, width)
  for _, divisor in ipairs({ 5, 2 }) do
    local candidate = step / divisor
    if candidate / lengthM * width >= ruler.MIN_TICK_PX then return candidate end
  end
  return nil
end

---The last answer, kept so the frame loop is not allocating a ruler a frame.
local memo = nil

---Where the marks go along one lap.
---
---Positions are 0..1 along the ribbon, so the caller multiplies by its own
---width and nothing here knows about pixels beyond how many there are.
---
---THE MARK AT ZERO CARRIES NO LABEL. It is the start line, it is the left
---edge of the ribbon, and "0 m" written there is a word where the eye is
---already being told the same thing by the edge itself.
---
---The same table comes back for the same question. Callers draw from it and
---do not keep it.
---@param lengthM number @the lap, in metres -- or the replay, in seconds
---@param width number @the ribbon, in pixels
---@param unit string|nil @'seconds' for a ribbon along the replay
---@return table[] @{ { position, label = string|nil, major = boolean } }
function ruler.ticks(lengthM, width, unit)
  local seconds = unit == 'seconds'
  if not isFinite(lengthM) or lengthM <= 0
      or not isFinite(width) or width <= 0 then
    if memo ~= nil and memo.empty then return memo.list end
    memo = { list = {}, empty = true }
    return memo.list
  end

  if memo ~= nil and memo.lengthM == lengthM and memo.width == width
      and memo.seconds == seconds then
    return memo.list
  end

  local step = labelStep(lengthM, width, seconds and SECONDS_LADDER or LADDER)
  local small = tickStep(step, lengthM, width)
  local list = {}

  -- Walked in units of the small step so a label and the mark it belongs to
  -- are the same mark, never two a rounding error apart.
  local unit = small or step
  local perLabel = math.floor(step / unit + 0.5)

  local i = 0
  while true do
    local metres = i * unit
    if metres >= lengthM then break end

    local major = (i % perLabel) == 0
    list[#list + 1] = {
      position = metres / lengthM,
      label = (major and i > 0)
        and (seconds and ruler.timeLabel(metres) or ruler.label(metres)) or nil,
      major = major,
    }
    i = i + 1
  end

  memo = { lengthM = lengthM, width = width, seconds = seconds, list = list }
  return list
end

---Forget the kept answer. For tests, which ask the same question twice on
---purpose and need to know which time it was computed.
function ruler.reset()
  memo = nil
end

return ruler
