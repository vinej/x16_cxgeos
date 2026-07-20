# CXGEOS SDK Guide — the generated ABI header

**Release 0.7.1** · ABI version 1 · 100 slots (append-only; slot 99
`cx_menu_active` added in 0.7.1)

This documents `sdk/include_<compiler>/cxgeos.h` (and `.inc`) — the
**generated**, low-level binding to the kernel. It is what every CXGEOS app
ultimately calls. Most developers prefer a friendly layer over it —
[csdk](csdkguide.md) for C, [asmsdk](asmsdkguide.md) for ca65 assembly — but
both are written *against* this binding, so understanding it explains what they
do under the hood.

The header is generated from `abi/cxgeos.abi` by `abi/gen_bindings.py`; do not
edit it by hand. There is one per toolchain (`include_llvm`, `include_ca65`,
`include_acme`, …). **llvm-mos** is the fully-supported C target and the one
described here; the other C headers are partial stubs today (a bare `cx_call`,
no A/X passing).

---

## How a call works

An app never links kernel code. The kernel is already in memory; you call it
through a table of `JMP`s at a fixed address. Arguments go in a **parameter
block** — eight bytes plus the CPU registers — and each ABI entry is a
`#define` for that call's jump-table address.

```c
#include <cbm.h>
#include "sdk/include_llvm/cxgeos.h"

cx_p[0] = 100; cx_p[1] = 0;      /* x = 100  (low, high) */
cx_p[2] = 50;  cx_p[3] = 0;      /* y = 50 */
cx_call_a(CX_GFX_PSET, 3);       /* plot one pixel in colour 3 */
```

### The mirror block (llvm-mos)

The kernel's real block lives at zero-page `$22`. On llvm-mos that collides
with the compiler's own soft-stack pointer, so this header exposes a **mirror**
in ordinary memory and copies it across the real block inside `cx_run()`:

| symbol | type | meaning |
|---|---|---|
| `cx_p[0..7]` | `volatile unsigned char` | the eight parameter bytes (16-bit values are low then high, e.g. x in `cx_p[0]`/`cx_p[1]`) |
| `cx_a`, `cx_x`, `cx_y` | `volatile unsigned char` | the A/X/Y registers going in; `cx_a`/`cx_x` also carry the result out |
| `cx_c` | `volatile unsigned char` | the **carry** flag coming back (1 = set) — a 6502 result C otherwise cannot see |
| `cx_slot` | `volatile unsigned int` | the jump-table address to call; set by the macros |

`cx_run()` is the crossing itself: it parks the slot address, saves `$22–$25`
**and the compiler's whole imaginary-register file at `$02–$21`** on the
hardware stack, copies the mirror into the real block, loads A/X/Y, `jsr`s the
slot, then copies the block, A, X and carry back out. The `$02–$21` save
matters: llvm-mos's registers are the KERNAL's own r0–r15, and any slot that
reaches the KERNAL (the text mode, the loaders, the DOS glue) scribbles them.
The header also plants a constructor that moves the **C soft stack to `$8000`**
before `main` — the cx16 target's default pins it at `$9F00`, inside the
kernel's graphics port, where a mode switch would copy an engine image over
live stack frames. An event IRQ landing mid-crossing is safe — the kernel's
handler preserves `$02–$31` around itself.

### The call macros

| macro | expands to | use for |
|---|---|---|
| `cx_call(slot)` | set `cx_slot`, run | a call needing only the block (or nothing) |
| `cx_call_a(slot, a)` | load A, run | a call taking a byte in A (colour, key, flags) |
| `cx_call_ax(slot, a, x)` | load A and X, run | a call taking A and X |
| `cx_call_p(slot, ptr)` | A = low, X = high, run | a call taking a **pointer** in A/X (a string, a descriptor) |
| `cx_ret(slot)` | run, evaluate to `cx_a` | a call returning a byte in A |
| `cx_ret16(slot)` | run, evaluate to `cx_a \| cx_x<<8` | a call returning a 16-bit value in A/X |

After any call, read results back from `cx_p[]`, `cx_a`, `cx_x`, and `cx_c`.

### Worked examples of each pattern

