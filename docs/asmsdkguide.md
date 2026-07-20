# CXGEOS asmsdk Guide — the friendly ca65 macros

**ABI version 1 · 100 slots** · include: `asmsdk/ca65/cxgeos.inc`

The asmsdk is to assembly what [csdk](csdkguide.md) is to C: named one-line
**macros** over the raw jump-table equates, plus the shared constants and
descriptor builders — so an app reads by intent instead of hand-loading the
`X16_P0..P7` parameter block before every `jsr`. It is the ca65 edition; the
other assemblers get sibling folders under `asmsdk/` in a later version.

```asm
    lda #<50            ; the long way: one rectangle, fourteen lines
    sta X16_P0
    stz X16_P1
    lda #130
    sta X16_P2
    ; ... six more pairs ...
    lda #3
    jsr cx_gfx_rect
```
```asm
    cxm_gfx_rect 50, 130, 150, 130, 3   ; the same, one line
```

A macro expands to **exactly** the code you would have written by hand — the
internal store even emits `stz` for a constant zero high byte the way a human
does — so it costs not one extra byte or cycle. Verified byte-identical.

## Setup

Include it **after** `x16.asm` (the macros use `X16_P0..P7`, and expand to
`jsr` into the generated equates it pulls in):

```asm
    .include "x16.asm"
    .include "asmsdk/ca65/cxgeos.inc"
```

```
.\build.ps1 -Source apps\myapp\myapp.asm     # assemble one app
python tools\mkcxap.py build\MYAPP.PRG build\MYAPP.CXA --name "My App"
```

> **Coordinates & colours.** Positions and sizes are pixels on the 640×480
> screen. A colour is a palette index **0–3** (2bpp = 4 colours); the RGB
> behind each index comes from the active theme (`cxm_theme_set`,
> `cxm_theme_rec`). In `CX_MODE_BMP8` colours are 0–255; in `CX_MODE_TEXT`,
> cells and attributes.

## Three tiers, no name clashes

| tier | looks like | is | where from |
|---|---|---|---|
| addresses | `cx_gfx_rect` (lower) | the ABI slot address (`= $8028`) | generated, pulled in for you |
| constants | `CX_MODE_GUI` (UPPER) | the shared enums/flags | this include |
| **macros** | `cxm_gfx_rect` (lower, **m** = macro) | the friendly wrapper | this include |

Naming is **strict 1:1**: for every ABI slot `cx_<name>` there is a macro
`cxm_<name>` taking the slot's arguments (see [sdkguide.md](sdkguide.md) for
the `in -> out` of each), packed for you. Word arguments are split into the
P-block; byte/register arguments load `A`/`X`/`Y`; a pointer argument takes a
label. Return values are left in place — read `A`/`X`, the carry, or the
P-block after the call, exactly as the ABI documents.

`cxm_say` is a kept friendly alias for `cxm_font_draw` (they are identical).

---

## Call macros

Every slot has one. Grouped as in the ABI; the argument order matches the
slot. A blank "args" cell means the macro takes none.

### System
| macro | args |
|---|---|
| `cxm_version` | — (→ `A`/`X` = ABI version) |
| `cxm_exit` | — (never returns; back to the shell) |

### Screen / graphics — the same calls in every mode
| macro | args |
|---|---|
| `cxm_gfx_init` | — (mode GUI, fresh canvas) |
| `cxm_gfx_clear` | `col` |
| `cxm_gfx_mode` | `mode` (`CX_MODE_*`; → carry if unknown) |
| `cxm_gfx_info` | — (→ `A`=mode, `P0/1`=w, `P2/3`=h, `P4`=bpp, `P5/6`=stride) |
| `cxm_gfx_pset` | `x, y, col` |
| `cxm_gfx_read` | `x, y` (→ `A` = colour, `$FF` off screen) |
| `cxm_gfx_hline` / `cxm_gfx_vline` | `x, y, len, col` |
| `cxm_gfx_rect` / `cxm_gfx_frame` | `x, y, w, h, col` |
| `cxm_gfx_line` | `x0, y0, x1, y1, col` |
| `cxm_gfx_pattern` | `pat, bg, fg` |
| `cxm_gfx_patrect` | `x, y, w, h` |
| `cxm_gfx_blit` | `x, y, wbytes, h, src, op` |
| `cxm_gfx_blitm` | `x, y, h, cols, src` |
| `cxm_gfx_circle` / `cxm_gfx_disc` | `cx, cy, r, col` |
| `cxm_gfx_ellipse` / `cxm_gfx_fellipse` | `cx, cy, rx, ry, col` |
| `cxm_gfx_flood` | `x, y, col` (→ carry if the seed stack overflowed) |
| `cxm_icon` | `id, x, y` (a built-in 24×24 icon; modes 0/1) |
| `cxm_pal_set` | `index, rgb` (one entry; `rgb` is 12-bit `$0RGB`) |
| `cxm_pal_load` | `src, first, count` |

