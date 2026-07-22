#!/usr/bin/env python3
"""fontconv.py -- BDF to CXF, the CXRF font format.

    python tools/fontconv.py fonts/pxl8.bdf fonts/pxl8.cxf
    python tools/fontconv.py --selftest

CXF is specified in docs/formats.md. In short: a 16-byte header, one
advance-width byte per glyph, then `height` bitmap rows per glyph with
the leftmost pixel in bit 7. Glyph `i` lives at `bitmaps + i*height`,
which is why glyph ink cannot exceed 8 pixels -- the advance may be
narrower, and that is what makes the font proportional.

Only the mechanical part of BDF is read: the encoding, the advance, the
bounding box and the bitmap. BDF is a big format and CXRF wants none
of the rest of it.

The one subtlety is vertical placement. A BDF glyph's bitmap is not
positioned by its top edge but by its bounding box, whose origin sits
`BBX yoff` rows above the baseline. This walks each glyph's rows down
into a fixed `height`-row cell using the font's own ascent, so a
descender lands below the baseline instead of at the top of the cell.
Getting that backwards is silent: the text still draws, one row off.
"""
import argparse
import re
import sys

MAGIC = b"CXF1"
HEADER = 16
MAX_INK = 8             # a glyph row is one byte


class BdfError(Exception):
    pass


def parse_bdf(text):
    """-> (height, ascent, {code: (width, [rows])}) with rows top-first."""
    ascent = descent = None
    glyphs = {}

    code = width = None
    bbx = None
    bitmap = None

    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        parts = line.split()
        key = parts[0].upper()

        if bitmap is not None:
            if key == "ENDCHAR":
                if code is None or width is None or bbx is None:
                    raise BdfError("glyph %r is missing ENCODING/DWIDTH/BBX"
                                   % code)
                glyphs[code] = (width, bbx, bitmap)
                code = width = bbx = bitmap = None
            else:
                # A BDF bitmap row is hex, padded right to a byte
                # multiple; bit 7 of the first byte is the leftmost pixel,
                # so the first byte alone covers our 8-pixel ceiling.
                bitmap.append(int(line[:2], 16))
            continue

        if key == "FONT_ASCENT":
            ascent = int(parts[1])
        elif key == "FONT_DESCENT":
            descent = int(parts[1])
        elif key == "ENCODING":
            code = int(parts[1])
        elif key == "DWIDTH":
            width = int(parts[1])
        elif key == "BBX":
            bbx = (int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]))
        elif key == "BITMAP":
            bitmap = []

    if ascent is None or descent is None:
        raise BdfError("FONT_ASCENT/FONT_DESCENT missing")
    if not glyphs:
        raise BdfError("no glyphs")
    return ascent + descent, ascent, glyphs


def place(height, ascent, bbx, bitmap):
    """Walk a BDF glyph's rows into a height-row cell, top-first.

    BBX is (w, h, xoff, yoff): the box's bottom edge sits yoff rows above
    the baseline, and the baseline is `ascent` rows down from the cell's
    top. So the box's top row lands at ascent - (yoff + h).
    """
    bw, bh, xoff, yoff = bbx
    cell = [0] * height
    top = ascent - (yoff + bh)
    for i, row in enumerate(bitmap[:bh]):
        r = top + i
        if 0 <= r < height:
            # xoff shifts the box right within the cell; a negative xoff
            # (ink left of the origin) would fall off the byte, so clamp
            # rather than wrap it around into the wrong columns.
            cell[r] |= (row >> xoff) & 0xFF if xoff >= 0 else (row << -xoff) & 0xFF
    return cell


def build(text, name, spacing=1, first=None, last=None):
    height, ascent, glyphs = parse_bdf(text)
    if not 1 <= height <= 16:
        raise BdfError("height %d out of range 1-16" % height)

    codes = sorted(glyphs)
    lo = codes[0] if first is None else first
    hi = codes[-1] if last is None else last
    if lo > hi:
        raise BdfError("empty range %d..%d" % (lo, hi))
    if hi > 255 or lo < 0:
        raise BdfError("CXF1 codepoints are one byte: %d..%d" % (lo, hi))
    count = hi - lo + 1
    if count > 255:
        raise BdfError("%d glyphs; CXF1 counts them in a byte" % count)

    blank = (0, (0, 0, 0, 0), [])
    widths, bitmaps = [], []
    for code in range(lo, hi + 1):
        width, bbx, bitmap = glyphs.get(code, blank)
        if width > MAX_INK:
            raise BdfError("U+%04X advances %d; CXF1 allows %d"
                           % (code, width, MAX_INK))
        cell = place(height, ascent, bbx, bitmap)
        widths.append(width)
        bitmaps.extend(cell)

    nm = name.encode("ascii", "replace")[:6]
    out = bytearray(MAGIC)
    out += bytes([height, ascent, lo, count, max(widths), spacing])
    out += nm + b"\0" * (6 - len(nm))
    assert len(out) == HEADER
    out += bytes(widths)
    out += bytes(bitmaps)
    return bytes(out)


