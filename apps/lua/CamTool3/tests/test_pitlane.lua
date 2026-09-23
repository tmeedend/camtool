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

--------------------------------------------------------------------------------
-- Selection: the second walk over the pit cameras
--------------------------------------------------------------------------------

local lap = require('tests/lap')
local interpolation = require('core/interpolation')

-- camera_file_lap carries two pit cameras: 1 from 0.035, 10 from 0.816.
local LAP = 'tests/fixtures/camera_file_lap'

local function always() return true end

---Where a car driving down the pit lane is, read off the file's pit spline.
local function pitSampler(doc)
  local pit = doc.pit_spline
  return function(position)
    local at = position < 0.5 and position + 1 or position
    return interpolation.interpolate_spline(at, pit.the_x, pit.loc_x),
      interpolation.interpolate_spline(at, pit.the_x, pit.loc_y),
      interpolation.interpolate_spline(at, pit.the_x, pit.loc_z)
  end
end

test('in the pit lane only pit cameras play, wrapping like the track ones', function()
  local result = lap.runCore({ cameraFile = require(LAP), frames = 300,
    inPitlane = always })
  local first = result.doc.pos[1].camera_in
  local second = result.doc.pos[10].camera_in
  local seen = {}
  for _, row in ipairs(result.frames) do
    local expected = (row.position >= first and row.position < second) and 1 or 10
    eq(row.activeCam, expected, string.format('at %.3f', row.position))
    seen[row.activeCam] = true
  end
  eq(seen[1] and seen[10], true, 'both pit cameras played')
end)

test('a pit camera is last among pit cameras, and only there', function()
  local result = lap.runCore({ cameraFile = require(LAP), frames = 300,
    inPitlane = always })
  for _, row in ipairs(result.frames) do
    eq(row.isLastCamera, row.activeCam == 10, string.format('at %.3f', row.position))
  end
end)

test('a file with no pit camera keeps its track cameras in the pit lane', function()
  -- And the first of them does not become "last" for it, which is what the
  -- legacy did: it asked whether the car was in the pit lane, not whether the
  -- camera was a pit camera.
  local fixture = 'tests/fixtures/camera_file_seb'
  local onTrack = lap.runCore({ cameraFile = require(fixture), frames = 200 })
  local inPits = lap.runCore({ cameraFile = require(fixture), frames = 200,
    inPitlane = always })
  for i = 1, 200 do
    local a, b = onTrack.frames[i], inPits.frames[i]
    eq(b.activeCam, a.activeCam, 'frame ' .. i)
    eq(b.isLastCamera, a.isLastCamera, 'frame ' .. i)
    runner.near(b.x, a.x, 1e-12, 'frame ' .. i .. ' x')
  end
end)

test('the app sees the car in the pit lane and plays the pit cameras', function()
  -- Driven down the pit lane across the line, so both pit cameras take over.
  -- The app decides from the file's splines; the core is told outright. If the
  -- app missed the pit lane anywhere, the two would part there.
  local raw = require(LAP)
  local sampler = pitSampler(data.load(raw))
  local opts = { cameraFile = raw, frames = 120, from = 0.002, to = 0.09,
    sampler = sampler }
  local viaApp = lap.run(opts)
  viaApp.handle.restoreIo()
  opts.inPitlane = always
  local viaCore = lap.runCore(opts)

  local seen = {}
  for i = 1, 120 do
    local a, b = viaApp.frames[i], viaCore.frames[i]
    seen[b.activeCam] = true
    runner.near(a.x, b.x, 1e-12, 'frame ' .. i .. ' x')
    runner.near(a.y, b.z, 1e-12, 'frame ' .. i .. ' y is the core z')
    runner.near(a.z, b.y, 1e-12, 'frame ' .. i .. ' z is the core y')
    runner.near(a.lx, b.lookX, 1e-12, 'frame ' .. i .. ' look x')
  end
  eq(seen[1] and seen[10], true, 'the run crosses from one pit camera to the other')
end)