### Text
| macro | args |
|---|---|
| `cxm_font_set` | `cxf` (→ carry if bad) |
| `cxm_font_style` | `flags` (`CX_BOLD` \| `CX_UNDER`) |
| `cxm_font_measure` | `str` (→ `P0/1` = pixel width) |
| `cxm_font_draw` / `cxm_say` | `str, x, y` (→ `P0/1` = pen x) |
| `cxm_ink` | `col` (text ink for the CURRENT mode) |

### Events — a handler table is ALWAYS `CX_ET_COUNT` vectors
| macro | args |
|---|---|
| `cxm_ev_init` | — (clear the queue, hook the raster) |
| `cxm_ev_handlers` | `tbl` |
| `cxm_ev_mainloop` | — (never returns) |
| `cxm_ev_dispatch` | — (one event, then return) |
| `cxm_ev_get` / `cxm_ev_next` | — (→ `P0..P7` = a record; `ev_next` routes mouse to the toolkit first) |
| `cxm_ev_post` | — (`P0..P7` = a record you fill) |
| `cxm_ev_count` | — (→ `A` = records waiting) |
| `cxm_ev_timer` | `frames` (0 = off) |
| `cxm_ev_frames` | — (→ `A` = the frame counter) |
| `cxm_ev_mask` | `sources` (`CX_EVS_*`) |
| `cxm_ev_raster` | `handler` (a game's per-frame IRQ, or 0 to remove) |
| `cxm_ev_stop` | — (return the raster line to the game handler) |

### Pointer, menus, widgets
| macro | args |
|---|---|
| `cxm_mouse_show` | `ptr` (1 = the arrow) |
| `cxm_mouse_hide` | — |
| `cxm_menu_set` | `bar` |
| `cxm_menu_off` | — |
| `cxm_menu_key` | `key` (→ carry if it was a menu key) |
| `cxm_menu_active` | — (→ `A` = 1 if a menu is open, mouse OR keyboard; Z set if none) |
| `cxm_wg_set` | `list` |
| `cxm_wg_draw` | — |
| `cxm_wg_key` | `key` (→ carry if it was a widget key) |

`cxm_menu_active` lets an app that shows a menu bar send the cursor keys to a
menu the user opened **with the mouse** — otherwise a mouse-opened menu is
invisible to the app and the arrows drive the wrong widget. The desktop uses
it (see `apps/filer`).

### Themes & dialogs
| macro | args |
|---|---|
| `cxm_theme_set` | `rec` (a 12-byte theme record) |
| `cxm_dlg_alert` | `desc` (→ `A` = the chosen button) |
| `cxm_dlg_prompt` | `msg, buf, cap` (→ `A` = length, carry if cancelled) |
| `cxm_panel` | `desc` (→ `A` = the chosen button) |

### Audio — PSG, YM2151, PCM
| macro | args |
|---|---|
| `cxm_psg_init` | — (silence all 16 voices) |
| `cxm_psg_freq` | `voice, freq` |
| `cxm_psg_vol` | `voice, vol, pan` (`pan` = `CX_PAN_*`) |
| `cxm_psg_wave` | `voice, wave, pw` (`wave` = `CX_WAVE_*`) |
| `cxm_psg_off` | `voice` |
| `cxm_ym_init` | — (reset the chip, load the default patches) |
| `cxm_ym_note` | `chan, code` (`code` = `CX_YM(octave, note)`; 0 releases) |
| `cxm_ym_off` | `chan` |
| `cxm_ym_vol` | `chan, atten` |
| `cxm_ym_patch` | `chan, idx` (a ROM patch 0–162) |
| `cxm_pcm_ctrl` | `ctrl` (`CX_PCM_*` \| volume 0–15) |
| `cxm_pcm_play` | `src, len, rate` (rate 1–128; 128 = 48 kHz) |
| `cxm_pcm_stop` | — |
| `cxm_pcm_active` | — (→ `A` = 1 while a sample still plays) |

### Joysticks & sprites
| macro | args |
|---|---|
| `cxm_joy_get` | `pad` (→ `A`/`X` = buttons, carry if absent) |
| `cxm_joy_enable` | `mask` (scan pads in `mask`, post `EV_JOY`; 0 = off) |
| `cxm_sprite_image` | `spr, addr, mode` (`addr` = VRAM, `mode` = `CX_SPR_4BPP`/`8BPP`) |
| `cxm_sprite_pos` | `spr, x, y` |
| `cxm_sprite_size` | `spr, w, h, pal` (`w`/`h` = `CX_SPR_8`/`16`/`32`/`64`) |
| `cxm_sprite_flags` | `spr, flags` (a full write; do once before `cxm_sprite_z`) |
| `cxm_sprite_z` | `spr, z` (`CX_SPR_HIDE`/`BEHIND`/`MIDDLE`/`FRONT`) |
| `cxm_spr_collide` | — (→ `A` = collision groups since last call) |

### Tiles *(CX_MODE_TILE)*
| macro | args |
|---|---|
| `cxm_tile_setup` | `layer` (→ carry outside mode 2) |
| `cxm_tile_scroll` | `layer, h, v` (0–4095 each axis) |
| `cxm_tile_cell` | `layer, column, row, cell` (`cell` = `CX_CELL(idx, pal)`) |
| `cxm_tile_fill` | `layer, cell` (into every cell of the layer) |

### Loader, DA, asset loaders
| macro | args |
|---|---|
| `cxm_app_load` | `name, len` (load + run a `.CXA`; returns only on failure) |
| `cxm_da_open` | `name, len` (open a `.CXD` over the running app) |
| `cxm_da_close` | — |
| `cxm_file_load` | `name, len, dst, cap` (→ carry, else `P4/5` = bytes read) |
| `cxm_vload` | `name, len, vaddr, vbank, raw` (a file straight into VRAM) |
| `cxm_bload` | `name, len, bank, addr, raw` (a file into banked RAM, bank 20+) |

### Directory & DOS
| macro | args |
|---|---|
| `cxm_dir_open` | `pat, len` (→ carry on a DOS error) |
| `cxm_dir_next` | `buf` (→ `A` = 0 file / 1 dir, carry = done) |
| `cxm_dir_close` | — |
| `cxm_dos_cmd` | `cmd, len` (→ `A` = status, carry if ≥ 20) |
| `cxm_dos_msg` | `buf` (copies the last DOS reply; → `A` = its length) |

### Clipboard & dirty rectangles
| macro | args |
|---|---|
| `cxm_clip_put` | `type, src, len` (→ carry if too big) |
| `cxm_clip_get` | `dst, cap` (→ `A` = type, `P2/3` = length copied) |
| `cxm_clip_type` | — (→ `A` = type waiting, `P2/3` = length) |
| `cxm_dirty_reset` | — |
| `cxm_dirty_add` | `x, y, w, h` |
| `cxm_dirty_count` | — (→ `A` = rects) |
| `cxm_dirty_get` | `idx` (→ `P0/1`=x0, `P2/3`=y0, `P4/5`=x1, `P6/7`=y1) |

> **A macro packs literals — not registers.** The wrappers load their
> arguments as immediates (`lda #<x`). When a value is already in a register or
> memory — a key in `X16_P1`, a computed pointer, a runtime length — call the
> slot directly (`jsr cx_wg_key`); the equate is right there. The macros are
> for the constant/label case, which is most of them.

---

## Descriptor builders

The UI descriptors the kernel reads are packed byte arrays
([formats.md](formats.md)). The builders lay those bytes down by name, so a
miscounted record — the white-screen bug — cannot happen. Register the list
with one call (`cxm_wg_set`, `cxm_menu_set`); the kernel draws it and posts
events.

### Widget records — one 16-byte record each

| macro | builds |
|---|---|
| `cxm_wg_button x, y, w, h, label` | a push button |
| `cxm_wg_check x, y, w, h, on, label` | a checkbox (`on` = 0/1) |
| `cxm_wg_radio x, y, w, h, on, group, label` | a radio in `group` |
| `cxm_wg_scroll x, y, w, h, val, max` | a horizontal scrollbar |
| `cxm_wg_field x, y, w, h, cap, buf` | a text field editing `buf` |
| `cxm_wg_list x, y, w, h, count, ptrs` | a list of `count` strings at `ptrs` |
| `cxm_wg_icon x, y, w, h, id, label` | a 24×24 icon (`id` = `CX_ICON_*`) |
| `cxm_wg_hit x, y, w, h, shape, trig` | an invisible hit region (`shape` = `CX_WH_*`, `trig` = trigger mask) |

**`cxm_wcount first, last`** — a widget list is a count byte then the records.
Put a label at each end and let the count compute itself:

```asm
widgets:
    cxm_wcount    widgets, widgets_end       ; the count, never miscounted
    cxm_wg_button 520, 448, 100, 24, s_exit
    cxm_wg_check   40, 100, 160, 14, 1, s_wrap
    cxm_wg_radio   40, 160, 120, 14, 0, 1, s_left
    cxm_wg_scroll 360, 116, 200, 16, 2, 9
    cxm_wg_field   40, 290, 300, 16, 24, fieldbuf
    cxm_wg_list   195,  36, 115, 44, 4, listptrs
widgets_end:

    cxm_wg_set widgets
```

A record label (e.g. `wg_year:` before a `cxm_wg_field`) lets the app patch a
field in place at runtime — `wg_year + 9` is its `WG_VAL` byte.

### Menu bar

`cxm_menu_bar n` opens the bar; `cxm_menu title, items` is one entry;
`cxm_items n` opens a dropdown; `cxm_item label` is one item.

```asm
bar:
    cxm_menu_bar 2
    cxm_menu s_file,  file_items
    cxm_menu s_theme, theme_items
file_items:
    cxm_items 2
    cxm_item s_new
    cxm_item s_quit
theme_items:
    cxm_items 2
    cxm_item s_day
    cxm_item s_night

    cxm_menu_set bar          ; a pick arrives as EV_MENU: P1 = item, P2 = menu
```

### Dialog & panel

`cxm_dialog nbuttons, msg` then a `cxm_item` per button — an alert descriptor
for `cxm_dlg_alert` (returns the button index):

```asm
confirm:
    cxm_dialog 2, s_delmsg
    cxm_item s_keep
    cxm_item s_delete
```

`cxm_panel_hdr x, y, w, h, title, wlist, nbuttons` then a `cxm_item` per
button — a modal panel (a widget list in a box with confirm/cancel), for
`cxm_panel`.

### Theme record

**`cxm_theme_rec c0, c1, c2, c3, paper, hi, frame`** — a 12-byte theme: four
12-bit `$0RGB` palette colours, then the role indices. `$0FFF` is white,
`$0000` black.

```asm
theme_night:
    cxm_theme_rec $0001, $0123, $0356, $0ABC, 0, 1, 3
    cxm_theme_set theme_night
```

---

## Constants

The `CX_*` set is the same one the [csdk](csdkguide.md#constants) documents:
`CX_MODE_*`, event types `CX_ET_*`, widget types `CX_WG_*`, hit shapes/triggers
`CX_WH_*`, icon ids `CX_ICON_*`, font flags `CX_BOLD`/`CX_UNDER`, theme roles
`CX_PAPER`/`CX_HI`/`CX_FRAME`, keys `CX_K_*`, audio `CX_WAVE_*`/`CX_PAN_*`, PCM
`CX_PCM_*`, joystick `CX_J_*`, sprite `CX_SPR_*`, tile `CX_TILE_IMG`/`CX_CELL_*`,
painter geometry `CX_FONT_H`/`CX_BOX`/`CX_THUMB`/`CX_SLIDER_H`, event sources
`CX_EVS_*`, and `CX_WG_SIZE` (16). Two are function-like `.define`s:
`CX_YM(octave, note)` packs a note code, `CX_CELL(idx, pal)` packs a tile cell.

## Maintainer note

A ca65 macro **parameter must never be named `x`, `y`, or `a`**. Inside a
nested macro expansion ca65 re-reads the substituted bare token as the index
register and fails with *"Unexpected trailing garbage characters."* The
SDK's coordinate parameters are `x0`/`y0`/`xc`/`yc`/`rx`/`ry` for this reason;
follow suit if you add a macro.

## Reference apps

Every app under `apps/` that is `.asm` uses this SDK:

- `apps/hello_asm/hello.asm` — the smallest: `cxm_gfx_clear`, `cxm_say`,
  `cxm_ev_get`, `cxm_exit`.
- `apps/gallery/gallery.asm` — a menu bar, the full widget set, and two themes,
  built with the descriptor builders.
- `apps/hittest/hittest.asm` — the `cxm_wg_hit` invisible hit regions.
- `apps/cpanel/cpanel.asm` — a form of fields patched in place at runtime.
- `apps/tui/tui.asm` / `apps/m1ui/m1ui.asm` — the toolkit in `CX_MODE_TEXT` and
  `CX_MODE_BMP8`.
- `apps/gameloop/gameloop.asm` — a game's own raster IRQ (`cxm_ev_raster`) that
  borrows the events for a modal `cxm_panel`.
- `apps/filer/filer.asm` — the desktop: directory, list widget, menu routing
  via `cxm_menu_active`.

## See also

- [sdkguide.md](sdkguide.md) — the low-level ABI these macros call (the `in ->
  out` of every slot).
- [csdkguide.md](csdkguide.md) — the C wrapper; the same ideas for C apps.
- [formats.md](formats.md) — the exact byte layouts the builders lay down.
