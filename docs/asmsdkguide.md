# CXGEOS asmsdk Guide — the friendly ca65 macros

**Release 0.8.0** · ABI version 2 · 101 slots · include: `asmsdk/ca65/cxgeos.inc`

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
| `cxm_gfx_shape` | `kind, cx, cy, r, p5, p6, col` — one slot: kind 0 polygon, 1 fpolygon, 2 arc, 3 pie; polygon: p5=sides, p6=rot; arc/pie: p5=start, p6=end (byte angles) |
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

`cxm_wg_icon` and, especially, `cxm_wg_hit` get a full section further down
— see [Icons](#icons) and
[Hit regions — build your own widget (`WG_HIT`)](#hit-regions--build-your-own-widget-wg_hit).

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

## Icons

The kernel ships a built-in 24×24 icon sheet — the same eight glyphs the
desktop's file browser draws — plus `cxm_icon` to blit any one of them
directly, in either bitmap mode.

| id | constant | icon |
|---|---|---|
| 0 | `CX_ICON_UP` | up one directory level |
| 1 | `CX_ICON_FOLDER` | a directory |
| 2 | `CX_ICON_APP` | an application |
| 3 | `CX_ICON_FONT` | a font |
| 4 | `CX_ICON_ACCESSORY` | a desk accessory |
| 5 | `CX_ICON_DATA` | any other file |
| 6 | `CX_ICON_IMAGE` | a picture/image |
| 7 | `CX_ICON_DISK` | a disk/volume |

```asm
cxm_icon CX_ICON_FOLDER, 40, 60      ; paint one icon directly
cxm_say  s_projects, 44, 88          ; your own caption under it
```

### As a widget (`cxm_wg_icon`)

The kernel-managed form draws the icon **and** a centred label, tracks
clicks, and — like the desktop's icon view — tells a single click from a
double: `EV_WIDGET` posts value 0 on click (select), 1 on double-click
(open). It is one call in a widget list, same as any other builder:

```asm
files:
    cxm_wcount   files, files_end
    cxm_wg_icon   40, 60, 96, 66, CX_ICON_FOLDER, s_projects
    cxm_wg_icon  140, 60, 96, 66, CX_ICON_APP,    s_editor
files_end:

    cxm_wg_set files
    ; a click -> EV_WIDGET: P1 = index, P2 = 0 (select) or 1 (open)

s_projects .byte "Projects", 0
s_editor   .byte "Editor", 0
```

See `apps/filer/filer.asm` for the real icon-grid file browser this exists
for — it builds the records at runtime, one per directory entry, rather
than as a static list, but the 16-byte record is identical either way.

## Hit regions — build your own widget (`WG_HIT`)

Six of the seven widget types are the kernel drawing something. `WG_HIT`
(`cxm_wg_hit`) is the exception, and it is the most important one: **it
paints nothing at all.** You draw a shape with your own `cxm_gfx_*` calls —
a dial, a sprite, a game piece, an image map over a picture you loaded —
and lay an invisible `WG_HIT` record over it. The toolkit hit-tests that
record with the same region-stack machinery already serving every button
and checkbox on screen, including true **hover** tracking. This is the
sanctioned way to build a custom widget in CXGEOS: the kernel does not need
to know your shape, only its box and which of three built-in tests to run
against it.

### Why it earns its keep

- **Any look.** The widget can be anything you can draw — the kernel's
  contribution is purely "is the pointer inside," not pixels.
- **Real geometry, not just a bounding box.** `WG_HIT` can test a
  rectangle, a circle, or an ellipse inscribed in the box — the exact math
  `cxm_gfx_circle`/`cxm_gfx_ellipse` use to draw the outline, so the hit
  region lines up with what the user actually sees, not an invisible
  square around it.
- **Hover for free.** No other technique in the toolkit gives you
  enter/leave tracking without polling the mouse position yourself every
  frame.
- **Zero cost when unused.** The shape math and hover state live in bank
  16 with the rest of the widget engine; a click-only list, or a list with
  no hit region at all, pays nothing extra on a mouse move.

### The shape (`shape` / `WG_VAL`)

| constant | value | tests |
|---|---|---|
| `CX_WH_RECT` | 0 | the box itself — the default, every other widget's test |
| `CX_WH_CIRCLE` | 1 | a circle inscribed in the box — make the box square |
| `CX_WH_ELLIPSE` | 2 | an ellipse inscribed in the box |

Circle and ellipse share one normalised test — from the box's centre,
`nx = |dx|·128/rx`, `ny = |dy|·128/ry`, inside when `nx²+ny² ≤ 128²` — the
same fixed-point routine `cxm_gfx_circle`/`cxm_gfx_ellipse` use to draw the
outline, so a hit region's edge lines up with the shape you actually drew.
Keep the box's width and height each ≤ 510 px.

### Mouse functionality — the trigger mask (`trig` / `WG_GRP`)

| constant | bit | fires on |
|---|---|---|
| `CX_WH_CLICK` | `%001` | mouse button pressed inside the shape |
| `CX_WH_RELEASE` | `%010` | mouse button released inside the shape |
| `CX_WH_HOVER` | `%100` | the pointer enters or leaves the shape — no button needed |

Combine bits with `|` in the macro call (ca65 evaluates it at assemble
time); `trig = 0` means click-only. Every event a subscribed region posts
arrives as `EV_WIDGET` — `X16_P1` is the region's index in the list,
`X16_P2` is the **phase**:

| `X16_P2` | phase |
|---|---|
| 2 | down — `CX_WH_CLICK` fired |
| 3 | up — `CX_WH_RELEASE` fired |
| 1 | hover-in: the pointer just entered |
| 0 | hover-out: the pointer just left (or left everything) |

A double-click inside the region still posts phase 2, same as a single
click — hit regions do not distinguish the two the way the icon and list
widgets do.

### Building one

`cxm_wg_hit x0, y0, w0, h0, shape, trig` lays down the whole 16-byte record
— `.byte CX_WG_HIT, 0`, the box, the shape and trigger, a null label
(unused), and the reserved pad — nothing to miscount, the same guarantee
every `cxm_wg_*` builder gives. Put it in a list with `cxm_wcount`, exactly
like a button or a checkbox:

```asm
hits:
    cxm_wcount hits, hits_end
    ;            x    y    w    h   shape          triggers
    cxm_wg_hit  50, 130, 150, 130, CX_WH_RECT,    CX_WH_CLICK | CX_WH_HOVER
    cxm_wg_hit 255, 120, 150, 150, CX_WH_CIRCLE,  CX_WH_CLICK | CX_WH_HOVER
    cxm_wg_hit 450, 130, 180, 130, CX_WH_ELLIPSE, CX_WH_CLICK | CX_WH_HOVER
hits_end:

    cxm_wg_set hits
```

### Worked example — the shipped demo, `apps/hittest/hittest.asm`

Three outlines the app draws itself — a rectangle, a circle, an ellipse —
each backed by exactly the `hits` list above, click *and* hover both on.
Hovering names the shape on the status line; clicking stamps a filled disc
at its centre. The point of the demo: the fill only ever lands where the
pointer is really inside the shape, not merely inside its bounding box,
because bank 16 did the circle/ellipse math, not the app.

```asm
draw_shapes
    cxm_gfx_frame   50, 130, 150, 130, 3    ; rectangle at (50,130) 150x130
    cxm_gfx_circle  330, 195, 75, 3         ; circle:  centre (330,195) r 75
    cxm_gfx_ellipse 540, 195, 90, 65, 3     ; ellipse: centre (540,195) rx 90 ry 65
    rts

; on_widget -- a WG_HIT fired: P1 = region index, P2 = phase
on_widget
    lda X16_P2
    cmp #2
    beq @click
    cmp #1
    beq @hover
    jsr status_idle              ; hover-out: back to the prompt
    rts
@hover
    lda X16_P1                   ; hover-in: name the shape
    jmp status_name
@click
    lda X16_P1
    jmp stamp                    ; stamp a dot at that shape's centre
```

The full source also builds with `-DHITTEST_SELFTEST`, which synthesises a
click in each shape at start-up for a headless `-gif` capture; run normally
it is mouse-driven end to end, ESC to quit. See `apps/hittest/hittest.asm`.

### See also

- [formats.md](formats.md#the-icon-and-hit-region-widgets-types-6-7) — the
  exact byte layout both `WG_ICON` and `WG_HIT` share with every widget.
- [sdkguide.md](sdkguide.md#hit-regions--the-widget-you-draw-yourself-wg_hit) —
  the ABI mechanics: the shape test, the far-call cost, the raw record.
- [csdkguide.md](csdkguide.md#hit-regions--build-your-own-widgets-wg_hit) —
  the same feature for C apps, with a full worked poll loop.

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
