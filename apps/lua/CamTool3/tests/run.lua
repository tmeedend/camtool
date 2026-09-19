--[[
  Test entry point. Run from the app folder:

    luajit tests/run.lua

  Exits non-zero when anything fails, so it can gate a commit later.

  Test files are listed explicitly rather than scanned from disk: directory
  listing needs a C module (lfs), and the whole point of this setup is to stay
  at zero dependencies. Add new files to the list below.
]]

package.path = './?.lua;' .. package.path

local runner = require('tests/runner')

-- Before anything else: CSP defines rgbm, vec2 and vec3 ahead of any app
-- code, and modules call them while loading.
require('tests/fakes/csp').installGlobals()

require('tests/test_fov')
require('tests/test_angles')
require('tests/test_cubic')
require('tests/test_interpolation')
require('tests/test_data')
require('tests/test_evaluate')
require('tests/test_tracking')
require('tests/test_spline')
require('tests/test_trackmap')
require('tests/test_shake')
require('tests/test_focus')
require('tests/test_app_smoke')
require('tests/test_playback_golden')
require('tests/test_lap_sweep')
require('tests/test_trace_replay')
require('tests/test_ui_atr')
require('tests/test_edit')
require('tests/test_serialise')

os.exit(runner.run() and 0 or 1)
