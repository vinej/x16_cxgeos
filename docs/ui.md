# CXGEOS UI architecture (Phase 5)

## Where UI code lives, and why

The resident budget is 7,424 bytes and the kernel proper uses ~5,500 of
it. Menus, dialogs and widgets are several kilobytes each — they do not
fit, and they should not: they are cold code that runs when a human is
deciding, not when pixels are moving. They live in **kernel banks**
(banks 2–5 of the memory map), loaded at boot from `CXBANKS.BIN`, and
are reached through the far-call trampoline below. The ABI does not
know any of this: an app calls a fixed slot like any other, the slot
jumps to a five-byte resident stub, and the stub crosses the bank.

What stays resident is what every frame or every event needs: the
region stack (event routing must not cross a bank per mouse move), the
trampoline itself, and the stubs.

## The far-call trampoline (`kernel/resident/farcall.asm`)

The hard requirement: **A, X and Y are argument registers** in this
ABI, so a stub may not use any of them to say where it is going. The
stub therefore says it inline, after a `jsr`:

```
cx_menu_set (the ABI slot) --> jmp stub
stub:   jsr cxb_call
        .byte 2                 ; the bank
        .addr $A012             ; the routine, in that bank's window
```

`cxb_call` pops the return address to find the bank and target, parks A
and Y in cells while it reads them, saves the caller's `RAM_BANK`,
switches, and jumps. On return it restores the caller's bank and hands
back A, X, Y **and the flags** — carry is how kernel calls report
refusal, and a trampoline that ate it would poison every contract
passing through it. Nested far-calls are safe: every parked value is
dead by the time the inner call could clobber it. The event IRQ never
far-calls, by rule.

Each bank begins with its own jump table at `$A000` (3 bytes a slot,
bank-local, NOT part of the ABI — only the resident stubs name these,
and stubs and banks ship together in one build). Bank code may call
resident code directly (low RAM is always mapped) and other banks via
`cxb_call` like anyone else.

## Regions (`kernel/ui/region.asm`, resident)

A region is a rectangle with a handler: "while I am on top, mouse
events inside me are mine." The stack is strict LIFO, `CX_RG_MAX` = 8
deep — a menu bar, an open drop-down, a dialog, a desk accessory and
room to spare. Records are 10 bytes: x0, y0, x1, y1 as words
(inclusive), then the handler vector.

Routing lives in `ev_dispatch`: for mouse records (MOVE, DOWN, UP,
DBLCLICK), the region stack is walked top-down; the first region
containing the point gets the record — the whole record, in
`X16_P0..P7`, exactly as a type handler would — and the app's handler
table is not consulted. A miss on every region falls through to the
app's table as before. Key and timer events never route through
regions: focus is not geometry.

This is the plan's "stacked, not general-overlapping" window model in
its smallest form. A menu drop-down is a push; closing it is a pop; the
dialog engine is the same push with a different painter.

## Save-under (Phase 5a: menus)

Menu drop-downs save the pixels they cover into the VRAM strip area at
`$12C00` (16 KB, `docs/memory-map.md`) and restore with `fx_copy` —
which is why the kernel now gates `X16_USE_VERAFX_COPY` alongside
`_FILL`. Dialogs and desk accessories will save to banked RAM instead
(bigger, slower, rarer); that is Phase 5b.

## Menus (Phase 5a, bank 2)

An app hands `cx_menu_set` a menu tree in its own memory ($0801–$7FFF
is always mapped, so bank code can read it in place). Setting the menu
pushes the bar region; a click in the bar opens a drop-down: save-under,
draw, push the drop-down region. A click on an item pops back, restores
the pixels, and posts an `EV_MENU` record with the menu/item indices —
the app hears about menus the same way it hears about everything else.

## Themes (Phase 5b, `kernel/ui/theme.asm`)

A theme is the four palette RGBs plus which index plays which role —
paper, highlight, frame. Twelve bytes, and they are RESIDENT (`cx_theme`),
because the menu and dialog engines execute in bank 2 and could not read
a theme kept in bank 1. Text ink is not a role: the glyph cache is built
as colour-3 coverage, so text is always index 3 and a theme recolours it
through the palette entry. `cx_theme_set` copies the record in and
reprograms the palette on the spot — the colours change instantly,
everywhere; role changes show on the next redraw, which is the app's
business. The menu engine reads `th_paper`/`th_hi`/`th_frame` for every
band it draws, so a theme switch is visible the next time a menu opens.

## Dialogs (Phase 5b, `kernel/ui/dialog.asm`, bank 2)

`cx_dlg_alert` is SYNCHRONOUS, the GEOS shape: the app calls it, the box
appears, and the call does not return until a button is chosen — the
engine runs its own `ev_dispatch` loop inside. That is what makes a
dialog one line of app code instead of a state machine. While the box is
up it owns the machine: a full-screen modal region eats the mouse, and
the handler table is swapped for the engine's own so RETURN can stand in
for button 0. Both are restored before the call returns, and the pixels
come back from the banked save-under. Geometry is fixed (400×96, centred;
72×16 buttons right-aligned) so a blind test can click a known button.
