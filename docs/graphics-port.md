# The graphics port — pluggable video modes

The resident kernel contains **no graphics engine**. It contains a *port*:
a fixed region of resident RAM whose first bytes are an entry vector, and
a small manager that copies **engine images** into it. Which engine
answers the drawing ABI is a runtime choice — `cx_gfx_mode` — and adding
a new mode never moves a slot, changes a signature, or touches an app.

## The pieces

| piece | where | what |
|---|---|---|
| the region (`OVL`) | `$9500`–`$9EFF` resident RAM (`kernel.cfg`, `CX_OVL` in `kernel/video/ovl.inc`) | 2,560 bytes the current engine occupies |
| the entry vector | the region's first 42 bytes | 14 × `jmp`, one per gfx slot, in slot order: init, clear, pset, read, hline, vline, rect, frame, line, pattern set, pattern rect, blit, masked blit, **text**. The 14th (text) is `cx_say`: mode 0 points it at the CXF font, text mode at its cell writer, the rest refuse — so `cx_say` is mode-aware through the port, not a special case. One byte of ENGINE state follows at `CX_OVL+42`: `cxov_ink`, the text ink `cx_ink` sets — it rides the image, so every mode entry resets it to that mode's default and a value never leaks across a switch |
| an engine image | an ld65 overlay segment: `run = OVL`, `load =` a kernel bank | the vector + the engine + any argument adapters |
| the manager | `kernel/video/engine0.asm` (resident) | `cx_ov_load` copies image *n* from `cx_mbank[n]` / `cx_msrc[n]` (interrupts masked); `cx_gfx_mode` = copy + the new engine's init; `cx_gfx_init` **forces mode 0**, so `cx_exit` → shell always restores the desktop |
| the canvas facts | `cx_gfx_info` (slot 77), `cx_cur_w/h` | mode, width, height, bpp, stride — how client code adapts without naming engines |

The gfx ABI slots (2–14) target the vector's constants forever. The
toolkit (fonts, widgets, menus, dialogs) calls the mode-0 engine's labels
directly. Its ABI entries pass through `gui_gate` (`engine0.asm`): in
mode 0 the call proceeds; in any other mode it **refuses with carry**
rather than blit a 2bpp glyph into another mode's picture. Internal
kernel callers use the routines directly and pay nothing — there is no
dispatch tax on the hot path.

## The modes today

| mode | canvas | engine | image (bank) | notes |
|---|---|---|---|---|
| 0 `CX_MODE_GUI` | 640×480, 4 colours, stride 160 | x16lib `bitmap2` | 3 | the desktop; all 14 entries native (text = the CXF font) |
| 1 `CX_MODE_BMP8` | 320×240, 256 colours, stride 320 | x16lib `bitmap` | 4 | thin adapters (colour A→P3, line operands); pattern takes bg/fg as full bytes in P4/P5; blit widths in pixels; blitm's `$00` transparent. **Text works** (0.4.0): 8×8 charset glyphs from VRAM `$1F000` in the `cx_ink` colour — init normalizes the charset (CINT + the CHR$(14) switch, then reprograms VERA for the bitmap), and a custom charset is a per-entry 2 KB upload to `$1F000`, same contract as mode 3 |
| 2 `CX_MODE_TILE` | 320×240, two 64×32 tile maps | refusal vector + real init | 5 (shared, via `__OV2CODE_LOAD__`) | bitmap entries refuse (a map is not a bitmap); the API is `cx_tile_*` (slots 81–84); tiles at VRAM `$00000`, maps `$08000`/`$09000` |
| 3 `CX_MODE_TEXT` | 80×60 text cells, 16 colours | KERNAL console (`screen.asm`), **all in the overlay** | 5 (shared, via `__OV3CODE_LOAD__`) | a CELL grid, not pixels: clear/rect fill cells with a colour (and set the "paper" later drawing sits on); **frame is a real box in the PETSCII frame glyphs** (┌ ┐ └ ┘ ─ │: codes `$B0 $AE $AD $BD $C0 $DD`); hline/vline are ruled lines; **line works for horizontal/vertical runs** and refuses diagonals; `cx_say` prints ASCII at (col,row), letters mapped to the PETSCII upper/lower charset so the case on screen is the case in the string. pset/read/pattern/blit refuse. Runs in the overlay (low RAM), not a bank, because the KERNAL screen routines do not preserve `RAM_BANK` and would corrupt banked code. Init is `CINT` (a full reset — `screen_set_mode` alone left the text layer dark) then the `CHR$(14)` switch out of ISO (the X16 default, whose charset has no box glyphs) |

