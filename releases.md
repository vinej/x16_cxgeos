# CXRF releases

CXRF (Commander X16 Runtime Framework) shipped as **CXGEOS** through v0.9.0 and
was renamed at v0.10.0. Git tags keep their `vX.Y.Z` names; dates are tag dates.
Newest release first.

## v0.11.0 — x16lib v0.11.1 vendored, tile/text UI polish (2026-07-23)

- **Vendored x16lib re-synced to v0.11.1.** The whole `x16lib/` tree is a clean
  snapshot of the upstream `src_ca65` at v0.11.1: the bitmap modules were renamed
  and split (`bitmap.asm` → `bitmap8l.asm`, `bitmap2.asm` → `bitmap2h.asm`, with
  `gfx_*` → `gfx8l_*` and `gfx2_*` → `gfx2h_*`), `X16_USE_ALL` is gone in favour
  of per-module gates, and many new modules ride along gated-out. Two gates CXRF
  needs for its split-bank, bare-VERA kernel were **upstreamed into x16_library
  v0.11.1 first** — `X16_SKIP_BASE` (source `shapes.asm` twice, base + extras in
  separate banks) and `X16_BITMAP8L_NO_INIT` (omit `gfx8l_init`'s
  `screen_set_mode`) — so the vendored copy stays a plain snapshot with nothing
  hand-patched.
- **~130 B of resident reclaimed — free rose from ~194 B to 327 B.** Dropping the
  KERNAL console/input shims (SCREEN, INPUT) for inline KERNAL calls, plus finer
  opt-in x16lib gates — `X16_USE_VERA` split into `_ADDR`/`_FILL`/`_FXPROBE` and
  `irq_remove` behind `X16_USE_IRQ_REMOVE`, both also upstreamed — let the kernel
  carry `vera_fill` alone and drop the address setters, FX probe and `irq_remove`
  it never calls.
- **Fixed a boot crash into the machine monitor.** `font_set`'s inline far call
  (`jsr cxb_call` + inline bank/addr) is a *tail* call — `cxb_call` consumes the
  stub's frame to read its data and returns to the ORIGINAL caller — so the
  refactored rollback code after it was dead, and its pushed bytes were popped as
  a return address, BRK-ing to the monitor at boot. Now behind its own 5-byte
  stub. The flat test runner links `fs_parse` directly and never saw it; only the
  boot smoke caught it.
- **Tile/text dialogs: upper-case text no longer renders as graphics.** The
  mode-2 glyph charset was staged with `CINT` + `CHR$(14)`, but on the X16 the
  case toggle only sets the editor's mode FLAG — it does not re-upload the VRAM
  charset — so `$1F000` kept the upper/GRAPHICS set and every `A-Z` in a tile
  dialog drew as a graphic tile. `ov2_init` now uploads explicitly with
  `SCREEN_SET_CHARSET(3)`. TILETEXT's self-test gained a charset-glyph assertion
  so it cannot regress silently.
- **Cell-mode widget polish** (mode-2 tiles + mode-3 TUI, one shared path): text
  fields grew a **block caret** (there was none); the focus outline no longer
  boxes a field (the caret is the cue); the slider's fill is a **solid rectangle**
  drawn as a colour fill instead of `#` (a glyph rendered differently by the tile
  and KERNAL ports); and every widget now shares the **dialog's background**
  instead of a stale or black one — with no stray cyan.
- **`fontconv.py` gains a `--x16-charset` path** — raw 8x8/1bpp X16 tile fonts to
  CXF, remapping screen-code order into CXRF's codepoints; a set of `.cxf` fonts
  is staged for future use.
- **ABI unchanged (v4, 105 slots).** The freeze canary still passes. Green:
  62/62 tests, the asmsdk byte-identical fidelity gate, and every headless boot
  (SD, cartridge, FAT32, standalone cart).

## v0.10.1 — desktop file sizes, longer filenames (2026-07-22)

- **File sizes in the desktop list** — the list view now shows each entry's
  size (its CMDR-DOS block count) as a right-aligned second column beside the
  name. `cx_dir_next` surfaces the block count it used to discard, in P2/P3; a
  new `cxm_wg_list2` builder gives the list widget an optional parallel
  size-string array, drawn right-aligned. Folders and the "../" row show no
  size. It costs nothing extra — the count was already in the DOS listing.
