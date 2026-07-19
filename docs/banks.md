# Banks — how the kernel's code is laid out, and how to add to it

CXGEOS's kernel is one ca65 translation unit (`kernel/kernel.asm` includes
everything) linked by `kernel/kernel.cfg` into a resident image plus banked
code. This is the map, the far-call contract, and the playbooks for adding a
widget, a shape, a bank, or an ABI slot without reshuffling anything.

For the byte budget of every region, run `python tools/mapreport.py` after a
`build.ps1 -Kernel`; the per-bank *theme* and *growth policy* are the ledger
in [memory-map.md](memory-map.md).

## The layout in one breath

- **Resident** (`$81A9`–`$95FF`, ~5 KB): only what must be fast or always
  mapped — the IRQ + event loop, region routing, the far-call trampoline
  `cxb_call`, the loader, the clipboard, the save-under streamer, and the
  font *draw* path. Keeps ~130 free bytes; `mapreport` fails under 128.
- **Jump table** (`$8010`–`$81A4`): 95 slots defined, 135 reserved (40 free).
  Slot *n* lives at `$8010 + n·3` **forever** — that and `$8000`/`$9F00` are
  the only external promises. The build word `CX_KBUILD` is the 4 bytes at
  `$81A5`, the reserve's tail.
- **OVL window** (`$9600`–`$9EFF`, 2,304 B): the current graphics engine
  image, copied in from its storage bank by `cx_gfx_mode`.
- **Code banks 2–5** (`CXBANKS.BIN`, one boot LOAD): 2 UI core, 3/4 mode-0/1
  images, 5 dialogs + mode-2/3 images.
- **Code banks 16–19** (`CXBANKS2.BIN`, a second boot LOAD): 16 widgets, 17
  graphics extras, 18 fs/system, 19 audio/sprites. Each opens with an
  8-byte build signature stage-0 checks.
- **Data banks 6–15**, **app banks 20+** — see the ledger.

## The far-call contract (`kernel/resident/farcall.asm`)

Banked code is reached only through `cxb_call`. A resident stub is:

```
cx_do_thing
    jsr cxb_call
    .byte <bank>       ; the RAM bank the routine lives in
    .addr <routine>    ; its address in that bank's $A000 window
```

`cxb_call` preserves A, X, Y and **all flags including carry**, saves the
caller's `RAM_BANK` on the stack and restores it on return — so `jsr` into a
bank reads exactly like a direct call. Cost ≈ 150 cycles (~0.1 % of a frame):
fine for anything not per-pixel or per-event. **Rules:**

- **IRQ code never far-calls** — the event handler and everything it touches
  is resident. This includes a game's borrowed raster handler
  (`cx_ev_raster`): it runs at IRQ time, so it must not call the audio,
  shape, widget or any other banked slot from inside the handler — those are
  `cxb_call` targets. Sample input and set state in the handler; do the
  banked work from the mainline. (The `gameloop` demo's handler is
  audio-free for exactly this reason.)
- **A flag passed as an ARGUMENT does not survive** `cxb_call` (it restores
  the caller's flags). If a banked routine needs carry set/clear as input,
  put a one-line shim on the bank side that sets it before the real jump
  (see `ym_note_retrig` in `kernel/audio/audio.asm`).
- **Banked code must never write `RAM_BANK`** to reach another bank's data —
  it would page its own execution window away mid-instruction. Route the
  access through a resident helper that switches, acts, and restores the
  caller's bank (`f_peek`/`f_store_row` in `kernel/font/font.asm`,
  `vrows_save` in `kernel/resident/vrows.asm`). Reading *resident* data
  (the theme record, the OVL vectors, ZP) from a bank is always fine.
- **Bank-N code cannot read bank-M data directly.** If a bank-5 dialog needs
  bank-16 widget state, it trampolines through a bank-16 helper that owns
  that state (`dlg_wg_setup`/`wg_setup`).

## How a module rides a bank

The vendored-library pattern (audio, dos, shapes, sprites): keep the module's
`X16_USE_*` gate OFF in `kernel.asm` (so `x16_code.asm` does not also place it
resident), then `.include` its source inside a `.segment "BnnCODE"` wrapper.
Point the resident stubs' `.byte` at the bank constant from
`kernel/resident/banks.inc`, and switch back to `.segment "CODE"` after.

