#!/usr/bin/env python3
"""tools/icons/sheet.py :: contact sheets to browse icons (docs/APP.md "Icons").
sheet.py OUT_PREFIX FILE_OR_GLOB... [--cols 10] [--per 60]
Writes OUT_PREFIX_1.png, OUT_PREFIX_2.png, ... (96px thumbnails with their file names) and
prints the sheet paths. Read the sheets as images to look at the icons."""
import sys, glob, os
from PIL import Image, ImageDraw
args = sys.argv[1:]
cols, per = 10, 60
if "--cols" in args: i = args.index("--cols"); cols = int(args[i + 1]); del args[i:i + 2]
if "--per" in args: i = args.index("--per"); per = int(args[i + 1]); del args[i:i + 2]
out, pats = args[0], args[1:]
files = []
for p in pats:
	files += sorted(glob.glob(p)) if any(c in p for c in "*?[") else [p]
files = [f for f in files if f.lower().endswith(".png") and ":" not in os.path.basename(f)]
T, LH = 96, 26
for n in range(0, len(files), per):
	chunk = files[n:n + per]
	rows = (len(chunk) + cols - 1) // cols
	img = Image.new("RGB", (cols * (T + 8), rows * (T + LH)), (205, 200, 190))
	d = ImageDraw.Draw(img)
	for i, f in enumerate(chunk):
		x, y = (i % cols) * (T + 8) + 4, (i // cols) * (T + LH)
		try:
			im = Image.open(f).convert("RGBA").resize((T, T))
			img.paste(im, (x, y + 2), im)
		except Exception as e:
			d.text((x, y + 40), "ERR", fill="red")
		name = os.path.splitext(os.path.basename(f))[0]
		d.text((x, y + T + 3), name[:17], fill="black")
		if len(name) > 17: d.text((x, y + T + 13), name[17:34], fill="black")
	path = f"{out}_{n // per + 1}.png"
	img.save(path)
	print(path)
