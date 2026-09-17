--[[
  FOV storage conversion -- pure logic, no ac/CSP dependency.

  Ported from CamToolTool.convert_fov_2_focal_length (stdlib64/CamToolTool.py).
  CamTool stores camera_fov in a converted form so that it interpolates nicely,
  so every data file users already have is written in that form. This module
  must reproduce the Python semantics exactly, quirks included, or existing
  files would be read back with the wrong field of view.

  Legacy mapping:
    convert_fov_2_focal_length(v)               -> encode(v)
    convert_fov_2_focal_length(v, reverse=true) -> decode(v)
]]

local fov = {}

-- The Python code assigns self.x = 15 as a side effect before using it. The
-- value is what matters; the assignment is noise.
local OFFSET = 15

-- Legacy quirk: zero is answered with this sentinel in BOTH directions, so
-- encode and decode are not inverses at zero. Reproduced on purpose -- do not
-- "fix" it without checking what it does to existing camera files.
local ZERO_RESULT = 0.00001

---Field of view (degrees) -> stored value.
---@param fovDeg number
---@return number
function fov.encode(fovDeg)
  if fovDeg == 0 then return ZERO_RESULT end
  return 1 / (fovDeg + OFFSET)
end

---Stored value -> field of view (degrees).
---@param stored number
---@return number
function fov.decode(stored)
  if stored == 0 then return ZERO_RESULT end
  return (1 - OFFSET * stored) / stored
end

return fov
