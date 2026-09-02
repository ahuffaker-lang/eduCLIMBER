#!/usr/bin/env python3
"""Generate the app icon: Resources/AppIcon.png and Resources/AppIcon.icns.

    python3 scripts/make_icon.py

The artwork is drawn here rather than stored as a binary blob, so it can be
tweaked in one place and regenerated. Requires Pillow (pip install pillow); the
generated files are committed, so a normal build does not need it.
"""

from __future__ import annotations

import os
import struct

from PIL import Image, ImageDraw

SIZE = 1024
SCALE = 4  # draw large, downsample once -- cheap anti-aliasing
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BLUE_TOP = (59, 130, 246)
BLUE_BOTTOM = (29, 78, 216)
PAPER = (255, 255, 255)
RULE = (203, 213, 225)
RULE_HEAD = (96, 165, 250)
STEP = (251, 191, 36)
STEP_TOP = (253, 224, 71)


def draw_icon() -> Image.Image:
    side = SIZE * SCALE
    image = Image.new("RGBA", (side, side), (0, 0, 0, 0))

    # Vertical gradient, clipped to the rounded-square app shape.
    gradient = Image.new("RGBA", (side, side))
    pixels = gradient.load()
    for y in range(side):
        ratio = y / (side - 1)
        colour = tuple(
            round(BLUE_TOP[channel] + (BLUE_BOTTOM[channel] - BLUE_TOP[channel]) * ratio)
            for channel in range(3)
        )
        for x in range(side):
            pixels[x, y] = colour + (255,)

    mask = Image.new("L", (side, side), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, side - 1, side - 1], radius=round(0.225 * side), fill=255)
    image.paste(gradient, (0, 0), mask)

    draw = ImageDraw.Draw(image)

    def box(x0, y0, x1, y1):
        return [x0 * SCALE, y0 * SCALE, x1 * SCALE, y1 * SCALE]

    # The record: a sheet with ruled lines. Content is inset evenly on both
    # sides so the icon sits centred in the Dock rather than leaning right.
    draw.rounded_rectangle(box(120, 200, 500, 825), radius=26 * SCALE, fill=PAPER)
    draw.rounded_rectangle(box(172, 278, 360, 313), radius=18 * SCALE, fill=RULE_HEAD)
    for top in (395, 485, 575, 665):
        draw.rounded_rectangle(
            box(172, top, 448, top + 34), radius=17 * SCALE, fill=RULE)

    # The climb: reading levels rising to the right.
    draw.rounded_rectangle(box(540, 615, 648, 825), radius=24 * SCALE, fill=STEP)
    draw.rounded_rectangle(box(668, 470, 776, 825), radius=24 * SCALE, fill=STEP)
    draw.rounded_rectangle(box(796, 325, 904, 825), radius=24 * SCALE, fill=STEP_TOP)

    return image.resize((SIZE, SIZE), Image.LANCZOS)


# icns member types by pixel size. The PNG-based types are what modern macOS
# reads; each entry is 4-byte type + 4-byte length (header included) + payload.
ICNS_TYPES = [
    ("icp4", 16), ("icp5", 32), ("ic11", 32), ("ic12", 64), ("ic07", 128),
    ("ic13", 256), ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024),
]


def build_icns(master: Image.Image, path: str) -> None:
    import io

    chunks = b""
    for kind, size in ICNS_TYPES:
        buffer = io.BytesIO()
        master.resize((size, size), Image.LANCZOS).save(buffer, format="PNG")
        payload = buffer.getvalue()
        chunks += kind.encode("ascii") + struct.pack(">I", len(payload) + 8) + payload
    with open(path, "wb") as handle:
        handle.write(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def main() -> None:
    icon = draw_icon()
    png_path = os.path.join(ROOT, "Resources", "AppIcon.png")
    icns_path = os.path.join(ROOT, "Resources", "AppIcon.icns")
    icon.save(png_path)
    build_icns(icon, icns_path)
    print(f"wrote {png_path}")
    print(f"wrote {icns_path} ({os.path.getsize(icns_path):,} bytes)")


if __name__ == "__main__":
    main()