# ---------------------------------------------------------------------
# self-tests: the host half of the phase's verification. The on-target
# suite proves the kernel reads what this writes; these prove this wrote
# what the BDF said.
# ---------------------------------------------------------------------
MINI = """STARTFONT 2.1
FONTBOUNDINGBOX 8 8 0 -1
STARTPROPERTIES 2
FONT_ASCENT 7
FONT_DESCENT 1
ENDPROPERTIES
CHARS 3
STARTCHAR sp
ENCODING 32
DWIDTH 3 0
BBX 3 8 0 -1
BITMAP
00
00
00
00
00
00
00
00
ENDCHAR
STARTCHAR bar
ENCODING 33
DWIDTH 2 0
BBX 2 8 0 -1
BITMAP
C0
C0
C0
C0
C0
C0
C0
00
ENDCHAR
STARTCHAR desc
ENCODING 34
DWIDTH 4 0
BBX 4 3 0 -1
BITMAP
F0
90
F0
ENDCHAR
ENDFONT
"""


def selftest():
    fails = []

    def check(cond, what):
        print(("  ok   " if cond else "  FAIL ") + what)
        if not cond:
            fails.append(what)

    f = build(MINI, "mini")
    check(f[:4] == MAGIC, "magic")
    check(f[4] == 8 and f[5] == 7, "height 8, ascent 7")
    check(f[6] == 32 and f[7] == 3, "first 32, count 3")
    check(f[8] == 4, "maxwidth is the widest advance, not the cell")
    check(f[10:16] == b"mini\0\0", "name padded")
    check(len(f) == HEADER + 3 + 3 * 8, "size = header + widths + bitmaps")

    widths = f[HEADER:HEADER + 3]
    check(list(widths) == [3, 2, 4], "widths in code order")

    bm = f[HEADER + 3:]
    check(list(bm[0:8]) == [0] * 8, "space is blank")
    check(list(bm[8:16]) == [0xC0] * 7 + [0x00], "bar keeps its rows")

    # The descender: BBX 4 3 0 -1 puts the box's bottom one row BELOW the
    # baseline, so with ascent 7 its three rows land at cell rows 5,6,7 --
    # not 0,1,2. This is the test that fails if `place` is naive.
    desc = list(bm[16:24])
    check(desc == [0, 0, 0, 0, 0, 0xF0, 0x90, 0xF0], "descender sits on rows 5-7")

    # A glyph missing from the BDF still gets a slot, so indexing stays
    # first + code without a lookup table.
    holey = MINI.replace("ENCODING 33", "ENCODING 40")
    h = build(holey, "holey")
    check(h[7] == 9, "range spans the hole (32..40)")
    check(h[HEADER + 1] == 0, "the hole's advance is 0")

    for bad, why in (
        (MINI.replace("DWIDTH 4 0", "DWIDTH 9 0"), "advance past 8 rejected"),
        (MINI.replace("FONT_ASCENT 7\n", ""), "missing ascent rejected"),
    ):
        try:
            build(bad, "bad")
            check(False, why)
        except BdfError:
            check(True, why)

    print("selftest: %d failed" % len(fails))
    return 1 if fails else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("bdf", nargs="?")
    ap.add_argument("cxf", nargs="?")
    ap.add_argument("--name", default=None, help="font name (default: stem)")
    ap.add_argument("--spacing", type=int, default=1,
                    help="pixels after each glyph (default 1)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        sys.exit(selftest())
    if not args.bdf or not args.cxf:
        ap.error("need BDF and CXF paths (or --selftest)")

    name = args.name or args.cxf.replace("\\", "/").split("/")[-1].split(".")[0]
    with open(args.bdf, encoding="latin-1") as f:
        text = f.read()
    try:
        blob = build(text, name, spacing=args.spacing)
    except BdfError as e:
        sys.exit("%s: %s" % (args.bdf, e))
    with open(args.cxf, "wb") as f:
        f.write(blob)

    count = blob[7]
    print("%s: %d glyphs, height %d, ascent %d, maxwidth %d, %d bytes"
          % (args.cxf, count, blob[4], blob[5], blob[8], len(blob)))


if __name__ == "__main__":
    main()