The flat test runner links every segment into one address space with
`CX_NO_OVERLAY=1`, so a module that has a bank/flat split (shapes, widgets,
the font cold half) guards it:

```
.ifndef CX_NO_OVERLAY
.segment "B17CODE"
.else
.segment "CODE"
.endif
```

`prg.cfg` maps every `BnnCODE`/`BnnSIG` segment into `MAIN`, so the runner
resolves the labels even though it never banks.

---

## Playbook: add a widget

1. Write it in `kernel/ui/widget.asm` — it is already `B16CODE`, so the code
   and any new `wg_*` state land in bank 16 automatically. Keep new state
   with the other `wg_*` vars (code and state must share the bank).
2. If it needs a new ABI slot, follow the ABI playbook below.
3. Draw through the graphics port (`cxov_*`) and the theme record
   (`th_paper`/`th_hi`/`th_frame`) — both resident, both readable from bank
   16. **Do not `jsr mn_ink`** (bank 2); use the same-bank `wg_ink`.
4. Verify: `build.ps1 -Test`, then a visual boot — GALLERY (mode 0), TUI
   (mode 3). A mode-0 list only shows in the desktop file browser, so gif
   that too (this is how the `wg_p_list` cross-bank bug was caught).

## Playbook: add a shape

1. Add it to `kernel/video/shapes.asm` (bank 17, `B17CODE`) or the vendored
   `x16lib/gfx/shapes.asm` it includes. Draw through the port override
   symbols (`SHP_PSET`/`SHP_READ`/`SHP_HLINE`, bounds `cx_cur_w`/`cx_cur_h`)
   so it is correct in every bitmap mode.
2. New ABI slot → the ABI playbook. Keep any state in bank 17 with the code.
3. Never call a shape from IRQ context.
4. Verify with PAINT (flood/circle/ellipse) on target.

## Playbook: add a bank (a third code file)

Banks 2–5 and 16–19 are full-themed with reserve; you need this only if a
theme bank genuinely overflows AND has no sibling reserve to borrow. Adding
`CXBANKS3.BIN` (banks 20+, which pushes the app floor up again) takes:

1. `kernel.cfg`: a new `MEMORY` region per bank (`start=$A000, size=$2000,
   fill=yes, file="build/CXBANKS3.BIN"`) and `BnnSIG`/`BnnCODE` segments.
2. `banks.inc`: the bank constants; bump `CX_APP_BANK_FLOOR`.
3. `banksig.asm`: a signature + anchor for each new bank.
4. `kernel/boot/auto.asm`: a third `LOAD` (set `RAM_BANK`, `SETNAM`, `LOAD
   $A000`) and a signature probe, plus a refusal string.
5. `kernel/boot/cart.asm` + `cart.cfg`: two more ROM banks and a third
   `bankcopy` call.
6. `build.ps1` `Stage-SdRoot` + `mksd.py`: stage the new file; extend the
   negative skew smoke.
7. `prg.cfg`: map the new segments into `MAIN`.
8. `mapreport.py`: add the new regions.

## Playbook: add an ABI slot

The table has 40 free slots (cap 135). Slots are **append-only** — never
reorder or repurpose one; the frozen canary (`test/canary/CANARY.CXA`) is an
app from the past that must keep passing.

1. Append the slot to `abi/cxgeos.abi` (name, arg count, doc).
2. `python abi/gen_bindings.py` — regenerates `kernel/resident/jumptab.asm`,
   all `sdk/` headers and `csdk/`. Commit the regenerated files in the SAME
   commit (the `--check` gate in `build.ps1 -Test` fails otherwise).
3. Implement `cx_do_<name>`: a resident body, or a `cxb_call` stub into a
   theme bank.
4. Bump the header slot count only by appending — `test_abi_header` asserts
   it, and the canary asserts every existing slot's address and contract are
   unchanged.
5. Never rebuild `CANARY.CXA`.

## When you see garbage after a bank move

A wrong `.byte <bank>` in a stub, or a `jsr` to another bank's routine that
should be same-bank, jumps to that address *interpreted in the current bank*
— usually `$00` (BRK) or random code. Symptoms: a blank/garbled draw, a
hang, a monitor drop. **Suspect the bank byte first.** `mapreport` and each
theme's own smoke (BEEP, PAINT, GALLERY, the desktop file list) are the net.
