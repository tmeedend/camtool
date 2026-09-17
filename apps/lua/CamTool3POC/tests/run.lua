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

require('tests/test_fov')
require('tests/test_angles')
require('tests/test_cubic')
require('tests/test_interpolation')
require('tests/test_data')
require('tests/test_evaluate')
require('tests/test_app_smoke')

os.exit(runner.run() and 0 or 1)
