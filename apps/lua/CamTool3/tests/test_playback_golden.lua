--[[
  Characterisation of the whole playback chain over a lap.

  This is the golden master CLAUDE.md asks for before refactoring an area: it
  does not claim the numbers are right, it claims they must not change by
  accident. Every other test here checks one function; this one drives the real
  app, over a real camera file, for a whole lap, and compares what it asks of
  the camera frame by frame.

  It is also the closest thing to what used to need Assetto Corsa: the failures
  it is here to catch -- a camera that stops moving, an aim that flips, a FOV
  that stays put -- are the ones that were previously found by watching.

  When it fails after an intended change of behaviour, regenerate with
  tools/gen_playback_golden.lua and say in the commit message what changed and
  why. When it fails after a refactoring, the refactoring is wrong.
]]

local runner = require('tests/runner')
local lap = require('tests/lap')
local golden = require('tests/fixtures/playback_golden')

local test, near, eq = runner.test, runner.near, runner.eq

-- Positions are metres and angles are unit-vector components, so one part in a
-- billion is far below anything a real change of behaviour would produce, and
-- far above the noise of reassociating a sum.
local EPSILON = 1e-9

for _, scenario in ipairs(golden.scenarios) do
  test('the lap matches the golden: ' .. scenario.name, function()
    local result = lap.run({
      cameraFile = require(scenario.fixture),
      frames = golden.frames,
      checkboxes = scenario.checkboxes,
    })
    result.handle.restoreIo()

    eq(#result.frames, golden.frames)

    for _, row in ipairs(scenario.rows) do
      local frame = row[1]
      local actual = result.frames[frame]
      if actual == nil then
        error('frame ' .. frame .. ' was never run', 2)
      end

      for i, field in ipairs(golden.fields) do
        near(actual[field], row[i + 1], EPSILON,
          string.format('%s, frame %d, %s', scenario.name, frame, field))
      end
    end
  end)
end

test('the lap keeps every number finite', function()
  -- Lua returns inf for a division by zero instead of raising, so a camera that
  -- would have thrown in Python drives the view to infinity here instead. That
  -- is the portability trap CLAUDE.md names, and this is the sweep that would
  -- find it: a whole lap of a real file, every value the camera is given.
  for _, scenario in ipairs(golden.scenarios) do
    local result = lap.run({
      cameraFile = require(scenario.fixture),
      frames = golden.frames,
      checkboxes = scenario.checkboxes,
    })
    result.handle.restoreIo()

    for _, row in ipairs(result.frames) do
      for _, field in ipairs(lap.FIELDS) do
        local value = row[field]
        if type(value) ~= 'number' or value ~= value
            or value == math.huge or value == -math.huge then
          error(string.format('%s, frame %d: %s is %s',
            scenario.name, row.frame, field, tostring(value)), 2)
        end
      end
    end
  end
end)
