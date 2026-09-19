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

---The three columns.
---
---Saturated only in the header: over a game image, twenty-one vivid blocks
---tire the eye fast, and the colour only has to say which column you are in.
---The pills keep a light cast of the same hue, enough to group them.
theme.columns = {
  camera = {
    title = 'CAMERA',
    accent = rgbm(0.55, 0.32, 0.72, 1),
    pill = rgbm(0.28, 0.24, 0.32, 1),
    pillHover = rgbm(0.36, 0.30, 0.42, 1),
  },
  transform = {
    title = 'TRANSFORM',
    accent = rgbm(0.32, 0.66, 0.36, 1),
    pill = rgbm(0.23, 0.29, 0.24, 1),
    pillHover = rgbm(0.30, 0.38, 0.31, 1),
  },
  tracking = {
    title = 'TRACKING',
    accent = rgbm(0.80, 0.58, 0.25, 1),
    pill = rgbm(0.32, 0.28, 0.22, 1),
    pillHover = rgbm(0.42, 0.36, 0.28, 1),
  },
}

---The keyframe marker, in its three states.
---
---Empty: this camera never animates the parameter. Hollow: it does, but not
---on the keyframe you have selected. Filled: it does, here. That is the
---convention of every animation tool, and it says out loud what CamTool 2
---only hinted at by turning a value red -- which left nobody sure whether
---red meant "keyframed" or "in use".
theme.diamondEmpty = rgbm(0.38, 0.38, 0.38, 1)
theme.diamondHollow = rgbm(0.85, 0.55, 0.30, 1)
theme.diamondFilled = rgbm(0.85, 0.16, 0.20, 1)

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

---The map of the track.
---
---The two greys alternate from one camera to the next so that neighbours can
---be told apart without reading a number. The camera being edited and the one
---the car has made live keep the strip's colours, because they mean the same
---thing in both places and learning them twice would be silly.
theme.mapBackground = rgbm(0.14, 0.14, 0.14, 1)
theme.mapTrack = rgbm(0.46, 0.46, 0.46, 1)
theme.mapTrackAlt = rgbm(0.34, 0.34, 0.34, 1)
---The car, on top of everything else.
theme.mapPlayhead = rgbm(1, 1, 1, 1)
---Where the lap starts and ends.
theme.mapStartLine = rgbm(0.70, 0.70, 0.70, 1)

---How tall the map sits in the panel, and how thick the track is drawn.
---
---A RANGE rather than a height. A band the full width of the panel and a
---fixed 150 px tall wastes four fifths of itself on a circuit that is taller
---than it is wide, which is most of them: the height binds, and the track is
---drawn small in the middle of a lot of nothing. The widget takes the height
---the track's shape asks for and stops at the ceiling, so the map is as big
---as the panel can afford and no taller.
theme.mapHeightMin = 120
theme.mapHeightMax = 300
---And never more than this share of the window, whatever its shape asks for.
---A map worth having in a window dragged out wide, and not two thirds of the
---default panel.
theme.mapShareOfWindow = 0.35
---Kept for anything still asking for one height.
theme.mapHeight = 150
theme.mapPadding = 8
theme.mapThickness = 3
---How close a click has to land to count as hitting the track, in pixels.
---Generous on purpose: the line is three pixels wide and nobody hits three
---pixels.
theme.mapClickRadius = 14

---Measurements, in pixels at the panel's default scale.
-- Tall enough that a line of text sits comfortably in the middle of it.
-- At 19 and 15 the glyphs rode high in their boxes, which reads as sloppy
-- long before anyone can say why.
theme.rowHeight = 22
theme.labelHeight = 17
---The buttons of the session bar. Same height as a value row: at 18 the text
---rode high in them, which is the one thing that still looked untidy once the
---rows below were fixed.
theme.barHeight = 22
---The numbered cells of the two strips. They were 16, which is shorter than
---a line of text needs and left the digits sitting high in their boxes.
theme.stripHeight = 20
theme.arrowWidth = 16
theme.gap = 4
theme.padding = 6
theme.columnGap = 5

---Rounding used on every pill, so one change moves them all.
theme.rounding = 2

return theme
