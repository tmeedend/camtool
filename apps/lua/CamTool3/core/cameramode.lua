--[[
  The Assetto Corsa cameras a CamTool camera can hand the view to.

  camera_use_specific_cam is -1 when CamTool drives, and 0 to 13 when it steps
  aside and lets one of Assetto Corsa's own cameras take over. Eleven of the
  589 reference cameras use it -- on Le Lancone, camera 5 hands over to the
  steering wheel view.

  CamTool 2 could not ask for one of these directly. For the F1 family it
  pressed F1 the right number of times, counting from a remembered offset
  (CamMode.changeCamModeZero), which is why the user had to line the view up
  by hand before starting. CSP does have the calls -- setCurrentDrivableCamera
  and setCurrentCarCamera take the camera they want -- so the counting, and
  the manual sync with it, are gone.

  The numbers below are CamTool 2's, taken from the branch in CamTool_2.py
  that dispatches to CamMode. The names are CamTool 2's too, which matters
  more than it looks: they are the words already in the user's head, and
  "steering wheel" is findable where "AC cam 0" is not.

  Pure: this says what to do, it does not do it. The adapter that talks to
  CSP is the one allowed to call ac.*.
]]

local cameramode = {}

---CamTool drives. Anything below zero means the same thing.
cameramode.CAMTOOL = -1

---@class SpecificCamera
---@field value integer @what the file stores
---@field label string @what to show, in CamTool 2's own words
---@field mode string @which ac.CameraMode to ask for
---@field drivable integer|nil @which ac.DrivableCamera, for the F1 family
---@field carCamera integer|nil @which car camera index, for the F6 family

---@type SpecificCamera[]
cameramode.CAMERAS = {
  { value = 0, label = 'steering wheel', mode = 'Drivable', drivable = 5 },
  { value = 1, label = 'free outside', mode = 'OnBoardFree' },
  { value = 2, label = 'helicopter', mode = 'Helicopter' },
  { value = 3, label = 'roof', mode = 'Car', carCamera = 0 },
  { value = 4, label = 'wheel', mode = 'Car', carCamera = 1 },
  { value = 5, label = 'inside car', mode = 'Car', carCamera = 2 },
  { value = 6, label = 'passenger', mode = 'Car', carCamera = 3 },
  { value = 7, label = 'driver', mode = 'Car', carCamera = 4 },
  { value = 8, label = 'behind', mode = 'Car', carCamera = 5 },
  { value = 9, label = 'chase', mode = 'Drivable', drivable = 0 },
  { value = 10, label = 'chase far', mode = 'Drivable', drivable = 1 },
  { value = 11, label = 'hood', mode = 'Drivable', drivable = 2 },
  { value = 12, label = 'subjective', mode = 'Drivable', drivable = 3 },
  { value = 13, label = 'cockpit', mode = 'Drivable', drivable = 4 },
}

cameramode.MIN = -1
cameramode.MAX = 13

local byValue = {}
for _, entry in ipairs(cameramode.CAMERAS) do byValue[entry.value] = entry end

---@param value integer|nil
---@return SpecificCamera|nil @nil means CamTool drives
function cameramode.find(value)
  if type(value) ~= 'number' then return nil end
  return byValue[value]
end

---What to write in the panel.
---@param value integer|nil
---@return string
function cameramode.label(value)
  local entry = cameramode.find(value)
  if entry == nil then return 'CamTool' end
  return entry.label
end

---Step through the list, wrapping at both ends as CamTool 2 does.
---@param value integer|nil
---@param direction integer
---@return integer
function cameramode.cycle(value, direction)
  if type(value) ~= 'number' then value = cameramode.CAMTOOL end
  local next_ = value + (direction or 1)
  if next_ > cameramode.MAX then next_ = cameramode.MIN end
  if next_ < cameramode.MIN then next_ = cameramode.MAX end
  return next_
end

---Does this camera hand the view to Assetto Corsa?
---@param value integer|nil
---@return boolean
function cameramode.handsOver(value)
  return cameramode.find(value) ~= nil
end

return cameramode