```c
/* A-only, no result */
cx_call_a(CX_GFX_CLEAR, 2);                 /* clear to colour 2 */

/* block in, no result */
cx_p[0]=10; cx_p[1]=0; cx_p[2]=10; cx_p[3]=0;
cx_p[4]=100; cx_p[5]=0; cx_p[6]=40; cx_p[7]=0;
cx_call_a(CX_GFX_RECT, 3);                  /* rect 10,10,100,40 colour 3 */

/* pointer in A/X */
cx_call_p(CX_FONT_DRAW, "hi");              /* P0/P1 must hold x,y first */

/* byte result in A */
unsigned char col = cx_ret(CX_GFX_READ);    /* after setting P0..P3 = x,y */

/* 16-bit result in A/X */
unsigned ver = cx_ret16(CX_VERSION);

/* carry as a result */
cx_call_p(CX_FONT_SET, my_cxf);
if (cx_c) { /* the font was rejected */ }
```

### Build requirement

Compile C apps with **`-mreserve-zp=90`** — clang's whole-program pass would
otherwise claim zero page from `$26` up, which belongs to the kernel and the
app ZP convention:

```
mos-cx16-clang -Os -mreserve-zp=90 -I . -o build/MYAPP.PRG apps/myapp.c
python tools/mkcxap.py build/MYAPP.PRG build/MYAPP.CXA --name "My App"
```

### Header constants

| name | value | meaning |
|---|---|---|
| `CX_ABI_VERSION` | `1` | the ABI version these bindings were cut from |
| `CX_ABI_SLOTS` | `100` | the number of slots defined (indices 0–99) |

Query the *running* kernel's version with `cx_version` (slot 0); the loader
refuses an app whose min-ABI exceeds it.

---

## The slot reference

Each entry is a `#define` naming its jump-table address. Below, **args** are
the inputs (`Pn` = `cx_p[n]`; a 16-bit value spans `Pn/Pn+1`), and **result**
is what comes back. `carry` means `cx_c`.

### System

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 0 | `CX_VERSION` | `$8010` | → A/X = version | the running ABI version |
| 1 | `CX_EXIT` | `$8013` | — (never returns) | end the app; reloads `SHELL.CXA` |

### Screen — gfx2, 640×480 @ 2bpp (4 colours)

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 2 | `CX_GFX_INIT` | `$8016` | — | set up the bitmap layer / framebuffer |
| 3 | `CX_GFX_CLEAR` | `$8019` | A = colour 0–3 | fill the whole screen |
| 4 | `CX_GFX_PSET` | `$801C` | P0/P1=x, P2/P3=y, A=colour | plot one pixel (clipped) |
| 5 | `CX_GFX_READ` | `$801F` | P0/P1=x, P2/P3=y → A=colour | read a pixel; A=`$FF` off screen |
| 6 | `CX_GFX_HLINE` | `$8022` | P0/P1=x, P2/P3=y, P4/P5=len, A=colour | horizontal line |
| 7 | `CX_GFX_VLINE` | `$8025` | P0/P1=x, P2/P3=y, P4/P5=len, A=colour | vertical line |
| 8 | `CX_GFX_RECT` | `$8028` | P0/P1=x, P2/P3=y, P4/P5=w, P6/P7=h, A=colour | filled rectangle |
| 9 | `CX_GFX_FRAME` | `$802B` | P0/P1=x, P2/P3=y, P4/P5=w, P6/P7=h, A=colour | 1px rectangle outline |
| 10 | `CX_GFX_LINE` | `$802E` | P0/P1=x0, P2/P3=y0, P4/P5=x1, P6/P7=y1, A=colour | arbitrary line |
| 11 | `CX_GFX_PATTERN` | `$8031` | A/X=8×8 pattern, Y=(bg<<2)\|fg | set the fill pattern |
| 12 | `CX_GFX_PATRECT` | `$8034` | P0/P1=x, P2/P3=y, P4/P5=w, P6/P7=h | fill a rect with the pattern |
| 13 | `CX_GFX_BLIT` | `$8037` | P0/P1=x, P2/P3=y, P4=wbytes, P5=h, P6/P7=src, A=op | blit a bitmap |
| 14 | `CX_GFX_BLITM` | `$803A` | P0/P1=x, P2/P3=y, P4=h, P5=cols, P6/P7=src | masked blit |

