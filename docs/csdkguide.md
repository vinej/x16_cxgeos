# CXGEOS csdk Guide — the friendly C wrapper

**Release 0.3.0** · header: `csdk/cxsdk.h`

The csdk turns the low-level [ABI](sdkguide.md) into clean, named `cx_*`
functions, a typed event record, the shared constants, immediate-mode widget
painters, and packed descriptor builders — so C apps read by intent and no one
re-derives the parameter-block plumbing.

It is **header-only**: every wrapper is `static`, so `-Os` drops the ones you
do not call. It targets **llvm-mos** (the fully-supported C toolchain).

```c
#include <cbm.h>
#include "sdk/include_llvm/cxgeos.h"   /* the generated ABI: slots + macros */
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
`CX_WG_FIELD`=4, `CX_WG_LIST`=5.

### Font style flags

`CX_BOLD`=1, `CX_UNDER`=2 (combine with `|`).

### Theme role colours (palette indices)

`CX_PAPER`=0 (background), `CX_HI`=1 (highlight fill), `CX_FRAME`=3 (borders).
A `cx_theme()` swap changes the RGB behind an index, never the index, so
drawing with these recolours automatically. Index 2 has no role name.

### Keys (PETSCII, as `EV_KEY` delivers them)

`CX_K_ENTER`=`$0D`, `CX_K_ESC`=`$1B`, `CX_K_TAB`=`$09`, `CX_K_BTAB`=`$18`
(shift-TAB), `CX_K_DEL`=`$14`, `CX_K_UP`=`$91`, `CX_K_DOWN`=`$11`,
`CX_K_LEFT`=`$9D`, `CX_K_RIGHT`=`$1D`, `CX_K_SPACE`=`$20`.

### Painter geometry

`CX_FONT_H`=8 (glyph height), `CX_BOX`=12 (checkbox marker), `CX_THUMB`=16
(slider thumb width), `CX_SLIDER_H`=16 (slider height).

### Audio *(0.2.0)*

PSG waveforms: `CX_WAVE_PULSE`=`$00`, `CX_WAVE_SAW`=`$40`, `CX_WAVE_TRI`=`$80`,
`CX_WAVE_NOISE`=`$C0`. Panning: `CX_PAN_LEFT`=`$40`, `CX_PAN_RIGHT`=`$80`,
`CX_PAN_BOTH`=`$C0`. `CX_YM(octave, note)` packs a YM note code. PCM format:
`CX_PCM_16BIT`=`$20`, `CX_PCM_STEREO`=`$10` (low nibble is volume 0–15).

### Joysticks, modes, shapes, tiles *(0.3.0)*

Joystick button masks (ACTIVE HIGH): `CX_J_UP/DOWN/LEFT/RIGHT`,
`CX_J_A/B/X/Y`, `CX_J_L/R`, `CX_J_START/SELECT`. Graphics modes:
`CX_MODE_GUI` (0), `CX_MODE_BMP8` (1), `CX_MODE_TILE` (2). Tiles:
`CX_TILE_IMG`, `CX_CELL(index, palette)`, `CX_CELL_HF`, `CX_CELL_VF`.
(The functions are in the sections further down.)

## Sprites *(0.2.0)*

Depth: `CX_SPR_4BPP`=`$00`, `CX_SPR_8BPP`=`$80`. Size codes: `CX_SPR_8`=0,
`CX_SPR_16`=1, `CX_SPR_32`=2, `CX_SPR_64`=3. Z-depth: `CX_SPR_HIDE`=`$00`,
`CX_SPR_BEHIND`=`$04`, `CX_SPR_MIDDLE`=`$08`, `CX_SPR_FRONT`=`$0C`. Flips:
`CX_SPR_HFLIP`=`$01`, `CX_SPR_VFLIP`=`$02`. `CX_SPR_VRAM`=`$1E000` is the
reserved app sprite-image region (sprite 0 is the mouse; apps use 1–127).

---

## System

**`void cx_exit(void)`** — end the app and reload the shell. Never returns;
`main` must not fall past it.
```c
cx_exit();
```

**`unsigned cx_version(void)`** — the running kernel's ABI version.
```c
if (cx_version() < 1) { /* too old */ }
```

## Screen / graphics

All take a colour 0–3. Coordinates and sizes are in pixels.

**`void cx_gfx_init(void)`** — set up the bitmap layer. Call once at start.

**`void cx_clear(unsigned char color)`** — fill the whole screen.
```c
cx_gfx_init();
cx_clear(CX_PAPER);
```

**`void cx_pset(unsigned x, unsigned y, unsigned char color)`** — plot one
pixel (clipped to the screen).

**`unsigned char cx_pget(unsigned x, unsigned y)`** — read a pixel's colour;
returns `0xFF` if off-screen.
```c
cx_pset(100, 50, CX_FRAME);
unsigned char c = cx_pget(100, 50);        /* -> 3 */
```

**`void cx_hline(unsigned x, unsigned y, unsigned len, unsigned char color)`**
**`void cx_vline(unsigned x, unsigned y, unsigned len, unsigned char color)`**
— axis-aligned lines `len` pixels long.
```c
cx_hline(10, 10, 200, CX_FRAME);
cx_vline(10, 10, 100, CX_FRAME);
```

**`void cx_rect(unsigned x, unsigned y, unsigned w, unsigned h, unsigned char color)`**
— filled rectangle.

**`void cx_frame(unsigned x, unsigned y, unsigned w, unsigned h, unsigned char color)`**
— 1-pixel rectangle outline.
```c
cx_rect(20, 20, 120, 60, CX_PAPER);        /* fill */
cx_frame(20, 20, 120, 60, CX_FRAME);       /* border */
```

**`void cx_line(unsigned x0, unsigned y0, unsigned x1, unsigned y1, unsigned char color)`**
— an arbitrary line.
```c
cx_line(0, 0, 320, 240, CX_FRAME);
```

**`void cx_pattern(const void *pat8, unsigned char bg, unsigned char fg)`** —
set an 8×8 fill pattern (`pat8` = 8 bytes) with background/foreground colours.

**`void cx_patrect(unsigned x, unsigned y, unsigned w, unsigned h)`** — fill a
rectangle with the current pattern.
```c
static const unsigned char hatch[8] = {0x88,0x44,0x22,0x11,0x88,0x44,0x22,0x11};
cx_pattern(hatch, CX_PAPER, CX_FRAME);
cx_patrect(40, 40, 160, 80);
```

**`void cx_blit(unsigned x, unsigned y, unsigned char wbytes, unsigned char h, const void *src, unsigned char op)`**
— blit a packed 2bpp bitmap `wbytes`×4 pixels wide, `h` rows, `op` = blit
operation.

**`void cx_blitm(unsigned x, unsigned y, unsigned char h, unsigned char cols, const void *src)`**
— masked blit (transparent pixels skipped).

## Text

**`char cx_font(const void *cxf)`** — select a CXF font image; returns 0 on
success, 1 if it was rejected.

**`void cx_style(unsigned char flags)`** — set the text style, e.g.
`cx_style(CX_BOLD | CX_UNDER)` or `cx_style(0)` to clear.

**`unsigned cx_measure(const char *s)`** — the pixel width `s` would draw.

**`unsigned cx_say(const char *s, unsigned x, unsigned y)`** — draw `s` at
`(x,y)`; returns the pen x just past the text (chain calls, or place a caret).
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

**`void cx_button(unsigned x, unsigned y, unsigned w, unsigned h, const char *label)`**
— a framed button with its label centred both ways.
```c
cx_button(520, 448, 100, 24, "exit");
if (ev.type == CX_ET_DOWN && ev.x >= 520 && ev.x < 620
      && ev.y >= 448 && ev.y < 472) exit_now();   /* you hit-test */
