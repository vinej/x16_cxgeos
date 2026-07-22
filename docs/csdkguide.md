# CXRF csdk Guide — the friendly C wrapper

**Release 0.10.1** · header: `csdk/cxsdk.h`

The csdk turns the low-level [ABI](sdkguide.md) into clean, named `cx_*`
functions, a typed event record, the shared constants, immediate-mode widget
painters, and packed descriptor builders — so C apps read by intent and no one
re-derives the parameter-block plumbing.

It is **header-only**: every wrapper is `static`, so `-Os` drops the ones you
do not call. It targets **llvm-mos** (the fully-supported C toolchain).

```c
#include <cbm.h>
#include "sdk/include_llvm/cxrf.h"   /* the generated ABI: slots + macros */
#include "csdk/cxsdk.h"                /* the friendly wrappers */
```

```
mos-cx16-clang -Os -mreserve-zp=90 -I . -o build/MYAPP.PRG apps/myapp.c
python tools/mkcxap.py build/MYAPP.PRG build/MYAPP.CXA --name "My App"
```

> **Coordinates & colours.** Positions and sizes are pixels on the 640×480
> screen. A colour is a palette index **0–3** (2bpp = 4 colours); the RGB
> behind each index comes from the active theme (see `cx_theme`, `cx_theme_rec`).

---

## Constants

### Event types — a `cx_event.type` (`CX_ET_*`)

Named `CX_ET_*` (event **t**ype), distinct from the generated header's
`CX_EV_*` slot names.

| name | value | meaning |
|---|---|---|
| `CX_ET_NULL` | 0 | the queue is empty |
| `CX_ET_MOVE` | 1 | mouse moved (`x`,`y`) |
| `CX_ET_DOWN` | 2 | mouse button pressed |
| `CX_ET_UP` | 3 | mouse button released |
| `CX_ET_DBL` | 4 | double-click |
| `CX_ET_KEY` | 5 | key (`detail` = code) |
| `CX_ET_TIMER` | 6 | the timer fired |
| `CX_ET_MENU` | 7 | menu pick (`detail` = item, `x` = menu) |
| `CX_ET_WIDGET` | 8 | widget acted (`detail` = index, `x` = value) |
| `CX_ET_JOY` | 9 | a pad changed (`detail` = pad, `x` = buttons, `y` = changed bits); opt-in via `cx_joy_enable` |
| `CX_ET_TYPES` | 10 | the count, for a handler table |

### Widget types — a descriptor's `type` (`CX_WG_*`)

`CX_WG_BUTTON`=0, `CX_WG_CHECK`=1, `CX_WG_RADIO`=2, `CX_WG_SCROLL`=3,
`CX_WG_FIELD`=4, `CX_WG_LIST`=5, `CX_WG_ICON`=6, `CX_WG_HIT`=7.

