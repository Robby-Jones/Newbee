#!/usr/bin/env python3
"""Adds a caption and a gradient background to an App Store screenshot.

Usage: caption-screenshots.py INPUT.png "Caption text" OUTPUT.png

The output is 1206 x 2622 (App Store Connect's "iPhone with Dynamic Island (medium display)"
size). The screenshot is scaled down, given rounded corners and placed under the caption. Any
iPhone screenshot works as input. Needs Pillow and a bold font (FONT env var, or Inter / the
macOS system font if found).
"""
import os
import sys
import textwrap

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1206, 2622
TOP, BOTTOM = (124, 92, 214), (64, 186, 190)  # the app icon's purple and teal
FONTS = [
    os.environ.get("FONT", ""),
    "/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf",
    "/System/Library/Fonts/SFNSRounded.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def font(size):
    for path in FONTS:
        if path and os.path.exists(path):
            return ImageFont.truetype(path, size)
    sys.exit("No font found. Set FONT to a .ttf or .otf file.")


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    source, caption, destination = sys.argv[1:]

    canvas = Image.new("RGB", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(canvas)
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        draw.line([(0, y), (WIDTH, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))

    lines = textwrap.wrap(caption, width=20)
    face = font(92)
    y = 150
    for line in lines:
        width = draw.textlength(line, font=face)
        draw.text(((WIDTH - width) / 2, y), line, font=face, fill="white")
        y += 112

    shot = Image.open(source).convert("RGB")
    top = y + 70
    shot_width = 980
    shot_height = round(shot.height * shot_width / shot.width)
    shot = shot.resize((shot_width, shot_height), Image.LANCZOS)
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot_width, shot_height], radius=90, fill=255)
    left = (WIDTH - shot_width) // 2
    # A soft border so light screenshots stand out from the background.
    draw.rounded_rectangle([left - 10, top - 10, left + shot_width + 10, top + shot_height + 10], radius=100, fill=(255, 255, 255))
    canvas.paste(shot, (left, top), mask)
    canvas.save(destination)


if __name__ == "__main__":
    main()