### Text

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 15 | `CX_FONT_SET` | `$803D` | A/X=CXF image → carry set if bad | select a font |
| 16 | `CX_FONT_STYLE` | `$8040` | A=`CX_BOLD`\|`CX_UNDER` | set the text style |
| 17 | `CX_FONT_MEASURE` | `$8043` | A/X=string → P0/P1=width | pixel width of a string |
| 18 | `CX_FONT_DRAW` | `$8046` | P0/P1=x, P2/P3=y, A/X=string → P0/P1=pen | draw text; returns the pen x past it |
| 89 | `CX_INK` | `$811B` | A=ink for the CURRENT mode | text ink: a palette index (mode 1), an attribute 0–15 (mode 3); mode 0's ink is the theme's |

### Events

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 19 | `CX_EV_HANDLERS` | `$8049` | A/X=a table of `CX_EV_COUNT` vectors | register a handler table (asm apps) |
| 20 | `CX_EV_MAINLOOP` | `$804C` | — (never returns) | dispatch forever (asm apps) |
| 21 | `CX_EV_DISPATCH` | `$804F` | — | dispatch one event and return |
| 22 | `CX_EV_GET` | `$8052` | → P0..P7=record; carry if none | pull one raw event |
| 23 | `CX_EV_POST` | `$8055` | P0..P7=record | enqueue a synthetic event |
| 24 | `CX_EV_COUNT` | `$8058` | → A=count | records waiting |
| 25 | `CX_EV_TIMER` | `$805B` | A=frames (0 = off) | set the timer-event interval |
| 26 | `CX_EV_FRAMES` | `$805E` | → A=counter | the free-running frame counter |
| 32 | `CX_EV_INIT` | `$8070` | — | clear the queue and hook the raster (call first) |
| 54 | `CX_EV_NEXT` | `$80B2` | → P0..P7=next non-mouse event; carry if none | pull an event, routing mouse to the toolkit first |
| 87 | `CX_EV_MASK` | `$8115` | A=source mask (bit0=mouse, bit1=keys) | which sources the frame tick samples |
| 93 | `CX_EV_RASTER` | `$8127` | A/X=a per-frame handler (scanline 0), or 0 to remove | a game owns the raster IRQ; `CX_EV_INIT`/`CX_EV_STOP` save + restore it |
| 94 | `CX_EV_STOP` | `$812A` | — | stop the sampler; return the line to the `CX_EV_RASTER` handler installed before `CX_EV_INIT` |

An 8-byte event record: `P0`=type (`EV_*`), `P1`=detail (key / widget index /
menu item), `P2/P3`=x, `P4/P5`=y, `P6`=frame stamp, `P7`=0.

**Lending the IRQ to a game.** A game installs its own per-frame handler
with `CX_EV_RASTER` and reads input directly, never starting the sampler. To
show a dialog it borrows the events for the length of one modal call, then
takes the line back: `CX_EV_RASTER(game_irq)` → play → `CX_EV_INIT` →
`CX_PANEL`/`CX_DLG_ALERT` → `CX_EV_STOP`. The kernel saves the game's handler
across the borrow and returns it on scanline 0. See
[apps/gameloop/gameloop.asm](../apps/gameloop/gameloop.asm).

### Dirty rectangles

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 27 | `CX_DIRTY_RESET` | `$8061` | — | clear the dirty list |
| 28 | `CX_DIRTY_ADD` | `$8064` | P0/P1=x, P2/P3=y, P4/P5=w, P6/P7=h | mark a rectangle dirty |
| 29 | `CX_DIRTY_COUNT` | `$8067` | → A=count | how many rectangles |
| 30 | `CX_DIRTY_GET` | `$806A` | A=index → P0/P1=x0, P2/P3=y0, P4/P5=x1, P6/P7=y1 | read a merged rectangle |