`CX_WG_ICON` and `CX_WG_HIT` are documented in full further down — see
[Icons](#icons) and, especially,
[Hit regions — build your own widgets (`WG_HIT`)](#hit-regions--build-your-own-widgets-wg_hit),
the toolkit's mechanism for a widget the kernel didn't have to invent.

### Font style flags

`CX_BOLD`=1, `CX_UNDER`=2 (combine with `|`).

### Theme role colours (palette indices)

`CX_PAPER`=0 (background), `CX_HI`=1 (highlight fill), `CX_FRAME`=3 (borders).
A `cx_theme()` swap changes the RGB behind an index, never the index, so
drawing with these recolours automatically. Index 2 has no role name.

### Keys (PETSCII, as `EV_KEY` delivers them)

A `CX_ET_KEY` event carries the key in `ev.detail` as a PETSCII code. These
are the named non-printable ones an app usually tests for; printable keys
arrive as their plain ASCII/PETSCII value (`'a'`, `'1'`, …).

| constant | value | key | typical use |
|---|---|---|---|
| `CX_K_ENTER` | `$0D` | RETURN | confirm / activate the focused control |
| `CX_K_ESC` | `$1B` | ESC | cancel / quit / dismiss a dialog |
| `CX_K_TAB` | `$09` | TAB | move focus to the next widget |
| `CX_K_BTAB` | `$18` | shift-TAB | move focus to the previous widget |
| `CX_K_DEL` | `$14` | DEL / backspace | erase the character before the caret |
| `CX_K_UP` | `$91` | cursor up | move up a list / menu |
| `CX_K_DOWN` | `$11` | cursor down | move down a list / menu |
| `CX_K_LEFT` | `$9D` | cursor left | step left / switch menus |
| `CX_K_RIGHT` | `$1D` | cursor right | step right / switch menus |
| `CX_K_SPACE` | `$20` | space bar | toggle the focused checkbox / press a button |

The toolkit's own key handlers (`cx_menu_key`, `cx_wg_key`) already act on
these; the table matters when an app reads keys itself with `cx_poll`, or
wants to handle a shortcut before passing the key on.

### Painter geometry

The fixed pixel dimensions the immediate-mode
[widget painters](#immediate-mode-widget-painters) draw with, exposed as
constants so hand-laid-out code can align to them and match the kernel
toolkit's look exactly (`CX_BOX` and `CX_THUMB` mirror the kernel's own
`WG_BOX` / `WG_THUMB`).

| constant | value | what it measures |
|---|---|---|
| `CX_FONT_H` | 8 | the system font's glyph height, in pixels — the baseline for vertically centring text in a control |
| `CX_BOX` | 12 | the side of a checkbox / radio marker square |
| `CX_THUMB` | 16 | the width of a slider's draggable thumb |
| `CX_SLIDER_H` | 16 | the overall height of a slider trough |

### Audio 

The constants the audio wrappers (in the **Audio** section further down)
take.

**PSG waveforms** — the shape of a VERA PSG voice, passed to
`cx_psg_wave(voice, wave, pw)`:

| constant | value | waveform |
|---|---|---|
| `CX_WAVE_PULSE` | `$00` | pulse / square (the `pw` argument sets its width) |
| `CX_WAVE_SAW` | `$40` | sawtooth |
| `CX_WAVE_TRI` | `$80` | triangle |
| `CX_WAVE_NOISE` | `$C0` | noise |

**Panning** — where a voice sits in the stereo field, passed to
`cx_psg_vol(voice, vol, pan)`:

| constant | value | routing |
|---|---|---|
| `CX_PAN_LEFT` | `$40` | left channel only |
| `CX_PAN_RIGHT` | `$80` | right channel only |
| `CX_PAN_BOTH` | `$C0` | both channels (centred) |

**YM2151 note codes** — `CX_YM(octave, note)` packs an octave (0–7) and a
note (1–12) into the single byte `cx_ym_note(chan, code)` expects.

**PCM format** — OR these into the `cx_pcm_ctrl` byte; the low nibble is the
volume (0–15), so `0x0F` is 8-bit mono at full volume:

| constant | value | selects |
|---|---|---|
| `CX_PCM_16BIT` | `$20` | 16-bit samples (else 8-bit) |
| `CX_PCM_STEREO` | `$10` | stereo (else mono) |

### Joystick buttons 

The button bits `cx_joy(pad)` returns and a `CX_ET_JOY` event carries in its
`x` (current buttons) and `y` (which bits changed). They are **active-high**:
a set bit means pressed. Test them by ANDing the mask, e.g.
`if (buttons & CX_J_LEFT)`.

| constant | mask | button |
|---|---|---|
| `CX_J_UP` | `$0008` | D-pad up |
| `CX_J_DOWN` | `$0004` | D-pad down |
| `CX_J_LEFT` | `$0002` | D-pad left |
| `CX_J_RIGHT` | `$0001` | D-pad right |
| `CX_J_A` | `$8000` | A |
| `CX_J_B` | `$0080` | B |
| `CX_J_X` | `$4000` | X |
| `CX_J_Y` | `$0040` | Y |
| `CX_J_L` | `$2000` | left shoulder |
| `CX_J_R` | `$1000` | right shoulder |
| `CX_J_START` | `$0010` | START |
| `CX_J_SELECT` | `$0020` | SELECT |

### Graphics modes 

The canvas `cx_mode(m)` switches to (and the `mode` field
`cx_screen_info` reports):

| constant | value | canvas |
|---|---|---|
| `CX_MODE_GUI` | 0 | 640×480, 4 colours — the desktop; the only mode for the CXF fonts and desk accessories (the toolkit runs more widely — see below) |
| `CX_MODE_BMP8` | 1 | 320×240, 256 colours — for richer bitmaps and `cx_pal_*` custom palettes |
| `CX_MODE_TILE` | 2 | two hardware tile layers + sprites — for games |
| `CX_MODE_TEXT` | 3 | 80×60 text cells, 16 colours — coordinates become cells, "colour" an attribute |

### Event sources 

The bits `cx_ev_mask(sources)` uses to pick which inputs the per-frame tick
samples — mask off what you don't use to reclaim the KERNAL time it costs:

| constant | value | samples |
|---|---|---|
| `CX_EVS_MOUSE` | 1 | the mouse (an SMC round-trip each frame) |
| `CX_EVS_KEYS` | 2 | the keyboard (a `GETIN` drain each frame) |

### Tiles 

Constants for the tile mode (used with the [Tiles](#tiles-030--cx_mode_tile-only)
functions below):

| constant | meaning |
|---|---|
| `CX_TILE_IMG` | the VRAM base address of the tile-image sheet (`0x00000`); upload tiles here with `cx_vram_write` |
| `CX_CELL(index, palette)` | pack a tile index and 4-bit palette into a 2-byte map cell |
| `CX_CELL_HF` | OR into a cell to flip that tile horizontally |
| `CX_CELL_VF` | OR into a cell to flip that tile vertically |

## Sprite constants 

The values the sprite wrappers (under [Sprites](#sprites-020) further down)
take. Sprite 0 is the KERNAL mouse pointer; apps drive sprites **1–127**.

**Colour depth** — for `cx_sprite_image(s, addr, mode)`:

| constant | value | image format |
|---|---|---|
| `CX_SPR_4BPP` | `$00` | 4 bits per pixel (16 colours from a palette offset) |
| `CX_SPR_8BPP` | `$80` | 8 bits per pixel (256 colours) |

**Size codes** — the per-axis width and height for `cx_sprite_size(s, w, h, pal)`:

| constant | value | pixels |
|---|---|---|
| `CX_SPR_8` | 0 | 8 |
| `CX_SPR_16` | 1 | 16 |
| `CX_SPR_32` | 2 | 32 |
| `CX_SPR_64` | 3 | 64 |

**Z-depth** — where the sprite sits in the layer stack, for `cx_sprite_z(s, z)`
(or the low bits of `cx_sprite_flags`). This is also how you show or hide a
sprite:

| constant | value | placement |
|---|---|---|
| `CX_SPR_HIDE` | `$00` | not drawn (hidden) |
| `CX_SPR_BEHIND` | `$04` | behind both bitmap/tile layers |
| `CX_SPR_MIDDLE` | `$08` | between layer 0 and layer 1 |
| `CX_SPR_FRONT` | `$0C` | in front of everything |

**Flips** — OR into `cx_sprite_flags(s, flags)` to mirror the image:

| constant | value | effect |
|---|---|---|
| `CX_SPR_HFLIP` | `$01` | flip horizontally |
| `CX_SPR_VFLIP` | `$02` | flip vertically |

**Image region** — `CX_SPR_VRAM` (`$1E000`) is the 4 KB block of VRAM the
desktop reserves for app sprite images. Upload 32-byte-aligned image data
here with `cx_vram_write`, then point a sprite at it.

---

## System

| function | purpose |
|---|---|
| `cx_exit()` | end the app and reload the shell (never returns; `main` must not fall past it) |
| `cx_version()` → `unsigned` | the running kernel's ABI version |

## Screen / graphics

The same calls in every mode; a colour is 0–3, coordinates and sizes are pixels.

| function | purpose |
|---|---|
| `cx_gfx_init()` | set up the bitmap layer (once, at start) |
| `cx_clear(color)` | fill the whole screen |
| `cx_pset(x, y, color)` | plot one pixel (clipped) |
| `cx_pget(x, y)` → `color` | read a pixel's colour; `0xFF` off-screen |
| `cx_hline(x, y, len, color)` | horizontal line, `len` pixels |
| `cx_vline(x, y, len, color)` | vertical line, `len` pixels |
| `cx_rect(x, y, w, h, color)` | filled rectangle |
| `cx_frame(x, y, w, h, color)` | 1-pixel outline |
| `cx_line(x0, y0, x1, y1, color)` | an arbitrary line |
| `cx_pattern(pat8, bg, fg)` | set an 8×8 fill pattern (`pat8` = 8 bytes) |
| `cx_patrect(x, y, w, h)` | fill a rectangle with the current pattern |
| `cx_blit(x, y, wbytes, h, src, op)` | blit a packed 2bpp bitmap (`wbytes`×4 px wide, `h` rows) |
| `cx_blitm(x, y, h, cols, src)` | masked blit (transparent pixels skipped) |

```c
static const unsigned char hatch[8] = {0x88,0x44,0x22,0x11,0x88,0x44,0x22,0x11};
cx_pattern(hatch, CX_PAPER, CX_FRAME);
cx_patrect(40, 40, 160, 80);               /* a hatched fill */
```

## Text

| function | purpose |
|---|---|
| `cx_font(cxf)` → 0 ok / 1 bad | select a CXF font image |
| `cx_style(flags)` | set the text style (`CX_BOLD` \| `CX_UNDER`; 0 clears) |
| `cx_measure(s)` → `unsigned` | the pixel width `s` would draw |
| `cx_say(s, x, y)` → pen x | draw `s` at `(x,y)`; the return chains calls or places a caret |

```c
unsigned pen = cx_say("Name: ", 10, 10);
cx_say(name, pen, 10);                      /* continue on the same line */
```

## Immediate-mode widget painters

These **draw** a control so custom-layout code reads by intent; the app
hit-tests the coordinates itself (see `apps/paint`, `apps/calc`). They match
the toolkit's look and use the theme role colours, so a hand-painted control
sits beside a real one. For *interactive* widgets the kernel manages, use the
[descriptor builders](#descriptor-builders) + `cx_wg_set` instead.

| function | purpose |
|---|---|
| `cx_button(x, y, w, h, label)` | a framed button, label centred both ways |
| `cx_checkbox(x, y, label, checked)` | a marker box (filled when `checked`) + a label (this immediate-mode helper draws a box; the toolkit's `WG_RADIO` widget is round — a circle with a filled centre dot when selected) |
| `cx_slider(x, y, w, value, max)` | a trough with a thumb at `value/max` (0..max inclusive); height `CX_SLIDER_H` |
| `cx_edit(x, y, w, h, text)` | a framed field showing `text`, no caret (repaint to update) |

```c
cx_button(520, 448, 100, 24, "exit");
if (ev.type == CX_ET_DOWN && ev.x >= 520 && ev.x < 620
      && ev.y >= 448 && ev.y < 472) exit_now();   /* you hit-test */
```

## Events

The one record every poll fills:
```c
typedef struct { unsigned char type, detail; unsigned int x, y; unsigned char frame; } cx_event;
```
`type` is `CX_ET_*`. For a mouse event `x`/`y` are the point; for
`CX_ET_WIDGET`, `detail` is the widget index and `x` its value; for
`CX_ET_MENU`, `detail` is the item and `x` the menu.

| function | purpose |
|---|---|
| `cx_ev_init()` | clear the queue + hook the raster (once, **before** `cx_menu_set`/`cx_wg_set`) |
| `cx_poll(&ev)` → 1 / 0 | **raw** poll: mouse arrives as `CX_ET_DOWN`/`MOVE`/`UP`, you hit-test |
| `cx_next(&ev)` → 1 / 0 | **toolkit** poll: routes the mouse through the widget/menu regions first |
| `cx_post(&ev)` | enqueue a synthetic event (looks real to a poll) |
| `cx_timer(frames)` | post `CX_ET_TIMER` every `frames` (60/sec); 0 = off |
| `cx_frames()` → `unsigned char` | the free-running frame counter |
| `cx_ev_mask(sources)`  | which sources the tick samples (`CX_EVS_MOUSE` \| `CX_EVS_KEYS`) |
| `cx_mainloop()` | run the kernel dispatch loop forever (asm-handler apps) |
| `cx_handlers(table)` | register a `CX_ET_TYPES`-entry handler table (asm interop) |

```c
cx_event ev;                                 /* RAW: hit-test your own pixels */
for (;;) {
    if (!cx_poll(&ev)) continue;
    if (ev.type == CX_ET_KEY && ev.detail == CX_K_ESC) break;
    if (ev.type == CX_ET_DOWN) draw_at(ev.x, ev.y);
}
```
```c
cx_wg_set(&panel);                           /* TOOLKIT: cx_next routes clicks */
for (;;) {
    if (!cx_next(&ev)) continue;
    if (ev.type == CX_ET_WIDGET && ev.detail == W_EXIT) break;
    if (ev.type == CX_ET_KEY) { cx_menu_key(ev.detail); cx_wg_key(ev.detail); }
}
```

`cx_ev_mask` earns back real time: `CX_EVS_MOUSE` is an SMC round-trip and
`CX_EVS_KEYS` a `GETIN` drain, both KERNAL calls paid every frame — mask off
what you don't use (a game: `cx_ev_mask(CX_EVS_KEYS)` for keyboard + pads, no
mouse). `cx_ev_init` resets to mouse+keys; the timer, the pads
(`cx_joy_enable`) and PCM keep their own switches.

### Lending the raster line to a game 

A game owns the raster IRQ for smooth, frame-locked motion and reads input
directly, never starting the sampler. To ask the user something it borrows the
events for one modal dialog, then takes the line back.

| function | purpose |
|---|---|
| `cx_ev_raster(handler)` | install a per-frame handler on scanline 0, or 0 to remove it |
| `cx_ev_stop()` | stop the sampler and hand the raster line back to that handler |

The handler runs **inside the IRQ** — registers and the VERA address port are
saved around it, but it shares the app's zero page and soft stack, so keep it
tiny (bump a counter, poke VERA) or mark it `__attribute__((interrupt))`. It
also chains the KERNAL IRQ, so `GETIN` and the DOS keep working during play.
```c
cx_ev_raster(game_irq);          /* own the line; play, game_irq animates */
for (;;) { if (want_menu()) break; /* ... GETIN / cx_joy ... */ }
cx_ev_init();                    /* borrow: the kernel samples (irq saved) */
cx_panel(&options);              /* a modal dialog the kernel's IRQ drives  */
cx_ev_stop();                    /* the line returns to game_irq; resume    */
```
A top-of-frame handler is fully restored; a mid-screen raster split re-installs
its scanline after `cx_ev_stop`.

## Pointer

The pointer is VERA sprite 0, and mouse events are gated by `cx_ev_mask`
(the `CX_EVS_MOUSE` bit), independently of whether the pointer is shown.

| function | purpose |
|---|---|
| `cx_mouse_show(sprite)` | show the pointer (1 = the default arrow, `0xFF` = show but keep the app's own sprite-0 cursor) |
| `cx_mouse_hide()` | remove the pointer sprite but keep the mouse scanned — events keep arriving with `CX_EVS_MOUSE` |
| `cx_mouse_pointer(img, w, h, pal)` | a CUSTOM cursor: point sprite 0 at your uploaded 4bpp image (`CX_SPR_*` size codes) and show it |

A game that draws its own cursor calls `cx_mouse_hide()` and reads
`EV_MOVE`/`EV_DOWN`/`EV_UP`. A custom arrow: `cx_vram_write` a 4bpp sprite,
then `cx_mouse_pointer(addr, CX_SPR_16, CX_SPR_16, 0)`. `cx_mouse_show(1)`
restores the default arrow. See `apps/tiledlg` (a crosshair over the game).

## Menus & widgets

| function | purpose |
|---|---|
| `cx_menu_set(bar)` → 0 ok / 1 full | install + draw a menu bar (after `cx_ev_init`); owns the top strip |
| `cx_menu_off()` | forget the menu (only with none open) |
| `cx_menu_key(key)` → 1 if a menu key | drive the bar from the keyboard; **clobbers X/Y** |
| `cx_menu_active()` → 1 / 0  | is a menu dropped, by mouse **or** keyboard? |
| `cx_wg_set(list)` | install + draw a widget list; routes clicks, posts `CX_ET_WIDGET` |
| `cx_wg_draw()` | redraw the current list (e.g. after `cx_theme`) |
| `cx_wg_key(key)` → 1 if a widget key | drive widgets from the keyboard (TAB/arrows/SPACE/type); **clobbers X/Y** |

`cx_menu_active` lets an app with both a menu bar and its own widgets send the
cursor keys to a menu the user opened **by clicking** — otherwise a mouse-opened
menu is invisible and the arrows drive the wrong widget:
`if (cx_menu_active()) cx_menu_key(key); else cx_wg_key(key);`

```c
cx_ev_init();
cx_menu_set(&bar);
cx_wg_set(&panel);
/* then poll with cx_next; feed CX_ET_KEY to cx_menu_key + cx_wg_key */
```

## Icons

The kernel ships a built-in 24×24 icon sheet — the same eighteen glyphs the
desktop's file browser draws — plus `cx_icon` to blit any one of them
directly, in either bitmap mode.

| constant | id | icon |
|---|---|---|
| `CX_ICON_UP` | 0 | up one directory level |
| `CX_ICON_FOLDER` | 1 | a directory |
| `CX_ICON_APP` | 2 | an application |
| `CX_ICON_FONT` | 3 | a font |
| `CX_ICON_ACCESSORY` | 4 | a desk accessory |
| `CX_ICON_DATA` | 5 | any other file |
| `CX_ICON_IMAGE` | 6 | a picture/image |
| `CX_ICON_DISK` | 7 | a disk/volume |

Ids 8–17 are the desktop's per-app icons — 8 calc, 9 paint, 10 game, 11
text, 12 sound, 13 sprite, 14 tile, 15 term, 16 gears, 17 globe — drawn by
number (see the filer's `ICON_*` and `tools/icongen.py`); they have no named
SDK constant.

| function | purpose |
|---|---|
| `cx_icon(id, x, y)`  | draw a built-in 24×24 icon at `(x, y)`; `CX_MODE_GUI`/`CX_MODE_BMP8` only |

```c
cx_icon(CX_ICON_FOLDER, 40, 60);           /* paint one icon directly */
cx_say("Projects", 44, 88);                /* your own caption under it */
```

### As a widget (`CX_WG_ICON`)

The kernel-managed form draws the icon **and** a centred label, tracks
clicks, and — like the desktop's icon view — tells a single click from a
double: `EV_WIDGET(index, 0)` on click (select), `(index, 1)` on
double-click (open).

`cxsdk.h` has no `CX_ICON(...)` compound-literal constructor the way it does
for `CX_BUTTON`/`CX_CHECK`/etc. — the name is already taken by the ABI's
`cx_icon`/`CX_ICON` call — so build the 16-byte `cx_widget` record directly,
or define a small helper once, in the same shape as the others:

```c
#define CX_ICONW(x, y, w, h, id, lbl) \
    (cx_widget){ CX_WG_ICON, 0, (x), (y), (w), (h), (id), 0, (lbl), {0,0,0} }

CX_WIDGETS(files,
    CX_ICONW( 40, 60, 96, 66, CX_ICON_FOLDER, "Projects"),
    CX_ICONW(140, 60, 96, 66, CX_ICON_APP,    "Editor"));

cx_wg_set(&files);
/* ev.type == CX_ET_WIDGET; ev.x == 0 selects, ev.x == 1 opens */
```

See `apps/filer/filer.asm` for the real icon-grid file browser this exists
for (it builds the records at runtime, one per directory entry, rather than
as a static list — the record layout is identical either way).

## Hit regions — build your own widgets (`WG_HIT`)

Six of the seven widget types are the kernel drawing something. `CX_WG_HIT`
is the exception, and it is the most important one: **it paints nothing at
all.** You draw a shape with your own `cx_*` calls — a dial, a sprite, a
game piece, an image map over a picture you loaded — and lay an invisible
`WG_HIT` record over it. The toolkit hit-tests that record with the same
region-stack machinery already serving every button and checkbox on screen,
including true **hover** tracking. This is the sanctioned way to build a
custom widget in CXRF: the kernel does not need to know your shape, only
its box and which of three built-in tests to run against it.

### Why it earns its keep

- **Any look.** The widget can be anything you can draw — the kernel's
  contribution is purely "is the pointer inside," not pixels.
- **Real geometry, not just a bounding box.** `WG_HIT` can test a rectangle,
  a circle, or an ellipse inscribed in the box — the exact math
  `cx_circle`/`cx_ellipse` use to draw the outline, so the hit region lines
  up with what the user actually sees, not with an invisible square around it.
- **Hover for free.** No other technique in the toolkit gives you
  enter/leave tracking without polling the mouse position yourself every
  frame.
- **Zero cost when unused.** The shape math and hover state live in the
  kernel's widget bank; a click-only list, or a list with no hit region at
  all, pays nothing extra on a mouse move.

### The shape (`val`)

| constant | value | tests |
|---|---|---|
| `CX_WH_RECT` | 0 | the box itself — the default, every other widget's test |
| `CX_WH_CIRCLE` | 1 | a circle inscribed in the box — make the box square |
| `CX_WH_ELLIPSE` | 2 | an ellipse inscribed in the box |
| `CX_WH_POLYGON` | 3 | a regular *n*-gon — matches `cx_polygon` (square box) |
| `CX_WH_PIE` | 4 | a pie/arc **wedge** — matches `cx_pie`/`cx_arc` (square box) |

Circle and ellipse accept a point when, measured from the box's centre,
`(dx/rx)² + (dy/ry)² ≤ 1` (the kernel computes this in fixed point, not
floats, but that is exactly what it tests). Keep the box's width and height
each ≤ 510 px.

`CX_WH_POLYGON` and `CX_WH_PIE` are circle-based, so pass a **square box**
(centre + radius, the way `cx_polygon`/`cx_pie` draw). They take two more
numbers than the box holds — a polygon's *sides* and *rotation*, a wedge's
*start* and *end* angle (byte angles: 0 = east, 64 = south, 128 = west, 192
= north) — so they get their own builders, `CX_HIT_POLY` and `CX_HIT_PIE`,
below. An **arc** has no interior; its clickable area is the same wedge a
**pie** covers, so one `CX_WH_PIE` serves both.

### Mouse functionality — the trigger mask (`grp`)

| constant | bit | fires on |
|---|---|---|
| `CX_WH_CLICK` | `0x01` | mouse button pressed inside the shape |
| `CX_WH_RELEASE` | `0x02` | mouse button released inside the shape |
| `CX_WH_HOVER` | `0x04` | the pointer enters or leaves the shape — no button needed |

Combine bits with `|`; `grp = 0` means click-only. Every event a region is
subscribed to arrives as `CX_ET_WIDGET`: `detail` is the region's index in
the list, `x` is the **phase**:

| `ev.x` | phase |
|---|---|
| 2 | down — `CX_WH_CLICK` fired |
| 3 | up — `CX_WH_RELEASE` fired |
| 1 | hover-in: the pointer just entered |
| 0 | hover-out: the pointer just left (or left everything) |

A double-click inside the region still reports phase 2, same as a single
click — hit regions do not distinguish the two the way `CX_WG_ICON` and
`CX_WG_LIST` do.

### Building one

`cxsdk.h` provides three constructors: `CX_HIT(x, y, w, h, shape, trig)` for
the rect/circle/ellipse shapes (whose params all fit the record), and
`CX_HIT_POLY(x, y, w, h, sides, rot, trig)` / `CX_HIT_PIE(x, y, w, h, a0,
a1, trig)` for the two round shapes that carry an extra pair of numbers in
the pad. All three are plain macros, available on every compiler:

```c
#define CX_HIT(x, y, w, h, shape, trig) \
    (cx_widget){ CX_WG_HIT, 0, (x), (y), (w), (h), (shape), (trig), 0, {0,0,0} }
#define CX_HIT_POLY(x, y, w, h, sides, rot, trig) \
    (cx_widget){ CX_WG_HIT, 0, (x), (y), (w), (h), CX_WH_POLYGON, (trig), 0, {(sides),(rot),0} }
#define CX_HIT_PIE(x, y, w, h, a0, a1, trig) \
    (cx_widget){ CX_WG_HIT, 0, (x), (y), (w), (h), CX_WH_PIE, (trig), 0, {(a0),(a1),0} }
```

### Worked example — hand-drawn shapes, invisibly clickable

This mirrors the shipped ca65 demo, `apps/hittest/hittest.asm`, in C:
outlines the app draws itself, each backed by a `WG_HIT` of the matching
shape with click *and* hover both on. Hovering names the shape; clicking
stamps a dot at its centre — and the fill only ever lands where the pointer
is really inside the shape, not merely inside its bounding box, because the
toolkit did the circle/ellipse/polygon/wedge math.

```c
CX_WIDGETS(hotspots,
    CX_HIT     ( 25, 135,  90, 120, CX_WH_RECT,    CX_WH_CLICK | CX_WH_HOVER),
    CX_HIT     (150, 150,  90,  90, CX_WH_CIRCLE,  CX_WH_CLICK | CX_WH_HOVER),
    CX_HIT     (265, 153, 110,  84, CX_WH_ELLIPSE, CX_WH_CLICK | CX_WH_HOVER),
    CX_HIT_POLY(397, 147,  96,  96, 6, 0,          CX_WH_CLICK | CX_WH_HOVER),
    CX_HIT_PIE (522, 147,  96,  96, 224, 32,       CX_WH_CLICK | CX_WH_HOVER));

static const char    *names[]    = { "rectangle","circle","ellipse","hexagon","pie" };
static const unsigned centre_x[] = { 70, 195, 320, 445, 570 };  /* each shape's own centre -- */
static const unsigned centre_y[] = { 195, 195, 195, 195, 195 }; /* the app drew it, so it knows */

cx_gfx_init();  cx_clear(CX_PAPER);
cx_frame  ( 25, 135,  90, 120,     CX_FRAME);  /* the app draws the shapes; the  */
cx_circle (195, 195,  45,          CX_FRAME);  /* WG_HIT records above are laid  */
cx_ellipse(320, 195,  55,  42,     CX_FRAME);  /* over them, invisibly. POLYGON  */
cx_polygon(445, 195,  48, 6, 0,    CX_FRAME);  /* and PIE take a square box, so  */
cx_pie    (570, 195,  48, 224, 32, CX_HI);     /* the region matches the drawing */

cx_ev_init();
cx_mouse_show(1);
cx_wg_set(&hotspots);

cx_event ev;
for (;;) {
    if (!cx_next(&ev)) continue;
    if (ev.type == CX_ET_KEY && ev.detail == CX_K_ESC) break;
    if (ev.type != CX_ET_WIDGET) continue;
    if (ev.x == 1)                                  /* hover-in: name it   */
        cx_say(names[ev.detail], 24, 36);
    else if (ev.x == 2)                              /* click: stamp a dot */
        cx_disc(centre_x[ev.detail], centre_y[ev.detail], 16, CX_FRAME);
}
```

### See also

- [formats.md](formats.md#the-icon-and-hit-region-widgets-types-6-7) — the
  exact byte layout both `WG_ICON` and `WG_HIT` share with every widget.
- [sdkguide.md](sdkguide.md#hit-regions--the-widget-you-draw-yourself-wg_hit) —
  the ABI mechanics: the shape test, the far-call cost, the raw record.
- [asmsdkguide.md](asmsdkguide.md#hit-regions--build-your-own-widget-wg_hit) —
  the same feature with the `cxm_wg_hit` builder macro, for ca65 apps.
- `apps/hittest/hittest.asm` — the runnable demo this example is based on.

## Themes & dialogs

| function | purpose |
|---|---|
| `cx_theme(rec12)` | swap to a 12-byte theme; the palette changes instantly (follow with `cx_wg_draw`) |
| `cx_alert(desc)` → button | a **synchronous** modal alert; RETURN picks button 0 |
| `cx_prompt(msg, buf, cap)` → len / −1 | a **synchronous** one-line editor over `buf`; −1 if cancelled (ESC) |
| `cx_panel(desc)` → button  | a **synchronous** modal panel (box + widget list + ≤3 buttons); records update in place |

All three are synchronous — they run their own dispatch loop and return the
chosen button (`cx_panel`: 0 = confirm, last = cancel). Read a panel's or
prompt's values straight back from the descriptor/buffer afterward.

```c
if (cx_alert(&confirm) == 1) do_delete();             /* button 1 = "delete" */

char name[24] = "";
if (cx_prompt("New folder:", name, sizeof name) >= 0) make_folder(name);

if (cx_panel(&options) == 0) apply(options_widgets);  /* OK, not Cancel */
```

## Loader & desk accessories

| function | purpose |
|---|---|
| `cx_launch(name)` → reason | load + run a `.CXA`; returns **only on failure** (1 not an app, 2 too new) |
| `cx_da_open(name)` → 0 ok / 1 fail | open a `.CXD` desk accessory over the running app |
| `cx_da_close()` | close the desk accessory, restoring the screen |
| `cx_file_load(name, dst, cap)` → n / −1  | load any file into a buffer (≤ `cap` bytes; reason in `cx_a`) |
| `cx_vload(name, vbank, addr, raw)` → 0 / 1  | a file **straight into VRAM** (BASIC's `VLOAD`) |
| `cx_bload(name, bank, addr, raw)` → 0 / 1  | a file into **banked RAM** (BASIC's `BVLOAD`; banks 20+) |

`cx_file_load` is how **fonts and charsets become disk assets**; `cx_vload`
takes the raw-VRAM shape the whole X16 tool ecosystem emits (Aloevera,
X16PngConverter, TilemapEd, Tiled+tmx2vera, the GIMP plugins) behind the
standard 2-byte header (`raw = 1` for headerless); `cx_bload` gets **ZSM music**
and level data into banked RAM. Both loaders return the end address in
`cx_p[4]/[5]` (`cx_bload` the end bank in `cx_p[6]`).

```c
if (cx_file_load("MYFONT.CXF", buf, sizeof buf) > 0) cx_font(buf);  /* a font */

cx_mode(CX_MODE_TILE);
cx_vload("TILES.BIN",   0, 0x0000, 0);   /* tile images at $00000 */
cx_vload("MAP.BIN",     0, 0x8000, 0);   /* layer-0 map at $08000 */
cx_vload("PALETTE.BIN", 1, 0xFA00, 0);   /* the palette at $1FA00 */

cx_bload("SONG.ZSM", 20, 0xA000, 0);     /* banks 20+ are the app's */
```
*(Playing that ZSM is the missing half: a **zsmkit**-based player is planned but
**not in yet**. Today `cx_bload` gets it into memory; the player comes later.)*

## Directory & DOS

| function | purpose |
|---|---|
| `cx_dir_open(pattern)` → 0 / 1 | open the directory channel (`"$"` = all); 1 on a DOS error |
| `cx_dir_next(buf17)` → 0 file / 1 dir / −1 end | read the next entry name (≥17 B; the first is the volume header) |
| `cx_dir_close()` | close the directory channel |
| `cx_dos(cmd)` → status | run a CMDR-DOS command (`"S:"`, `"R:NEW=OLD"`, `"MD:"`, `"CD:"`); ≥20 = error |
| `cx_dos_msg(buf64)` → len | copy the last DOS reply (e.g. `"62,FILE NOT FOUND,00,00"`) |

```c
char nm[17];
if (!cx_dir_open("$")) {
    cx_dir_next(nm);                         /* skip the volume header */
    signed char t;
    while ((t = cx_dir_next(nm)) >= 0) { /* t: 0 file, 1 dir */ }
    cx_dir_close();
}
cx_dos("MD:PROJECTS");                       /* make a folder */
```

## Clipboard

| function | purpose |
|---|---|
| `cx_clip_put(type, src, len)` → 0 / 1 | put bytes on the clipboard (`type` 1 = TEXT; 0/len 0 empties); 1 if too big (~32 KB) |
| `cx_clip_get(dst, cap, type_out)` → n | copy the clipboard into `dst`; `type_out` (may be NULL) gets the type |
| `cx_clip_type(len_out)` → type | the waiting type (0 = empty) without consuming; `len_out` may be NULL |

```c
cx_clip_put(1, "hello", 5);
char buf[32]; unsigned char ty;
unsigned n = cx_clip_get(buf, sizeof buf, &ty);
```

## Audio 

The VERA PSG (16 voices), the YM2151 FM chip, and streamed PCM — all in a
kernel bank, reached through the ABI. See `apps/beep`.

| function | purpose |
|---|---|
| `cx_psg_init()` | silence all voices |
| `cx_psg_freq(voice, freq)` | pitch (`freq` = Hz × 2.68435, A4 = 1181) |
| `cx_psg_vol(voice, vol, pan)` | volume 0–63 and `CX_PAN_*` |
| `cx_psg_wave(voice, wave, pw)` | a `CX_WAVE_*` and pulse width |
| `cx_psg_off(voice)` | silence one voice |
| `cx_tone(voice, freq, vol)` | a one-call pulse tone |
| `cx_ym_init()` | reset + default patches (once) |
| `cx_ym_note(chan, code)` | play `CX_YM(octave, note)` on chan 0–7 (0 releases) |
| `cx_ym_off(chan)` | release the note |
| `cx_ym_vol(chan, atten)` | attenuation |
| `cx_ym_patch(chan, idx)` | load ROM instrument 0–162 |
| `cx_pcm_ctrl(ctrl)` | format/volume (`0x0F` = 8-bit mono, full) |
| `cx_pcm_play(src, len, rate)` | stream signed samples from low RAM at rate 1–128 |
| `cx_pcm_stop()` | stop |
| `cx_pcm_active()` → 1 / 0 | 1 while a sample still plays |

PCM needs `cx_ev_init` running (the FIFO is topped up each frame off the event
IRQ).

```c
cx_psg_init();  cx_tone(0, 1181, 50);                 /* A4 on voice 0 */
cx_ym_init();   cx_ym_patch(0, 1);  cx_ym_note(0, CX_YM(4, 1));
cx_pcm_ctrl(0x0F);  cx_pcm_play(sample, sizeof sample, 64);
```

## Joysticks 

Pad 0 is the keyboard joystick; 1–4 are SNES pads. Buttons are ACTIVE-HIGH
`CX_J_*` masks (UP/DOWN/LEFT/RIGHT/A/B/X/Y/L/R/START/SELECT).

| function | purpose |
|---|---|
| `cx_joy(pad)` → buttons | the pad's buttons (0 = none); `cx_c` = 1 if no physical pad |
| `cx_joy_enable(mask)` | scan the masked pads each frame, post `CX_ET_JOY`; 0 stops |

```c
cx_joy_enable(1);
if (ev.type == CX_ET_JOY && (ev.x & CX_J_LEFT)) move_left();
```

## Graphics modes 

| function | purpose |
|---|---|
| `cx_mode(m)` → carry if unknown | switch to `CX_MODE_GUI`/`BMP8`/`TILE`/`TEXT` |
| `cx_screen_info(&s)` | fill `cx_screen` (mode, w, h, bpp, stride) |
| `cx_ink(color)`  | text ink for the CURRENT mode (palette index in BMP8, attribute in TEXT) |
| `cx_pal_set(index, rgb)`  | set one VERA palette entry (`rgb` = 12-bit `0x0RGB`) |
| `cx_pal_load(src, first, count)`  | bulk-load `count` (1–128) entries from `src` |

The same drawing calls work across the bitmap modes; in `CX_MODE_TEXT`
coordinates are cells and "colour" is an attribute (`cx_clear`/`cx_rect` fill
cells, `cx_frame` draws a PETSCII box, `cx_say` prints ASCII, pixel-only calls
refuse). The **CXF font engine** (`cx_font_*`) and **desk accessories** are
GUI-only — outside mode 0 they refuse with carry, a safe no-op. The
**toolkit** — `cx_menu_*`, `cx_wg_*`, `cx_dlg_alert` / `cx_dlg_prompt` /
`cx_panel` — draws through the port, so it runs in modes 0, 1 and 3, and in
mode 2 (tiles) while a `cx_tile_text` overlay is up (widgets paint
ASCII-classic there, exactly as in text mode). `cx_say` is mode-aware too:
the CXF font in mode 0, cell text in the others. Sprites, audio, joysticks,
events, files and the shapes work in every mode; `cx_exit` always restores
the desktop. `cx_ink` is mode-local (a mode switch resets it to white).
`cx_pal_*` is handiest in `CX_MODE_BMP8`.

## Shapes  — every bitmap mode

| function | purpose |
|---|---|
| `cx_circle(cx, cy, r, color)` | an outline; clips wherever pset clips |
| `cx_disc(cx, cy, r, color)` | the same, filled; no clipping — keep it on screen |
| `cx_ellipse(cx, cy, rx, ry, color)`  | an axis-aligned ellipse outline |
| `cx_fellipse(cx, cy, rx, ry, color)` | the same, filled |
| `cx_flood(x, y, color)` → 1 if overflowed | scanline fill of the region holding the seed |
| `cx_polygon(cx, cy, r, sides, rot, color)`  | a regular convex N-gon outline (sides 3+), `rot` a byte angle |
| `cx_fpolygon(cx, cy, r, sides, rot, color)`  | the same, filled |
| `cx_arc(cx, cy, r, start, end, color)`  | a circle arc from `start` to `end` (byte angles) |
| `cx_pie(cx, cy, r, start, end, color)`  | a filled wedge over that arc |

```c
cx_disc(250, 222, 7, 220);
cx_circle(250, 222, 13, 15);
cx_flood(250, 212, 110);       /* fills the moat between them */
cx_polygon(120, 300, 60, 6, 0, 3);      /* a hexagon */
cx_pie(300, 300, 70, 0, 96, 1);         /* a 3/8 wedge (0 = east) */
```

Byte angles: 0 = east, 64 = south, 128 = west, 192 = north. The four
0.8.0 shapes share one lean ABI slot (`CX_GFX_SHAPE`, X = kind); these
wrappers pick the kind for you. `cx_shape(kind, ...)` is the raw call.

## Tiles  — CX_MODE_TILE only

Two 64×32 maps of 8×8 4bpp tiles. Upload tile pixels with
`cx_vram_write(CX_TILE_IMG + n*32, data, len)`; a cell is
`CX_CELL(index, palette)`, optionally `| CX_CELL_HF | CX_CELL_VF`.

| function | purpose |
|---|---|
| `cx_tile_setup(layer, bpp)` → carry | configure + enable a layer at `bpp` (2/4/8) |
| `cx_tile_fill(layer, cell)` | carpet the map |
| `cx_tile_cell(layer, col, row, cell)` | one cell |
| `cx_tile_scroll(layer, h, v)` | hardware scroll (a register write, nothing redrawn) |
| `cx_tile_text(layer, on)` | flip a layer to a 1bpp text overlay (`on=1`) and back (`on=0`) |
| `cx_tile_puts(layer, col, row, s, attr)` | write an ASCII string as text cells (`attr = fg\|bg<<4`) |
| `cx_vram_stream(vram_dst, bank, count)` | copy `count` bytes from banked RAM (rolling 8 KB banks) into VRAM |
| `cx_tile_load(vram_dst, first_bank, count, bpp)` | stream `count` tiles from banks into the VRAM tileset |
| `cx_tile_dbuf(layer, on)` → carry | double-buffer a layer (draws go to a hidden map) |
| `cx_tile_flip(layer)` → carry | present the drawn buffer at vblank, tear-free (needs `cx_ev_init`) |

8bpp needs the full 64 KB tileset, so its data usually lives in banked RAM
(`cx_bload` once) and streams to VRAM per level with `cx_tile_load`. See
`apps/tiles8`; the full VRAM/bank story is [remap.md](remap.md).

```c
cx_mode(CX_MODE_TILE);
cx_vram_write(CX_TILE_IMG, tiles, sizeof tiles);   /* small sets: direct */
cx_tile_setup(0, 4);                               /* 4bpp (2 / 4 / 8) */
cx_tile_fill(0, CX_CELL(0, 0));
cx_tile_scroll(0, h & 0x0FFF, 0);
```

**A pause overlay + dialogs.** `cx_tile_text(1, 1)` turns layer 1 into a
1bpp text layer over the still-visible world, then `cx_tile_text(1, 0)`
puts the game map back instantly (the map is never touched). While it is
up you can write cells directly (`cx_tile_puts`, `bg 0` = transparent), and
the whole toolkit draws here — `cx_rect`/`cx_frame`/`cx_say` in **cells**,
and the kernel's modal `cx_alert` / `cx_panel`, exactly as a desktop app:

```c
cx_ev_init();
cx_tile_text(1, 1);                 /* overlay up; the port is the text engine */
if (cx_alert(&paused) == 0) { /* Resume */ }
cx_tile_text(1, 0);                 /* the game map, untouched */
```
See `apps/tiledlg` for the full game + dialog.

## Sprites 

VERA hardware sprites. Sprite 0 is the mouse; drive sprites 1–127. Put image
data in VRAM at `CX_SPR_VRAM` (32-byte aligned) with `cx_vram_write`, point
the sprite at it, size and position it, then set flags to show it. See
`apps/sprite`.

| function | purpose |
|---|---|
| `cx_sprite_image(s, addr, mode)` | VRAM image address, `CX_SPR_4BPP`/`8BPP` |
| `cx_sprite_pos(s, x, y)` | move it |
| `cx_sprite_size(s, w, h, pal)` | `CX_SPR_8/16/32/64` per axis, palette offset |
| `cx_sprite_flags(s, flags)` | collision<<4 \| Z \| flips (a full write; before `cx_sprite_z`) |
| `cx_sprite_z(s, z)` | change only Z-depth (`CX_SPR_HIDE`/`BEHIND`/`MIDDLE`/`FRONT`) |

```c
cx_vram_write(CX_SPR_VRAM, img, sizeof img);   /* upload the pixels */
cx_sprite_image(1, CX_SPR_VRAM, CX_SPR_4BPP);
cx_sprite_size(1, CX_SPR_16, CX_SPR_16, 0);
cx_sprite_pos(1, 300, 220);
cx_sprite_flags(1, CX_SPR_FRONT);              /* show it */
```

## Dirty rectangles

| function | purpose |
|---|---|
| `cx_dirty_reset()` | clear the dirty list |
| `cx_dirty_add(x, y, w, h)` | mark a region changed |
| `cx_dirty_count()` → n | how many merged rectangles |
| `cx_dirty_get(i, &x0, &y0, &x1, &y1)` | read merged rectangle `i` (any pointer may be NULL) |

```c
cx_dirty_reset();
cx_dirty_add(10, 10, 40, 40);
for (unsigned char i = 0; i < cx_dirty_count(); i++) {
    unsigned x0,y0,x1,y1; cx_dirty_get(i, &x0,&y0,&x1,&y1);
}
```

## Utility

| function | purpose |
|---|---|
| `cx_print(s)` | CHROUT a NUL-terminated string + a return (the boot/debug marker) |
| `cx_vram_write(addr, src, len)` | copy `len` bytes from RAM into VRAM at `addr` (sprite/tile/raw uploads) |

## Picture files

Save or restore a screen rectangle to a SEQ file in one call — it streams as
native framebuffer bytes straight through VERA's data port (four 2-bit pixels a
byte), far faster than a `cx_pget`/`cx_pset` per pixel, interrupts masked
around it. **`x` and `w` must be multiples of 4**; a row is at most 640 pixels.
Device 8 (the SD).

| function | purpose |
|---|---|
| `cx_pic_save(name, x, y, w, h)` | save the `w`×`h` rect at `(x,y)` to SEQ file `name` (replaces any) |
| `cx_pic_load(name, x, y, w, h)` → rows | load it back; 0 = no file / empty |

```c
cx_pic_save("PAINT.DAT", 120, 72, 400, 288);
if (!cx_pic_load("PAINT.DAT", 120, 72, 400, 288)) show("nothing saved yet");
```

---

## Descriptor builders

The UI descriptors the kernel reads are packed byte arrays
([formats.md](formats.md)). The csdk gives them **packed struct types that
mirror those layouts exactly**, plus macros for the count-prefixed lists, so a
C app declares UI as compiler-checked data. Registering a list is one call
(`cx_wg_set`, `cx_menu_set`); the kernel draws it and posts events.

### Widgets

**`cx_widget`** — one 16-byte record:
```c
typedef struct __attribute__((packed)) {
    unsigned char type, flags;      /* CX_WG_*, bit0 = disabled */
    unsigned int  x, y, w;          /* position and width */
    unsigned char h, val, grp;      /* height; value; group/max/capacity */
    const void   *label;            /* string, field buffer, or list-of-pointers */
    unsigned char pad[3];           /* pad[0] = scroll offset for a list */
} cx_widget;
```

Per-type constructors (compound literals):

| macro | builds |
|---|---|
| `CX_BUTTON(x, y, w, h, lbl)` | a push button labelled `lbl` |
| `CX_CHECK(x, y, w, on, lbl)` | a checkbox, `on` = initial 0/1 |
| `CX_RADIO(x, y, w, on, group, lbl)` | a radio in group `group` |
| `CX_SCROLL(x, y, w, val, max)` | a horizontal scrollbar, value 0..`max` |
| `CX_FIELD(x, y, w, cap, buf)` | a text field editing `buf` (capacity `cap`) |
| `CX_LIST(x, y, w, h, count, ptrs)` | a list of `count` strings at `ptrs` |

**`CX_WIDGETS(name, ...)`** — declare a mutable widget list (a count byte then
the records; the toolkit writes state back into it):
```c
static char field[24];
static const char *rows[] = { "apple", "banana", "cherry" };

CX_WIDGETS(panel,
    CX_BUTTON(520, 448, 100, 24, "exit"),
    CX_CHECK (40, 100, 160, 1, "wrap lines"),
    CX_RADIO (40, 160, 120, 0, 1, "left"),
    CX_SCROLL(360, 116, 200, 2, 9),
    CX_FIELD (40, 290, 300, 24, field),
    CX_LIST  (360, 250, 200, 120, 3, rows));

cx_wg_set(&panel);
```

### Menus

**`cx_menu_entry`** — `{ const void *title, *items; }`, one bar entry.

- **`CX_MENU(title, items)`** — a bar entry pointing a title at a dropdown.
- **`CX_MENU_ITEMS(name, ...)`** — a dropdown: a count then a label per item.
- **`CX_MENU_BAR(name, ...)`** — the bar: a count then `CX_MENU(...)` entries.
```c
CX_MENU_ITEMS(file_items, "new", "quit");
CX_MENU_ITEMS(theme_items, "day", "night");
CX_MENU_BAR(bar,
    CX_MENU("File",   &file_items),
    CX_MENU("Themes", &theme_items));

cx_ev_init();
cx_menu_set(&bar);
/* a pick arrives as CX_ET_MENU: ev.detail = item, ev.x = menu */
```

### Dialogs

**`CX_DIALOG(name, message, ...buttons)`** — an alert/prompt descriptor: a
message and one or more button labels. Pass to `cx_alert` (returns the button
index).
```c
CX_DIALOG(about,   "CXRF -- a C app", "ok");
CX_DIALOG(confirm, "delete it?", "keep", "delete");

if (cx_alert(&confirm) == 1) do_delete();
```

### Themes

**`cx_theme_rec`** — a 12-byte theme:
```c
typedef struct __attribute__((packed)) {
    unsigned char pal[8];               /* 4 colours, 2 bytes each (VERA 12-bit RGB) */
    unsigned char paper, hi, frame, reserved;   /* the role indices */
} cx_theme_rec;

static const cx_theme_rec night = {
    { 0x01,0x00, 0x23,0x01, 0x56,0x03, 0xBC,0x0A }, 0, 1, 3, 0
};
cx_theme(&night);
```
Each palette colour is two little-endian bytes: byte0 = `GGGGBBBB`, byte1 =
`0000RRRR`. So `{0xFF,0x0F}` = `$0FFF` = white, `{0x00,0x00}` = black.

---

## Reference apps

- `apps/hello_c/hello.c` — the smallest example: `cx_print`, `cx_say`,
  `cx_clear`, `cx_poll`.
- `apps/calc/calc.c` — a real app: `cx_button` and `cx_say`, immediate-mode
  events via `cx_poll`.
- `apps/cdemo/cdemo.c` — the descriptor builders: a menu bar, the full widget
  set, a dialog and two themes, driven by `cx_next`.
- `apps/paint/paint.c` — mouse-drag drawing (`cx_line`/`cx_pset`/`cx_rect`) and
  `cx_pic_save`/`cx_pic_load` persistence.
- `apps/gfx8/gfx8.c`  -- 256-colour mode: the same drawing calls
  in `CX_MODE_BMP8`, plus the shapes.
- `apps/tiles/tiles.c`  -- the tile mode: upload, fill, cells,
  and hardware scrolling by keys, joystick, or drift; SPACE pauses with a
  modal dialog (`cx_tile_text` + `cx_alert`) over the still-visible world.
- `apps/tiledlg/tiledlg.c`  -- the whole toolkit on tiles: a modal
  `cx_panel` of widgets (checkbox, radios, slider, field, buttons) drawn
  over a scrolling tile game while it is paused.
- `apps/beep/beep.c`  — audio: a PSG scale, a YM note, and a PCM blip.
- `apps/sprite/sprite.c`  — a hardware sprite that follows the mouse.

## See also

- [sdkguide.md](sdkguide.md) — the low-level ABI these wrappers call.
- [formats.md](formats.md) — the exact byte layouts the descriptors mirror.
- `csdk/README.md` — the quick-start overview.
