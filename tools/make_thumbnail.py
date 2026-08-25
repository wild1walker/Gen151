"""Draw thumbnail.png -- original artwork, no ROM-derived bytes.

The mod index shows a thumbnail next to each entry.  Rather than ship pixels
lifted from anywhere, this draws one: the four-shade DMG green ramp, a tall
grass silhouette, and "151" in a glyph set defined here in full.  A pure-Python
PNG writer keeps it dependency-free, so `tools/regen.sh` can rebuild it on any
checkout.

    python3 tools/make_thumbnail.py [--out thumbnail.png] [--scale 4]
"""

import argparse
import struct
import zlib

# The DMG's four shades, darkest last -- the ramp every Game Boy screen is
# drawn from.
PALETTE = [
    (0x9B, 0xBC, 0x0F),  # 0 lightest
    (0x8B, 0xAC, 0x0F),  # 1
    (0x30, 0x62, 0x30),  # 2
    (0x0F, 0x38, 0x0F),  # 3 darkest
]

# A 5x7 glyph per digit, as index rows.  Defined here in full so the numerals
# owe nothing to any font sheet.
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

# One tuft of tall grass, 8x5, the shape the overworld uses for a grass cell.
GRASS = [
    "..#..#..",
    ".######.",
    "########",
    ".######.",
    "..####..",
]


def blank(w, h, shade=0):
    return [[shade] * w for _ in range(h)]


def stamp(canvas, rows, x, y, shade, edge=None):
    h = len(canvas)
    w = len(canvas[0])
    for dy, line in enumerate(rows):
        for dx, ch in enumerate(line):
            if ch != "#":
                continue
            px, py = x + dx, y + dy
            if 0 <= px < w and 0 <= py < h:
                canvas[py][px] = shade
            if edge is None:
                continue
            for ox, oy in ((1, 0), (0, 1), (1, 1)):
                ex, ey = px + ox, py + oy
                if 0 <= ex < w and 0 <= ey < h and canvas[ey][ex] == 0:
                    canvas[ey][ex] = edge


def draw(size=128):
    # Work at 32x32 and scale up, so every edge lands on a whole pixel the way
    # a tile-based screen's would.
    grid = 32
    canvas = blank(grid, grid, 0)

    # frame
    for i in range(grid):
        canvas[0][i] = 3
        canvas[grid - 1][i] = 3
        canvas[i][0] = 3
        canvas[i][grid - 1] = 3
        canvas[1][i] = canvas[1][i] if i in (0, grid - 1) else 2
        canvas[grid - 2][i] = canvas[grid - 2][i] if i in (0, grid - 1) else 2
    for i in range(1, grid - 1):
        canvas[i][1] = 2
        canvas[i][grid - 2] = 2

    # a band of tall grass across the lower third: what the whole mod is about
    for x in range(3, grid - 3, 8):
        stamp(canvas, GRASS, x, 22, 2)
    for x in range(7, grid - 3, 8):
        stamp(canvas, GRASS, x, 25, 3)

    # "151", centred in the upper half
    text = "151"
    glyph_w = 5
    gap = 2
    total = len(text) * glyph_w + (len(text) - 1) * gap
    x = (grid - total) // 2
    for ch in text:
        stamp(canvas, DIGITS[ch], x, 8, 3, edge=2)
        x += glyph_w + gap

    scale = size // grid
    out = blank(grid * scale, grid * scale, 0)
    for y in range(grid):
        for x in range(grid):
            shade = canvas[y][x]
            for dy in range(scale):
                for dx in range(scale):
                    out[y * scale + dy][x * scale + dx] = shade
    return out


def write_png(path, pixels):
    height = len(pixels)
    width = len(pixels[0])
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
    args = ap.parse_args()
    write_png(args.out, draw(args.size))


if __name__ == "__main__":
    main()
