# csdk — a friendly C wrapper over the CXGEOS ABI

`csdk/cxsdk.h` is a header-only layer over the generated ABI header
(`sdk/include_llvm/cxgeos.h`). The generated header is deliberately
low-level: you set the parameter block by hand and call a slot number.

```c
/* the generated ABI, by hand */
cx_p[0] = x & 0xFF; cx_p[1] = x >> 8;
cx_p[2] = y & 0xFF; cx_p[3] = y >> 8;
cx_p[4] = w & 0xFF; cx_p[5] = w >> 8;
cx_p[6] = h & 0xFF; cx_p[7] = h >> 8;
cx_call_a(CX_GFX_RECT, colour);
```

The csdk turns that into one named call:

```c
cx_rect(x, y, w, h, colour);          /* the csdk */
```

Every C app used to re-define the same private `rect()`/`frame()`/`say()`/
`marker()` helpers before it could draw anything, and reading a mouse
event meant pulling `cx_p[2] | cx_p[3] << 8` apart inline. The csdk gives
those a home so no one re-derives the plumbing.

## Using it

Include it **after** the generated header — it builds on that header's
macros (`cx_p`, `cx_call_a`, `cx_call_p`, `cx_ret`, `cx_a`/`cx_x`/`cx_c`):

```c
#include <cbm.h>
#include "sdk/include_llvm/cxgeos.h"   /* the generated ABI: slots + macros */
#include "csdk/cxsdk.h"                /* the friendly wrappers */
```

Build unchanged — it is header-only. Every wrapper is `static`, so `-Os`
drops the ones an app does not call; nothing is added to the image for a
function you never name.

```
mos-cx16-clang -Os -mreserve-zp=90 -I . -o build\MYAPP.PRG apps\myapp.c
python tools\mkcxap.py build\MYAPP.PRG build\MYAPP.CXA --name "My App"
```

## What it gives you

- **Named calls** for every ABI slot: `cx_rect`, `cx_frame`, `cx_line`,
  `cx_say`, `cx_clear`, `cx_menu_set`, `cx_wg_set`, `cx_theme`, `cx_alert`,
  `cx_dir_next`, `cx_dos`, `cx_clip_put`, … — see the header for the full
  list, grouped by area (graphics, text, events, pointer, menus/widgets,
  themes/dialogs, loader/DAs, directory/DOS, clipboard, dirty rects).
