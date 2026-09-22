--[[
  Take a window out of a manifest, in place.

      luajit tools/strip_window.lua <manifest path> <window id>

  Run by the release workflow to drop the diagnostic probes from what people
  download. Everything it knows is in core/manifest, which is pure and tested;
  this is the shell that reads and writes the file.

  IT FAILS IF IT FINDS NOTHING. A window that has been renamed would otherwise
  leave the release shipping the panel it was told to remove, and nobody looks
  at a manifest inside a zip.
]]

package.path = './?.lua;' .. package.path

local manifest = require('core/manifest')

local path, id = ...

if path == nil or id == nil then
  io.stderr:write('usage: luajit tools/strip_window.lua <manifest> <id>\n')
  os.exit(2)
end

local file = io.open(path, 'rb')
if file == nil then
  io.stderr:write('cannot read ' .. path .. '\n')
  os.exit(2)
end
local text = file:read('*a')
file:close()

local stripped, removed = manifest.withoutWindow(text, id)

if not removed then
  io.stderr:write(string.format(
    'no [WINDOW_...] with ID = %s in %s -- renamed, or already gone\n',
    id, path))
  os.exit(1)
end

-- 'wb', so the CRLF the file came with is the CRLF it goes back with rather
-- than being doubled.
local out = assert(io.open(path, 'wb'))
out:write(stripped)
out:close()

print(string.format('removed window %s from %s', id, path))
