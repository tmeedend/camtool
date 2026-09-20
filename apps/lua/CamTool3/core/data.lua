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

local fov = require('core/fov')

local data = {}

data.CURRENT_VERSION = 2

---Reproduce the legacy curve maths, quirks and all. What every CamTool 2 file
---is loaded as.
data.MODE_LEGACY = 'legacy'

---Corrected curve maths. Only for cameras authored in CamTool 3.
---
---A DEFINED SET, not "everything the legacy got wrong". It covers exactly
---two: the last camera ignoring its keyframes (#23) and the tracking buffer
---primed from the world origin (#16). The two quirks of the curve solver --
---SolveCubic returning nothing on an exact double root, and
---SolveQuadratic(0, 0, c) handing back the constant -- are reproduced in BOTH
---modes, deliberately and by Théo's decision. See docs/etat.md.
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

---Version 2: every camera gets an identity of its own.
---
---Until now a camera was known by its place in the list, and that place moves.
---The list is sorted by camera_in, so adding a camera between the fifth and
---the sixth renumbers everything after it: what was camera 14 becomes 15, and
---so does every note, every mental landmark and every bug report that said
---"camera 14".
---
---CamTool 2 looks like it solved this -- every camera carries a `slot` -- but
---sort_cameras does `slot = i` on every sort (classes/data.py:455). It is a
---cached rank, not an identity. So this is the first stable handle the tool
---has had.
---
---`id` is for the program: it never changes, never repeats, and survives a
---sort, a rename and a save. `name` is for the user and is optional; a file
---where nobody named anything is perfectly normal. Both are additive, so a
---camera missing them is not a broken camera, it is one from before.
local function migrateFromV1(doc)
  local next_ = 1

  -- Whatever ids are already there are kept, so a file half-migrated by some
  -- future路 mistake cannot end up with two cameras sharing one.
  for _, listName in ipairs(CAMERA_LISTS) do
    local list = doc[listName]
    if type(list) == 'table' then
      for i = 1, #list do
        local id = list[i].id
        if type(id) == 'number' and id >= next_ then next_ = id + 1 end
      end
    end
  end

  for _, listName in ipairs(CAMERA_LISTS) do
    local list = doc[listName]
    if type(list) == 'table' then
      for i = 1, #list do
        if type(list[i].id) ~= 'number' then
          list[i].id = next_
          next_ = next_ + 1
        end
      end
    end
  end

  -- The counter lives on the document rather than being worked out from the
  -- highest id in use. Deleting the last camera and adding another would
  -- otherwise hand the new one the id the deleted one had, and anything
  -- pointing at the old one would quietly follow the new.
  doc.next_camera_id = math.max(next_, doc.next_camera_id or 1)
  doc.version = 2

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
    return migrateFromV1(migrateFromV0(raw))
  end

  if version == 1 then
    local doc = deepCopy(raw)
    -- A version 1 file with no mode recorded was written by CamTool 3, so it
    -- gets the corrected maths.
    if doc.interpolation_mode == nil then
      doc.interpolation_mode = data.MODE_FIXED
    end
    return migrateFromV1(doc)
  end

  if version == data.CURRENT_VERSION then
    local doc = deepCopy(raw)
    if doc.interpolation_mode == nil then
      doc.interpolation_mode = data.MODE_FIXED
    end
    -- Ids are not optional at version 2, so a file that says 2 and has none
    -- is repaired rather than trusted.
    return migrateFromV1(doc)
  end

  -- Refuse loudly rather than guess. A file from a newer build may use fields
  -- this one would silently drop on the next save.
  error(string.format(
    'unsupported camera file version %s; this build reads up to %d',
    tostring(version), data.CURRENT_VERSION), 2)
end

---Take the next camera id from a document, and move the counter on.
---
---The document owns the counter; nothing works it out from the cameras in
---hand. See migrateFromV1 for why.
---@param doc table|nil
---@return number
function data.claimCameraId(doc)
  if type(doc) ~= 'table' then return 1 end
  local id = doc.next_camera_id
  if type(id) ~= 'number' or id < 1 then id = 1 end
  doc.next_camera_id = id + 1
  return id
end

---What to call a camera on screen.
---
---The name when it has one, its rank when it does not. The rank is the number
---users already know, and it stays the fallback rather than being replaced:
---it is what a hotkey reaches for and what two people say to each other about
---a bug. The name is what survives a camera being inserted ahead of it.
---@param camera table|nil
---@param index number @its place in the list, 1-based
---@return string
function data.cameraLabel(camera, index)
  if type(camera) == 'table' and type(camera.name) == 'string'
      and camera.name ~= '' then
    return camera.name
  end
  return tostring(index)
end

---Is a flag from a camera file on?
---
---Needed because CamTool 2 writes some of its flags as numbers rather than
---booleans -- camera_use_tracking_point is 0 or 1 across all 589 reference
---cameras, 24 of them 0 -- and Lua calls 0 true where Python calls it false.
---Reading such a flag with a plain `if` turns every camera's autofocus on.
---Same family as the division by zero CLAUDE.md warns about: Python semantics
---that do not survive the crossing.
---
---camera_pit is a real boolean in every reference file and works either way.
---@param value any
---@return boolean
function data.isOn(value)
  if value == nil or value == false then return false end
  if value == 0 then return false end
  return true
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
