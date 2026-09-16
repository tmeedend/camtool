--[[
  Camera file loading and migration -- pure logic, no ac/CSP dependency.

  Takes an already-parsed table, not a file path or a JSON string: parsing is
  the adapter's job (CSP ships JSON.parse), and keeping it out of here is what
  lets the migration be tested out of game.

  Two axes, deliberately separate:

    version             how values are ENCODED on disk
    interpolation_mode  which curve MATHS applies

  Collapsing them into one field is tempting and wrong. Migrating a CamTool 2
  file to the new encoding must not also switch it to the corrected curves,
  because that would silently change footage people have already cut. So a
  migrated file is version 1 and still says interpolation_mode = 'legacy'; only
  cameras authored in CamTool 3 get 'fixed'. The mode is carried through saves.

  See the legacy quirk register in CLAUDE.md for what 'legacy' actually means.
]]

local fov = require('core.fov')

local data = {}

data.CURRENT_VERSION = 1

---Reproduce the legacy curve maths, quirks and all. What every CamTool 2 file
---is loaded as.
data.MODE_LEGACY = 'legacy'

---Corrected curve maths. Only for cameras authored in CamTool 3.
data.MODE_FIXED = 'fixed'

-- The two camera lists at the top of every file, one per camera mode.
local CAMERA_LISTS = { 'time', 'pos' }

local function deepCopy(value)
  if type(value) ~= 'table' then return value end
  local copy = {}
  for k, v in pairs(value) do
    copy[k] = deepCopy(v)
  end
  return copy
end

---Walk every keyframe in a document, calling fn(interpolationTable).
local function forEachKeyframe(doc, fn)
  for listIndex = 1, #CAMERA_LISTS do
    local list = doc[CAMERA_LISTS[listIndex]]
    if type(list) == 'table' then
      for c = 1, #list do
        local keyframes = type(list[c]) == 'table' and list[c].keyframes or nil
        if type(keyframes) == 'table' then
          for k = 1, #keyframes do
            local interp = type(keyframes[k]) == 'table' and keyframes[k].interpolation or nil
            if type(interp) == 'table' then fn(interp) end
          end
        end
      end
    end
  end
end

---Schema version of a parsed document. CamTool 2 wrote no version field, so
---anything without one is version 0.
---@param raw table
---@return number
function data.versionOf(raw)
  local version = raw.version
  if type(version) ~= 'number' then return 0 end
  return version
end

---CamTool 2 -> version 1.
---
---The only encoded field is camera_fov, stored as 1/(fov+15). Checked against
---all 32 of the reference camera files: 1768 values, every one decoding to
---between 0.5 and 55.4 degrees, none zero or negative. camera_focus_point
---looked like a candidate but holds plain metres (0.07 to 358), so it passes
---through unchanged.
---
---Everything else is already in honest units -- radians for angles, 0..1 for
---track positions -- and is copied unchanged.
local function migrateFromV0(raw)
  local doc = deepCopy(raw)

  forEachKeyframe(doc, function(interp)
    if type(interp.camera_fov) == 'number' then
      interp.camera_fov = fov.decode(interp.camera_fov)
    end
  end)

  doc.version = 1
  -- Encoding is modernised; the maths is not. See the note at the top.
  doc.interpolation_mode = data.MODE_LEGACY

  return doc
end

---Load a parsed camera document, migrating it if it predates version 1.
---Never mutates the input.
---@param raw table @already parsed from JSON
---@return table @a version 1 document
function data.load(raw)
  if type(raw) ~= 'table' then
    error('data.load expects a parsed table, got ' .. type(raw), 2)
  end

  local version = data.versionOf(raw)

  if version == 0 then
    return migrateFromV0(raw)
  end

  if version == data.CURRENT_VERSION then
    local doc = deepCopy(raw)
    -- A version 1 file with no mode recorded was written by CamTool 3, so it
    -- gets the corrected maths.
    if doc.interpolation_mode == nil then
      doc.interpolation_mode = data.MODE_FIXED
    end
    return doc
  end

  -- Refuse loudly rather than guess. A file from a newer build may use fields
  -- this one would silently drop on the next save.
  error(string.format(
    'unsupported camera file version %s; this build reads up to %d',
    tostring(version), data.CURRENT_VERSION), 2)
end

---Count the cameras in a document, across both modes.
---@param doc table
---@return number
function data.cameraCount(doc)
  local total = 0
  for listIndex = 1, #CAMERA_LISTS do
    local list = doc[CAMERA_LISTS[listIndex]]
    if type(list) == 'table' then total = total + #list end
  end
  return total
end

return data
