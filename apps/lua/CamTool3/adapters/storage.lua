--[[
  Storage adapter -- the only place that touches the filesystem.

  Everything under core/ takes parsed tables, which is what lets it be tested
  out of game. This module is the boundary: it lists and reads files, parses
  JSON, and hands core/data.lua a plain table.

  Read only, by design: nothing here writes a camera file.
]]

local data = require('core/data')

local storage = {}

-- The current directory for an AC script is the AC root, so this is where
-- CamTool 2 keeps its camera files. Read only: these are users' own files.
storage.CAMTOOL2_DATA_DIR = 'apps/python/CamTool_2/data'

---File name prefix for the track being driven, the same one CamTool 2 builds:
---`<track folder>_<layout folder>-`. Tracks with no layout give a trailing
---underscore, which is why real files look like `le_lancone_-lancia.json`.
---@return string
function storage.trackPrefix()
  return ac.getTrackID() .. '_' .. ac.getTrackLayout() .. '-'
end

---List the CamTool 2 camera files, sorted by name.
---@param allTracks boolean|nil @true lists every track's files, not just this one
---@return string[] files, string prefix @file names without the directory
function storage.listCameraFiles(allTracks)
  local found = io.scanDir(storage.CAMTOOL2_DATA_DIR, '*.json')
  local prefix = storage.trackPrefix()
  if type(found) ~= 'table' then return {}, prefix end

  local files = {}
  for i = 1, #found do
    local name = found[i]
    -- CamTool 2 keeps its settings next to the camera files; it is not one.
    if name ~= 'settings.json' then
      -- Match CamTool 2, which only offers the current track's files. With 32
      -- files across a dozen tracks, listing them all is just scrolling.
      if allTracks or name:sub(1, #prefix) == prefix then
        files[#files + 1] = name
      end
    end
  end

  table.sort(files)
  return files, prefix
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
