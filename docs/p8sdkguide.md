# CXGEOS p8sdk Guide — Prog8 for CXGEOS

**Release 0.8.0** · ABI version 2 · binding: `sdk/include_prog8/cxgeos.p8`
(block `cx`) · friendly layer: `p8sdk/cxui.p8` (block `ui`)

Prog8 ([Irmen de Jong's structured 6502 language](https://prog8.readthedocs.io))
is a first-class CXGEOS toolchain. There are **two layers**:

- **`cx`** — the generated ABI binding: every [ABI](sdkguide.md) slot as a typed
  Prog8 call, plus the shared `cx.*` constants. This is the "normal wrappers".
- **`ui`** — the friendly p8sdk (parallel of [csdk](csdkguide.md)): immediate-mode
  widget painters, a one-call event poll, and descriptor builders.

```
%import syslib
%import cxgeos          ; the ABI binding: block cx
%import cxui            ; the p8sdk friendly layer: block ui  (optional)
%zeropage basicsafe
%option no_sysinit      ; REQUIRED — see below
%zpreserved $02,$5f     ; REQUIRED — see below
```

```
prog8c -target cx16 -srcdirs sdk\include_prog8 -srcdirs p8sdk  apps\myapp.p8
python tools\mkcxap.py build\MYAPP.PRG build\MYAPP.CXA --name "My App"
```

> **Coordinates & colours.** Positions and sizes are pixels on the 640×480
> screen. A colour is a palette index **0–3** (2bpp = 4 colours); the RGB behind
> each index comes from the active theme (`cx.theme_set`).

---

## The two rules every Prog8 CXGEOS app must follow

A Prog8 CXGEOS app is a **guest**: the kernel owns the machine and its zero
page. Two directives in your **main** program make that safe. Prog8 applies them
per-program, so they can't be inherited from the binding — every app repeats
them.

| directive | why |
|---|---|
| `%option no_sysinit` | Prog8's default startup (`init_system`) does a full machine reset — `RESTOR`, `CINT`, `IOINIT`, `mouse_config` — that tears out the live kernel IRQ and video. It looks fine on a boot autorun but **crashes the moment the desktop launches your app.** `no_sysinit` skips it; you call `cx.gfx_init` / `cx.ev_init` yourself. |
| `%zpreserved $02,$5f` | The kernel owns zero page `$02–$5F` and clobbers it on **every** API call (`kernel/resident/zp.inc`). Only `$60–$7F` is yours. Reserving `$02–$5F` keeps Prog8's variables out of that range; without it a variable there is silently corrupted by the next call. |

---

## Constants

All live in the `cx` block (`cx.ET_DOWN`, `cx.PAPER`, …).

### Event types — an event record's byte 0 (`cx.ET_*`)

| name | value | meaning |
|---|---|---|
| `cx.ET_NULL` | 0 | the queue is empty |
| `cx.ET_MOVE` | 1 | mouse moved (`mx`,`my`) |
| `cx.ET_DOWN` | 2 | mouse button pressed |
| `cx.ET_UP` | 3 | mouse button released |
| `cx.ET_DBL` | 4 | double-click |
| `cx.ET_KEY` | 5 | key (`detail` = code) |
| `cx.ET_TIMER` | 6 | the timer fired |
| `cx.ET_MENU` | 7 | menu pick (`detail` = item, `mx` = menu) |
| `cx.ET_WIDGET` | 8 | widget acted (`detail` = index, `mx` = value) |
| `cx.ET_JOY` | 9 | a pad changed (`detail` = pad, `mx` = buttons, `my` = changed); opt-in via `cx.joy_enable` |
| `cx.ET_COUNT` | 10 | the count, for a handler table |

### Widget types — a descriptor's type (`cx.WG_*`)

| name | value | widget |
|---|---|---|
| `cx.WG_BUTTON` | 0 | a push button |
| `cx.WG_CHECK` | 1 | a checkbox |
| `cx.WG_RADIO` | 2 | a radio button |
| `cx.WG_SCROLL` | 3 | a scrollbar / slider |
| `cx.WG_FIELD` | 4 | an editable text field |
| `cx.WG_LIST` | 5 | a scrolling list |
| `cx.WG_ICON` | 6 | a 24×24 icon + label |
| `cx.WG_HIT` | 7 | an invisible hit region you draw yourself |

One record is `cx.WG_SIZE` = 16 bytes.

### Hit-region shapes & triggers (`cx.WH_*`)

Shape — a `WG_HIT` record's `val`:

| name | value | shape |
|---|---|---|
| `cx.WH_RECT` | 0 | the whole rectangle |
| `cx.WH_CIRCLE` | 1 | the inscribed circle |
| `cx.WH_ELLIPSE` | 2 | the inscribed ellipse |

Trigger mask — its `grp`, combine with `|`:

| name | value | fires on |
|---|---|---|
| `cx.WH_CLICK` | 1 | a mouse press |
| `cx.WH_RELEASE` | 2 | a mouse release |
| `cx.WH_HOVER` | 4 | the pointer entering / leaving |

### Icon ids (`cx.ICON_*`)

| name | value | icon |
|---|---|---|
| `cx.ICON_UP` | 0 | up one directory level |
| `cx.ICON_FOLDER` | 1 | a directory |
| `cx.ICON_APP` | 2 | an application |
| `cx.ICON_FONT` | 3 | a font |
| `cx.ICON_ACCESSORY` | 4 | a desk accessory |
| `cx.ICON_DATA` | 5 | a data file |
| `cx.ICON_IMAGE` | 6 | an image |
| `cx.ICON_DISK` | 7 | a disk |

### Font styles, theme colours

Styles (combine with `|`):

| name | value | style |
|---|---|---|
| `cx.BOLD` | 1 | bold |
| `cx.UNDER` | 2 | underline |

Theme role colours (palette indices) — a `cx.theme_set` swap changes the RGB
behind an index, never the index, so drawing with these recolours automatically:

| name | value | role |
|---|---|---|
| `cx.PAPER` | 0 | background |
| `cx.HI` | 1 | highlight |
| `cx.FRAME` | 3 | borders |

### Keys (PETSCII, as `ET_KEY` delivers them)

Printable keys arrive as their ASCII byte; these are the named non-printable ones:

| name | value | key |
|---|---|---|
| `cx.K_ENTER` | `$0D` | RETURN |
| `cx.K_ESC` | `$1B` | ESC |
| `cx.K_TAB` | `$09` | TAB |
| `cx.K_BTAB` | `$18` | shift-TAB |
| `cx.K_DEL` | `$14` | DEL / backspace |
| `cx.K_UP` | `$91` | cursor up |
| `cx.K_DOWN` | `$11` | cursor down |
| `cx.K_LEFT` | `$9D` | cursor left |
| `cx.K_RIGHT` | `$1D` | cursor right |
| `cx.K_SPACE` | `$20` | space bar |

### Graphics modes

| name | value | canvas |
|---|---|---|
| `cx.MODE_GUI` | 0 | 640×480, 4 colours — the desktop |
| `cx.MODE_BMP8` | 1 | 320×240, 256 colours |
| `cx.MODE_TILE` | 2 | two tile layers + sprites |
| `cx.MODE_TEXT` | 3 | 80×60 text |

### Audio, joystick, sprites, tiles, event sources

| group | constants |
|---|---|
| PSG waveform (`cx.psg_wave`) | `cx.WAVE_PULSE` / `SAW` / `TRI` / `NOISE` |
| PSG pan (`cx.psg_vol`) | `cx.PAN_LEFT` / `RIGHT` / `BOTH` |
| PCM format (`cx.pcm_ctrl`) | `cx.PCM_16BIT`, `cx.PCM_STEREO` (low nibble = volume 0–15) |
| Joystick, byte mask (active high) | `cx.J_RIGHT` / `LEFT` / `DOWN` / `UP` / `START` / `SELECT` / `Y` / `B` |
| Joystick, word mask | `cx.J_R` / `L` / `X` / `A` |
| Sprite depth | `cx.SPR_4BPP` / `SPR_8BPP` |
| Sprite size (per axis) | `cx.SPR_8` / `16` / `32` / `64` |
| Sprite Z-depth | `cx.SPR_HIDE` / `BEHIND` / `MIDDLE` / `FRONT` |
| Sprite flip | `cx.SPR_HFLIP` / `SPR_VFLIP` |
| Tile cell flip | `cx.CELL_HF`, `cx.CELL_VF` |
| Painter metrics | `cx.FONT_H`=8, `cx.BOX`=12, `cx.THUMB`=16, `cx.SLIDER_H`=16 |
| Event sources (`cx.ev_mask`) | `cx.EVS_MOUSE`=1, `cx.EVS_KEYS`=2, `cx.EVS_SPRCOL`=4 |

---

## How a `cx.*` call works

Each slot is a normal Prog8 call — pass typed args, get typed returns. Under the
hood a slot is one of two kinds, and it matters only when you read a **result**:

- **Register calls** return in registers: a `uword` (e.g. `cx.version()`), a
  `ubyte` (`cx.gfx_read()`), or a `bool` from carry (`cx.gfx_flood()`).
- **Block calls** that also *return* data leave it in the `$22` parameter block.
  Read it out of `cx.pb[n]` / `cx.pbwN` **immediately**, before any array index
  or pointer deref — those reuse Prog8's SCRATCH_PTR, which lives at `$22`.

```
cx.pb[0..7]                 ; the block as 8 bytes  (P0..P7)
cx.pbw0 = $22   cx.pbw1 = $24   cx.pbw2 = $26   cx.pbw3 = $28   ; as words
```

A call that returns a value used as a statement wants `void`:
`void cx.say("hi", 10, 10)`. Multi-value returns are captured with a
multi-assign: `bool ok; ubyte code;  ok, code = cx.bload(...)`.

> **Watch the `as` cast.** Prog8's `as` binds *looser* than `+`/`*`, so
> `GX + col as uword * STEP` reparses as `(GX + col) as uword * STEP`. Widen
> through plain `uword` locals in mixed expressions instead of casting inline.

---

## System

| call | purpose |
|---|---|
| `cx.exit()` | end the app and reload the shell (never returns) |
| `cx.version() -> uword` | the running kernel's ABI version (`cx.ABI_VERSION` = built-against) |

## Screen / graphics

A colour is 0–3; coordinates and sizes are pixels. The same calls in every mode.

| call | purpose |
|---|---|
| `cx.gfx_init()` | set up the bitmap layer (once, at start) |
| `cx.gfx_clear(col)` | fill the whole screen |
| `cx.gfx_pset(x, y, col)` | plot one pixel (clipped) |
| `cx.gfx_read(x, y) -> ubyte` | read a pixel's colour; `$FF` off-screen |
| `cx.gfx_hline(x, y, len, col)` / `cx.gfx_vline(...)` | a horizontal / vertical line, `len` px |
| `cx.gfx_rect(x, y, w, h, col)` | filled rectangle |
| `cx.gfx_frame(x, y, w, h, col)` | 1-pixel outline |
| `cx.gfx_line(x0, y0, x1, y1, col)` | an arbitrary line |
| `cx.gfx_pattern(pat, bg, fg)` | set an 8×8 fill pattern (`pat` → 8 bytes) |
| `cx.gfx_patrect(x, y, w, h)` | fill a rectangle with the current pattern |
| `cx.gfx_blit(x, y, wbytes, h, src, op)` | blit a packed 2bpp bitmap |
| `cx.gfx_blitm(x, y, h, cols, src)` | masked blit (transparent pixels skipped) |

Shapes — every bitmap mode:

| call | purpose |
|---|---|
| `cx.gfx_circle(xc, yc, rad, col)` | an outline (clips with pset) |
| `cx.gfx_disc(xc, yc, rad, col)` | the same, filled (no clipping) |
| `cx.gfx_ellipse(xc, yc, rx, ry, col)` | an axis-aligned ellipse outline |
| `cx.gfx_fellipse(xc, yc, rx, ry, col)` | the same, filled |
| `cx.gfx_flood(x, y, col) -> bool` | scanline fill of the seed's region (**true = overflowed** the budget) |
| `cx.gfx_shape(kind, xc, yc, rad, p5, p6, col)` | the v0.8.0 extra shapes on one dispatched slot |

`cx.gfx_shape`'s `kind` is 0 polygon, 1 fpolygon, 2 arc, 3 pie. For a
polygon `p5` = sides (3+) and `p6` = rotation; for an arc/pie `p5` = start
and `p6` = end (byte angles: 0 = east, 64 = south, 128 = west, 192 = north).

## Text

| call | purpose |
|---|---|
| `cx.font_set(cxf) -> bool` | select a CXF font image (carry set = bad magic) |
| `cx.font_style(flags)` | text style (`cx.BOLD` \| `cx.UNDER`; 0 clears) |
| `cx.font_measure(txt) -> uword` | the pixel width `txt` would draw |
| `cx.say(txt, x, y) -> uword` | draw `txt` at `(x,y)`; returns the pen x (chains calls) |
| `cx.ink(col)` | set the text colour role |

Strings are ASCII-indexed in the CXGEOS font, so pass `iso:"..."` literals (not
Prog8's default PETSCII):

```
uword pen = cx.say(iso:"Name: ", 10, 10)
void cx.say(name, pen, 10)                  ; continue on the same line
```

## Events

`cx.ev_get` / `cx.ev_next` fill the `$22` block with a record: byte 0 = type
(`cx.ET_*`), byte 1 = detail, `cx.pbw1` = x, `cx.pbw2` = y, byte 6 = frame. Read
it out at once (or let `ui.poll` do it — see below). Carry set = the queue was
empty, so `if not cx.ev_get() { ... }` means "an event arrived".

| call | purpose |
|---|---|
| `cx.ev_init()` | clear the queue + hook the raster (once, **before** `menu_set`/`wg_set`) |
| `cx.ev_get() -> bool` | **raw** poll: mouse arrives as `ET_DOWN`/`MOVE`/`UP` (carry = empty) |
| `cx.ev_next() -> bool` | **toolkit** poll: routes the mouse through widget/menu regions first |
| `cx.ev_post()` | enqueue a synthetic event from the block |
| `cx.ev_count() -> ubyte` | how many events are waiting |
| `cx.ev_timer(frames)` | post `ET_TIMER` every `frames` (60/sec); 0 = off |
| `cx.ev_frames() -> ubyte` | the free-running frame counter |
| `cx.ev_mask(sources)` | which sources the tick samples (`cx.EVS_MOUSE`\|`cx.EVS_KEYS`) |
| `cx.ev_raster(hdlr)` | install a per-frame raster handler (a game owns the line) |
| `cx.ev_stop()` | stop the sampler / return the raster line |
| `cx.ev_mainloop()` / `cx.ev_dispatch()` | kernel dispatch loop / one dispatch (handler-table apps) |
| `cx.ev_handlers(tbl)` | register a `cx.ET_COUNT`-entry handler table |

```
repeat {
    if not cx.ev_get() {            ; raw: hit-test your own pixels
        ubyte t  = cx.pb[0]         ; read the block AT ONCE
        ubyte d  = cx.pb[1]
        uword mx = cx.pbw1
        uword my = cx.pbw2
        if t == cx.ET_KEY and d == cx.K_ESC  cx.exit()
        if t == cx.ET_DOWN  draw_at(mx, my)
    }
}
```

## Pointer, menus & widgets

| call | purpose |
|---|---|
| `cx.mouse_show(ptr)` | show the pointer (1 = the default arrow, `$FF` = show but keep your own sprite-0 cursor) |
| `cx.mouse_hide()` | remove the pointer sprite but keep the mouse scanned (events still arrive with `EVS_MOUSE`) |
| `cx.menu_set(bar) -> bool` | install + draw a menu bar (carry = region stack full) |
| `cx.menu_off()` | remove the menu bar |
| `cx.menu_key(key) -> bool` | drive the menu with a key (true = it was a menu key) |
| `cx.menu_active() -> ubyte` | 1 if a menu is open (mouse or keyboard) |
| `cx.wg_set(lst)` | install, draw + route a widget list |
| `cx.wg_draw()` | redraw the current widget list |
| `cx.wg_key(key) -> bool` | drive widget focus with a key (true = it was a widget key) |

Build the `bar` / `lst` descriptors with the `ui.*` builders below. Poll with
`cx.ev_next` (or `ui.next`) so a click surfaces as `ET_WIDGET` / `ET_MENU`.

## Themes & dialogs

| call | purpose |
|---|---|
| `cx.theme_set(rec)` | install a 12-byte theme record (see `ui.theme`) |
| `cx.dlg_alert(desc) -> ubyte` | modal alert; returns the button index pressed |
| `cx.dlg_prompt(msg, buf, cap) -> ubyte, bool` | modal text prompt into `buf` (carry = cancelled) |
| `cx.panel(desc) -> ubyte` | a modal panel (title + widget list + buttons); returns the button |

## Icons & palette

| call | purpose |
|---|---|
| `cx.icon(id, x, y)` | draw a 24×24 system icon (`cx.ICON_*`) |
| `cx.pal_set(index, rgb)` | set one palette entry (`rgb` = `$0RGB`) |
| `cx.pal_load(src, first, count)` | load `count` palette entries from `src` |

## Loader & desk accessories

| call | purpose |
|---|---|
| `cx.app_load(name, nlen) -> bool, ubyte` | load + run a `.CXA` (returns only on failure: carry, A=1 not an app / 2 too new) |
| `cx.da_open(name, nlen) -> bool` | open a desk accessory over the app (carry = fail) |
| `cx.da_close()` | close the accessory, restore the app |

## Files

Each returns `bool, ubyte` (carry set = error, A = a code); the byte count read
lands in the block (`cx.pbw2`).

| call | purpose |
|---|---|
| `cx.file_load(name, nlen, dst, cap) -> bool, ubyte` | load a file into RAM at `dst`, up to `cap` |
| `cx.vload(name, nlen, vaddr, vbank, raw) -> bool, ubyte` | load straight into VRAM |
| `cx.bload(name, nlen, bank, addr, raw) -> bool, ubyte` | load into a banked-RAM window |

## Directory & DOS

| call | purpose |
|---|---|
| `cx.dir_open(pat, nlen) -> bool` | open a directory listing (carry = DOS error) |
| `cx.dir_next(buf) -> ubyte, bool` | next entry name into `buf` (carry = listing done; A = kind) |
| `cx.dir_close()` | close the listing |
| `cx.dos_cmd(cmd, nlen) -> ubyte, bool` | send a DOS command (A = status, ≥20 = error) |
| `cx.dos_msg(buf) -> ubyte` | copy the last DOS reply into `buf`; returns its length |

## Clipboard

| call | purpose |
|---|---|
| `cx.clip_put(type, src, nlen) -> bool` | put `nlen` bytes on the clipboard (carry = fail) |
| `cx.clip_get(dst, cap) -> ubyte` | copy the clipboard into `dst`; returns the type, length in the block |
| `cx.clip_type() -> ubyte` | the type waiting (0 = empty); length in the block |

## Audio

PSG (the VERA sound chip):

| call | purpose |
|---|---|
| `cx.psg_init()` | reset all 16 voices |
| `cx.psg_freq(voice, freq)` | set a voice's frequency |
| `cx.psg_vol(voice, vol, pan)` | volume 0–63 + pan (`cx.PAN_*`) |
| `cx.psg_wave(voice, wave, pw)` | waveform (`cx.WAVE_*`) + pulse width |
| `cx.psg_off(voice)` | silence a voice |

YM2151 (FM):

| call | purpose |
|---|---|
| `cx.ym_init()` | reset the chip + load the default patches |
| `cx.ym_note(chan, code)` | play `code` on chan 0–7 (0 releases) |
| `cx.ym_off(chan)` | release the note |
| `cx.ym_vol(chan, atten)` | attenuation |
| `cx.ym_patch(chan, idx)` | load ROM instrument 0–162 |

PCM (streamed samples):

| call | purpose |
|---|---|
| `cx.pcm_ctrl(ctrl)` | format / volume bits |
| `cx.pcm_play(src, nlen, rate)` | stream signed samples from low RAM (rate 1–128) |
| `cx.pcm_stop()` | stop |
| `cx.pcm_active() -> ubyte` | 1 while a sample still plays |

## Joysticks

| call | purpose |
|---|---|
| `cx.joy_enable(mask)` | start sampling pads into the event stream (`ET_JOY`) |
| `cx.joy_get(pad) -> uword, bool` | read a pad's buttons now (`cx.J_*`; carry = not connected) |

## Graphics modes, tiles, sprites, dirty rects

Modes:

| call | purpose |
|---|---|
| `cx.gfx_mode(m) -> bool` | switch mode (carry = unknown) |
| `cx.gfx_info() -> ubyte` | A = current mode; w/h/bpp/stride follow in the block |

Tiles (`cx.MODE_TILE`):

| call | purpose |
|---|---|
| `cx.tile_setup(layer) -> bool` | configure + enable a layer |
| `cx.tile_scroll(layer, hscroll, vscroll)` | hardware scroll |
| `cx.tile_cell(layer, col, row, cell)` | one map cell |
| `cx.tile_fill(layer, cell)` | carpet the map |
| `cx.tile_text(layer, on)` | flip a layer to a 1bpp text overlay and back |

While a `cx.tile_text` overlay is up the toolkit — menus, widgets,
`cx.dlg_alert`, `cx.panel` — draws on it, over the still-visible game.

Sprites:

| call | purpose |
|---|---|
| `cx.sprite_image(spr, addr, bank, mode)` | VRAM image (17-bit addr = `uword addr` + a `bank` bit) |
| `cx.sprite_pos(spr, x, y)` | move it |
| `cx.sprite_size(spr, wcode, hcode, pal)` | size codes + palette offset |
| `cx.sprite_flags(spr, flags)` | a full write (do once before `cx.sprite_z`) |
| `cx.sprite_z(spr, z)` | change only Z-depth |
| `cx.spr_collide() -> ubyte` | collision groups seen since the last call |

Dirty rectangles:

| call | purpose |
|---|---|
| `cx.dirty_reset()` | clear the dirty list |
| `cx.dirty_add(x, y, w, h)` | mark a region changed |
| `cx.dirty_count() -> ubyte` | how many merged rectangles |
| `cx.dirty_get(idx)` | read a merged rectangle (fills the block) |

---

## The `ui` layer — the p8sdk

`%import cxui` adds the `ui` block over the raw `cx` binding: painters, a poll
helper, and descriptor builders. Prog8 links only the subs an app calls.

### Immediate-mode painters

Draw one control for a custom layout; the app hit-tests the pixels itself. They
match the toolkit's look, so a painted control sits beside a real one.

| call | purpose |
|---|---|
| `ui.button(x, y, w, h, label)` | a framed button, label centred both ways |
| `ui.checkbox(x, y, label, checked)` | a marker box (filled when `checked`) + a label |
| `ui.slider(x, y, w, value, maxv)` | a trough with a thumb at `value/maxv` (0..maxv inclusive) |
| `ui.edit(x, y, w, h, text)` | a framed field showing `text`, no caret |

```
ui.button(520, 448, 100, 24, iso:"exit")
; you hit-test: if the ET_DOWN mx/my fall in that box, quit
```

### Event poll

Pull the next event and read it out of the block into `ui.*` in one call.

| call | purpose |
|---|---|
| `ui.poll() -> bool` | **raw** poll (mouse as `ET_DOWN`/`MOVE`/`UP`); true if one waited |
| `ui.next() -> bool` | **toolkit** poll (routes clicks to `cx.wg_set`/`menu_set`) |

After a true return, read the fields: `ui.etype` (`cx.ET_*`), `ui.detail`,
`ui.mx`, `ui.my`, `ui.frame`.

```
repeat {
    if ui.poll() {
        when ui.etype {
            cx.ET_KEY -> { if ui.detail == cx.K_ESC  cx.exit() }
            cx.ET_DOWN -> click(ui.mx, ui.my)
        }
    }
}
```

### Descriptor builders

Kernel-managed widgets, menus and dialogs are byte-packed descriptors. C and asm
lay them down as static data; Prog8 builds them into an app RAM **buffer** at
startup (a byte-array literal can't embed pointers). Declare a buffer, fill it
with a builder, then hand it to the kernel. Size a widget buffer `1 + 16*N`
bytes. The builders are **stateful** — finish one list before starting another
of the same kind.

**Widgets** (`cx.wg_set`):

| call | record |
|---|---|
| `ui.wg_begin(buffer)` | start the list (count byte = 0) |
| `ui.wg_button(x, y, w, h, label)` | a button |
| `ui.wg_check(x, y, w, on, label)` | a checkbox |
| `ui.wg_radio(x, y, w, on, group, label)` | a radio in `group` |
| `ui.wg_scroll(x, y, w, val, maxv)` | a scrollbar/slider |
| `ui.wg_field(x, y, w, cap, textbuf)` | an editable text field |
| `ui.wg_icon(x, y, id, label)` | a 24×24 icon + label |
| `ui.wg_hit(x, y, w, h, shape, trig)` | an invisible hit region you draw yourself |

```
ubyte[1 + 16*2] panel
ui.wg_begin(&panel)
ui.wg_button(420, 110, 150, 34, &s_ok)
ui.wg_button(420, 160, 150, 34, &s_cancel)
cx.wg_set(&panel)
; ... later, in the loop:
if ui.next() and ui.etype == cx.ET_WIDGET {
    ; ui.detail = the widget index (0 = OK, 1 = Cancel)
}
```

**Menus** (`cx.menu_set`) — build each drop-down's item list first, then the bar:

| call | purpose |
|---|---|
| `ui.items_begin(buffer)` / `ui.item(label)` | one drop-down: a count + label pointers |
| `ui.menu_begin(buffer)` / `ui.menu(title, items)` | the bar: a count + (title, items) per menu |

**Dialogs** (`cx.dlg_alert` / `cx.panel`) & **themes** (`cx.theme_set`):

| call | purpose |
|---|---|
| `ui.dlg_begin(buffer, message)` / `ui.dlg_button(label)` | a count, the message, then button labels |
| `ui.theme(buffer, c0, c1, c2, c3, paper, hi, frame)` | four `$0RGB` colours + the role indices |

---

## Reference apps

- **`apps/calc/calc.p8`** — the calculator: `ui.button` paints the keypad,
  `ui.poll` drives the loop, Prog8 floats do the maths.
- **`apps/uidemo_prog8/uidemo.p8`** — the p8sdk showcase: the four painters on the
  left, a live `ui.wg_*` widget list (`cx.wg_set`) on the right.
- **`apps/smoke_prog8/smoke.p8`** — the minimal binding smoke test.

## See also

- [sdkguide.md](sdkguide.md) — the raw ABI (what `cx.*` calls under the hood).
- [csdkguide.md](csdkguide.md) / [asmsdkguide.md](asmsdkguide.md) — the C and
  assembler friendly layers (same shapes, other languages).
- [formats.md](formats.md) — the descriptor byte layouts the `ui.*` builders emit.
- `memory/prog8-binding-gotchas` — the hard-won Prog8 runtime rules.
