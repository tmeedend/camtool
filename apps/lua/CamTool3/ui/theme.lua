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
---
---`pillAnimated` is the field of a parameter this camera animates. A step up
---from `pill`, no more: it has to be findable when you sweep the column and
---invisible when you are not looking for it. The diamond still says where the
---keyframe is; the tint only says the parameter moves at all.
theme.columns = {
  camera = {
    title = 'CAMERA',
    accent = rgbm(0.55, 0.32, 0.72, 1),
    pill = rgbm(0.28, 0.24, 0.32, 1),
    pillAnimated = rgbm(0.35, 0.28, 0.42, 1),
    pillHover = rgbm(0.36, 0.30, 0.42, 1),
  },
  transform = {
    title = 'TRANSFORM',
    accent = rgbm(0.32, 0.66, 0.36, 1),
    pill = rgbm(0.23, 0.29, 0.24, 1),
    pillAnimated = rgbm(0.26, 0.36, 0.28, 1),
    pillHover = rgbm(0.30, 0.38, 0.31, 1),
  },
  tracking = {
    title = 'TRACKING',
    accent = rgbm(0.80, 0.58, 0.25, 1),
    pill = rgbm(0.32, 0.28, 0.22, 1),
    pillAnimated = rgbm(0.42, 0.33, 0.24, 1),
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
---The ring under the pointer: which camera a click would take.
theme.mapHover = rgbm(1, 1, 1, 0.75)

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

---The help layer.
---
---THERE ARE NO TOOLTIPS, so there is no delay to tune. Théo had them taken
---out: a bubble appears over the panel you are working in and covers the row
---under the pointer and its neighbours, which are the things you are looking
---at while you drag a value. The sentences all survive, in the status line.
---
---The status line at the bottom: always there, so the panel can be learned
---without knowing there is anything to hover.
theme.statusLine = rgbm(0.70, 0.70, 0.70, 1)

---The track band: one lap as a ribbon.
---
---Short on purpose. It is a reading, not a picture, and every pixel it takes
---is one the parameters do not get. The ribbon sits at the bottom of it and
---the keyframes above, so the two never overlap.
---The ribbon is tall enough to write in: a segment carries the camera's name,
---or its number, and ten pixels cannot hold either. The keyframes sit above
---it, so the two never overlap.
theme.bandHeight = 34
theme.bandRibbon = 18
theme.bandKeyframeY = 7
theme.bandDiamond = 4
---Room left either side of a label inside its segment, so text never touches
---the edge of its own colour.
theme.bandLabelPadding = 3
---Room a label needs beyond its own width before it is drawn without an
---ellipsis. Asking only whether the text fits exactly gets it drawn as "..."
---instead: the ellipsis wants room of its own.
theme.bandLabelSlack = 6

---A label needs this much of a segment before it is worth drawing at all.
---Below it the segment stays blank unless it is the one being pointed at.
theme.bandLabelMin = 14
---Text on a segment. Dark on the pale tints, light on the dark ones, and the
---ribbon has both.
theme.bandLabel = rgbm(1, 1, 1, 0.92)
---The hand-over from one camera to the next. Dark rather than bright: it has
---to be countable without competing with the names written beside it.
theme.bandTick = rgbm(0.09, 0.09, 0.09, 1)

---The ruler across the top of the ribbon.
---
---A THIN STRIP WITH ITS OWN BACKGROUND, and the background is the part that
---matters: it is what makes two zones out of one ribbon without a word of
---explanation. Above the line you move the playhead, below it you pick a
---camera, and nobody has to be told which is which.
---
---Sixteen pixels rather than the ten the brief asked for. A line of text in
---this panel is thirteen, and a ruler you cannot write a distance on is a row
---of marks that measure nothing.
theme.bandRulerHeight = 16
---How far the small unlabelled marks rise from the bottom of the strip. The
---labelled ones cross the whole of it.
theme.bandRulerMinorTick = 4
---Room between a labelled mark and the text that belongs to it.
theme.bandRulerLabelGap = 3

theme.bandRulerBackground = rgbm(0.21, 0.21, 0.21, 1)
---Behind a stretch the track itself has a name for. A tint, not an outline:
---the names are the point, and a box round each one would be louder than
---what is in it.
theme.bandRulerSection = rgbm(0.28, 0.28, 0.30, 1)
theme.bandRulerTick = rgbm(0.62, 0.62, 0.62, 1)
theme.bandRulerLabel = rgbm(0.78, 0.78, 0.78, 1)
theme.bandRulerName = rgbm(0.92, 0.92, 0.92, 1)

---Half the width of the playhead's grip, the triangle in the ruler. Five
---pixels each way is a target a pointer finds without aiming, which a line
---the width of the playhead itself is not.
theme.bandPlayheadGrip = 5

---The rename field is never narrower than this, however thin the segment.
theme.bandRenameWidth = 150
---A diamond is four pixels across and nobody hits four pixels.
theme.bandClickRadius = 7

---Rounding used on every pill, so one change moves them all.
theme.rounding = 2

return theme
