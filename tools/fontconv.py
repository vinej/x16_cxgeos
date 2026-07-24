#!/usr/bin/env python3
"""fontconv.py -- BDF or raw X16 charset to CXF, the CXRF font format.

    python tools/fontconv.py fonts/pxl8.bdf fonts/pxl8.cxf
    python tools/fontconv.py --x16-charset font/LIGHTFONT.BIN fonts/light.cxf
    python tools/fontconv.py --selftest

CXF is specified in docs/formats.md. In short: a 16-byte header, one
advance-width byte per glyph, then `height` bitmap rows per glyph with
the leftmost pixel in bit 7. Glyph `i` lives at `bitmaps + i*height`,
which is why glyph ink cannot exceed 8 pixels -- the advance may be
narrower, and that is what makes the font proportional.

Only the mechanical part of BDF is read: the encoding, the advance, the
bounding box and the bitmap. BDF is a big format and CXRF wants none
of the rest of it.

The X16 charset path reads the common 8x8, 1bpp tile font format: 256
glyphs, 8 bytes each, often with a two-byte PRG load address at the
front. Those fonts are usually in C64/X16 screen-code order (@, A-Z,
punctuation, digits...), not ASCII order, so the converter remaps the
printable ASCII range into CXRF's codepoint slots. Lowercase folds to
uppercase because these downloaded PETSCII-style fonts normally do not
carry a second mixed-case alphabet in ASCII order.

The one subtlety is vertical placement. A BDF glyph's bitmap is not
positioned by its top edge but by its bounding box, whose origin sits
`BBX yoff` rows above the baseline. This walks each glyph's rows down
into a fixed `height`-row cell using the font's own ascent, so a
descender lands below the baseline instead of at the top of the cell.
Getting that backwards is silent: the text still draws, one row off.
"""
import argparse
import os
import re
import sys
import tempfile

MAGIC = b"CXF1"
HEADER = 16
MAX_INK = 8             # a glyph row is one byte
ASCII_FIRST = 0x20
ASCII_LAST = 0x7E
X16_CELL_H = 8
X16_ASCENT = 7
X16_SPACE_WIDTH = 3


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


def pack_cxf(height, ascent, first, widths, bitmaps, name, spacing):
    if not 1 <= height <= 16:
        raise BdfError("height %d out of range 1-16" % height)
    count = len(widths)
    if count > 255:
        raise BdfError("%d glyphs; CXF1 counts them in a byte" % count)
    if any(w > MAX_INK for w in widths):
        raise BdfError("CXF1 allows advances up to %d" % MAX_INK)

    nm = name.encode("ascii", "replace")[:6]
    out = bytearray(MAGIC)
    out += bytes([height, ascent, first, count, max(widths), spacing])
    out += nm + b"\0" * (6 - len(nm))
    assert len(out) == HEADER
    out += bytes(widths)
    out += bytes(bitmaps)
    return bytes(out)


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

    return pack_cxf(height, ascent, lo, widths, bitmaps, name, spacing)


def read_x16_charset(path):
    """Read 256 8x8 1bpp glyphs, skipping an optional two-byte load word."""
    with open(path, "rb") as f:
        blob = f.read()
    if len(blob) == 2 + 256 * X16_CELL_H:
        blob = blob[2:]
    if len(blob) != 256 * X16_CELL_H:
        raise BdfError("%s is %d bytes; need 2048 bytes of 1bpp 8x8 glyphs"
                       % (path, len(blob)))
    return [blob[i:i + X16_CELL_H] for i in range(0, len(blob), X16_CELL_H)]


def screen_code_for_ascii(code):
    """C64/X16 display-code order for the printable ASCII range."""
    if 0x40 <= code <= 0x5F:
        return code - 0x40      # @, A-Z, [, \, ], ^, _
    if 0x60 <= code <= 0x7E:
        return code - 0x60      # fold lowercase/punctuation to the first set
    return code                 # space through ?


def trim_cell(cell, space_width=X16_SPACE_WIDTH):
    ink = [c for c in range(MAX_INK)
           if any(row >> (MAX_INK - 1 - c) & 1 for row in cell)]
    if not ink:
        return [0] * X16_CELL_H, space_width
    left, right = ink[0], ink[-1]
    return [(row << left) & 0xFF for row in cell], right - left + 1


def build_x16_charset(path, name, spacing=1, first=ASCII_FIRST, last=ASCII_LAST,
                      layout="screen", space_width=X16_SPACE_WIDTH):
    if first < 0 or last > 255 or first > last:
        raise BdfError("bad output range %d..%d" % (first, last))
    cells = read_x16_charset(path)
    widths, bitmaps = [], []
    for code in range(first, last + 1):
        src = code if layout == "ascii" else screen_code_for_ascii(code)
        rows, width = trim_cell(cells[src], space_width)
        widths.append(width)
        bitmaps.extend(rows)
    return pack_cxf(X16_CELL_H, X16_ASCENT, first, widths, bitmaps, name, spacing)


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

    raw = bytearray(256 * X16_CELL_H)
    raw[1 * 8:1 * 8 + 8] = bytes([0x60, 0x90, 0xF0, 0x90, 0x90, 0, 0, 0])
    raw[33 * 8:33 * 8 + 8] = bytes([0x80, 0x80, 0x80, 0, 0x80, 0, 0, 0])
    fd, p = tempfile.mkstemp()
    try:
        os.write(fd, b"\0\0" + raw)
        os.close(fd)
        fd = -1
        x = build_x16_charset(p, "raw")
        xw = x[HEADER:HEADER + (ASCII_LAST - ASCII_FIRST + 1)]
        xb = x[HEADER + len(xw):]
        aoff = (ord("A") - ASCII_FIRST) * X16_CELL_H
        loff = (ord("a") - ASCII_FIRST) * X16_CELL_H
        check(xw[ord("A") - ASCII_FIRST] == 4, "raw charset maps A from screen code 1")
        check(list(xb[aoff:aoff + 3]) == [0x60, 0x90, 0xF0], "raw charset keeps A bitmap")
        check(list(xb[loff:loff + 3]) == [0x60, 0x90, 0xF0], "raw charset folds lowercase")
    finally:
        if fd != -1:
            os.close(fd)
        try:
            os.remove(p)
        except OSError:
            pass

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
    ap.add_argument("--x16-charset", action="store_true",
                    help="input is a raw 256-glyph X16/C64 8x8 charset")
    ap.add_argument("--raw-layout", choices=("screen", "ascii"), default="screen",
                    help="raw charset glyph order (default: screen)")
    ap.add_argument("--space-width", type=int, default=X16_SPACE_WIDTH,
                    help="advance for blank raw glyphs (default 3)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        sys.exit(selftest())
    if not args.bdf or not args.cxf:
        ap.error("need BDF and CXF paths (or --selftest)")

    name = args.name or args.cxf.replace("\\", "/").split("/")[-1].split(".")[0]
    try:
        if args.x16_charset:
            blob = build_x16_charset(args.bdf, name, spacing=args.spacing,
                                     layout=args.raw_layout,
                                     space_width=args.space_width)
        else:
            with open(args.bdf, encoding="latin-1") as f:
                text = f.read()
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
