# p8sdk — a friendly Prog8 layer over the CXGEOS ABI

`p8sdk/cxui.p8` (block `ui`) is a small friendly layer over the generated
Prog8 ABI binding (`sdk/include_prog8/cxgeos.p8`, block `cx`). The binding
is already ergonomic — `cx.gfx_rect(x, y, w, h, colour)` — but a real app
still re-derives the same helpers: a framed button with a centred label,
pulling a mouse event out of the `$22` block, laying down a widget-list
descriptor byte by byte. The p8sdk gives those a home, exactly as
`csdk/cxsdk.h` does for C.

It is the Prog8 parallel of the csdk's widget helpers and adds three things.

## 1. Immediate-mode painters

Draw one widget by name, for a custom layout (a keypad, a status bar). They
only paint — the app hit-tests the pixels itself — and match the kernel
toolkit's look, so a hand-painted button sits beside a real one.

```
ui.button(x, y, w, h, label)            ; a framed box, label centred both ways
ui.checkbox(x, y, label, checked)       ; a marker box (filled if checked) + label
ui.slider(x, y, w, value, maxv)         ; a trough with a thumb at value/maxv
ui.edit(x, y, w, h, text)               ; a framed field, text left-aligned
```

## 2. A one-call event poll

Pull the next event and read it out of the block into `ui.*` fields at once
(before any indirect op reuses Prog8's SCRATCH_PTR at `$22`).

```
ui.poll()   -> bool     ; RAW: mouse events as ET_DOWN/MOVE/UP (hit-test yourself)
ui.next()   -> bool     ; TOOLKIT: routes clicks to cx.wg_set/menu_set widgets
```

After a true return, read `ui.etype`, `ui.detail`, `ui.mx`, `ui.my`, `ui.frame`.

## 3. Runtime descriptor builders

For the kernel-managed toolkit. C and asm lay these out as static data;
Prog8 builds them into a RAM buffer at startup (which sidesteps embedding
pointers in a byte-array literal). Fill an app buffer, then hand it over.

```
; a widget list -> cx.wg_set
ui.wg_begin(&buf)
ui.wg_button(x, y, w, h, label)
ui.wg_check(x, y, w, on, label)   ui.wg_radio(x, y, w, on, group, label)
ui.wg_scroll(x, y, w, val, maxv)  ui.wg_field(x, y, w, cap, textbuf)
ui.wg_icon(x, y, id, label)       ui.wg_hit(x, y, w, h, shape, trig)
cx.wg_set(&buf)

; a menu bar -> cx.menu_set (build the item lists first)
ui.items_begin(&file); ui.item(&s_open); ui.item(&s_quit)
ui.menu_begin(&bar);   ui.menu(&s_file, &file)
cx.menu_set(&bar)

; a dialog -> cx.dlg_alert / cx.panel     ; a theme -> cx.theme_set
ui.dlg_begin(&d, &message); ui.dlg_button(&s_ok); ui.dlg_button(&s_cancel)
ui.theme(&t, c0, c1, c2, c3, paper, hi, frame)
```

The builders are stateful (a write cursor per kind): finish one list before
starting another of the same kind. Size a widget buffer `1 + 16*N` bytes.

## Using it

Import it alongside the binding and put **both** source dirs on the path:

```
%import cxgeos      ; the generated ABI: block cx
%import cxui        ; the friendly layer: block ui
```
```
prog8c -target cx16 -srcdirs sdk\include_prog8 -srcdirs p8sdk  app.p8
```

The p8sdk uses only the public `cx` binding, so it inherits its rules — your
**main program** must still declare `%option no_sysinit` and
`%zpreserved $02,$5f` (see the binding header and
`memory/prog8-binding-gotchas`). Prog8 links only the `ui` subs an app
actually calls.

## Examples

- `apps/calc/calc.p8` — the calculator: `ui.button` paints the keypad,
  `ui.poll` drives the event loop.
- `apps/uidemo_prog8/uidemo.p8` — the showcase: the four painters on the
  left, a live `ui.wg_*` widget list (`cx.wg_set`) on the right.
