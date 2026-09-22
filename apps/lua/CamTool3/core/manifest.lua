--[[
  Taking a window out of an app manifest -- pure text, no ac/CSP dependency.

  WHAT THIS IS FOR. CamTool 3 has two windows: the ATR panel, and the
  diagnostic probes. The probes are how a camera problem gets pinned down
  without guessing, and they are developer surface -- Théo wants them while
  working from the repository and not in what people download. They cannot
  become an app of their own: CSP would let two scripts talk through
  ac.connect, but the probes' whole value is reading the app's own locals at
  the moment they are computed, and a wall between them turns a debug panel
  into a protocol to debug.

  So the release build takes the window out of the manifest on its way into
  the zip, beside where it already stamps the version. The Lua stays; nothing
  declares a window onto it.

  WHY A TESTED FUNCTION AND NOT A LINE OF sed. An INI section has no end
  marker -- it runs until the next one -- so cutting one out is a small piece
  of parsing, and small pieces of parsing done in a regular expression inside
  a YAML file are how a release quietly ships the wrong thing. This can be
  read, and it is checked.

  WHERE A COMMENT BELONGS. Above a section header, not below the previous
  one. That is how anybody writes an INI and it is how this manifest is
  written, so a block runs from its own comments down to the comments of the
  next -- otherwise removing the probes would take the paragraph explaining
  the ATR panel with them.
]]

local manifest = {}

---Trim, and drop the carriage return of a CRLF file.
local function bare(line)
  return (line:gsub('[\r\n]+$', ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function isHeader(line)
  return bare(line):match('^%[.*%]$') ~= nil
end

local function isComment(line)
  local text = bare(line)
  return text:sub(1, 1) == ';' or text:sub(1, 1) == '#'
end

---Split keeping every line ending exactly as it was, so a CRLF file stays a
---CRLF file. Assetto Corsa reads either, but a diff that rewrites every line
---of a file hides the one line that changed.
local function lines(text)
  local out = {}
  for line in text:gmatch('[^\n]*\n?') do
    if line ~= '' then out[#out + 1] = line end
  end
  return out
end

---Remove the `[WINDOW_...]` block whose ID is `id`.
---
---Says whether it found one. The caller is a release build, and a window that
---has been renamed must stop the build rather than ship what it was meant to
---take out.
---@param text string @the whole manifest
---@param id string @the ID line to look for, e.g. 'main'
---@return string text, boolean removed
function manifest.withoutWindow(text, id)
  if type(text) ~= 'string' or type(id) ~= 'string' or id == '' then
    return text, false
  end

  local all = lines(text)

  -- Where each section begins, counting the run of comments above its header
  -- as part of it.
  local starts = {}
  for i = 1, #all do
    if isHeader(all[i]) then
      local from = i
      while from > 1 and isComment(all[from - 1]) do from = from - 1 end
      starts[#starts + 1] = { header = i, from = from }
    end
  end

  for index = 1, #starts do
    local section = starts[index]
    local header = bare(all[section.header]):upper()

    if header:match('^%[WINDOW') then
      -- A section ends where the next one begins, comments and all.
      local last = starts[index + 1] ~= nil and (starts[index + 1].from - 1)
        or #all

      local matches = false
      for i = section.header + 1, last do
        local key, value = bare(all[i]):match('^([%w_]+)%s*=%s*(.-)$')
        if key ~= nil and key:upper() == 'ID' and value == id then
          matches = true
          break
        end
      end

      if matches then
        local kept = {}
        for i = 1, #all do
          if i < section.from or i > last then kept[#kept + 1] = all[i] end
        end
        return table.concat(kept), true
      end
    end
  end

  return text, false
end

return manifest
