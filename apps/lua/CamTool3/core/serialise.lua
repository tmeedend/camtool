--[[
  Turning a camera document back into JSON text.

  Written by hand rather than handed to CSP's JSON.stringify, for one reason:
  this is the code that writes over files people cannot get back. data/ is not
  in git and some of those camera sets are years old. A serialiser I can run
  in a test, and pin down case by case, is worth more than one I can only
  watch work.

  Three things a naive writer gets wrong on this data, all of them tested:

  An empty camera list has to come out as [] and an empty keyframe as {}. Lua
  spells both {}, so the caller has to say which it meant -- guessing from
  emptiness turns a file with no cameras into one with a broken shape.

  A keyframe carries only the parameters it sets. The rest are absent, not
  null, which is how CamTool 2 writes them too and what makes the files
  readable.

  And numbers have to survive the trip. %.17g is the shortest form that reads
  back as the same double, which matters because a position written short is
  a camera that has quietly moved.
]]

local serialise = {}

---Keys that hold an array, even when empty. Everything else that is empty is
---an object.
local ARRAYS = {
  pos = true, time = true, keyframes = true,
  the_x = true, loc_x = true, loc_y = true, loc_z = true,
  rot_x = true, rot_y = true, rot_z = true,
}

local ESCAPES = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function quote(text)
  local out = text:gsub('[%c"\\]', function(c)
    return ESCAPES[c] or string.format('\\u%04x', c:byte())
  end)
  return '"' .. out .. '"'
end

local function number(value)
  if value ~= value then error('cannot write a NaN to a camera file', 0) end
  if value == math.huge or value == -math.huge then
    error('cannot write an infinity to a camera file', 0)
  end

  -- Integers without a trailing .0, which keeps slots and indices looking
  -- like what CamTool 2 wrote.
  if value == math.floor(value) and math.abs(value) < 1e15 then
    return string.format('%d', value)
  end
  return string.format('%.17g', value)
end

---Is this table an array? Length alone is not enough: an empty one could be
---either, so the key it arrived under decides.
local function isArray(value, key)
  if #value > 0 then return true end
  if next(value) ~= nil then return false end
  return ARRAYS[key] == true
end

local write

---@param value any
---@param key string|nil @the key this value arrived under, for empty tables
---@param indent number
---@param out table
write = function(value, key, indent, out)
  local kind = type(value)

  if value == nil then
    out[#out + 1] = 'null'
  elseif kind == 'boolean' then
    out[#out + 1] = value and 'true' or 'false'
  elseif kind == 'number' then
    out[#out + 1] = number(value)
  elseif kind == 'string' then
    out[#out + 1] = quote(value)
  elseif kind == 'table' then
    local pad = string.rep('  ', indent + 1)
    local closePad = string.rep('  ', indent)

    if isArray(value, key) then
      if #value == 0 then
        out[#out + 1] = '[]'
        return
      end
      out[#out + 1] = '[\n'
      for i = 1, #value do
        out[#out + 1] = pad
        write(value[i], nil, indent + 1, out)
        out[#out + 1] = i < #value and ',\n' or '\n'
      end
      out[#out + 1] = closePad .. ']'
    else
      -- Sorted, so saving the same document twice gives the same bytes and a
      -- diff between two saves shows what actually changed.
      local keys = {}
      for k in pairs(value) do
        if type(k) == 'string' then keys[#keys + 1] = k end
      end
      table.sort(keys)

      if #keys == 0 then
        out[#out + 1] = '{}'
        return
      end
      out[#out + 1] = '{\n'
      for i = 1, #keys do
        out[#out + 1] = pad .. quote(keys[i]) .. ': '
        write(value[keys[i]], keys[i], indent + 1, out)
        out[#out + 1] = i < #keys and ',\n' or '\n'
      end
      out[#out + 1] = closePad .. '}'
    end
  else
    error('cannot write a ' .. kind .. ' to a camera file', 0)
  end
end

---@param document table
---@return string
function serialise.toJson(document)
  if type(document) ~= 'table' then
    error('serialise.toJson expects a table, got ' .. type(document), 2)
  end

  local out = {}
  write(document, nil, 0, out)
  out[#out + 1] = '\n'
  return table.concat(out)
end

return serialise
