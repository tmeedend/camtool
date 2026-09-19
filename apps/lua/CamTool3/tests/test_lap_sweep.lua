--[[
  Sweep a whole lap of every reference camera file and check what a person
  would otherwise have to watch for.

  Where the golden master says "these exact numbers", this says "no number
  anywhere in the lap is nonsense". The two catch different things: the golden
  catches a change, this catches a class of failure -- an infinity, a teleport
  mid-shot, a camera nobody can ever reach -- in a file it has never seen. New
  fixtures can be added to the list below and are checked with no further work.

  The lap is sampled at sweep.FRAMES_PER_LAP -- 90 seconds at 60 frames per
  second -- because one of the checks is in degrees per frame and only means
  something at a stated frame rate. Four files at that rate cost a third of a
  second, which the suite can afford.
]]

local runner = require('tests/runner')
local lap = require('tests/lap')
local sweep = require('tests/sweep')

local test, eq = runner.test, runner.eq

local FIXTURES = {
  {
    name = 'red bull ring, whole file',
    fixture = 'tests/fixtures/camera_file_lap',
  },
  {
    name = 'le lancone, 48 cameras',
    fixture = 'tests/fixtures/camera_file_lastcam',
  },
  {
    name = 'silverstone, recorded paths',
    fixture = 'tests/fixtures/camera_file_splines',
  },
  {
    name = 'red bull ring, trimmed',
    fixture = 'tests/fixtures/camera_file_v0',
  },
}

---Run one lap and fail with every finding, not just the first.
local function sweepFixture(fixture, options)
  local result = lap.runCore({
    cameraFile = require(fixture),
    frames = sweep.FRAMES_PER_LAP,
    options = options,
  })
  local spans = lap.spans(result.frames)
  local found = sweep.findings(result.doc, result.frames, spans,
    options and options.listName)

  if #found > 0 then
    error('\n       ' .. table.concat(found, '\n       '), 3)
  end

  return result, spans
end

