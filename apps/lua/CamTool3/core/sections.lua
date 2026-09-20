--[[
  The named stretches of a circuit -- pure logic, no ac/CSP dependency.

  A track carries a `sections.ini` naming parts of the lap: Eau Rouge, Kemmel
  Straight, Les Combes. Each entry gives IN and OUT as lap positions and a
  TEXT. That is exactly what the ruler above the ribbon needs, and what
  `ac.getTrackSectorName` cannot give: it answers one position at a time, so
  drawing a name over the stretch it covers would mean probing the lap a
  thousand times a frame to find out where the name starts and stops.

  WHAT THIS FILE IS FOR. The adapter reads the file, this turns what it read
  into something drawable. The files are hand-written by track authors and
  show it: bounds the wrong way round, a section running past the line, an
  empty TEXT, the odd value that is not a number at all. None of that should
  reach the drawing code.

  SECTIONS DO NOT COVER THE LAP. Between them there is nothing, and nothing is
  the right answer -- a stretch nobody named gets no label rather than an
  invented one. Same reasoning as track.sectionNameAt returning nil and not ''.

  A SECTION CAN CROSS THE START LINE. The last corner before the line and the
  first after it are often one named stretch, so OUT comes out smaller than
  IN. The ribbon is cut at the line and cannot draw that in one piece, so it
  is split in two -- the same thing core/trackmap does with the camera that
  holds the line.
]]

local sections = {}

local function isFinite(v)
  return type(v) == 'number' and v == v and v - v == 0
end

---A lap position brought into 0..1.
---
---1 is kept as 1 rather than wrapped to 0: it is a legitimate way to say "the
---line" as an END, and `1 % 1` would turn a section covering the last tenth
---of the lap into one covering the whole of it.
local function lapPosition(v)
  if v == 1 then return 1 end
  local p = v % 1
  if p < 0 then p = p + 1 end
  return p
end

---What a TEXT is worth once the spaces are off it.
---@return string|nil @nil for a section with no name, which is not a name of ''
local function usableText(v)
  if type(v) ~= 'string' then return nil end
  local text = v:gsub('^%s+', ''):gsub('%s+$', '')
  if text == '' then return nil end
  return text
end

---Turn what the adapter read into stretches that can be drawn.
---
---One entry in, one or two out: a section crossing the start line becomes two
---pieces, both carrying the same name, and both marked `wrapped` so a caller
---that wants to count sections rather than draw them can tell.
---@param raw table[]|nil @{ { text = , from = , to = } }, in file order
---@return table[] @{ { from, to, text, wrapped } }, in lap order
function sections.normalise(raw)
  local out = {}
  if type(raw) ~= 'table' then return out end

  for i = 1, #raw do
    local entry = raw[i]
    if type(entry) == 'table'
        and isFinite(entry.from) and isFinite(entry.to) then
      local from, to = lapPosition(entry.from), lapPosition(entry.to)
      local text = usableText(entry.text)

      if from < to then
        out[#out + 1] = { from = from, to = to, text = text, wrapped = false }
      elseif from > to then
        -- Round the back of the lap. Either half can be empty -- a section
        -- from 0.9 to 0 is one piece, not two with a piece of nothing.
        if from < 1 then
          out[#out + 1] = { from = from, to = 1, text = text, wrapped = true }
        end
        if to > 0 then
          out[#out + 1] = { from = 0, to = to, text = text, wrapped = true }
        end
      end
      -- from == to is a section of no length, and there is nothing to draw.
    end
  end

  table.sort(out, function(a, b)
    if a.from ~= b.from then return a.from < b.from end
    return a.to < b.to
  end)

  return out
end

---What this part of the lap is called, according to the sections.
---
---The first stretch covering the position, which is what a well-formed file
---offers anyway: sections are meant not to overlap, and where a careless one
---does, the earlier of the two is as good an answer as any.
---@param list table[]|nil @as returned by normalise
---@param position number @0..1
---@return string|nil
function sections.at(list, position)
  if type(list) ~= 'table' or not isFinite(position) then return nil end
  local p = lapPosition(position)

  for i = 1, #list do
    local section = list[i]
    if p >= section.from and p < section.to and section.text ~= nil then
      return section.text
    end
  end

  return nil
end

return sections