- **Longer filenames** — the desktop's name limit rose from **16 to 34
  characters**. `cx_dir_next`'s name cap is now 34 (its buffer contract grows
  to >=35 bytes), and the file browser's name pool and its prompt / DOS-command
  buffers grew to match. Both browsing/launching and create/rename/copy handle
  34-char names in list view. (The X16 itself allows up to 255; 34 is the
  desktop's practical cap — icon-view captions can overflow their cell for the
  longest names, list view is unaffected.)
- **`docs/exit-to-basic.md`** — records a known instability found while
  prototyping "launch a standard X16 program": handing the machine from CXRF to
  BASIC resets the board ~1 s later, and CXRF's own `cx_exit -> BASIC` fallback
  does the same. It is NOT the SMC watchdog (there is none). The note keeps the
  evidence, the dead ends (no KERNAL soft re-init fixes it), and the
  hardware-reset / boot-chain path that would, so a future fix starts informed.
- **ABI unchanged (v4, 105 slots).** The `cx_dir_next` change is behaviour-only,
  so the freeze canary still passes. Green: 59/59 tests, the asmsdk fidelity
  gate, and every headless boot (SD, cartridge, FAT32, standalone cart).

## v0.10.0 — CXRF: the rename, and a standalone cartridge (2026-07-21)

- **Renamed CXGEOS → CXRF** (Commander X16 Runtime Framework) across the whole
  repo: identifiers, comments, docs, build outputs (`cxrf_cart.bin`) and the
  generated bindings, plus the source files themselves (`abi/cxrf.abi`,
  `sdk/include_*/cxrf.{inc,h,p8}`, `asmsdk/*/cxrf.inc`). All 13 toolchains and
  the ABI generators regenerate consistently; the `cx_*` ABI names are
  unchanged, so existing apps rebuild untouched.
- **Standalone cartridge** — `build.ps1 -Cart -App <CXA>` bakes an app into a
  sixth ROM bank (37); the boot stub copies it to `$0801` and runs it, so the
  cartridge boots straight into the program with **no SD card at all** — a
  single-item deliverable. `paint.bat` is the worked example (PAINT in ROM).
- **Clean exit to BASIC** — with no `SHELL.CXA` to load (a standalone cart, or
  a card without one), `cx_exit` now rebuilds the stock text screen (`CINT`:
  charset, layers, palette the 2bpp desktop clobbered) and hands the machine to
  the **X16 BASIC prompt**. It uses `ENTER_BASIC`, not a reset, so the
  cartridge's `"CX16"` auto-boot does not re-fire. The old "NO SHELL.CXA" halt
  is gone.
- Green: 59/59 tests, the ABI-freeze canary, the asmsdk byte-identical fidelity
  gate, and every headless boot (SD, cartridge, FAT32, standalone cart).

## v0.9.0 — desktop matures, 8bpp tiles (2026-07-21)

The icon view becomes a real file browser: an **18-icon** sheet with a per-app
picture mapped by filename, tighter single-line cells, single-click select /
double-click open, keyboard grid navigation, and a selection that **survives an
app launch** (the launched file's index rides resident byte `$800B`, and a new
`WG_SELECTED` flag installs a list focused, so `cx_exit` lands the frame back on
the app you ran). Radio buttons draw **round**, the prompt field centres its
text, and **TAB toggles** the menu bar. Fixed a latent `cx_do_icon` blit-op bug
that vanished any icon whose sheet address had `(high & 3) == 2`. Tile mode
gained an **8bpp path** — a 64 KB set streamed to VRAM (`cx_vram_stream`,
`cx_tile_load`) with maps relocated to `$10000` — plus **double-buffering**
(`cx_tile_dbuf`/`cx_tile_flip`) and a mode-2 **dialog overlay** (`cx_tile_text`).
ABI **v4, 105 slots**; vendored x16lib bumped to **0.9.1** with an
`X16_SKIP_SHAPES`/`X16_SKIP_MATH` include opt-out. 59/59 tests green.

## v0.8.0 — Prog8 support, and more shapes (2026-07-20)