**Mode-agnostic by construction:** events, audio, sprites, PCM, files,
clipboard, joysticks — and the *shapes* (slots 78–80, ellipses 85–86):
circle, disc, ellipse, filled ellipse and flood are one copy of code in
bank 5 drawing **through the vector itself**, with bounds from
`cx_cur_w/h`, so they are correct in every bitmap mode automatically.

**The toolkit through the port:** the menu, widgets and dialogs draw
through the port vector (not the mode-0 engine's labels), measure text
through a 15th `measure` entry, and save what a transient element covers
through `rsave`/`rrest` entries — so the same toolkit code lays out in
any mode's units. The per-mode geometry (bar height, row height, the
insets, the title air) rides each engine image as nine metric bytes
after the ink; the frame thicknesses are "one unit" in every mode and
stay literal.

The **menu** is the first to cross: `cx_menu_set`/`off`/`key` run in
mode 0 *and* mode 3 (a real text-mode TUI — the bar, drop-downs as
framed PETSCII boxes, items in cells, reverse-video highlights; mode 3
stashes the covered cells in bank 6, mode 0 the pixel rows in banks
14–15). `menu_gate` allows those two modes; the bitmap modes still
refuse (an 8bpp save-under is future). Highlights stay legible because
the menu sets `cxov_ink` to the contrasting theme role before each
label — mode 3's text writer honours it, mode 0's font ignores it and
inks from the theme, so the desktop is unchanged. Keyboard nav works
today; mouse-in-TUI needs event-coordinate scaling (deferred).

**Still mode-0-only:** fonts (`cx_font_set`/`style`), widgets, dialogs,
and desk accessories — held to mode 0 by `gui_gate` until they cross the
same way. A mistaken call outside mode 0 refuses with carry, a clean
no-op, not a crash. Text in tile mode is font *tiles* (`cx_tile_cell`
with a glyph's tile index), the classic approach.

## How to add mode N

1. **Write the engine image**: a new `OVnCODE` overlay segment (`run =`
   a new `OVLn` area, `load =` a bank with room). First bytes: the
   14-entry vector, `.assert`ed at `CX_OVL`, then the `cxov_ink` byte
   (its default ink — the byte rides the image, so entry resets it).
   Entries the engine can't honour: `sec` + `rts`. Include real code +
   adapters after it. Keep the image ≤ `CX_OVL_SIZE`.
2. **Register it**: `CX_MODES` +1 and one entry each in `cx_mbank`,
   `cx_msrc_lo/hi`, and the `cx_minfo` table (w, h, bpp, stride) in
   `engine0.asm`.
3. **Mode-specific calls**, if any: append-only ABI slots far-called into
   bank code, guarded on `cx_vmode` (the tile slots are the template).
4. **csdk**: a `CX_MODE_x` constant; wrappers for any new slots.
5. **Docs**: a row in the table above; guide sections.

Nothing else changes: not the jump table, not the slots' numbers, not the
toolkit, not one existing app. That property was proven three times —
mode 1 and mode 2 were added after mode 0 shipped, and the frozen canary
binary still draws.

## Budget notes

Resident cost of the whole port: the manager (~200 bytes) — the region
itself replaced the engine that used to live in resident RAM. Engine
images ride banks 3–5 (bank 5 holds the shapes, the tile machinery, and
the mode-2 and mode-3 images).

**The four-bank ceiling.** The boot's KERNAL LOAD of `CXBANKS.BIN` wraps
exactly **four banks (32 KB, banks 2–5)** and then stops — a fifth bank
gets nothing. So all banked code must fit banks 2–5, and a new engine
image shares an existing bank rather than claiming a new one. Mode 3 was
first parked in bank 6 and crashed to the monitor for exactly this
reason (`$9601`, blown stack: the copy pulled `$FF` from an unloaded
bank). Banks 2–5 currently hold ~12 KB of code, so there is room; when
they fill, the boot loader needs a second LOAD.
