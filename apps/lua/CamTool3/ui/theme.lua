--[[
  Colours and measurements for the ATR panel.

  Presentation only: nothing here knows what a camera is. The values come from
  ATR's mockup (apps/python/CamTool_2/atr-new-ui.png, the panel at the top),
  and from the colour code CamTool 2 already uses, which docs/ui-inventory.md
  records: red means a keyframe sits here and the value shown is the
  keyframe's, grey means it is interpolated or comes from the camera.

  The three column colours are not decoration. They are the tabs of CamTool 2
  -- Camera, Transform, Tracking -- laid side by side instead of stacked, so
  someone who knows the old UI can find a parameter without reading labels.
]]

local theme = {}

---Panel background, behind everything.
theme.background = rgbm(0.20, 0.20, 0.20, 1)

---The three columns, and the shade their value pills use.
theme.columns = {
  camera = {
    title = 'CAMERA',
    fill = rgbm(0.36, 0.20, 0.47, 1),
    pill = rgbm(0.45, 0.28, 0.56, 1),
    pillHover = rgbm(0.54, 0.35, 0.66, 1),
  },
  transform = {
    title = 'TRANSFORM',
    fill = rgbm(0.22, 0.45, 0.24, 1),
    pill = rgbm(0.30, 0.55, 0.32, 1),
    pillHover = rgbm(0.38, 0.65, 0.40, 1),
  },
  tracking = {
    title = 'TRACKING',
    fill = rgbm(0.55, 0.39, 0.15, 1),
    pill = rgbm(0.64, 0.47, 0.20, 1),
    pillHover = rgbm(0.74, 0.56, 0.26, 1),
  },
}

---Keyframed at the playhead. The same red CamTool 2 uses, and the same
---meaning, so the habit carries over.
theme.keyframed = rgbm(0.85, 0.16, 0.20, 1)
theme.keyframedHover = rgbm(0.95, 0.26, 0.30, 1)

---Labels above each value.
theme.label = rgbm(0.86, 0.86, 0.86, 1)
---A value that exists but that this camera does not drive.
theme.muted = rgbm(0.60, 0.60, 0.60, 1)
---A parameter with nothing to show at all.
theme.absent = rgbm(0.45, 0.45, 0.45, 1)

theme.text = rgbm(1, 1, 1, 1)
theme.headerBar = rgbm(0.78, 0.09, 0.13, 1)
theme.strip = rgbm(0.28, 0.28, 0.28, 1)
---The keyframe row, a shade apart from the camera row above it so the two
---strips do not read as one.
theme.stripKeyframe = rgbm(0.21, 0.21, 0.21, 1)
theme.stripActive = rgbm(0.85, 0.16, 0.20, 1)
---The camera the car has made live, when it is not the one being edited.
theme.stripLive = rgbm(0.45, 0.22, 0.24, 1)

---Measurements, in pixels at the panel's default scale.
theme.rowHeight = 19
theme.labelHeight = 15
theme.arrowWidth = 16
theme.gap = 4
theme.padding = 6
theme.columnGap = 5

---Rounding used on every pill, so one change moves them all.
theme.rounding = 2

return theme