**Prog8** (Irmen de Jong's structured 6502 language) joins as a 13th toolchain:
`abi/prog8.py` generates the `cx.*` binding to every slot, and `p8sdk/` is the
Prog8 parallel of the C csdk. `apps/calc/calc.p8` is the worked example. x16lib
0.8.0's extra shapes — polygon, fpolygon, arc, pie — arrive through a single
dispatched slot, `cx_gfx_shape` (X selects the shape; a `jmp(tbl,X)` routes it),
for 6 resident bytes. Bank 19 was cleared for them (audio + sprites → bank 18).
ABI bumped to **v2** (slot 100, append-only), with friendly layers across all
toolchains. 56/56 on-target tests, byte-identical asmsdk fidelity, zero
regression.

## v0.7.1 — a friendly assembly macro SDK, and desktop fixes (2026-07-20)

`asmsdk/ca65`: named `cxm_*` macros + descriptor builders over the jump table,
the assembly parallel of the C csdk, expanding byte-identical to hand code; all
ten in-tree asm apps use it. `cx_menu_active` (slot 99) reports whether a menu
is open (mouse or keyboard) so the desktop routes cursor keys to a click-opened
menu. Two exit-path fixes stop a mode-switching app from returning to the
desktop on the wrong file. New `docs/asmsdkguide.md`.

## v0.7.0 — invisible hit regions, palette API, persistent desktop view (2026-07-19)

`WG_HIT`: a hotspot the app draws itself while the toolkit only routes the mouse
— rect/circle/ellipse, click/release/hover — for 0 resident bytes.
`cx_pal_set`/`cx_pal_load` (slots 97–98) program VERA's palette directly. The
desktop remembers its list-vs-icons view across app launches. x16lib v0.7.0 gfx
re-vendored (~600 B saved); the C SDK now wraps all 99 slots.

## v0.6.1 — icon widget + dual-view desktop (2026-07-19)

A graphical icon widget and an icon-view desktop, plus sprite-collision capture.
One 24×24 2bpp icon sheet serves both bitmap modes; the filer's View menu
toggles a file-type icon grid against the classic list.

## v0.6.0 — memory architecture restructured for growth (2026-07-19)

The per-bank memory architecture: banks re-themed, the font split, the jump
table grown (110 → 135 slots), resident free 20 → 130 B, bank 2 shrunk 7 KB →
1.8 KB. RAM banks 16–19 now belong to the kernel; the first app bank (and
`cx_bload` floor) moved from 16 to **20**. See `docs/banks.md`.

## v0.5.1 — cartridge boot, a game's own IRQ (2026-07-19)

Boot the whole framework from a **cartridge** (`build.ps1 -Cart`, ROM banks
32–36, the KERNAL's `"CX16"` auto-boot) — no ROM patch. `cx_ev_raster` /
`cx_ev_stop` (slots 93–94) let a game own a raster line and borrow the kernel's
events for a dialog.

## v0.5.0 — the toolkit in every mode (2026-07-19)

The widget toolkit, menus, and modal dialogs draw in every video mode, not just
the desktop — the menu gate and text-port work that lets a tile or bitmap app
raise the whole UI.

## v0.4.0 — pluggable fonts & charsets, cx_file_load, cx_ink, mode-1 text (2026-07-18)

Pluggable fonts and charsets, the `cx_file_load` asset loader, `cx_ink` for
mode-1 text colour, and an event **source mask** so an app subscribes only to
the event kinds it wants.

## v0.3.1 — ellipses in the ABI (2026-07-18)

Ellipse primitives added at slots 85–86.

## v0.3.0 — the graphics port: four video modes (2026-07-18)

Four video modes behind a pluggable graphics port (`cx_mode`) — the same drawing
calls reinterpreted per canvas (GUI, 8bpp bitmap, tiles, text) — plus
joysticks, the mode-agnostic shapes, and text boxes.

## v0.2.0 — audio, sprites and PCM (2026-07-17)

x16lib's multimedia through the ABI (now 74 slots, still v1): the VERA PSG (16
voices), the YM2151 FM chip, and streamed PCM (`cx_psg_*`, `cx_ym_*`,
`cx_pcm_*`); hardware sprites 1–127 (`cx_sprite_*`, sprite 0 is the mouse) with
`cx_vram_write`. New examples `apps/beep` and `apps/sprite`.

## v0.1.0 — first tagged release (2026-07-17)

A from-scratch, GEOS-inspired desktop for the Commander X16 (640×480 @ 2bpp,
stock R49+ ROM) with a documented SDK. Kernel ABI **v1, 55 slots** (graphics,
text, events, menus, widgets, themes, dialogs, directory, DOS, clipboard, desk
accessories). Header-only C wrapper (`csdk/`). Apps: the desktop/file manager,
widget gallery, control panel, notes desk accessory, and C examples hello_c,
calc, cdemo, paint. 40/40 tests, six boot chains green.
