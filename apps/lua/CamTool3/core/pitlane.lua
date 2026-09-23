--[[
  Is the car in the pit lane? Pure logic, no ac/CSP dependency.

  Ported from Data.update_custom_car_info. CamTool 2 answers the question two
  ways, and which one depends on the camera file:

  1. The file carries a recorded track spline AND a recorded pit spline. The
     car is in the pit lane when it is closer, on the ground plane, to the pit
     spline than to the track spline, both read at the car's track position.
     This is what decides on every reference file that has pit cameras.
  2. Otherwise, the game's own flag: ac.isCarInPitline, car.isInPitlane in CSP.

  The pit spline is recorded across the start line, so its positions run past
  1 (0.886 to 1.097 on the Red Bull Ring file). The legacy reads it at
  trackPos + 1 below half a lap to line up with that; the track spline, which
  covers the whole lap, is read cyclically instead.
]]

local interpolation = require('core/interpolation')

local pitlane = {}

---Has this spline been recorded, at least as far as the ground plane goes?
---The legacy only checks the_x; a spline with positions and no values would
---raise there and keep last frame's answer. Refusing it up front is the same
---answer without the exception.
local function recorded(spline)
  return type(spline) == 'table'
    and type(spline.the_x) == 'table' and #spline.the_x > 0
    and type(spline.loc_x) == 'table' and #spline.loc_x > 0
    and type(spline.loc_y) == 'table' and #spline.loc_y > 0
end

---Does this document decide the pit lane from its own splines?
---@param doc table|nil
---@return boolean
function pitlane.usesSplines(doc)
  return doc ~= nil and recorded(doc.track_spline) and recorded(doc.pit_spline)
end

---Is the car in the pit lane?
---@param doc table|nil @a migrated camera document
---@param trackPos number|nil @the car's normalised track position, 0..1
---@param carX number|nil @car world position in CamTool space (Z up)
---@param carY number|nil
---@param gameSays boolean|nil @the game's own flag, used when the file has no splines
---@return boolean
function pitlane.isCarInPitlane(doc, trackPos, carX, carY, gameSays)
  if not pitlane.usesSplines(doc) or trackPos == nil
      or carX == nil or carY == nil then
    return gameSays and true or false
  end

  local track, pit = doc.track_spline, doc.pit_spline

  local trackX = interpolation.interpolate_spline(trackPos, track.the_x, track.loc_x, true)
  local trackY = interpolation.interpolate_spline(trackPos, track.the_x, track.loc_y, true)

  local pitPos = trackPos
  if pitPos < 0.5 then pitPos = pitPos + 1 end
  local pitX = interpolation.interpolate_spline(pitPos, pit.the_x, pit.loc_x)
  local pitY = interpolation.interpolate_spline(pitPos, pit.the_x, pit.loc_y)

  if trackX == nil or trackY == nil or pitX == nil or pitY == nil then
    return gameSays and true or false
  end

  local toTrack = (carX - trackX) ^ 2 + (carY - trackY) ^ 2
  local toPit = (carX - pitX) ^ 2 + (carY - pitY) ^ 2
  return toPit < toTrack
end

return pitlane
