--[[
  Tests for core/ruler.lua, the graduations along the top of the ribbon.

  All arithmetic, so all checkable: a lap is a known number of metres and a
  ribbon a known number of pixels, and everything about the marks follows from
  those two. What these cannot say is whether it LOOKS right -- that is the
  in-game checklist.

  The case worth the most is the one nobody would try in game: a panel dragged
  narrow. That is where a fixed step turns the ruler into a smear.
]]

local runner = require('tests/runner')
local ruler = require('core/ruler')

local test, eq, near = runner.test, runner.eq, runner.near

local SPA_M = 7004
local SHORT_M = 1200

local function majors(ticks)
  local out = {}
  for i = 1, #ticks do
    if ticks[i].major then out[#out + 1] = ticks[i] end
  end
  return out
end

local function labelled(ticks)
  local out = {}
  for i = 1, #ticks do
    if ticks[i].label ~= nil then out[#out + 1] = ticks[i] end
  end
  return out
end

--------------------------------------------------------------------------
-- Writing a distance down
--------------------------------------------------------------------------

test('short distances are metres and long ones kilometres', function()
  eq(ruler.label(500), '500 m')
  eq(ruler.label(999), '999 m')
  eq(ruler.label(1000), '1 km')
  eq(ruler.label(7000), '7 km')
end)

test('a round number of kilometres has no decimal to read', function()
  eq(ruler.label(2000), '2 km')
  eq(ruler.label(2500), '2.5 km')
end)

test('a distance that is not a number is written as nothing', function()
  eq(ruler.label(0 / 0), '')
  eq(ruler.label(1 / 0), '')
end)

--------------------------------------------------------------------------
-- Choosing the step
--------------------------------------------------------------------------

test('labels are far enough apart to be read', function()
  for _, width in ipairs({ 120, 240, 460, 900, 1600 }) do
    for _, lengthM in ipairs({ SHORT_M, 4300, SPA_M, 20800 }) do
      ruler.reset()
      local marks = labelled(ruler.ticks(lengthM, width))

      for i = 2, #marks do
        local gap = (marks[i].position - marks[i - 1].position) * width
        eq(gap >= ruler.MIN_LABEL_PX - 0.001, true, string.format(
          '%d m over %d px: labels %.1f px apart', lengthM, width, gap))
      end
    end
  end
end)

test('a wider panel earns more labels, never fewer', function()
  ruler.reset()
  local narrow = #labelled(ruler.ticks(SPA_M, 300))
  ruler.reset()
  local wide = #labelled(ruler.ticks(SPA_M, 1200))

  eq(wide > narrow, true, 'four times the room says more, not the same')
end)

test('a panel squeezed to nothing still says what the ribbon measures', function()
  -- One label beats none: without it the ribbon is a bare line with no unit.
  ruler.reset()
  local marks = ruler.ticks(SPA_M, 40)
  eq(#marks > 0, true)
end)

test('the small marks line up with the labelled ones', function()
  -- A subdivision that is not a whole fraction of the step reads as a second,
  -- contradicting ruler.
  ruler.reset()
  local ticks = ruler.ticks(SPA_M, 600)
  local step = nil

  local run = 0
  for i = 1, #ticks do
    if ticks[i].major then
      if step ~= nil then eq(run, step, 'an uneven run of small marks') end
      if run > 0 then step = run end
      run = 0
    else
      run = run + 1
    end
  end
end)

test('the small marks are not a smear', function()
  for _, width in ipairs({ 120, 460, 1600 }) do
    ruler.reset()
    local ticks = ruler.ticks(SPA_M, width)
    for i = 2, #ticks do
      local gap = (ticks[i].position - ticks[i - 1].position) * width
      eq(gap >= ruler.MIN_TICK_PX - 0.001, true, string.format(
        '%d px wide: marks %.2f px apart', width, gap))
    end
  end
end)

--------------------------------------------------------------------------
-- Where the marks land
--------------------------------------------------------------------------

test('the marks are at round distances, and say so', function()
  ruler.reset()
  local marks = labelled(ruler.ticks(4000, 600))

  eq(#marks > 0, true)
  for i = 1, #marks do
    local metres = marks[i].position * 4000
    near(metres, math.floor(metres / 100 + 0.5) * 100, 0.001,
      'a label at a distance nobody thinks in')
    eq(marks[i].label, ruler.label(metres))
  end
end)

test('nothing is drawn past the finish line', function()
  ruler.reset()
  local ticks = ruler.ticks(SPA_M, 600)

  for i = 1, #ticks do
    eq(ticks[i].position >= 0 and ticks[i].position < 1, true,
      'a mark outside the lap')
  end
end)

test('the lap starts with a mark and no label on it', function()
  -- The left edge of the ribbon already says "the line". A "0 m" written on
  -- top of it is a word that has to be read to learn nothing.
  ruler.reset()
  local ticks = ruler.ticks(SPA_M, 600)

  near(ticks[1].position, 0)
  eq(ticks[1].major, true)
  eq(ticks[1].label, nil)
end)

--------------------------------------------------------------------------
-- Not allocating a ruler a frame
--------------------------------------------------------------------------

test('asking the same question twice gives back the same table', function()
  ruler.reset()
  local first = ruler.ticks(SPA_M, 460)
  local second = ruler.ticks(SPA_M, 460)

  eq(rawequal(first, second), true,
    'the panel draws this every frame and must not build it every frame')
end)

test('resizing the panel rebuilds it', function()
  ruler.reset()
  local first = ruler.ticks(SPA_M, 460)
  local second = ruler.ticks(SPA_M, 900)

  eq(rawequal(first, second), false)
end)

test('a track with no length answers with nothing, repeatedly', function()
  -- Before a session settles, the game has been seen to report no length at
  -- all. The ruler draws nothing then -- and still must not allocate.
  ruler.reset()
  local first = ruler.ticks(nil, 460)
  local second = ruler.ticks(0, 460)
  local third = ruler.ticks(0 / 0, 460)

  eq(#first, 0)
  eq(rawequal(first, second), true)
  eq(rawequal(second, third), true)
end)

test('a ribbon of no width answers with nothing', function()
  ruler.reset()
  eq(#ruler.ticks(SPA_M, 0), 0)
  eq(#ruler.ticks(SPA_M, -10), 0)
end)
