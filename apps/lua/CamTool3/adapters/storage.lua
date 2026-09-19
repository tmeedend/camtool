--[[
  Storage adapter -- the only place that touches the filesystem.

  Everything under core/ takes parsed tables, which is what lets it be tested
  out of game. This module is the boundary: it lists and reads files, parses
  JSON, and hands core/data.lua a plain table.

  It writes, too, and that is the part to be careful about: data/ is not in
  git and some of those camera sets are years old. See saveCameraFile for
  what stands between a bug here and a lost afternoon.
]]

local data = require('core/data')
local serialise = require('core/serialise')

local storage = {}

-- The current directory for an AC script is the AC root.
--
-- Two folders, and the split is the whole point. CamTool 2's is READ ONLY:
-- those are the user's own files, they are not in git, and some are years
-- old. CamTool 3 writes only into its own, so a save can never damage one of
-- them and CamTool 2 never sees a file it cannot read -- it lists *.json in
-- its own folder, and a version 1 document would make its loader throw,
-- which it swallows and shows as nothing at all.
--
-- Opening a CamTool 2 file and saving it therefore makes a copy here rather
-- than changing the original. That is the intended path from one to the
-- other, and it is one way, as docs/legacy.md already says of the format.
storage.CAMTOOL2_DATA_DIR = 'apps/python/CamTool_2/data'
storage.CAMTOOL3_DATA_DIR = 'apps/lua/CamTool3/data'

---File name prefix for the track being driven, the same one CamTool 2 builds:
---`<track folder>_<layout folder>-`. Tracks with no layout give a trailing
---underscore, which is why real files look like `le_lancone_-lancia.json`.
---@return string
function storage.trackPrefix()
  return ac.getTrackID() .. '_' .. ac.getTrackLayout() .. '-'
end

---@class CameraFileEntry
---@field name string @the file name, no directory
---@field dir string @which folder it is in
---@field own boolean @true for CamTool 3's own, false for a CamTool 2 file

---List the camera files of both folders, CamTool 3's first.
---@param allTracks boolean|nil @true lists every track's files, not just this one
---@return CameraFileEntry[] files, string prefix
function storage.listCameraFiles(allTracks)
  local prefix = storage.trackPrefix()
  local files = {}

  local function gather(dir, own)
    local found = io.scanDir(dir, '*.json')
    if type(found) ~= 'table' then return end

    local names = {}
    for i = 1, #found do
      local name = found[i]
      -- CamTool 2 keeps its settings next to the camera files; not one.
      if name ~= 'settings.json' then
        -- Match CamTool 2, which only offers the current track's files. With
        -- 32 files across a dozen tracks, listing them all is just scrolling.
        if allTracks or name:sub(1, #prefix) == prefix then
          names[#names + 1] = name
        end
      end
    end

    table.sort(names)
    for i = 1, #names do
      files[#files + 1] = { name = names[i], dir = dir, own = own }
    end
  end

  -- Ours first: once a file has been saved here, that copy is the one being
  -- worked on and the CamTool 2 original is only history.
  gather(storage.CAMTOOL3_DATA_DIR, true)
  gather(storage.CAMTOOL2_DATA_DIR, false)

  return files, prefix
end

---Read and migrate one camera file.
---Returns nil plus a message rather than raising, so the UI can show the
---problem instead of the app falling over mid-frame.
---@param entry CameraFileEntry|string @an entry, or a CamTool 2 file name
---@return table|nil document, string|nil error
function storage.loadCameraFile(entry)
  local fileName = type(entry) == 'table' and entry.name or entry
  local dir = type(entry) == 'table' and entry.dir or storage.CAMTOOL2_DATA_DIR
  local path = dir .. '/' .. fileName

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

---Suffix for the copy kept of a file the first time it is overwritten.
---Not .json, so it never shows up in the file list.
storage.BACKUP_SUFFIX = '.camtool3-backup'

---Write a camera document back out.
---
---Three things guard it, because these files cannot be got back:
---
---The text is built and checked before anything is opened. serialise.toJson
---refuses an infinity or a NaN -- which Lua produces from a division by zero
---where Python would have raised -- so a bad number stops the save instead
---of writing a file no parser will read.
---
---io.save with ensure writes to a temporary file and moves it into place, so
---a crash halfway cannot leave a half-written camera set behind.
---
---And the first time one of our own files is overwritten, it is copied
---aside. Once only: the point is to keep what was there before, not the
---state before the last save.
---
---Always into CamTool 3's folder, whichever folder the document came from. A
---CamTool 2 file opened here is never written back to: saving copies it
---across instead, so the original stays exactly as CamTool 2 left it.
---@param fileName string @as listCameraFiles gives it
---@param document table
---@return boolean ok, string|nil error
function storage.saveCameraFile(fileName, document)
  if type(fileName) ~= 'string' or fileName == '' then
    return false, 'no file name'
  end
  if type(document) ~= 'table' then
    return false, 'nothing to save'
  end

  if not io.exists(storage.CAMTOOL3_DATA_DIR) then
    io.createDir(storage.CAMTOOL3_DATA_DIR)
  end

  local path = storage.CAMTOOL3_DATA_DIR .. '/' .. fileName

  local ok, text = pcall(serialise.toJson, document)
  if not ok then
    return false, 'refusing to save: ' .. tostring(text)
  end

  if io.exists(path) then
    local backup = path .. storage.BACKUP_SUFFIX
    if not io.exists(backup) then
      -- Best effort: a failed backup is worth a warning, not a refusal to
      -- save work the user has just done.
      io.copyFile(path, backup, false)
    end
  end

  if not io.save(path, text, true) then
    return false, 'could not write ' .. path
  end

  return true, nil
end

return storage
