--[[
  Storage adapter -- the only place in the POC that touches the filesystem.

  Everything under core/ takes parsed tables, which is what lets it be tested
  out of game. This module is the boundary: it lists and reads files, parses
  JSON, and hands core/data.lua a plain table.

  Read only, by design. The POC never writes a camera file.
]]

local data = require('core/data')

local storage = {}

-- The current directory for an AC script is the AC root, so this is where
-- CamTool 2 keeps its camera files. Read only: these are users' own files.
storage.CAMTOOL2_DATA_DIR = 'apps/python/CamTool_2/data'

---List the CamTool 2 camera files, newest name order.
---@return string[] @file names, without the directory
function storage.listCameraFiles()
  local found = io.scanDir(storage.CAMTOOL2_DATA_DIR, '*.json')
  if type(found) ~= 'table' then return {} end

  local files = {}
  for i = 1, #found do
    -- CamTool 2 keeps its settings next to the camera files; it is not one.
    if found[i] ~= 'settings.json' then
      files[#files + 1] = found[i]
    end
  end

  table.sort(files)
  return files
end

---Read and migrate one camera file.
---Returns nil plus a message rather than raising, so the UI can show the
---problem instead of the app falling over mid-frame.
---@param fileName string
---@return table|nil document, string|nil error
function storage.loadCameraFile(fileName)
  local path = storage.CAMTOOL2_DATA_DIR .. '/' .. fileName

  local text = io.load(path)
  if text == nil then
    return nil, 'could not read ' .. path
  end

  -- JSON.parse does not raise on damaged input, it just returns something
  -- unpredictable, so the result has to be checked rather than trusted.
  local parsed = JSON.parse(text)
  if type(parsed) ~= 'table' then
    return nil, 'not valid JSON: ' .. fileName
  end
  if type(parsed.pos) ~= 'table' and type(parsed.time) ~= 'table' then
    return nil, 'no camera lists in ' .. fileName
  end

  local ok, result = pcall(data.load, parsed)
  if not ok then
    return nil, 'migration failed: ' .. tostring(result)
  end

  return result, nil
end

return storage