- **A typed event and a one-call poll.** `cx_poll(&ev)` hides the carry a
  raw C call cannot see: it returns 1 and fills the record when an event
  was waiting, 0 otherwise.

  ```c
  cx_event ev;
  for (;;) {
      if (!cx_poll(&ev)) continue;
      if (ev.type == CX_ET_KEY && ev.detail == CX_K_ESC) break;
      if (ev.type == CX_ET_DOWN) { /* ev.x, ev.y are the mouse point */ }
  }
  ```

  `cx_event` is `{ type, detail, x, y, frame }`. For a mouse event `x`/`y`
  are the point; for an `EV_WIDGET` `detail` is the widget index and `x`
  its value; for an `EV_MENU` `detail` is the item and `x` the menu.

  **`cx_poll` vs `cx_next` — which loop primitive.** `cx_poll` is the RAW
  poll: mouse clicks arrive as `EV_DOWN`/`EV_MOVE`/`EV_UP` and the app
  hit-tests `ev.x`/`ev.y` itself (the calculator). A **toolkit** app --
  one that called `cx_wg_set` / `cx_menu_set` -- must poll with `cx_next`
  instead: it routes each pending mouse event through the widget/menu
  regions first, so a click on a widget surfaces as the `EV_WIDGET` /
  `EV_MENU` the toolkit posts. `cx_poll` never reaches the widget engine,
  because the kernel routes the mouse only on the dispatch path, and a C
  app cannot take the asm callback the plain dispatcher uses (the event
  record lands in `$22`, which is llvm-mos's soft-stack pointer). `cx_next`
  (ABI slot 54, `cx_ev_next`) is the kernel doing that routing for you and
  handing back only the keys and posted events to poll.

  ```c
  cx_event ev;
  cx_wg_set(&panel);
  for (;;) {
      if (!cx_next(&ev)) continue;         /* routes the mouse for you */
      if (ev.type == CX_ET_KEY)    { cx_menu_key(ev.detail); cx_wg_key(ev.detail); }
      if (ev.type == CX_ET_WIDGET) { /* ev.detail = index, ev.x = value */ }
      if (ev.type == CX_ET_MENU)   { /* ev.detail = item,  ev.x = menu  */ }
  }
  ```

- **The shared constants**, so apps stop redefining them: event types
  `CX_ET_*` (`CX_ET_KEY`, `CX_ET_DOWN`, `CX_ET_MENU`, `CX_ET_WIDGET`, …),
  widget types `CX_WG_*`, font-style flags `CX_BOLD`/`CX_UNDER`, and the
  key codes `CX_K_ENTER`/`CX_K_ESC`/`CX_K_TAB`/`CX_K_BTAB`/arrows/…

  > Note the `CX_ET_*` spelling for **e**vent **t**ypes: the generated
  > header already owns `CX_EV_*` for the ABI **slot** numbers
  > (`CX_EV_GET`, `CX_EV_TIMER`), so the event-type constants use a
  > different prefix to avoid the clash.

- **Immediate-mode widget painters** — for custom layouts, functions that
  *draw* a widget by name so the code reads by intent instead of composing
  an anonymous `cx_frame()` + `cx_say()`:

  ```c
  cx_button(200, 150, 56, 28, "7");     /* framed box, label centred      */
  cx_checkbox(40, 100, "wrap", 1);      /* marker box (filled) + label    */
  cx_slider(360, 116, 200, 2, 9);       /* trough + thumb at value/max    */
  cx_edit(40, 290, 300, 24, buf);       /* framed field, its text inside  */
  ```

  These paint only — the app hit-tests the coordinates itself (this is how
  the calculator's keypad works). They match the kernel toolkit's look
  pixel for pixel and use the theme role colours `CX_PAPER`/`CX_HI`/
  `CX_FRAME`, so a hand-painted button sits beside a real one and both
  recolour on a `cx_theme()` swap. **Two ways to make a widget:** use these
  when you own the layout and event handling; use the descriptor builders
  below when you want the kernel to draw *and* dispatch clicks/focus.

- **Descriptor builders** — packed structs that mirror the kernel's byte
  layouts (see `docs/formats.md`) plus macros for the count-prefixed
  lists, so an interactive, kernel-managed UI is C data the compiler
  checks instead of a raw byte array:

  ```c
  static char field[32];
  static const char *rows[] = { "apple", "banana", "cherry" };

  CX_WIDGETS(panel,                       /* mutable: the toolkit writes back */
      CX_BUTTON(520, 448, 100, 24, "exit"),
      CX_CHECK (40, 100, 160, 1, "wrap long lines"),
      CX_RADIO (40, 160, 120, 0, 1, "left"),
      CX_SCROLL(360, 116, 200, 2, 9),     /* value 2 (=3), max 9 (=10) */
      CX_FIELD (40, 290, 300, 24, field),
      CX_LIST  (360, 250, 200, 120, 3, rows));

  CX_MENU_ITEMS(file_items, "about", "quit");
  CX_MENU_BAR(bar, CX_MENU("File", &file_items));

  CX_DIALOG(about, "hello from C", "ok");

  static const cx_theme_rec night = {
      { 0x01,0x00, 0x23,0x01, 0x56,0x03, 0xBC,0x0A }, 0, 1, 3, 0
  };

  cx_menu_set(&bar);
  cx_wg_set(&panel);
  cx_theme(&night);
  ```

  The packed structs must disassemble byte-identical to the layouts the
  kernel reads — that is validated end to end by `apps/cdemo`, which draws
  and responds exactly like the asm `apps/gallery` if (and only if) every
  field lands where the kernel expects it.

- **Picture files** — save or restore a screen rectangle to a SEQ file in
  one call:

  ```c
  cx_pic_save("PAINT.DAT", x, y, w, h);            /* screenshot a region  */
  if (cx_pic_load("PAINT.DAT", x, y, w, h)) { ... } /* returns rows loaded */
  ```

  The rectangle streams as native framebuffer bytes straight through
  VERA's data port (four 2-bit pixels a byte), a row at a time, with
  interrupts masked — far faster than a `cx_pget`/`cx_pset` per pixel
  (each of those is a full ABI crossing). `x` and `w` are in pixels and
  must be multiples of 4; a row is at most 640 px. This is how
  `apps/paint` persists its canvas.

## Reference apps

- `apps/hello_c/hello.c` — the smallest example: `cx_print`, `cx_say`,
  `cx_clear`, `cx_poll`.
- `apps/calc/calc.c` — a real app: `cx_button` for the keypad, `cx_say`
  for the display, and `cx_poll(&ev)` with `ev.type`/`ev.detail`/`ev.x`/
  `ev.y` events. The immediate-mode painter path.
- `apps/cdemo/cdemo.c` — the descriptor builders: a menu bar, the full
  widget set, a modal dialog and two themes, all declared as C data, and
  polled with `cx_next` so the mouse drives them. The kernel-managed
  toolkit path.
- `apps/paint/paint.c` — a small paint program: a pencil and an eraser
  driven by dragging the mouse (raw `cx_poll` + its own hit-testing,
  `cx_line`/`cx_pset`/`cx_rect`), plus save/load that stream the canvas
  to a SEQ file through the KERNAL (`cx_pget`/`cx_pset` pack the pixels,
  interrupts masked around the stream). The immediate-mode + file-I/O
  example.
- `apps/beep/beep.c` — audio: a PSG scale, a YM (FM) note, and a PCM blip
  (`cx_psg_*`, `cx_ym_*`, `cx_pcm_*`).
- `apps/sprite/sprite.c` — a hardware sprite following the mouse
  (`cx_sprite_*`, `cx_vram_write`).

> **0.2.0** adds audio (PSG/YM/PCM) and hardware sprites — see the full
> reference in [docs/csdkguide.md](../docs/csdkguide.md).

## Scope

Targets **llvm-mos**, the fully-supported C toolchain and where the apps
live. The header uses only the shared macro surface, so it extends to the
other C compilers (cc65/kickc/oscar64/vbcc) once their generated bindings
gain A/X passing — those stubs are partial today. No kernel or ABI change:
the csdk is pure client-side C.
