--[[
  Camera file names -- pure logic, no ac/CSP dependency.

  A camera file on disk is called `spa_-theo.json`. Three things are stuck
  together in that: the track it belongs to, the name somebody chose, and the
  format it is written in. Only the middle one is theirs.

  WHY THIS MATTERS RATHER THAN BEING TIDY. The panel used to show the whole
  string and hand the whole string to the field that renames it. So the track
  prefix and the extension were sitting there, editable, in a box whose job is
  to take a name -- and deleting either one produces a file the app will never
  offer again on this track, or one its own loader skips. The user is given a
  machine's business to look after, and the only thing they can do with it is
  get it wrong.

  So: the panel deals in the name, this file deals in the rest. `display`
  takes it apart, `build` puts it back together, and `build` assumes whoever
  typed into it may have typed anything at all -- including the prefix and the
  extension they had seen there a moment before.
]]

local filename = {}

---What the file is called, as far as anyone using it is concerned.
---@param name string @the file on disk, e.g. `spa_-theo.json`
---@param prefix string @this track's prefix, e.g. `spa_-`
---@return string @e.g. `theo`
function filename.display(name, prefix)
  if type(name) ~= 'string' then return '' end

  local out = name
  if type(prefix) == 'string' and prefix ~= ''
      and out:sub(1, #prefix) == prefix then
    out = out:sub(#prefix + 1)
  end

  -- Only at the end, and only once: a set called `notes.json backup` keeps
  -- its middle.
  if out:lower():sub(-5) == '.json' then out = out:sub(1, -6) end

  return out
end

---Characters Windows will not have in a file name, plus the ones that would
---make a name reach outside its folder. A camera file lives in one place.
local FORBIDDEN = '[\\/:%*%?"<>|%c]'

---The file a typed name should be written to.
---
---Everything about this is defensive, because the field it comes from accepts
---anything. Spaces are trimmed; characters no file name may hold are dropped
---rather than refused, so a stray slash costs nothing; a prefix and an
---extension the user typed anyway are taken back off, so `spa_-theo.json`
---typed in full is the same file as `theo`, not `spa_-spa_-theo.json.json`;
---and a name that is nothing once cleaned is refused outright rather than
---written as a file called `.json`.
---
---Trailing dots and spaces go too. Windows silently strips them when it
---creates a file, which means asking for `theo.` gets you a file called
---`theo` that the app then cannot find under the name it thinks it wrote.
---@param typed string @whatever was in the field
---@param prefix string @this track's prefix
---@return string|nil name @the file to write, prefix and extension included
---@return string|nil why @when there is no usable name in what was typed
function filename.build(typed, prefix)
  if type(typed) ~= 'string' then return nil, 'a file needs a name' end
  prefix = type(prefix) == 'string' and prefix or ''

  local name = typed:gsub(FORBIDDEN, '')

  -- Repeatedly, and in this order: someone who pastes the whole file name
  -- back in has typed a prefix AND an extension, and taking one off can leave
  -- the other newly at the end.
  local changed = true
  while changed do
    changed = false

    local trimmed = name:gsub('^%s+', ''):gsub('[%s%.]+$', '')
    if trimmed ~= name then name, changed = trimmed, true end

    if name:lower():sub(-5) == '.json' then
      name, changed = name:sub(1, -6), true
    end

    if prefix ~= '' and name:sub(1, #prefix) == prefix then
      name, changed = name:sub(#prefix + 1), true
    end
  end

  if name == '' then return nil, 'a file needs a name' end

  return prefix .. name .. '.json'
end

return filename
