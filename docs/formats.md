# CXGEOS file formats

## CXF — the font format

One font: metrics, per-glyph advance widths, and 1bpp glyph bitmaps.
Built from a BDF by `tools/fontconv.py`. The system font is
`fonts/pxl8.cxf`.

```
off  size        field
  0  4           magic, "CXF1"
  4  1           height    glyph rows, 1-16
  5  1           ascent    rows above the baseline (descent = height - ascent)
  6  1           first     codepoint of glyph 0
  7  1           count     glyphs, covering first .. first+count-1
  8  1           maxwidth  widest advance in the font (cache sizing)
  9  1           spacing   pixels added after every glyph
 10  6           name      NUL-padded, for a font menu
 16  count       widths    advance per glyph, in pixels, 0-8
 16+count        bitmaps   height rows per glyph, MSB = leftmost pixel
     count*height
```

Header is 16 bytes so the tables land aligned. The system font is
16 + 95 + 95*8 = 871 bytes.

### Why glyphs are 8 pixels wide and one byte per row

A glyph row is exactly one byte, so glyph `i` starts at
`bitmaps + i*height` — no offset table, no indirection, and the cache
builder walks it with a single index. The cost is a hard 8-pixel ceiling
on glyph *ink*; `widths[i]` is the advance and may be less (that is what
makes the font proportional), but never more.

That ceiling is not a limit on the format so much as a bet about the
screen: 640x480 with an 8-row font gives 60 lines of ~112 proportional
characters, which is more text than any 8-bit UI has wanted. A future
CXF2 with 16-pixel glyphs would add an offsets table and a second byte
per row; nothing else in the design would move.

### Storage

Uncompressed on disk. The font is small, and the boot path compresses
whole kernel bank images with ZX0 anyway (Phase 8) — compressing the
font separately would buy a few hundred bytes and cost a decompression
step in the one routine that has to be fast at boot.

### The baseline

`ascent` rows sit above the baseline, `height - ascent` below it. For
`pxl8`: height 8, ascent 7, descent 1 — rows 0-6 above, row 7 below,
which is where the ROM font draws the descenders of g/p/q/y. Draw
routines take the pen at the glyph's top-left; the baseline only matters
for mixing fonts on one line.

### Provenance of `pxl8`

The X16 ROM's ISO charset (PXLfont), which x16-rom's `LICENSE.md` places
in the **public domain**. `tools/charset2bdf.py` trims each 8x8 cell's
blank columns to make it proportional — the bitmaps are the ROM's,
untouched, just no longer padded to a monospace cell. Widths come out
2-8 pixels, averaging 5.7, so a line of text is about 29% shorter than
the same text on the 8-pixel grid.
