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
| the entry vector | the region's first 42 bytes | 14 × `jmp`, one per gfx slot, in slot order: init, clear, pset, read, hline, vline, rect, frame, line, pattern set, pattern rect, blit, masked blit, **text**. The 14th (text) is `cx_say`: mode 0 points it at the CXF font, text mode at its cell writer, the rest refuse — so `cx_say` is mode-aware through the port, not a special case |
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
| 0 `CX_MODE_GUI` | 640×480, 4 colours, stride 160 | x16lib `bitmap2` | 3 | the desktop; all 13 entries native |
| 1 `CX_MODE_BMP8` | 320×240, 256 colours, stride 320 | x16lib `bitmap` (core, `X16_BITMAP_MIN`) | 4 | thin adapters (colour A→P3, line operands); pattern takes bg/fg as full bytes in P4/P5; blit widths in pixels; blitm's `$00` transparent |
| 2 `CX_MODE_TILE` | 320×240, two 64×32 tile maps | refusal vector + real init | 5 (shared, via `__OV2CODE_LOAD__`) | bitmap entries refuse (a map is not a bitmap); the API is `cx_tile_*` (slots 81–84); tiles at VRAM `$00000`, maps `$08000`/`$09000` |
| 3 `CX_MODE_TEXT` | 80×60 text cells, 16 colours | KERNAL console (`screen.asm`), **all in the overlay** | 5 (shared, via `__OV3CODE_LOAD__`) | a CELL grid, not pixels: clear/rect fill cells with a colour (and set the "paper" later drawing sits on); **frame is a real box in the PETSCII frame glyphs** (┌ ┐ └ ┘ ─ │: codes `$B0 $AE $AD $BD $C0 $DD`); hline/vline are ruled lines; **line works for horizontal/vertical runs** and refuses diagonals; `cx_say` prints ASCII at (col,row), letters mapped to the PETSCII upper/lower charset so the case on screen is the case in the string. pset/read/pattern/blit refuse. Runs in the overlay (low RAM), not a bank, because the KERNAL screen routines do not preserve `RAM_BANK` and would corrupt banked code. Init is `CINT` (a full reset — `screen_set_mode` alone left the text layer dark) then the `CHR$(14)` switch out of ISO (the X16 default, whose charset has no box glyphs) |

**Mode-agnostic by construction:** events, audio, sprites, PCM, files,
clipboard, joysticks — and the *shapes* (slots 78–80, ellipses 85–86):
circle, disc, ellipse, filled ellipse and flood are one copy of code in
bank 5 drawing **through the vector itself**, with bounds from
`cx_cur_w/h`, so they are correct in every bitmap mode automatically.

**Mode-0-only, enforced:** the toolkit, fonts, dialogs, menus, desk
accessories, and the save-under machinery. Their ABI entries refuse with
carry (via `gui_gate`) outside mode 0, so a mistaken call in a bitmap or
tile app is a clean no-op, not a crash. Text in tile mode is font *tiles*
(`cx_tile_cell` with a glyph's tile index), the classic approach.

## How to add mode N

1. **Write the engine image**: a new `OVnCODE` overlay segment (`run =`
   a new `OVLn` area at `$9500`, `load =` a bank with room). First bytes:
   the 13-entry vector, `.assert`ed at `CX_OVL`. Entries the engine can't
   honour: `sec` + `rts`. Include real code + adapters after it. Keep the
   image ≤ `CX_OVL_SIZE`.
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