### The loader

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 31 | `CX_APP_LOAD` | `$806D` | A/X=filename, Y=length; returns only on failure: carry, A=1 not an app / 2 needs a newer kernel | load and run a `.CXA` |

### Menus

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 33 | `CX_MENU_SET` | `$8073` | A/X=menu bar → carry if region stack full | install the menu bar (draws it, owns the top strip) |
| 34 | `CX_MENU_OFF` | `$8076` | — | forget the menu (only with none open) |
| 41 | `CX_MENU_KEY` | `$808B` | A=key → carry if it was a menu key | drive the bar from the keyboard; clobbers X/Y |
| 99 | `CX_MENU_ACTIVE` | `$8139` | — → A=1 if a menu is open (mouse or keyboard), Z set if none | so an app can route the cursor keys to a menu the user opened by clicking |

### The pointer

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 35 | `CX_MOUSE_SHOW` | `$8079` | A=pointer number (1=arrow), or `$FF` to show without setting | show the mouse pointer |
| 36 | `CX_MOUSE_HIDE` | `$807C` | — | hide it |

### Themes and dialogs

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 37 | `CX_THEME_SET` | `$807F` | A/X=a 12-byte theme record | swap the palette + role colours instantly |
| 38 | `CX_DLG_ALERT` | `$8082` | A/X=dialog descriptor → A=chosen button | **synchronous** modal alert; RETURN picks button 0 |
| 48 | `CX_DLG_PROMPT` | `$80A0` | A/X=message, P0/P1=buffer, P2=capacity → A=length, carry if cancelled | **synchronous** one-line editor; RETURN=ok, ESC=cancel |
| 92 | `CX_PANEL` | `$8124` | A/X=a panel descriptor → A=chosen button | **synchronous** modal panel: a box, a widget list, up to 3 buttons; widgets update in place. Modes 0/1/3 |

### Widgets

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 39 | `CX_WG_SET` | `$8085` | A/X=a widget list | install + draw a widget list; routes its clicks, posts `EV_WIDGET` |
| 40 | `CX_WG_DRAW` | `$8088` | — | redraw the current list (e.g. after a theme change) |
| 42 | `CX_WG_KEY` | `$808E` | A=key → carry if it was a widget key | drive widgets from the keyboard; clobbers X/Y |

### Hit regions — the widget you draw yourself (`WG_HIT`)

`CX_WG_SET` accepts eight widget types, and type 7 is the odd one out:
**`WG_HIT` paints nothing.** Every other type is the toolkit drawing a
control it owns; a hit region is a hotspot the *app* draws with its own
`CX_GFX_*`/`CX_ICON`/sprite calls, overlaid with an invisible record so the
same region-stack routing that serves buttons and checkboxes also serves it.
This is how a CXGEOS app gets a **custom widget** — a dial, a game piece, a
clickable sprite, an odd-shaped icon, an image map — without the kernel
knowing anything about its shape: the app owns the pixels, `WG_HIT` owns
the mouse. It is the one widget type built specifically so app authors are
not limited to the built-in set.

**Why it costs nothing.** The shape math and hover-state tracking live
entirely in bank 16 with the rest of the widget engine (`kernel/ui/widget.asm`),
reached through the exact same far-call every other widget slot already
pays for. A list with no `WG_HIT` — or one whose hit regions only ask for
`CX_WH_CLICK` — walks no extra code on a mouse move; hover tracking is
skipped wholesale unless some region in the current list asked for it.

**Geometry — `WG_VAL` (record byte 9).** Picks the shape the box is tested
against:

| `WG_VAL` | constant | test |
|---|---|---|
| 0 | `CX_WH_RECT` | the box itself — the same test every other widget uses |
| 1 | `CX_WH_CIRCLE` | a circle inscribed in the box (make the box square) |
| 2 | `CX_WH_ELLIPSE` | an ellipse inscribed in the box |

Circle and ellipse share one normalised test — from the box's centre,
`nx = |dx|·128/rx`, `ny = |dy|·128/ry`, inside when `nx²+ny² ≤ 128²` — the
same routine `CX_GFX_CIRCLE`/`CX_GFX_ELLIPSE` use to draw the outline, so a
hit region's edge lines up with the shape you actually drew. Keep the box
≤ 510 px on a side (`rx`/`ry` must each fit a byte).

