# CXGEOS SDK Guide — the generated ABI header

**Release 0.2.0** · ABI version 1 · 74 slots

This documents `sdk/include_<compiler>/cxgeos.h` — the **generated**, low-level
binding to the kernel. It is what every CXGEOS app ultimately calls. C
developers will usually prefer the friendlier [csdk](csdkguide.md) layered on
top of it, but the csdk is written *against* this header, so understanding it
explains what the csdk does under the hood.

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
on the hardware stack, copies the mirror into the real block, loads A/X/Y,
`jsr`s the slot, then copies the block, A, X and carry back out. An event IRQ
landing mid-crossing is safe — the kernel's handler preserves `$02–$31`.

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
| `CX_ABI_SLOTS` | `74` | the number of slots defined (indices 0–73) |

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

An 8-byte event record: `P0`=type (`EV_*`), `P1`=detail (key / widget index /
menu item), `P2/P3`=x, `P4/P5`=y, `P6`=frame stamp, `P7`=0.

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

### Widgets

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 39 | `CX_WG_SET` | `$8085` | A/X=a widget list | install + draw a widget list; routes its clicks, posts `EV_WIDGET` |
| 40 | `CX_WG_DRAW` | `$8088` | — | redraw the current list (e.g. after a theme change) |
| 42 | `CX_WG_KEY` | `$808E` | A=key → carry if it was a widget key | drive widgets from the keyboard; clobbers X/Y |

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

### PCM audio — the VERA 4 KB FIFO

Refilled each frame off the event IRQ, so `CX_EV_INIT` must be running.
The sample source is low RAM; samples are signed bytes. *(Added in 0.2.0.)*

| slot | name | addr | args → result | purpose |
|---|---|---|---|---|
| 70 | `CX_PCM_CTRL` | `$80E2` | A=control (volume 0–15 \| `$20` 16-bit \| `$10` stereo) | set format + volume |
| 71 | `CX_PCM_PLAY` | `$80E5` | P0/P1=source, P2/P3=byte count, A=rate (1–128, 128=48 kHz) | reset FIFO, prime, start |
| 72 | `CX_PCM_STOP` | `$80E8` | — | silence and forget the sample |
| 73 | `CX_PCM_ACTIVE` | `$80EB` | → A=1 while playing, else 0 | is a sample still playing |

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
- [formats.md](formats.md) — the byte layouts of fonts, apps, menus, widgets,
  dialogs and themes.
- [memory-map.md](memory-map.md) — the ZP / RAM / VRAM ledger.
- `abi/cxgeos.abi` — the authoritative slot manifest (slots are append-only).
