# CXGEOS UI architecture (Phase 5)

## Where UI code lives, and why

The resident budget is ~5.2 KB with ~130 bytes free. Menus, dialogs and
widgets are several kilobytes each — they do not fit, and they should
not: they are cold code that runs when a human is deciding, not when
pixels are moving. They live in **kernel banks**, loaded at boot from
`CXBANKS.BIN` (banks 2–5) and `CXBANKS2.BIN` (banks 16–19), one theme
per bank so a new feature grows one bank and reshuffles nothing: 2 UI
core (menu/theme/DA), 5 dialogs, 16 widgets, 17 shapes/tiles, 18
fs/system, 19 audio/sprites (see [banks.md](banks.md) and
[memory-map.md](memory-map.md)). They are reached through the far-call
trampoline below. The ABI does not know any of this: an app calls a
fixed slot like any other, the slot jumps to a five-byte resident stub,
and the stub crosses the bank.

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

Bank 2 begins with its own jump table at `$A000` (`b2_table`, 3 bytes a
slot, bank-local, NOT part of the ABI — a historical indirection for the
UI-core module). The newer theme banks (5, 16–19) skip the table and let
the resident stubs far-call the routine by label directly (`.byte bank /
.addr routine`); banks 16–19 begin with an 8-byte build signature stage-0
verifies instead. Bank code may call resident code directly (low RAM is
always mapped) and other banks via `cxb_call` like anyone else — but it
must never write `RAM_BANK` to reach another bank's data (it would page
its own window away); a resident helper does that. See
[banks.md](banks.md) for the full contract.

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

## Keyboard menu navigation (`cx_menu_key`)

An app forwards each key to `cx_menu_key` from its `EV_KEY` handler; the
menu engine takes the ones it wants and reports (carry set) that it
consumed them, so the app acts only on the rest. With the bar closed,
DOWN drops the first menu; open, UP/DOWN move the highlight, LEFT/RIGHT
switch menus, RETURN picks, ESC dismisses. A keyboard pick posts the
same `EV_MENU` a click would, through the same `mn_finish` -- so an app
handles selections one way whichever drove them. This is the keyboard
half of the machine the mouse could not reach in one emulator; on
hardware both drive the same menus.

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

## Widgets (Phase 5b, `kernel/ui/widget.asm`, bank 16)

The toolkit draws a widget list and turns clicks on it into `EV_WIDGET`
events (docs/formats.md). Button, checkbox, radio and horizontal
scrollbar so far — the click widgets, which need no keyboard focus. Each
widget's state lives in its own record in the app's memory, which the
toolkit writes back, so the app never tracks a checkbox's checked-ness
itself; it just hears `EV_WIDGET(index, value)` and, if it cares, reads
the record. Everything draws in the live theme's colours, so a theme
switch plus `cx_wg_draw` recolours the lot.

`cx_wg_set` pushes one region over the bounding box of all the widgets,
so the routing is the same region machinery the menus use — the toolkit
hit-tests the individual widgets inside that box. The text field (a
caret, selection, keyboard focus) and the list view ride a later pass
that adds the focus model the click widgets do without.

## The bank-2 jump table

`menu.asm` owns the bank-local jump table at `$A000` — 16 three-byte
slots, most reserved, so a new bank-2 module (theme, dialog, widget, and
whatever follows) claims a reserved slot without moving the peekable
menu-state block that sits behind the table at `$A030`. The resident
stubs each module keeps in its CODE half name these slots by number; the
map is in `menu.asm`'s header comment. Sixteen was chosen after the
table grew 4→8 twice and moved the state block (and a test's peek
address) each time.
