--[[
  Tests for core/pitlane.lua: telling the pit lane from the track.

  The spline cases run on the Red Bull Ring reference file, the one with pit
  cameras, because that is where the answer matters.
]]

local runner = require('tests/runner')
local pitlane = require('core/pitlane')
local data = require('core/data')
local rawFile = require('tests/fixtures/camera_file_v0')

local test, eq = runner.test, runner.eq

local function redBullRing()
  return data.load(rawFile)
end

test('the reference file decides from its own splines', function()
  eq(pitlane.usesSplines(redBullRing()), true)
end)

test('a car on the pit spline is in the pit lane', function()
  local doc = redBullRing()
  local pit = doc.pit_spline
  for i = 1, #pit.the_x do
    -- Recorded past 1 across the start line; the car reports 0..1.
    local at = pit.the_x[i]
    if at >= 1 then at = at - 1 end
    eq(pitlane.isCarInPitlane(doc, at, pit.loc_x[i], pit.loc_y[i], false), true,
      string.format('pit sample %d at %.3f', i, pit.the_x[i]))
  end
end)

test('a car on the track spline is not, whatever the game says', function()
  local doc = redBullRing()
  local track = doc.track_spline
  for i = 1, #track.the_x do
    eq(pitlane.isCarInPitlane(doc, track.the_x[i], track.loc_x[i], track.loc_y[i], true),
      false, string.format('track sample %d at %.3f', i, track.the_x[i]))
  end
end)

test('without both splines, the game decides', function()
  local doc = redBullRing()
  doc.pit_spline = { the_x = {}, loc_x = {}, loc_y = {} }
  eq(pitlane.usesSplines(doc), false)
  eq(pitlane.isCarInPitlane(doc, 0.5, 0, 0, true), true)
  eq(pitlane.isCarInPitlane(doc, 0.5, 0, 0, false), false)
  eq(pitlane.isCarInPitlane(doc, 0.5, 0, 0, nil), false)
  eq(pitlane.isCarInPitlane(nil, 0.5, 0, 0, true), true, 'no file at all')
end)

test('a spline with positions but no values is not a spline', function()
  local doc = redBullRing()
  doc.track_spline = { the_x = { 0.1, 0.2 }, loc_x = {}, loc_y = {} }
  eq(pitlane.usesSplines(doc), false)
end)

test('no car position falls back to the game too', function()
  local doc = redBullRing()
  eq(pitlane.isCarInPitlane(doc, 0.5, nil, nil, true), true)
  eq(pitlane.isCarInPitlane(doc, nil, 0, 0, false), false)
end)