```

**`void cx_checkbox(unsigned x, unsigned y, const char *label, unsigned char checked)`**
— a marker box (filled when `checked`) with a label to its right. (Radios look
the same in this toolkit; manage the group's exclusivity yourself.)
```c
cx_checkbox(40, 100, "wrap lines", wrap_on);
```

**`void cx_slider(unsigned x, unsigned y, unsigned w, unsigned char value, unsigned char max)`**
— a trough with a thumb at `value/max` (0..max inclusive: a 1–10 slider passes
`value` 0–9, `max` 9). Height is `CX_SLIDER_H`.
```c
cx_slider(360, 116, 200, 2, 9);            /* shows 3 of 1..10 */
```

**`void cx_edit(unsigned x, unsigned y, unsigned w, unsigned h, const char *text)`**
— a framed field showing `text`, left-aligned and vertically centred. No caret
(the app owns the text; repaint to update it).
```c
cx_edit(40, 290, 300, 24, buffer);
```

## Events

**`typedef struct { unsigned char type; unsigned char detail; unsigned int x, y; unsigned char frame; } cx_event;`**
The one record every poll fills. For a mouse event `x`/`y` are the point; for
`CX_ET_WIDGET`, `detail` is the widget index and `x` its value; for
`CX_ET_MENU`, `detail` is the item and `x` the menu.

**`void cx_ev_init(void)`** — clear the queue and hook the raster. Call once,
**before** `cx_menu_set`/`cx_wg_set` (it resets the region stack).

**`char cx_poll(cx_event *ev)`** — **raw** poll: fills `*ev`, returns 1 if an
event was waiting, 0 if idle. Mouse events arrive as `CX_ET_DOWN`/`MOVE`/`UP`
for an app that hit-tests its own pixels. Hides the carry a raw C call cannot
see.
```c
cx_event ev;
for (;;) {
    if (!cx_poll(&ev)) continue;
    if (ev.type == CX_ET_KEY && ev.detail == CX_K_ESC) break;
    if (ev.type == CX_ET_DOWN) draw_at(ev.x, ev.y);
}
```

**`char cx_next(cx_event *ev)`** — **toolkit** poll: like `cx_poll`, but first
routes every pending mouse event through the widget/menu regions, so a click
surfaces as the `CX_ET_WIDGET`/`CX_ET_MENU` the toolkit posts. This is the loop
for an app built on `cx_wg_set`/`cx_menu_set` — `cx_poll` never reaches the
widget engine.
```c
cx_wg_set(&panel);
for (;;) {
    if (!cx_next(&ev)) continue;             /* routes the mouse for you */
    if (ev.type == CX_ET_WIDGET && ev.detail == W_EXIT) break;
    if (ev.type == CX_ET_KEY) { cx_menu_key(ev.detail); cx_wg_key(ev.detail); }
}
```

**`void cx_post(const cx_event *ev)`** — enqueue a synthetic event (looks real
to a poll).

**`void cx_timer(unsigned char frames)`** — post a `CX_ET_TIMER` every `frames`
frames (60/sec); 0 = off.
```c
cx_timer(60);                               /* one tick a second */
```

**`unsigned char cx_frames(void)`** — the free-running frame counter (for
timing/animation).

**`void cx_ev_mask(unsigned char sources)`** *(0.3.2)* — choose which
sources the frame tick samples: `CX_EVS_MOUSE` (the SMC round-trip)
and/or `CX_EVS_KEYS` (the GETIN drain). Both are KERNAL calls paid every
frame, so masking off the ones you do not use gives that time back —
with both off and the pads off, the tick costs only a few cycles.
`cx_ev_init` resets to mouse+keys; the timer, the pads (`cx_joy_enable`)
and PCM keep their own switches.
```c
cx_ev_mask(CX_EVS_KEYS);       /* a game: keyboard + joypads, no mouse */
```

**`void cx_mainloop(void)`** — run the kernel dispatch loop forever (asm-handler
apps; never returns).

**`void cx_handlers(const void *table)`** — register a `CX_ET_TYPES`-entry
handler-vector table (advanced / asm interop).

## Pointer

**`void cx_mouse_show(unsigned char sprite)`** — show the pointer (1 = the
arrow). The loader hides it between apps, so show it if you want it.

**`void cx_mouse_hide(void)`** — hide the pointer.
```c
cx_mouse_show(1);
```

## Menus & widgets

**`char cx_menu_set(const void *bar)`** — install and draw a menu bar (see
[descriptor builders](#descriptor-builders)); owns the top strip. Returns 0 on
success, 1 if the region stack is full. Call after `cx_ev_init`.

**`void cx_menu_off(void)`** — forget the menu (only with none open).

**`char cx_menu_key(unsigned char key)`** — drive the bar from the keyboard
(DOWN opens, arrows walk, RETURN picks, ESC dismisses); returns 1 if it was a
menu key. **Clobbers X/Y** — never carry a register across it.

**`void cx_wg_set(const void *list)`** — install and draw a widget list; routes
its clicks and posts `CX_ET_WIDGET`.

**`void cx_wg_draw(void)`** — redraw the current list (e.g. after `cx_theme`).

**`char cx_wg_key(unsigned char key)`** — drive widgets from the keyboard
(TAB/arrows move focus, SPACE/RETURN activate, printable keys type into a
focused field); returns 1 if it was a widget key. **Clobbers X/Y.**
```c
cx_ev_init();
cx_menu_set(&bar);
cx_wg_set(&panel);
/* then poll with cx_next; feed CX_ET_KEY to cx_menu_key + cx_wg_key */
```

## Themes & dialogs

**`void cx_theme(const void *rec12)`** — swap to a 12-byte theme
(`cx_theme_rec`): four palette colours plus the paper/hi/frame role indices.
The palette changes instantly; follow with `cx_wg_draw` to recolour widgets.
```c
cx_theme(&night);
cx_wg_draw();
```

**`unsigned char cx_alert(const void *desc)`** — a **synchronous** modal alert
(see `CX_DIALOG`); returns the chosen button index. RETURN picks button 0.
```c
if (cx_alert(&confirm) == 1) do_delete();   /* button 1 = "delete" */
```

**`int cx_prompt(const char *msg, char *buf, unsigned char cap)`** — a
**synchronous** one-line editor over `buf` (seeded if non-empty), capacity
`cap`; returns the new length, or −1 if cancelled (ESC).
```c
char name[24] = "";
if (cx_prompt("New folder:", name, sizeof name) >= 0) make_folder(name);
```

## Loader & desk accessories

**`unsigned char cx_launch(const char *name)`** — load and run a `.CXA`;
computes the length itself. Returns **only on failure**: 1 = not an app, 2 =
needs a newer kernel (on success, control never comes back).
```c
unsigned char why = cx_launch("CALC.CXA");  /* returns => it refused */
```

**`char cx_da_open(const char *name)`** — open a `.CXD` desk accessory over the
running app; returns 0 on success, 1 on failure.

**`void cx_da_close(void)`** — close the desk accessory, restoring the screen.

## Directory & DOS

**`char cx_dir_open(const char *pattern)`** — open the directory channel
(e.g. `"$"` for all); returns 0 on success, 1 on a DOS error.

**`signed char cx_dir_next(char *buf17)`** — read the next entry name into
`buf17` (≥17 bytes); returns 0 (file), 1 (directory), or −1 (listing done).
The first entry is the volume header.
```c
char nm[17];
if (!cx_dir_open("$")) {
    cx_dir_next(nm);                         /* skip the volume header */
    signed char t;
    while ((t = cx_dir_next(nm)) >= 0) { /* t: 0 file, 1 dir */ }
    cx_dir_close();
}
```

**`void cx_dir_close(void)`** — close the directory channel.

**`unsigned char cx_dos(const char *cmd)`** — run a CMDR-DOS command
(`"S:F"` scratch, `"R:NEW=OLD"` rename, `"MD:D"`, `"CD:D"`, …); returns the
status code (≥20 is an error), computing the length itself.
```c
cx_dos("MD:PROJECTS");                       /* make a folder */
```

**`unsigned char cx_dos_msg(char *buf64)`** — copy the last DOS reply
(e.g. `"62,FILE NOT FOUND,00,00"`) into `buf64` (≥64 bytes); returns its length.

## Clipboard

**`char cx_clip_put(unsigned char type, const void *src, unsigned len)`** — put
`len` bytes on the clipboard (`type` 1 = TEXT; 0 or `len` 0 empties it);
returns 0 on success, 1 if too big (~32KB fits).

**`unsigned cx_clip_get(void *dst, unsigned cap, unsigned char *type_out)`** —
copy the clipboard into `dst` (up to `cap`); returns the length copied and, via
`type_out` (may be NULL), the type.

**`unsigned char cx_clip_type(unsigned *len_out)`** — the waiting type (0 =
empty) without consuming; `len_out` (may be NULL) receives its length.
```c
cx_clip_put(1, "hello", 5);
char buf[32]; unsigned char ty;
unsigned n = cx_clip_get(buf, sizeof buf, &ty);
```

## Audio *(0.2.0)*

The VERA PSG (16 voices), the YM2151 FM chip, and streamed PCM. All three
live in a kernel bank, reached through the ABI like everything else. See
`apps/beep`.

**PSG** — `void cx_psg_init(void)` silences all voices;
`void cx_psg_freq(voice, freq)` sets pitch (`freq` = Hz × 2.68435, A4 = 1181);
`void cx_psg_vol(voice, vol, pan)` sets volume 0–63 and `CX_PAN_*`;
`void cx_psg_wave(voice, wave, pw)` sets a `CX_WAVE_*` and pulse width;
`void cx_psg_off(voice)` silences one voice.
`void cx_tone(voice, freq, vol)` is a one-call pulse tone.
```c
cx_psg_init();
cx_tone(0, 1181, 50);            /* A4 on voice 0 */
/* ...hold for a while... */  cx_psg_off(0);
```

**YM (FM)** — `void cx_ym_init(void)` (once); `void cx_ym_note(chan, code)`
plays `CX_YM(octave, note)` on a channel 0–7 (0 releases);
`void cx_ym_off(chan)`; `void cx_ym_vol(chan, atten)`;
`void cx_ym_patch(chan, idx)` loads ROM instrument 0–162.
```c
cx_ym_init();
cx_ym_patch(0, 1);
cx_ym_note(0, CX_YM(4, 1));      /* C, octave 4 */
```

**PCM** — needs `cx_ev_init` running (the FIFO is topped up each frame off
the event IRQ). `void cx_pcm_ctrl(ctrl)` sets format/volume (e.g. `0x0F` =
8-bit mono, full volume); `void cx_pcm_play(src, len, rate)` streams signed
sample bytes from low RAM at `rate` 1–128; `void cx_pcm_stop(void)`;
`unsigned char cx_pcm_active(void)` is 1 while playing.
```c
cx_pcm_ctrl(0x0F);
cx_pcm_play(sample, sizeof sample, 64);
```

## Joysticks *(0.3.0)*

Pad 0 is the keyboard joystick; 1-4 are SNES pads. Buttons are ACTIVE
HIGH `CX_J_*` masks (UP/DOWN/LEFT/RIGHT/A/B/X/Y/L/R/START/SELECT).

**`unsigned cx_joy(unsigned char pad)`** -- the pad's buttons (0 = none);
after the call `cx_c` is 1 if no physical pad is plugged in (pad 0's
keyboard data stays valid regardless).
**`void cx_joy_enable(unsigned char mask)`** -- scan the masked pads each
frame and post `CX_ET_JOY` on any change; 0 stops.
```c
cx_joy_enable(1);
if (ev.type == CX_ET_JOY && (ev.x & CX_J_LEFT)) move_left();
```

## Graphics modes *(0.3.0)*

**`char cx_mode(unsigned char m)`** -- switch to `CX_MODE_GUI` (0),
`CX_MODE_BMP8` (1: 320x240, colours 0-255), `CX_MODE_TILE` (2) or
`CX_MODE_TEXT` (3: 80x60 text cells, 16 colours -- coordinates are
cells, "colour" a text attribute. `cx_clear`/`cx_rect` fill cells and
set the paper; `cx_frame` draws a real box in the PETSCII frame glyphs;
`cx_hline`/`cx_vline` are ruled lines, and `cx_line` works for
horizontal/vertical runs (diagonals refuse); `cx_say` prints mixed-case
ASCII. The pixel-only calls refuse).
The same drawing calls work across the bitmap modes. The toolkit and fonts
(`cx_say`, `cx_measure`, `cx_wg_*`, `cx_menu_*`, dialogs, DAs) are
GUI-only: outside mode 0 they refuse with carry (`cx_c`) and do nothing,
so a stray call is a safe no-op, not a crash. Sprites, audio, joysticks,
events, files, and the shapes work in every mode. `cx_exit` always
restores the desktop.
**`void cx_screen_info(cx_screen *s)`** -- mode, w, h, bpp, stride: how
`cx_pic_*` (and your code) adapt to any canvas. See
[graphics-port.md](graphics-port.md).

## Shapes *(0.3.0)* -- every bitmap mode

**`void cx_circle(unsigned cx, unsigned cy, unsigned char r, unsigned char color)`**
-- an outline; clips wherever pset clips.
**`void cx_disc(...)`** -- the same, filled; no clipping, keep it on screen.
**`void cx_ellipse(unsigned cx, unsigned cy, unsigned char rx, unsigned char ry, unsigned char color)`**
*(0.3.1)* -- an axis-aligned ellipse outline; clips wherever pset clips.
**`void cx_fellipse(...)`** -- the same, filled; no clipping.
**`char cx_flood(unsigned x, unsigned y, unsigned char color)`** --
scanline fill of the region containing the seed; returns 1 if the seed
stack overflowed on a very tortured region.
```c
cx_disc(250, 222, 7, 220);
cx_circle(250, 222, 13, 15);
cx_flood(250, 212, 110);       /* fills the moat between them */
cx_fellipse(70, 222, 22, 9, 175);
cx_ellipse(70, 222, 28, 13, 15);
```

## Tiles *(0.3.0)* -- CX_MODE_TILE only

Two 64x32 maps of 8x8 4bpp tiles. Upload tile pixels with
`cx_vram_write(CX_TILE_IMG + n*32, data, len)`; a cell is
`CX_CELL(index, palette)`, optionally `| CX_CELL_HF | CX_CELL_VF`.

**`char cx_tile_setup(unsigned char layer)`** -- configure + enable a layer.
**`void cx_tile_fill(unsigned char layer, unsigned cell)`** -- carpet the map.
**`void cx_tile_cell(unsigned char layer, unsigned char col, unsigned char row, unsigned cell)`** -- one cell.
**`void cx_tile_scroll(unsigned char layer, unsigned h, unsigned v)`** --
hardware scroll: a register write, nothing redrawn.
```c
cx_mode(CX_MODE_TILE);
cx_vram_write(CX_TILE_IMG, tiles, sizeof tiles);
cx_tile_setup(0);
cx_tile_fill(0, CX_CELL(0, 0));
cx_tile_scroll(0, h & 0x0FFF, 0);
```

## Sprites *(0.2.0)*

VERA hardware sprites. Sprite 0 is the mouse; drive sprites 1–127. Put image
data in VRAM at `CX_SPR_VRAM` (32-byte aligned) with `cx_vram_write`, point
the sprite at it, size and position it, then set flags to show it. See
`apps/sprite`.

- `void cx_sprite_image(s, addr, mode)` — VRAM image address, `CX_SPR_4BPP`/`8BPP`.
- `void cx_sprite_pos(s, x, y)` — move it.
- `void cx_sprite_size(s, w, h, pal)` — `CX_SPR_8/16/32/64` per axis, palette offset.
- `void cx_sprite_flags(s, flags)` — collision<<4 \| Z \| `CX_SPR_VFLIP` \| `CX_SPR_HFLIP` (a full write; do once before `cx_sprite_z`).
- `void cx_sprite_z(s, z)` — change only Z-depth: `CX_SPR_HIDE`/`BEHIND`/`MIDDLE`/`FRONT`.
```c
cx_vram_write(CX_SPR_VRAM, img, sizeof img);   /* upload the pixels */
cx_sprite_image(1, CX_SPR_VRAM, CX_SPR_4BPP);
cx_sprite_size(1, CX_SPR_16, CX_SPR_16, 0);
cx_sprite_pos(1, 300, 220);
cx_sprite_flags(1, CX_SPR_FRONT);              /* show it */
```

## Dirty rectangles

**`void cx_dirty_reset(void)`** — clear the dirty list.
**`void cx_dirty_add(unsigned x, unsigned y, unsigned w, unsigned h)`** — mark a
region changed.
**`unsigned char cx_dirty_count(void)`** — how many merged rectangles.
**`void cx_dirty_get(unsigned char i, unsigned *x0, unsigned *y0, unsigned *x1, unsigned *y1)`**
— read merged rectangle `i` (any pointer may be NULL).
```c
cx_dirty_reset();
cx_dirty_add(10, 10, 40, 40);
for (unsigned char i = 0; i < cx_dirty_count(); i++) {
    unsigned x0,y0,x1,y1; cx_dirty_get(i, &x0,&y0,&x1,&y1);
}
```

## Utility

**`void cx_print(const char *s)`** — CHROUT a NUL-terminated string plus a
carriage return, through the KERNAL — the boot/debug marker every app prints.
```c
cx_print("MYAPP UP");
```

## Picture files

Save or restore a screen rectangle to a SEQ file in one call. The rectangle
streams as native framebuffer bytes straight through VERA's data port (four
2-bit pixels a byte), far faster than a `cx_pget`/`cx_pset` per pixel.
Interrupts are masked around the transfer. **`x` and `w` must be multiples of
4**; a row is at most 640 pixels. Device 8 (the SD).

**`void cx_pic_save(const char *name, unsigned x, unsigned y, unsigned w, unsigned h)`**
— save the `w`×`h` rectangle at `(x,y)` to SEQ file `name` (replacing any
existing one).

**`unsigned cx_pic_load(const char *name, unsigned x, unsigned y, unsigned w, unsigned h)`**
— load `name` back into the rectangle; returns the number of rows restored
(0 = no file / empty).
```c
cx_pic_save("PAINT.DAT", 120, 72, 400, 288);
if (!cx_pic_load("PAINT.DAT", 120, 72, 400, 288)) show("nothing saved yet");
```

**`void cx_vram_write(unsigned long addr, const void *src, unsigned len)`**
*(0.2.0)* — copy `len` bytes from RAM into VRAM at `addr`, through VERA's
auto-incrementing data port. For uploading sprite images (to `CX_SPR_VRAM`),
tiles, or any raw VRAM.

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
CX_DIALOG(about,   "CXGEOS -- a C app", "ok");
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
- `apps/gfx8/gfx8.c` *(0.3.0)* -- 256-colour mode: the same drawing calls
  in `CX_MODE_BMP8`, plus the shapes.
- `apps/tiles/tiles.c` *(0.3.0)* -- the tile mode: upload, fill, cells,
  and hardware scrolling by keys, joystick, or drift.
- `apps/beep/beep.c` *(0.2.0)* — audio: a PSG scale, a YM note, and a PCM blip.
- `apps/sprite/sprite.c` *(0.2.0)* — a hardware sprite that follows the mouse.

## See also

- [sdkguide.md](sdkguide.md) — the low-level ABI these wrappers call.
- [formats.md](formats.md) — the exact byte layouts the descriptors mirror.
- `csdk/README.md` — the quick-start overview.
