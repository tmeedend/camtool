--[[
  Tests for core/sections.lua and the adapter that feeds it.

  These are other people's files. A sections.ini is written by hand by whoever
  built the circuit, and the cases below are not hypothetical: bounds the
  wrong way round, a name that is only spaces, a stretch that runs across the
  start line. Each one of them reaches the ruler if nothing stops it here.
]]

local runner = require('tests/runner')
local fakes = require('tests/fakes/csp')
local sections = require('core/sections')
local track = require('adapters/track')

local test, eq, near = runner.test, runner.eq, runner.near

--------------------------------------------------------------------------
-- Making sense of what the file said
--------------------------------------------------------------------------

test('a plain section comes through as it was written', function()
  local list = sections.normalise({
    { from = 0.25, to = 0.35, text = 'Kemmel Straight' },
  })

  eq(#list, 1)
  near(list[1].from, 0.25)
  near(list[1].to, 0.35)
  eq(list[1].text, 'Kemmel Straight')
  eq(list[1].wrapped, false)
end)

test('sections come out in lap order, whatever order the file had', function()
  local list = sections.normalise({
    { from = 0.6, to = 0.7, text = 'C' },
    { from = 0.1, to = 0.2, text = 'A' },
    { from = 0.3, to = 0.4, text = 'B' },
  })

  eq(#list, 3)
  eq(list[1].text, 'A')
  eq(list[2].text, 'B')
  eq(list[3].text, 'C')
end)

test('a section across the start line is cut in two, both named', function()
  -- The last corner and the first are often one named stretch. The ribbon is
  -- cut at the line and cannot draw that in one piece.
  local list = sections.normalise({
    { from = 0.95, to = 0.05, text = 'Start/Finish' },
  })

  eq(#list, 2)
  near(list[1].from, 0)
  near(list[1].to, 0.05)
  near(list[2].from, 0.95)
  near(list[2].to, 1)
  eq(list[1].text, 'Start/Finish')
  eq(list[2].text, 'Start/Finish')
  eq(list[1].wrapped, true)
  eq(list[2].wrapped, true)
end)

test('a wrap that ends exactly on the line is one piece, not two', function()
  local list = sections.normalise({
    { from = 0.9, to = 0, text = 'Last corner' },
  })

  eq(#list, 1)
  near(list[1].from, 0.9)
  near(list[1].to, 1)
end)

test('a section of no length is dropped', function()
  eq(#sections.normalise({ { from = 0.5, to = 0.5, text = 'Nothing' } }), 0)
end)

test('bounds outside the lap are brought back into it', function()
  local list = sections.normalise({
    { from = 1.25, to = 1.35, text = 'Second lap' },
    { from = -0.9, to = -0.8, text = 'Backwards' },
  })

  eq(#list, 2)
  near(list[1].from, 0.1)
  near(list[1].to, 0.2)
  near(list[2].from, 0.25)
  near(list[2].to, 0.35)
end)

test('a bound of exactly 1 stays the end of the lap, not the start', function()
  -- `1 % 1` is 0, and taking it would turn the last tenth of the lap into
  -- the whole of it.
  local list = sections.normalise({ { from = 0.9, to = 1, text = 'Last' } })

  eq(#list, 1)
  near(list[1].from, 0.9)
  near(list[1].to, 1)
end)

test('a section with numbers that are not numbers is dropped', function()
  -- Lua hands back inf rather than raising, so a bad division in a hand-made
  -- file arrives here looking like a number.
  eq(#sections.normalise({
    { from = 0 / 0, to = 0.5, text = 'Nan' },
    { from = 0.1, to = 1 / 0, text = 'Inf' },
    { from = '0.2', to = 0.3, text = 'Text' },
    { from = 0.4, to = nil, text = 'Missing' },
  }), 0)
end)

test('a name that is only spaces is no name at all', function()
  local list = sections.normalise({
    { from = 0.1, to = 0.2, text = '   ' },
    { from = 0.3, to = 0.4, text = '  Eau Rouge  ' },
    { from = 0.5, to = 0.6 },
  })

  eq(#list, 3)
  eq(list[1].text, nil)
  eq(list[2].text, 'Eau Rouge', 'and it is trimmed')
  eq(list[3].text, nil)
end)

test('nothing at all is an empty list, not a crash', function()
  eq(#sections.normalise(nil), 0)
  eq(#sections.normalise('sections.ini'), 0)
  eq(#sections.normalise({ 'not a section', 7 }), 0)
end)

--------------------------------------------------------------------------
-- Asking what a place is called
--------------------------------------------------------------------------

local NAMED = sections.normalise({
  { from = 0.1, to = 0.2, text = 'Eau Rouge' },
  { from = 0.25, to = 0.35, text = 'Kemmel Straight' },
})

test('a position inside a section gets its name', function()
  eq(sections.at(NAMED, 0.15), 'Eau Rouge')
  eq(sections.at(NAMED, 0.3), 'Kemmel Straight')
end)

test('a stretch nobody named answers nothing', function()
  -- Not the empty string: the sections do not cover the lap, and a blank
  -- looks like a name.
  eq(sections.at(NAMED, 0.5), nil)
  eq(sections.at(NAMED, 0.22), nil)
end)

test('the end of a section belongs to what comes next', function()
  eq(sections.at(NAMED, 0.1), 'Eau Rouge', 'the start is inside')
  eq(sections.at(NAMED, 0.2), nil, 'the end is not')
end)

test('asking about nothing answers nothing', function()
  eq(sections.at(nil, 0.15), nil)
  eq(sections.at(NAMED, 0 / 0), nil)
end)

--------------------------------------------------------------------------
-- Reading the file
--------------------------------------------------------------------------

local function withTrack(opts)
  local handle = fakes.install(opts)
  track.clearCache()
  return handle
end

test('the adapter reads sections.ini and hands back drawable stretches', function()
  local handle = withTrack({ trackSections = {
    { TEXT = 'Eau Rouge', IN = 0.1, OUT = 0.2 },
    { TEXT = 'Kemmel Straight', IN = 0.25, OUT = 0.35 },
  } })

  local list = track.sections()
  eq(#list, 2)
  eq(list[1].text, 'Eau Rouge')
  near(list[2].from, 0.25)

  handle.restoreIo()
end)

test('a track with no sections.ini gets an empty list', function()
  local handle = withTrack({})
  eq(#track.sections(), 0)
  handle.restoreIo()
end)

test('a sections.ini that throws on open is an empty list too', function()
  local handle = withTrack({ trackDataRaises = true })
  eq(#track.sections(), 0)
  handle.restoreIo()
end)

test('a section missing a bound is left out rather than guessed', function()
  local handle = withTrack({ trackSections = {
    { TEXT = 'Half a section', IN = 0.1 },
    { TEXT = 'Whole one', IN = 0.4, OUT = 0.5 },
  } })

  local list = track.sections()
  eq(#list, 1)
  eq(list[1].text, 'Whole one')

  handle.restoreIo()
end)

test('the file is read once and kept', function()
  local reads = 0
  local handle = withTrack({ trackSections = {
    { TEXT = 'Only one', IN = 0.1, OUT = 0.2 },
  } })

  local inner = ac.INIConfig.trackData
  ac.INIConfig.trackData = function(name)
    reads = reads + 1
    return inner(name)
  end

  for _ = 1, 30 do track.sections() end
  eq(reads, 1, 'thirty frames, one read')

  handle.restoreIo()
end)

test('a different track is read again', function()
  local handle = withTrack({ trackID = 'spa',
    trackSections = { { TEXT = 'Eau Rouge', IN = 0.1, OUT = 0.2 } } })
  eq(track.sections()[1].text, 'Eau Rouge')
  handle.restoreIo()

  -- No clearCache here, deliberately: it is the track changing that has to
  -- throw the old names away, not a call nothing in the game ever makes.
  handle = fakes.install({ trackID = 'monza',
    trackSections = { { TEXT = 'Lesmo', IN = 0.3, OUT = 0.4 } } })
  eq(track.sections()[1].text, 'Lesmo', 'not the cached Spa')
  handle.restoreIo()
end)
