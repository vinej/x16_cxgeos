# CXGEOS — technical brief for Claude

A from-scratch GEOS-inspired desktop OS for the Commander X16. Clean break
from C64 GEOS (no binary compat, no VLIR, no .d64). Runs on **stock R49+
ROM** — never patch the KERNAL (that was the X16_Geos project's trap: the
C64 deskTop needed low RAM that collides with the X16 IRQ handler at $038B).

## Fixed decisions

- Screen: **640×480 @ 2bpp** (4 colors), VERA layer 0 bitmap, framebuffer at
  VRAM $00000, 160 bytes/row, 76,800 bytes. HSCALE/VSCALE = 128. There is no
  KERNAL screen mode for this — program VERA directly.
- Delivery: SD-loadable (`AUTOBOOT.X16`), cartridge later. No ROM patches.
- Kernel: hand-written 65C02 assembly, **ca65/ld65** (segments, symbol maps).
- Library: `x16lib/` = vendored `x16_library\src_ca65` (pin noted in README).
  General-purpose 2bpp primitives get upstreamed INTO x16_library as a new
  `gfx2` module (ACME reference first) and to x16_clib; only OS-specific code
  (dirty rects, regions, save-under, glyph cache policy) lives here.
- Apps: any toolchain, via a fixed jump table at $8000 (magic `CXOS` +
  version + 3-byte JMP slots, append-only forever). Bindings are GENERATED
  from the ld65 map (pattern: x16_library `dist.ps1`).

## Memory map (live ledger in docs/memory-map.md)

- ZP: $02–$21 KERNAL r0–r15 (caller-save scratch), $22–$31 x16lib (fixed),
  **$32–$5F kernel** (declare only in kernel/resident/zp.inc), **$60–$7F app**
  (kernel/IRQ never touch). $80–$FF untouched (Phase 8 may reclaim).
- Low RAM: $0801–$7FFF app space; $8000 jump table; $8200–$9EFF resident
  kernel (~7.4KB, budget enforced by kernel.cfg).
- Banked RAM: 1 kernel data/theme; 2–5 kernel code (far-called); 6–7
  fonts/icons; 8–9 reserved; 10–13 clipboard; 14–15 desk accessories;
  16+ dynamic pool (`bank_alloc`).
- VRAM: $00000 framebuffer; $12C00 menu save-unders (16KB); $16C00 glyph
  caches (pre-shifted ×4) + icons (~29.5KB); $1E000 sprites; $1F000 KERNAL
  charset (kept for panic console); $1F9C0+ hardware (PSG/palette/sprattr).

## Conventions

- x16lib ABI: args in A/X/Y, overflow in X16_P0..P7 ($22..$29); X16_T0..T7
  are scratch, never live across a library call. Errors: carry set.
- ca65 sources use `.feature labels_without_colons` (ACME shape), 65C02 cpu.
  One translation unit: `.include "x16.asm"`, set `X16_USE_*` gates, code,
  then `.include "x16_code.asm"` exactly once.
- IRQ discipline: handlers touch only their own state + A/X/Y (KERNAL stub
  saved them); anything else brackets with irq_save_regs/irq_restore_regs.
  VERA state touched in IRQ (CTRL, port addresses) must be saved/restored.
- FX facts: fx_fill/fx_copy destinations must be 4-byte aligned (= 16 pixels
  at 2bpp); FX transparency is byte-granular (4px) so masked blits are CPU
  RMW via DATA1(read)/DATA0(write).
- KERNAL CHROUT repositions the VERA data ports — never interleave KERNAL
  text output with port work (spike B lesson: buffer reads, then print).
- KERNAL mouse pointer image lives at VRAM $13000 (r49 io.inc sprite_addr);
  the ledger in docs/memory-map.md carves it out.
- Emulator ROM: use ONLY the official r49 release rom.bin (sha256 b81654cc…).
  The rom.bin in X16_Geos and x16_library is GEOS-modified (298e3e2a…).
- Tests: x16lib runner pattern — write via port 0, verify via port 1, print
  `PASS x`/`FAIL x`/`SKIP x` then `DONE pp/tt`; `build.ps1 -Test` enforces
  consistency. FS tests only against `test/fsroot`.

## Build

`.\build.ps1 -Source <file.asm> [-Config <file.cfg>] [-Run] [-Test]`
Defaults: test runner. Emulator: `emulator\x16emu.exe` + stock `rom.bin`.
Spike/demo output goes through CHROUT and is captured with `-echo`.

## Phase plan (full plan: C:\Users\jyv\.claude\plans\i-have-a-local-fancy-comet.md)

0. Bootstrap + risk spikes (fill rate, glyph blit, latency) ← CURRENT
1. gfx2 engine (primitives upstreamed to x16_library/x16_clib; dirty rects
   and window clip state stay here)
2. Font engine (CXF format, fontconv.py, VRAM glyph cache)
3. Event system (vsync IRQ → ring buffer → mainloop dispatcher)
4. Boot chain, $8000 ABI, CXAP app format + loader (ABI freeze test)
5. Windowing + widgets (stacked regions, save-under, themes)
6. Desktop + file manager (CMDR-DOS)
7. Clipboard, apps (calc, edit, paint), desk accessories
8. Perf polish, cartridge packaging, SDK release