**Mouse functionality — `WG_GRP` (record byte 10).** A trigger mask: which
mouse phases the region reports.

| bit | constant | fires on |
|---|---|---|
| `%001` | `CX_WH_CLICK` | button down inside the shape (the default when `WG_GRP` is 0) |
| `%010` | `CX_WH_RELEASE` | button up inside the shape |
| `%100` | `CX_WH_HOVER` | the pointer enters/leaves the shape on a plain move |

Combine bits with `|`. Every enabled trigger posts `EV_WIDGET` — `P1` = the
region's index in the list, `P2` = **phase**, reusing the raw mouse event
codes so there is no separate numbering to learn:

| `P2` | phase |
|---|---|
| 2 | down (`CX_WH_CLICK`) |
| 3 | up (`CX_WH_RELEASE`) |
| 1 | hover-in (pointer just entered) |
| 0 | hover-out (pointer just left, or left everything) |

A double-click inside the region still posts phase 2 — `WG_HIT` collapses
`EV_DBLCLICK` into a plain click, unlike the list and icon widgets, which
distinguish single from double.

**The record.** `WG_HIT` uses the same 16-byte layout as every widget
([formats.md](formats.md#the-icon-and-hit-region-widgets-types-6-7)); only
these fields differ from a visible widget:

| offset | field | for `WG_HIT` |
|---|---|---|
| 0 | type | `CX_WG_HIT` = 7 |
| 9 | val | the shape, `CX_WH_RECT`/`CIRCLE`/`ELLIPSE` |
| 10 | grp | the trigger mask, `CX_WH_CLICK`\|`RELEASE`\|`HOVER` |
| 11 | label | unused — leave it 0 |

**How to use it.** Lay one such record per hotspot into your widget list —
by hand at this ABI level, or with the one-line builders the friendly
layers add for exactly this (see [csdkguide.md](csdkguide.md#hit-regions--build-your-own-widgets-wg_hit)
for C, [asmsdkguide.md](asmsdkguide.md#hit-regions--build-your-own-widget-wg_hit)
for ca65) — draw the matching shape yourself with the graphics slots, then
call `CX_WG_SET` and read hits back from `CX_EV_NEXT`/`CX_EV_GET` like any
other `EV_WIDGET`. The desktop's icon grid ([`WG_ICON`, below](#icons--the-built-in-2424-sheet))
is built from this same record type — a hit region is simply one that draws
nothing. The runnable demo is `apps/hittest/hittest.asm`: a rectangle, a
circle and an ellipse, each an outline the app draws plus a matching
`WG_HIT` with click *and* hover on — hovering names the shape on the status
line, clicking stamps a dot at its centre, and the fill only ever lands
where the pointer is really inside the shape, not merely inside its
bounding box.

### The directory

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 43 | `CX_DIR_OPEN` | `$8091` | A/X=pattern (e.g. `"$"`), Y=length → carry on DOS error | open the directory channel |
| 44 | `CX_DIR_NEXT` | `$8094` | P0/P1=≥17-byte buffer → A=0 file / 1 dir, carry when done | read the next entry (first is the volume header) |
| 45 | `CX_DIR_CLOSE` | `$8097` | — | close the directory channel |

### The DOS command channel

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 46 | `CX_DOS_CMD` | `$809A` | A/X=command, Y=length → A=status, carry if error (≥20) | run a CMDR-DOS command (`S:F`, `R:NEW=OLD`, `MD:D`, `CD:D`, …) |
| 47 | `CX_DOS_MSG` | `$809D` | P0/P1=≥64-byte buffer → A=length | copy the last DOS reply, NUL-terminated |

### The clipboard

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 49 | `CX_CLIP_PUT` | `$80A3` | A=type (1=TEXT; 0/len 0 empties), P0/P1=src, P2/P3=len → carry if too big | put data on the clipboard (~32KB) |
| 50 | `CX_CLIP_GET` | `$80A6` | P0/P1=dst, P2/P3=cap → A=type, P2/P3=length copied | fetch the clipboard |
| 51 | `CX_CLIP_TYPE` | `$80A9` | → A=type (0=empty), P2/P3=length | peek the waiting type without consuming |

### Desk accessories

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 52 | `CX_DA_OPEN` | `$80AC` | A/X=`.CXD` name, Y=length → carry if it would not load | open a desk accessory over the running app |
| 53 | `CX_DA_CLOSE` | `$80AF` | — | close it, restoring the host's screen and handlers |

### Audio — the VERA PSG (16 voices)

Voice registers are write-only; a set is fire-and-forget. A frequency word
is Hz × 2.68435 (A4 = 440 Hz is 1181). *(Added in 0.2.0.)*

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 55 | `CX_PSG_INIT` | `$80B5` | — | silence all 16 voices |
| 56 | `CX_PSG_FREQ` | `$80B8` | X=voice (0–15), P0/P1=frequency word | set a voice's pitch |
| 57 | `CX_PSG_VOL` | `$80BB` | X=voice, A=volume (0–63), Y=pan (`$40` left/`$80` right/`$C0` both) | set volume + pan |
| 58 | `CX_PSG_WAVE` | `$80BE` | X=voice, A=waveform (`$00` pulse/`$40` saw/`$80` tri/`$C0` noise), Y=pulse width (0–63) | set waveform |
| 59 | `CX_PSG_OFF` | `$80C1` | X=voice | volume to zero (panning kept) |

### Audio — the YM2151 FM chip

Through the ROM audio driver (bank-switched). *(Added in 0.2.0.)*

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 60 | `CX_YM_INIT` | `$80C4` | — | reset the chip, load the default patches |
| 61 | `CX_YM_NOTE` | `$80C7` | A=channel (0–7), X=(octave<<4)\|note (1–12); X=0 releases | play a note (retriggers) |
| 62 | `CX_YM_OFF` | `$80CA` | A=channel | release the note |
| 63 | `CX_YM_VOL` | `$80CD` | A=channel, X=attenuation (0 = patch volume, larger = quieter) | set volume |
| 64 | `CX_YM_PATCH` | `$80D0` | A=channel, X=ROM patch index (0–162) | load an instrument |

### Sprites — VERA hardware sprites

Sprite 0 is the KERNAL mouse; apps drive 1–127 with image data in the
`$1E000` VRAM region. Image data is 32-byte aligned. *(Added in 0.2.0.)*

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 65 | `CX_SPRITE_IMAGE` | `$80D3` | X=sprite (1–127), P0=addr low, P1=mid, P2=bit 16, A=mode (0=4bpp, `$80`=8bpp) | point a sprite at its image |
| 66 | `CX_SPRITE_POS` | `$80D6` | X=sprite, P0/P1=x (0–1023), P2/P3=y | move a sprite |
| 67 | `CX_SPRITE_SIZE` | `$80D9` | X=sprite, A=width code (0=8,1=16,2=32,3=64), Y=height code, P0=palette offset | size + palette |
| 68 | `CX_SPRITE_FLAGS` | `$80DC` | X=sprite, A=collision<<4\|Z(0/4/8/`$C`)\|vflip<<1\|hflip | full write (do once before `CX_SPRITE_Z`) |
| 69 | `CX_SPRITE_Z` | `$80DF` | X=sprite, A=Z-depth only (0 hides, 4 behind, 8 middle, `$C` front) | show/hide (RMW) |
| 95 | `CX_SPR_COLLIDE` | `$812D` | → A=the collision groups seen since the last call (one bit per group, top nibble), Z if none | poll sprite collisions; arm with `CX_EV_MASK` bit 2 first. *(Added in 0.6.1.)* |

### Icons — the built-in 24×24 sheet

One 2bpp definition per icon serves both bitmap modes: mode 0 blits it, mode
1 expands each 2-bit index to an 8bpp pixel (tiles/text ignore it — `CX_ICON`
is a no-op there). The desktop's icon view and the `CX_WG_ICON` widget both
draw from this sheet (`kernel/ui/icon.asm`, built by `tools/icongen.py`); an
app can also blit an icon directly with `CX_ICON` — to badge a button, mark
a list row, or label a hit region without hand-drawing anything.

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

*(Added in 0.6.1.)*

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 96 | `CX_ICON` | `$8130` | A=icon id (0–7), P0/P1=x, P2/P3=y | draw a 24×24 icon at that pixel (modes 0 and 1) |

**As a widget.** `WG_ICON` (widget type 6, `WG_VAL` = the id above) is the
toolkit-managed form: it draws the icon with `WG_LBL` centred in text
beneath it and distinguishes select from open the way the desktop's icon
view does — a single click posts `EV_WIDGET(index, 0)`, a double-click
`EV_WIDGET(index, 1)`. It shares the same 16-byte record and the same
`CX_WG_SET` list as `WG_HIT` above — the two are siblings: one is the
kernel's own clickable icon, the other is what you reach for when the
built-in eight are not enough. See `apps/filer/filer.asm` for the icon-grid
file browser this exists for.

### Palette — VERA's 256-entry table at `$1FA00`

Program palette entries directly — most useful to a mode-1 (8bpp) app that
wants a few custom colours without loading a full 512-byte block through
`CX_VLOAD`. A 12-bit `$0RGB` colour stores as byte 0 = `Green<<4 | Blue`,
byte 1 = `Red` (so `$0F00` is pure red). The table is write-only. *(Added in
0.7.0.)*

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 97 | `CX_PAL_SET` | `$8133` | X=index (0–255), A=low (`G<<4\|B`), Y=high (`R`) | set one palette entry |
| 98 | `CX_PAL_LOAD` | `$8136` | P0/P1=source (2 B/entry, low first), A=first index, X=count (1–128) | bulk-load entries from RAM |

### PCM audio — the VERA 4 KB FIFO

Refilled each frame off the event IRQ, so `CX_EV_INIT` must be running.
The sample source is low RAM; samples are signed bytes. *(Added in 0.2.0.)*

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 70 | `CX_PCM_CTRL` | `$80E2` | A=control (volume 0–15 \| `$20` 16-bit \| `$10` stereo) | set format + volume |
| 71 | `CX_PCM_PLAY` | `$80E5` | P0/P1=source, P2/P3=byte count, A=rate (1–128, 128=48 kHz) | reset FIFO, prime, start |
| 72 | `CX_PCM_STOP` | `$80E8` | — | silence and forget the sample |
| 73 | `CX_PCM_ACTIVE` | `$80EB` | → A=1 while playing, else 0 | is a sample still playing |

### Joysticks

Button words are ACTIVE HIGH with the KERNAL's filler stripped: low byte
B/Y/SELECT/START/UP/DOWN/LEFT/RIGHT (bit 7..0), high byte A/X/L/R in bits
7:4. Pad 0 is the keyboard joystick -- its presence tracks a physical
pad, but its data is valid regardless. EV_JOY (event type 9) follows the
EV_MENU precedent: posted only after CX_JOY_ENABLE, so old handler
tables are never over-indexed. *(Added in 0.3.0.)*

| slot | name | addr | args -> result | purpose |
|---|---|---|---|---|
| 74 | `CX_JOY_GET` | `$80EE` | A=pad (0-4) -> A=buttons low, X=high; carry if absent | read a pad |
| 75 | `CX_JOY_ENABLE` | `$80F1` | A=pad mask (bit n = pad n) | scan each frame, post EV_JOY on change |

### The graphics port

The gfx slots (2-14) always target the port's entry vector; which engine
answers is the MODE -- see [graphics-port.md](graphics-port.md). Mode 0 =
640x480 @2bpp (the GUI), mode 1 = 320x240 @8bpp, mode 2 = tiles.
`CX_GFX_INIT` always lands in mode 0. *(Added in 0.3.0.)*

| slot | name | addr | args -> result | purpose |
|---|---|---|---|---|
| 76 | `CX_GFX_MODE` | `$80F4` | A=mode -> carry if unknown | swap the engine, run its init |
| 77 | `CX_GFX_INFO` | `$80F7` | -> A=mode, P0/P1=w, P2/P3=h, P4=bpp, P5/P6=stride | what canvas is this |

### Shapes -- every bitmap mode

One copy of code (bank 17 since the v0.6.0 restructure) drawing through
the port itself, so these are correct in mode 0 and mode 1 alike.
*(Added in 0.3.0.)*

| slot | name | addr | args -> result | purpose |
|---|---|---|---|---|
| 78 | `CX_GFX_CIRCLE` | `$80FA` | P0/P1=cx, P2/P3=cy, P4=r, A=colour | an outline (clips with pset) |
| 79 | `CX_GFX_DISC` | `$80FD` | same | filled; no clipping |
| 80 | `CX_GFX_FLOOD` | `$8100` | P0/P1=x, P2/P3=y, A=colour -> carry if the seed stack overflowed | scanline fill, fenced by pixels and the canvas |
| 85 | `CX_GFX_ELLIPSE` | `$810F` | P0/P1=cx, P2/P3=cy, P4=rx, P5=ry, A=colour | an axis-aligned outline (clips with pset) |
| 86 | `CX_GFX_FELLIPSE` | `$8112` | same | filled with spans; no clipping |

### Tiles -- mode 2 only

Tile images live at VRAM `$00000` (4bpp 8x8, 32 bytes each; upload with
the csdk's `cx_vram_write`); the maps are 64x32 cells at `$08000` (layer
0) / `$09000` (layer 1). All refuse with carry outside mode 2. *(Added
in 0.3.0.)*

| slot | name | addr | args -> result | purpose |
|---|---|---|---|---|
| 81 | `CX_TILE_SETUP` | `$8103` | A=layer (0/1) | ledger config + layer on |
| 82 | `CX_TILE_SCROLL` | `$8106` | A=layer, P0/P1=h, P2/P3=v | hardware scroll |
| 83 | `CX_TILE_CELL` | `$8109` | A=layer, X=col, Y=row, P0/P1=cell | one map cell |
| 84 | `CX_TILE_FILL` | `$810C` | A=layer, P0/P1=cell | the whole map |

### Asset loaders

Read a file off the SD straight into RAM, VRAM, or a banked buffer — how
fonts, charsets, bitmaps and sample data come off the disk. *(Added in 0.4.0.)*

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 88 | `CX_FILE_LOAD` | `$8118` | A/X=name, Y=len, P0/P1=dst, P2/P3=cap → carry clear, P4/P5=bytes; carry set, A=1 missing / 2 read error / 3 too big | load a file into a RAM buffer |
| 90 | `CX_VLOAD` | `$811E` | A/X=name, Y=len, P0/P1=VRAM addr, P2=VRAM bank, P3 bit0=raw → P4/P5=end; carry set, A=KERNAL error | load into VRAM |
| 91 | `CX_BLOAD` | `$8121` | A/X=name, Y=len, P0=RAM bank (20+), P1/P2=addr, P3 bit0=raw → P4/P5=end, P6=end bank; carry set, A=error | load into a banked buffer |

---

## The two event models

- **Asm apps** register a handler table (`CX_EV_HANDLERS`) and call
  `CX_EV_MAINLOOP`; the dispatcher routes mouse events to the widget/menu
  regions and calls the app's handlers.
- **C apps** poll instead, because a C function cannot serve as the asm
  callback the dispatcher invokes (the event lands in `$22`, the soft-stack
  pointer). Use `CX_EV_GET` for raw events (hit-test yourself) or **`CX_EV_NEXT`**
  for toolkit apps — it routes the mouse into the widget/menu regions for you
  and returns only the non-mouse events. The [csdk](csdkguide.md) wraps these
  as `cx_poll` and `cx_next`.

## See also

- [csdkguide.md](csdkguide.md) — the friendly C wrapper over these slots.
- [asmsdkguide.md](asmsdkguide.md) — the friendly ca65 macros over these slots.
- [p8sdkguide.md](p8sdkguide.md) — the Prog8 binding + friendly `ui` layer.
- [formats.md](formats.md) — the byte layouts of fonts, apps, menus, widgets,
  dialogs and themes.
- [memory-map.md](memory-map.md) — the ZP / RAM / VRAM ledger.
- `abi/cxgeos.abi` — the authoritative slot manifest (slots are append-only).
