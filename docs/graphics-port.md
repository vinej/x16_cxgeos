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
| the entry vector | the region's first 39 bytes | 13 × `jmp`, one per gfx slot, in slot order: init, clear, pset, read, hline, vline, rect, frame, line, pattern set, pattern rect, blit, masked blit |
| an engine image | an ld65 overlay segment: `run = OVL`, `load =` a kernel bank | the vector + the engine + any argument adapters |
| the manager | `kernel/video/engine0.asm` (resident) | `cx_ov_load` copies image *n* from `cx_mbank[n]` / `cx_msrc[n]` (interrupts masked); `cx_gfx_mode` = copy + the new engine's init; `cx_gfx_init` **forces mode 0**, so `cx_exit` → shell always restores the desktop |
| the canvas facts | `cx_gfx_info` (slot 77), `cx_cur_w/h` | mode, width, height, bpp, stride — how client code adapts without naming engines |

The gfx ABI slots (2–14) target the vector's constants forever. The
toolkit (fonts, widgets, menus, dialogs) calls the mode-0 engine's labels
directly — it is mode-0-only *by contract*, enforced where it matters, not
by a dispatch tax on every rect.

## The modes today

| mode | canvas | engine | image (bank) | notes |
|---|---|---|---|---|
| 0 `CX_MODE_GUI` | 640×480, 4 colours, stride 160 | x16lib `bitmap2` | 3 | the desktop; all 13 entries native |
| 1 `CX_MODE_BMP8` | 320×240, 256 colours, stride 320 | x16lib `bitmap` (core, `X16_BITMAP_MIN`) | 4 | thin adapters (colour A→P3, line operands); pattern takes bg/fg as full bytes in P4/P5; blit widths in pixels; blitm's `$00` transparent |
| 2 `CX_MODE_TILE` | 320×240, two 64×32 tile maps | refusal vector + real init | 5 (shared, via `__OV2CODE_LOAD__`) | bitmap entries refuse (a map is not a bitmap); the API is `cx_tile_*` (slots 81–84); tiles at VRAM `$00000`, maps `$08000`/`$09000` |

**Mode-agnostic by construction:** events, audio, sprites, PCM, files,
clipboard, joysticks — and the *shapes* (slots 78–80): circle, disc and
flood are one copy of code in bank 5 drawing **through the vector
itself**, with bounds from `cx_cur_w/h`, so they are correct in every
bitmap mode automatically.

**Mode-0-only by contract:** the toolkit, fonts, dialogs, menus, desk
accessories, and the save-under machinery.

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
images: bank 3 (2bpp, `$88C`), bank 4 (8bpp core, `$525`), bank 5 (shapes
+ tile machinery + mode-2 image). `CXBANKS.BIN` carries banks 2–5 and the
boot's single LOAD fills them all (the KERNAL wraps at `$BFFF`).
