# CXRF file formats

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

## CXAP — the app format

A CXAP (`.CXA`) is a 32-byte header in front of an ordinary PRG. That is
the entire design, and the design IS the point: every one of the twelve
toolchains already emits a working PRG at $0801, so every one of them
can produce a CXRF app without touching a linker script. The header
is prepended by `tools/mkcxap.py`, which finds the entry point by
reading the SYS target out of the PRG's own BASIC stub.

| offset | size | field |
|---|---|---|
| 0 | 4 | magic, `CXAP` |
| 4 | 2 | min ABI version, little-endian — the lowest kernel this app runs on |
| 6 | 2 | entry address |
| 8 | 1 | flags (none defined yet; zero) |
| 9 | 7 | reserved, zero |
| 16 | 16 | name, ASCII, zero-padded |
| 32 | — | a standard PRG: load address word ($0801), then the payload |

### How a load happens, and when it can be refused

`cx_app_load` (slot 31) reads the header into $0400 and judges it
BEFORE the payload touches memory, because the payload lands on top of
the caller. Refused with carry and the caller intact: wrong magic
(A = 1), a min-ABI above the kernel's version (A = 2 — "needs a newer
kernel", not "broken file"), an entry outside app space, a load address
that is not $0801. The app is refused, not relocated.

Past the first payload byte there is no going back: the caller is
partially overwritten, so a mid-stream I/O error or a payload that runs
into the kernel at $8000 ends at a text-mode message and a halt, never
at a silent half-program.

On success the loader stops the event system, hides the mouse, resets
the hardware stack, zeroes the app ZP ($60–$7F), and jumps to the
header's entry: every app starts in the same machine, whoever launched
it. Nothing returns to the caller — an app ends through `cx_exit`,
which loads SHELL.CXA through this same path.

### The C side (llvm-mos)

