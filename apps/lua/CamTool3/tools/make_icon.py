"""Draw the CamTool 3 icon.

    python tools/make_icon.py        (needs Pillow, on the desktop Python)

A generator rather than a hand-drawn PNG, for the reason every binary asset in
a repository eventually proves: an icon nobody can reopen is an icon nobody
can change. The palette and the shapes are written down here, so a future
version is a digit and a re-run.

THE DESIGN IS NOT ORIGINAL, DELIBERATELY. CamTool 2 already has an icon --
a white movie camera on a red disc inside a white ring, with a small 2 cut out
of its body -- and people find it in a list of thirty apps by its colour. The
point of a successor's icon is to be recognised before it is read, so this is
the same disc, the same ring, the same camera, and a 3.

The palette is not invented either: it is sampled from
content/gui/icons/CamTool_2_ON.png, which is #BE0202 on pure white.

Drawn at 256 and reduced, because a circle rasterised straight to the final
size has a staircase for an edge.
"""
import glob
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_PATH = os.path.join(HERE, '..', 'icon.png')

S = 256          # the size it is drawn at
OUT = 64         # the size it is saved at

# CamTool 2's own red and white, sampled from its icon.
RED = (190, 2, 2, 255)
WHITE = (255, 255, 255, 255)
NOTHING = (0, 0, 0, 0)

CX = CY = 128
R = 122          # the disc, including its ring
RING = 13        # the white ring CamTool 2 draws round its disc
SCALE = 0.82     # the glyph sits inside that ring, as CamTool 2's does


def font(size):
    """A bold face, whichever of them this machine has."""
    for name in ('arialbd.ttf', 'segoeuib.ttf', 'calibrib.ttf', 'arial.ttf'):
        found = glob.glob('C:/Windows/Fonts/' + name)
        if found:
            return ImageFont.truetype(found[0], size)
    for path in ('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def at(x, y):
    """A point of the drawing, scaled about the centre of the icon."""
    return (CX + (x - CX) * SCALE, CY + (y - CY) * SCALE)


def box(x1, y1, x2, y2):
    a, b = at(x1, y1), at(x2, y2)
    return (a[0], a[1], b[0], b[1])


def draw_icon():
    im = Image.new('RGBA', (S, S), NOTHING)
    d = ImageDraw.Draw(im)

    # The ring, then the fill inside it. Drawing the inner circle second is
    # what makes the ring: it erases what it covers rather than blending.
    d.ellipse((CX - R, CY - R, CX + R, CY + R), fill=WHITE)
    d.ellipse((CX - R + RING, CY - R + RING, CX + R - RING, CY + R - RING),
              fill=RED)

    # Reels. The left one is the smaller, as on CamTool 2.
    d.ellipse(box(60, 60, 124, 124), fill=WHITE)
    d.ellipse(box(120, 46, 200, 126), fill=WHITE)

    # Body.
    d.rounded_rectangle(box(52, 120, 176, 200), radius=12 * SCALE, fill=WHITE)

    # Lens, pointing right.
    d.polygon([at(176, 140), at(216, 118), at(216, 202), at(176, 180)],
              fill=WHITE)

    # The number, CUT OUT of the body rather than written on top of it, so it
    # reads as part of the camera. Same treatment as the 2.
    f = font(int(58 * SCALE))
    bb = d.textbbox((0, 0), '3', font=f)
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    cx, cy = at(114, 160)
    d.text((cx - w / 2 - bb[0], cy - h / 2 - bb[1]), '3', font=f, fill=RED)

    return im


if __name__ == '__main__':
    icon = draw_icon().resize((OUT, OUT), Image.LANCZOS)
    icon.save(OUT_PATH)
    print('wrote %s at %dx%d' % (os.path.normpath(OUT_PATH), OUT, OUT))
