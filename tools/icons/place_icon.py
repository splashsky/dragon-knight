#!/usr/bin/env python3
"""tools/icons/place_icon.py :: puts an icon into the game (docs/APP.md "Icons").
place_icon.py SRC DEST [--size N] [--hue DEG] [--sat F] [--bright F] [--tint #rrggbb:STRENGTH] [--flip]
SRC: a PNG from the icon packs (Icons/, not in the repository; standard art, not "nobg").
DEST: the game's file, e.g. public/images/items/hi_potion.png (relative to the repository
root, or absolute). Record it in docs/icon-sources.tsv. Needs Pillow and numpy. The
icon is resized to N x N (default 96; monsters 128), optionally recoloured (for variants):
--hue rotates the hue by DEG degrees (-180..180), --sat multiplies saturation (0.0 grey ..
2.0), --bright multiplies brightness, --tint blends toward a colour (STRENGTH 0..1), --flip
mirrors it. Transparency is kept. Saved as an optimized PNG."""
import sys, os
import numpy as np
from PIL import Image, ImageEnhance, ImageOps
a = sys.argv[1:]
def opt(name, conv, default=None):
	if name in a:
		i = a.index(name); v = a[i + 1]; del a[i:i + 2]; return conv(v)
	return default
size = opt("--size", int, 96); hue = opt("--hue", float, 0.0); sat = opt("--sat", float, 1.0)
bright = opt("--bright", float, 1.0); tint = opt("--tint", str); flip = "--flip" in a
if flip: a.remove("--flip")
src, dest = a[0], a[1]
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if not os.path.isabs(dest): dest = os.path.join(ROOT, dest)
im = Image.open(src).convert("RGBA")
alpha = im.getchannel("A")
rgb = im.convert("RGB")
if hue:
	hsv = np.array(rgb.convert("HSV")).astype(np.int16)
	hsv[..., 0] = (hsv[..., 0] + int(round(hue / 360 * 255))) % 256
	rgb = Image.fromarray(hsv.astype(np.uint8), "HSV").convert("RGB")
if sat != 1.0: rgb = ImageEnhance.Color(rgb).enhance(sat)
if bright != 1.0: rgb = ImageEnhance.Brightness(rgb).enhance(bright)
if tint:
	col, _, strength = tint.partition(":")
	c = tuple(int(col.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
	rgb = Image.blend(rgb, Image.new("RGB", rgb.size, c), float(strength or 0.3))
out = rgb.convert("RGBA"); out.putalpha(alpha)
if flip: out = ImageOps.mirror(out)
out = out.resize((size, size), Image.LANCZOS)
os.makedirs(os.path.dirname(dest), exist_ok=True)
out.save(dest, optimize=True)
print(dest, os.path.getsize(dest), "bytes")