The kernel's parameter block at $22 collides with llvm-mos's own zero
page: the compiler keeps its soft stack pointer in __rc0/__rc1 at
$22/$23. A C program that wrote $22 directly would corrupt its own
stack — it did, and the crash took an evening to bisect. So
`sdk/include_llvm/cxrf.h` mirrors the block: `cx_p[]`, `cx_a`,
`cx_x`, `cx_y` are ordinary memory, and `cx_run()` carries them across
the real block with $22–$25 — and, since 0.4.0, the whole imaginary
register file at $02–$21 — saved around the call: llvm's registers are
the KERNAL's own r0–r15, and any slot that reaches the KERNAL scribbles
them. The header also homes the C soft stack at $8000 before main (the
cx16 default, $9F00, sits inside the kernel's graphics port). The mirror also
returns the carry as `cx_c`, which raw C calls could never see. Build
C apps with `-mreserve-zp=90` — clang's whole-program pass otherwise
claims zero page from $26 up, all of which belongs to the kernel or to
the app ZP convention.

## The menu tree

An app hands `cx_menu_set` a tree in its own memory; the engine reads
it in place ($0801–$7FFF is always mapped) and never copies it, so it
must stay put while the menu is set. Strings are zero-terminated ASCII
in the font's range.

```
bar:        .byte n                     ; menus in the bar (up to 8)
            ; then n entries of:
            .addr title, items

items:      .byte n                     ; up to 10 -- the save-under
            ; then n words:             ; strip holds 102 rows
            .addr label
```

Call order matters: `cx_ev_init` first, then `cx_menu_set` — the bar
lives on the region stack, and `cx_ev_init` resets that stack. A
selection arrives as an `EV_MENU` event (type 7): `detail` (P1) is the
item index, P2 the menu index. Clicking anywhere outside an open
drop-down dismisses it and posts nothing; either way every pixel the
box covered comes back from the save-under strip.

## The widget list

An app hands `cx_wg_set` a widget list: a count byte, then that many
16-byte records, in the app's own memory (read and written in place —
the toolkit stores each widget's state back into its record).

```
0   type    .byte    0 button, 1 checkbox, 2 radio, 3 h-scrollbar,
                     4 text field, 5 list, 6 icon, 7 hit region
1   flags   .byte    bit0 = disabled (drawn, but not clickable)
                     bit6 = WG_SELECTED -- the widget a fresh list installs
                     focused (the desktop sets it on the icon/row an app was
                     launched from, so exit returns there)
2   x       .word
4   y       .word
6   w       .word
8   h       .byte
9   value   .byte    checkbox/radio 0-1; scrollbar 0..max;
                     icon: the id 0-17; hit region: the shape (WH_*)
10  group   .byte    radio: the group id; scrollbar: the max value;
                     hit region: the trigger mask (WH_CLICK/RELEASE/HOVER)
11  label   .word    a zero-terminated string (unused by a hit region)
13  --      3 bytes  reserved, zero -- but a WH_POLYGON/WH_PIE hit region
                     uses 13,14 for its two params (see below); 15 stays 0
```

A click updates the widget under it, redraws just that widget, and posts
`EV_WIDGET` (type 8): `detail` (P1) is the widget index, P2 its value.
A button reports value 1 (momentary). A checkbox toggles. A radio lights
and clears its group-mates. A scrollbar takes the value its click names.
The keyboard drives the same list through `cx_wg_key`: TAB/UP move a
focus frame, SPACE/RETURN activate the focused widget, LEFT/RIGHT step a
focused scrollbar -- and post the identical `EV_WIDGET`. A **text field**
(type 4) is different: `WG_LBL` points at a mutable buffer, `WG_VAL` is
its current length and `WG_GRP` its capacity. With the field focused,
printable keys append, DEL/backspace trims, and RETURN posts `EV_WIDGET`
with the length. `cx_menu_key` and `cx_wg_key` clobber X and Y (only A
and the carry survive), so never carry a register across them -- a loop
counter in X becomes garbage the moment either is called.
Every colour is the live theme's, so `cx_theme_set` then `cx_wg_draw`
recolours the whole list. Registering a list pushes a region over the
list's bounding box, so its clicks route to the toolkit and nowhere
else. Only an app that called `cx_wg_set` can receive `EV_WIDGET`.

### The list widget (type 5)

`WG_LBL` is an array of string pointers, `WG_GRP` the count, `WG_VAL`
the selected row, and byte 13 (`WG_TOP`) the scroll offset the toolkit
maintains. With the list focused, UP/DOWN move the selection (the view
scrolls to keep it visible), RETURN posts `EV_WIDGET` with the selected
index. It is the file browser's list.

### The icon and hit-region widgets (types 6, 7)

`WG_ICON` (type 6) draws a built-in 24×24 icon — `WG_VAL` is the icon id
(0–17, `kernel/ui/icon.asm`) — with `WG_LBL` centred beneath it; the
desktop's icon view is a grid of them. A single click posts
`EV_WIDGET(index, 0)`, a double-click `(index, 1)` — select versus open.

`WG_HIT` (type 7) is an **invisible hit region** — a hotspot the app draws
itself; the toolkit paints nothing and only routes the mouse. `WG_VAL` is
the shape (`WH_RECT`=0, `WH_CIRCLE`=1, `WH_ELLIPSE`=2; circle and ellipse
are inscribed in the box, so keep it ≤ 510 px), and `WG_GRP` a trigger mask
(`WH_CLICK`=1, `WH_RELEASE`=2, `WH_HOVER`=4; 0 means click-only). It posts
`EV_WIDGET(index, phase)` where phase is the mouse event — 2 down, 3 up,
1 hover-in, 0 hover-out. Hover routing is skipped entirely when no region
in the list asks for it, so a click-only list costs nothing on a move.

Two more shapes match the `cx_gfx_shape` family: `WH_POLYGON`=3 (a regular
convex *n*-gon) and `WH_PIE`=4 (a pie/arc **wedge** — an arc has no
interior, so its clickable area is the pie's). Both are **circle-based**
(radius = `WG_W`>>1, centred in the box — use a square box), and both carry
two extra numbers in the reserved pad: byte **13** is the polygon's sides
(3–24) or the wedge's start angle, byte **14** the rotation or the end angle
(byte angles: 0 = east, 64 = south, 128 = west, 192 = north). Their point
tests need trig, so they run in bank 19 (`kernel/video/shphit.asm`), reached
from the widget bank through the `wg_hit_far` far-call — the only hit shapes
that leave bank 16, and only on the click/hover of a region that uses them.

## The panel descriptor

`cx_panel` (slot 92) is a modal *form*: the message box's bigger
sibling. Where `cx_dlg_alert` shows a line of text, a panel shows a box
of your own widgets with confirm/cancel buttons, runs its own dispatch
loop, and returns only when a button closes it. The widget records are
edited in place, so the app reads the values straight from its own list
afterward. `A/X` points at the descriptor:

| offset | size | field | meaning |
|---|---|---|---|
| 0 | word | `x` | box left, in the mode's units (pixels; cells in mode 3) |
| 2 | word | `y` | box top |
| 4 | word | `w` | box width |
| 6 | byte | `h` | box height |
| 7 | word | `title` | a heading at the top-left, or 0 for none |
| 9 | word | `widgets` | a widget list (as above), placed at absolute coords inside the box |
| 11 | byte | `nbtn` | 1..3 buttons along the bottom, right-aligned |
| 12 | word × `nbtn` | `labels` | the button labels, button 0 leftmost |

The panel draws the box, the widgets and the buttons itself; the app
only places the widgets inside the box's rectangle. It returns `A` = the
chosen button — 0 is the confirm button (also what RETURN picks), and
the last button is what ESC picks. It works in modes 0, 1 and 3 — and in
mode 2 (tiles) while a `cx_tile_text` overlay is up. The box height is
bounded by the mode's save-under — about 100 rows in mode 0 (banks 14–15),
the VRAM strip in mode 1, ~50 cells in mode 3 (bank 6); on the tile overlay
there is no save-under (the layer reverts to the game on exit), so keep the
box within the 40×30 cell grid. The same budget the dialog draws from, so a
form the size of a dialog always fits.
