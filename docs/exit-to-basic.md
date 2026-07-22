# Exit-to-BASIC instability, and the shelved "launch a standard program"

**Status: KNOWN ISSUE / shelved feature.** This note records a real defect
found while trying to add "launch an ordinary X16 `.PRG` from the desktop",
so the next attempt starts from the evidence instead of the dead ends.

## The symptom

When CXRF hands the machine to BASIC, the board **resets itself ~1 second
later** — repeatedly, in a boot → BASIC → reset loop. It is not the launch
feature's fault: **CXRF's own `cx_exit → BASIC` fallback does it too.**

`cx_exit` (kernel/resident/core.asm) reloads `SHELL.CXA` and only falls
through to `CINT` + `ENTER_BASIC` when the shell is missing. A staged SD root
with **no `SHELL.CXA` and no `AUTORUN.CXA`** takes that fallback on every boot,
and `x16emu -fsroot <root> -warp -echo` shows the KERNAL cold-boot banner
(`512K HIGH RAM …`) **~107 times in 6 seconds** — it never stays at `READY`.
The desktop's "quit" reloads the shell instead, so nobody hits the fallback in
normal use, which is why this went unnoticed.

A control proves the transition is the problem, not BASIC or the program:
`x16emu -prg RUNME.PRG -run` (a plain SYS-stub `.PRG`, no CXRF) runs **rock
solid, no reset**. Only the CXRF → BASIC *software* hand-off is poisoned.

## What it is NOT

- **Not the SMC watchdog.** The [x16-smc firmware](https://github.com/X16Community/x16-smc)
  has **no watchdog / keep-alive** at all. The SMC (I2C `$42`) only resets on
  its explicit commands (offset `$02`) or the physical buttons. An early theory
  blamed a keep-alive; it was wrong.
- **Not the app-only teardown.** Reproduced with the kernel's own `ev_stop`
  path, and with every hand-written teardown tried.

## What did NOT fix it (all tried on `cx_exit`'s BASIC path)

| Attempt | Result |
|---|---|
| `MOUSE_CONFIG 0,0,0` (fully stop the mouse scan `mouse_hide` leaves running) | still ~106 resets |
| `+ IOINIT` before `CINT` | ~89 |
| `IOINIT` + `RESTOR` + `CINT` (the **exact** cold-boot sequence `kernel/boot/cart.asm` uses) | ~83 |
| `RESTOR` in general | *worse* — storms ~75/s |

Even byte-for-byte reproducing the cart boot's machine re-init does not clear
it. That strongly implies the bad state can only be cleared by an **actual
hardware reset**, which a KERNAL soft re-init cannot reproduce. Root cause
below the KERNAL (VIA/I2C/SMC or KERNAL keyboard state left by CXRF) is still
open.

## The path that WOULD work (for the launch feature)

Since a *fresh boot* runs programs stably, route the launch through a real
reset instead of a soft hand-off:

1. Desktop copies the target to a short temp name and drops a **marker**
   (a file, or a reset-surviving RAM cell).
2. Desktop triggers a **hardware reset** — SMC I2C `$42`, offset `$02`,
   value `$00` (`i2c_write_byte`).
3. `AUTOBOOT.X16` (kernel/boot/auto.asm) checks the marker on boot; if set, it
   clears it and runs the target in the **fresh** machine (stuff
   `LOAD"tmp"`/`RUN` into the keyboard queue + `ENTER_BASIC`, exactly the
   stable `-prg -run` situation).
4. Return to the desktop is another reset (marker absent → normal boot).

This touches the **boot chain**, so it is more than an app-only change — the
reason the app-only version (copy-to-temp + teardown + `ENTER_BASIC`, all in
`apps/filer/filer.asm`) was shelved. That app-only version DID launch programs
correctly (validated: RUNME loaded and ran); it just inherited this reset.

## Also worth doing regardless

Fix `cx_exit`'s BASIC fallback so "exit to BASIC" (a shipped v0.10.0 feature)
actually reaches a stable `READY`. It is the same bug, and the same
investigation solves both.