for _, case in ipairs(FIXTURES) do
  test('a clean lap of ' .. case.name, function()
    local result, spans = sweepFixture(case.fixture)

    -- A lap that selected no camera at all would pass every check above by
    -- having nothing to check.
    eq(#spans > 0, true, 'no camera was ever active')
    eq(#result.frames, sweep.FRAMES_PER_LAP)
  end)
end

test('the same files stay clean with the legacy switches off', function()
  -- The fixes are opt-in, so they are the path least walked. Both of them
  -- change which keyframes are read, which is exactly the kind of change that
  -- can leave a camera reading past the end of its own data.
  for _, case in ipairs(FIXTURES) do
    sweepFixture(case.fixture, {
      legacyLastCamera = false,
      legacyZeroFill = true,
    })
  end
end)

test('the lap is the same whether the app or the core drives it', function()
  -- Two paths reach the same code: the app, through CSP fakes and a grabbed
  -- camera, and core/playback on its own. They have to agree, or the sweep
  -- above would be checking something the game never runs.
  local fixture = 'tests/fixtures/camera_file_lap'
  local viaApp = lap.run({ cameraFile = require(fixture), frames = 120 })
  viaApp.handle.restoreIo()
  local viaCore = lap.runCore({ cameraFile = require(fixture), frames = 120 })

  for i = 1, 120 do
    local a, b = viaApp.frames[i], viaCore.frames[i]
    -- The app converts to AC's Y-up world on the way out; the core does not.
    runner.near(a.x, b.x, 1e-12, 'frame ' .. i .. ' x')
    runner.near(a.y, b.z, 1e-12, 'frame ' .. i .. ' y is the core z')
    runner.near(a.z, b.y, 1e-12, 'frame ' .. i .. ' z is the core y')
    runner.near(a.lx, b.lookX, 1e-12, 'frame ' .. i .. ' look x')
    runner.near(a.ly, b.lookY, 1e-12, 'frame ' .. i .. ' look y')
    runner.near(a.lz, b.lookZ, 1e-12, 'frame ' .. i .. ' look z')
  end
end)

test('the #23 fix unfreezes the last camera and touches nothing else', function()
  -- Le Lancone's last camera keyframes a zoom from 54 to 12 degrees across the
  -- final two percent of the lap. The legacy wrap makes it read its keyframes
  -- a lap back, land before all of them and return the first one forever, so
  -- the zoom never happens. This is issue #23 measured rather than described.
  local fixture = require('tests/fixtures/camera_file_lastcam')
  local legacy = lap.runCore({ cameraFile = fixture, frames = 600 })
  local fixed = lap.runCore({
    cameraFile = fixture,
    frames = 600,
    options = { legacyLastCamera = false },
  })

  local lastCamera = nil
  for i = 1, #legacy.doc.pos do
    if not legacy.doc.pos[i].camera_pit then lastCamera = i end
  end

  local differedElsewhere = 0
  local legacySpread, fixedSpread = 0, 0
  local legacyMin, legacyMax = math.huge, -math.huge
  local fixedMin, fixedMax = math.huge, -math.huge

  for i = 1, 600 do
    local a, b = legacy.frames[i], fixed.frames[i]
    if a.activeCam == lastCamera then
      if a.fov ~= nil then
        legacyMin = math.min(legacyMin, a.fov)
        legacyMax = math.max(legacyMax, a.fov)
      end
      if b.fov ~= nil then
        fixedMin = math.min(fixedMin, b.fov)
        fixedMax = math.max(fixedMax, b.fov)
      end
    elseif a.fov ~= b.fov or a.x ~= b.x or a.lookX ~= b.lookX then
      differedElsewhere = differedElsewhere + 1
    end
  end

  legacySpread = legacyMax - legacyMin
  fixedSpread = fixedMax - fixedMin

  eq(differedElsewhere, 0, 'the wrap must only affect the last camera')
  eq(legacySpread < 0.001, true, string.format(
    'the legacy last camera must be frozen, but its FOV spans %.3f deg',
    legacySpread))
  eq(fixedSpread > 30, true, string.format(
    'the fixed last camera must zoom, but its FOV spans only %.3f deg',
    fixedSpread))
end)

--------------------------------------------------------------------------------
-- The detector itself
--------------------------------------------------------------------------------
-- A check that never fires is indistinguishable from no check at all. Every
-- rule above is fed a lap broken in exactly the way it exists to notice.

local FRAMES = sweep.FRAMES_PER_LAP

---A blameless lap: one camera dollying in a straight line, steady lens.
local function cleanLap()
  local rows = {}
  for i = 1, FRAMES do
    rows[i] = {
      frame = i, active = true, activeCam = 1,
      position = (i - 1) / (FRAMES - 1),
      x = i * 0.1, y = 0, z = 0,
      lookX = 1, lookY = 0, lookZ = 0,
      upX = 0, upY = 1, upZ = 0,
      fov = 30, dofDistance = 50, dofFactor = 1,
      heading = 0, pitch = 0,
    }
  end
  return rows, { pos = { { camera_in = 0 } } }
end

---@return string[] @findings for a lap with one thing done to it
local function findingsFor(damage, doc)
  local rows, defaultDoc = cleanLap()
  if damage ~= nil then damage(rows) end
  return sweep.findings(doc or defaultDoc, rows, lap.spans(rows))
end

local function mentions(found, text)
  for _, line in ipairs(found) do
    if line:find(text, 1, true) ~= nil then return true end
  end
  return false
end

test('an untouched lap produces no findings', function()
  eq(#findingsFor(nil), 0)
end)

test('an infinity is caught', function()
  -- The one that matters most: Lua hands back inf for a division by zero where
  -- Python raised, so this is how a ported bug reaches the screen.
  local found = findingsFor(function(rows) rows[100].x = 1 / 0 end)
  eq(mentions(found, 'frame 100: x is inf'), true, table.concat(found, ' | '))
end)

test('a not-a-number is caught', function()
  local found = findingsFor(function(rows) rows[100].heading = 0 / 0 end)
  eq(#found >= 1, true)
  eq(mentions(found, 'heading is'), true, table.concat(found, ' | '))
end)

test('a look vector that is not a direction is caught', function()
  local found = findingsFor(function(rows) rows[100].lookX = 0.5 end)
  eq(mentions(found, 'the look vector is'), true, table.concat(found, ' | '))
end)

test('a nonsense lens is caught', function()
  eq(mentions(findingsFor(function(rows) rows[100].fov = 0 end),
    'FOV is 0 degrees'), true)
  eq(mentions(findingsFor(function(rows) rows[100].fov = 200 end),
    'FOV is 200 degrees'), true)
  eq(mentions(findingsFor(function(rows) rows[100].dofDistance = -1 end),
    'focus distance is -1 m'), true)
end)

test('a camera that teleports mid-shot is caught', function()
  -- Five metres, on a shot that dollies a tenth of a metre a frame. The bar is
  -- ten times what the shot usually does, so this is not a sensitive
  -- instrument: a displacement under a metre here would pass. It is aimed at
  -- the camera that ends up somewhere else entirely, which is the failure that
  -- costs a game launch to find.
  local found = findingsFor(function(rows) rows[100].x = rows[100].x + 5 end)
  eq(mentions(found, 'the camera jumps'), true, table.concat(found, ' | '))
end)

test('a shot that stands still and then twitches is caught', function()
  local found = findingsFor(function(rows)
    for i = 1, FRAMES do rows[i].x = 0 end
    rows[100].x = 0.5
  end)
  eq(mentions(found, 'the camera jumps'), true, table.concat(found, ' | '))
end)

test('a lens that cuts rather than zooms is caught', function()
  local found = findingsFor(function(rows) rows[100].fov = 60 end)
  eq(mentions(found, 'the FOV changes'), true, table.concat(found, ' | '))
end)

test('a camera nothing can select is caught', function()
  -- Three cameras in ascending order, but only the first is ever live.
  local doc = { pos = {
    { camera_in = 0 }, { camera_in = 0.4 }, { camera_in = 0.8 },
  } }
  local found = findingsFor(nil, doc)
  eq(mentions(found, 'camera 2 starts at 0.40000 and is never selected'), true,
    table.concat(found, ' | '))
  eq(mentions(found, 'camera 3 starts at 0.80000 and is never selected'), true,
    table.concat(found, ' | '))
end)

test('a camera another one shadows is not blamed', function()
  -- Two cameras starting at the same position: the walk can only ever reach
  -- the later one. That is the file's doing and CamTool 2 does the same, so it
  -- is not reported. One of the reference files is built this way.
  local doc = { pos = { { camera_in = 0 }, { camera_in = 0 } } }
  local found = findingsFor(function(rows)
    -- The later camera is the one the walk reaches.
    for i = 1, #rows do rows[i].activeCam = 2 end
  end, doc)
  eq(mentions(found, 'never selected'), false, table.concat(found, ' | '))
end)

test('a pit camera that never fires is not blamed', function()
  -- Selecting pit cameras is not built yet; see the pit camera chantier.
  local doc = { pos = { { camera_in = 0 }, { camera_in = 0.5, camera_pit = true } } }
  eq(#findingsFor(nil, doc), 0)
end)
