"""Draw thumbnail.png -- original artwork, no ROM-derived bytes.

The mod index shows a thumbnail next to each entry.  Nothing here is lifted:
"151" in a glyph set defined in this file, over a field of tall grass built
from one repeated tuft, in a four-shade pink ramp.  A pure-Python PNG writer
keeps it dependency-free so tools/regen.sh can rebuild it on any checkout.

Four shades and hard pixel edges, because that is the grammar the rest of the
screen is drawn in -- but pink rather than the DMG's green, so the tile reads
as this mod's own rather than as a screenshot of the game.

    python3 tools/make_thumbnail.py [--out thumbnail.png] [--size 128]
"""

import argparse
import struct
import zlib

# Four shades, lightest first: the Game Boy's ramp structure in pink.  Spaced
# so any two adjacent shades stay legible against each other at thumbnail
# size, which is the only thing a four-colour ramp has to get right.
PALETTE = [
    (0xFF, 0xD9, 0xEC),  # 0 lightest -- the sky
    (0xF2, 0xA0, 0xC4),  # 1
    (0xB0, 0x4E, 0x84),  # 2
    (0x45, 0x18, 0x36),  # 3 darkest -- the numerals and the near grass
]

SKY = 0
GRASS_FAR = 1
GRASS_MID = 2
GRASS_NEAR = 3
INK = 3
SHADOW = 2

# A 5x7 glyph per digit, as rows.  Defined here in full so the numerals owe
# nothing to any font sheet.
DIGITS = {
    "1": [
        "..#..",
        ".##..",
        "..#..",
        "..#..",
        "..#..",
        "..#..",
        ".###.",
    ],
    "5": [
        "#####",
        "#....",
        "####.",
        "....#",
        "....#",
        "#...#",
        ".###.",
    ],
}

# One tuft of tall grass, 8x5: the shape an overworld grass cell wears.
GRASS = [
    "..#..#..",
    ".######.",
    "########",
    ".######.",
    "..####..",
]

# The field, back to front: (row, x offset, shade).  Staggering the offsets
# keeps the repeated tuft from reading as a checkerboard, and darkening as it
# comes forward is what gives sixty-four pixels any depth at all.
FIELD = (
    (36, -2, GRASS_FAR),
    (40, 3, GRASS_FAR),
    (44, -5, GRASS_MID),
    (48, 1, GRASS_MID),
    (52, -3, GRASS_NEAR),
    (56, 4, GRASS_NEAR),
)

GRID = 64
TEXT = "151"
TEXT_TOP = 15
TEXT_SCALE = 3
GLYPH_GAP = 1


def blank(w, h, shade):
    return [[shade] * w for _ in range(h)]


def stamp(canvas, rows, x, y, shade, shadow=None):
    height, width = len(canvas), len(canvas[0])
    for dy, line in enumerate(rows):
        for dx, ch in enumerate(line):
            if ch != "#":
                continue
            if shadow is not None:
                for ox, oy in ((1, 0), (0, 1), (1, 1)):
                    px, py = x + dx + ox, y + dy + oy
                    if 0 <= py < height and 0 <= px < width \
                            and canvas[py][px] not in (shade, shadow):
                        canvas[py][px] = shadow
            px, py = x + dx, y + dy
            if 0 <= py < height and 0 <= px < width:
                canvas[py][px] = shade


def scale_glyph(rows, factor):
    out = []
    for line in rows:
        wide = "".join(ch * factor for ch in line)
        for _ in range(factor):
            out.append(wide)
    return out


def draw():
    canvas = blank(GRID, GRID, SKY)

    for row, offset, shade in FIELD:
        for x in range(offset, GRID, len(GRASS[0])):
            stamp(canvas, GRASS, x, row, shade)

    # "151", tripled, above the field.  The drop shadow is one pixel down and
    # right, which is how the game shades its own display numerals.
    glyph_w = len(DIGITS[TEXT[0]][0])
    step = (glyph_w + GLYPH_GAP) * TEXT_SCALE
    total = (len(TEXT) * glyph_w
             + (len(TEXT) - 1) * GLYPH_GAP) * TEXT_SCALE
    x = (GRID - total) // 2
    for ch in TEXT:
        stamp(canvas, scale_glyph(DIGITS[ch], TEXT_SCALE), x, TEXT_TOP, INK,
              shadow=SHADOW)
        x += step

    # frame, drawn last so nothing overlaps it
    for i in range(GRID):
        canvas[0][i] = INK
        canvas[GRID - 1][i] = INK
        canvas[i][0] = INK
        canvas[i][GRID - 1] = INK
    for i in range(1, GRID - 1):
        canvas[1][i] = SHADOW
        canvas[GRID - 2][i] = SHADOW
        canvas[i][1] = SHADOW
        canvas[i][GRID - 2] = SHADOW
    return canvas


def upscale(canvas, size):
    scale = max(1, size // GRID)
    out = blank(GRID * scale, GRID * scale, SKY)
    for y in range(GRID):
        for x in range(GRID):
            shade = canvas[y][x]
            for dy in range(scale):
                for dx in range(scale):
                    out[y * scale + dy][x * scale + dx] = shade
    return out


def write_png(path, pixels):
    height, width = len(pixels), len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter type 0
        for shade in row:
            raw.extend(PALETTE[shade])

    def chunk(tag, payload):
        body = tag + payload
        return (struct.pack(">I", len(payload)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR",
                 struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)
    print("wrote %s (%dx%d)" % (path, width, height))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="thumbnail.png")
    ap.add_argument("--size", type=int, default=128)
    ap.add_argument("--ascii", action="store_true",
                    help="print the grid as text, for tuning the layout")
    args = ap.parse_args()
    canvas = draw()
    if args.ascii:
        for row in canvas:
            print("".join(" .oO"[shade] for shade in row))
    write_png(args.out, upscale(canvas, args.size))


if __name__ == "__main__":
    main()
