--[[
  Settings adapter -- what CamTool 3 remembers from one session to the next.

  CamTool 2 kept a settings.json beside its camera files. CSP offers the same
  thing without a file of ours: ac.storage, which it writes itself into the
  user's Documents a few seconds after a change. So nothing here opens a file,
  and a crash half way through a write cannot leave a broken settings file
  behind -- there is no file to break.

  Values are strings, numbers or booleans. A build without ac.storage keeps
  them for the session only, which is what a missing settings.json gave in
  CamTool 2.
]]

local settings = {}

---What a build without ac.storage keeps, for the session only.
local session = {}

---A wrapper for one key. Asked for each time rather than kept: settings are
---read on a load or a click, never per frame, and a kept wrapper would
---outlive the storage it came from.
---@param key string
---@param default string|number|boolean
---
---ac.storage is a TABLE that can be called, not a function -- the SDK
---declares it as both -- so its presence is tested and pcall decides.
local function wrapper(key, default)
  if type(ac) ~= 'table' or ac.storage == nil then return nil end
  local ok, value = pcall(ac.storage, 'camtool3.' .. key, default)
  if ok and value ~= nil then return value end
  return nil
end

---@param key string
---@param default string|number|boolean
function settings.get(key, default)
  local w = wrapper(key, default)
  if w ~= nil then
    local ok, value = pcall(w.get, w)
    if ok and value ~= nil then return value end
    return default
  end
  if session[key] ~= nil then return session[key] end
  return default
end

---@param key string
---@param value string|number|boolean
function settings.set(key, value)
  local w = wrapper(key, value)
  if w ~= nil then
    pcall(w.set, w, value)
    return
  end
  session[key] = value
end

---Forget the wrappers. For tests only.
function settings.reset()
  session = {}
end

---Whether to open the last file of a track when the app first sees it.
---CamTool 2's load_last_used_data, on by default there too.
function settings.loadOnStartup()
  return settings.get('loadOnStartup', true) == true
end

---The file last opened on a track, remembered per track as CamTool 2 did.
---@param prefix string @storage.trackPrefix()
---@return string|nil @'own:<name>' or 'camtool2:<name>'
function settings.lastFile(prefix)
  local value = settings.get('lastFile.' .. prefix, '')
  if type(value) ~= 'string' or value == '' then return nil end
  return value
end

---@param prefix string
---@param entry table @a CameraFileEntry
function settings.setLastFile(prefix, entry)
  if type(entry) ~= 'table' or type(entry.name) ~= 'string' then return end
  settings.set('lastFile.' .. prefix, (entry.own and 'own:' or 'camtool2:') .. entry.name)
end

---Which entry of a file list a remembered value names, or nil.
---@param files table[] @CameraFileEntry list
---@param remembered string|nil
---@return number|nil
function settings.findFile(files, remembered)
  if type(remembered) ~= 'string' then return nil end
  local kind, name = remembered:match('^(%w+):(.+)$')
  if kind == nil then return nil end
  local own = kind == 'own'
  for i = 1, #files do
    if files[i].name == name and (files[i].own == true) == own then return i end
  end
  return nil
end

return settings
