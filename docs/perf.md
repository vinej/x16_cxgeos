# CXRF performance ledger — Phase 0 spike results

Measured 2026-07-16 on x16emu (stock R49 ROM, sha256 `b81654cc…`,
official `X16Community/x16-rom` r49 release), 8 MHz 65C02, VERA FX.
1 jiffy (JF) = 1/60 s = one 60 Hz frame ≈ 133,333 CPU cycles.
1 scanline ≈ 31.7 µs (525 lines/frame).

Re-run any time:

```powershell
.\build.ps1 -Source spikes\spike_a.asm -Capture
.\build.ps1 -Source spikes\spike_b.asm -Capture
.\build.ps1 -Source spikes\spike_c.asm -Capture
```

## Spike A — bulk fill/copy bandwidth (640×480@2bpp = 76,800 B screen)

| Path | Raw | Per full screen | Bandwidth | Cycles/byte |
|---|---|---|---|---|
| `vera_fill` (CPU byte loop) | VFILL8 = 42 JF | 5.25 JF = 87.5 ms | 0.88 MB/s | ~9.1 |
| `fx_fill` (32-bit cache) | FXFILL8 = 10 JF | 1.25 JF = 20.8 ms | 3.7 MB/s | ~2.3 |
| `fx_copy` (VRAM→VRAM) | FXCOPY8H = 15 JF (8 half screens) | 3.75 JF equiv. | 1.2 MB/s | ~6.5 |

Consequences:

- Full-screen clears/pattern floods go through **fx_fill: 1.25 frames**.
  Never CPU-fill more than a strip.
- Save-under for a typical 200×150 px drop-down (50 B × 150 rows =
  7.5KB) via fx_copy ≈ **6 ms save + 6 ms restore** — well inside a frame.
- A full-screen fx_copy restore (dialog over everything) ≈ 62 ms ≈ 3.7
  frames: acceptable for dialog dismissal, not for per-frame animation.

## Spike B — glyph blit (8×8 glyph, pre-shifted ×4, column-major, VERA_INC_160)

| Path | Raw | Per glyph | Glyphs/frame |
|---|---|---|---|
| masked RMW (transparent, arbitrary x) | MASK1600 = 10 JF | 104 µs ≈ 833 cyc | **160** |
| opaque on color-0 bg (pure writes) | OPAQ1600 = 7 JF | 73 µs ≈ 583 cyc | **229** |

Correctness: framebuffer dump verified byte-identical against a host-side
simulation — all 4 shift phases, overlapping glyphs, transparency over
two backgrounds (`spikes/spike_b.asm` dump + scratchpad `verify_b.py`).

Targets from the plan, checked:

| Target | Budget | Measured | Verdict |
|---|---|---|---|
| menu-bar redraw < 1 frame | ~40 chars + bar fill | 40×104 µs + fx strip fill ≈ 5 ms | ✔ 0.3 frames |
| keystroke echo < 1 frame | 1 glyph + caret | ~0.2 ms | ✔ |
| full desktop paint < 4 frames | bg flood + chrome + ~200 chars | 21 + ~10 + 21 ms ≈ 3.1 frames | ✔ |

Headroom: the spike uses `(zp),y` addressing; the Phase 1 engine can
move to absolute-indexed/self-modifying streams for another ~20%.

## Spike C — event heartbeat

| Check | Result |
|---|---|
| CINV chain over 2bpp mode: KERNAL jiffy alive | FRAMES60 = 60, JIFFY60 = 60 ✔ |
| KERNAL hw-sprite mouse pointer over the bitmap | works; image at VRAM $13000, past our fb ✔ |
| IRQ-context `mouse_get` → 5-byte event → ring buffer → mainloop pop | QLAT min 22 / max 31 scanlines = **0.7–1.0 ms**, stable |

Input pipeline latency budget: mouse sampled once per frame at scanline
0, dispatched to the mainloop ~1 ms later, paint lands in the same
frame's vblank-adjacent window → **click→pixel ≤ 2 frames by
construction.** (Interactive check: `spike_c.asm -Run`, hold left
button to paint at the pointer.)

## Phase 1 — torture demo (the regression gate)

`demos/torture.asm` draws every gfx2 primitive in one composite scene:
full-screen 640×480 checker `gfx2_pattern_rect`, 8 `gfx2_rect` +
`gfx2_frame`, a 16-line `gfx2_line` starburst, 32 `gfx2_blit` raster
ops, 200 `gfx2_blitm` masked glyphs.

| Measure | Raw | Per scene |
|---|---|---|
| SCENE4 (4 full composites) | **160 JF** | 40 JF ≈ 0.67 s |

This is the deliberate worst case — everything repainted through the
slowest paths (CPU pattern flood is ~7 JF/screen alone; pset-driven
lines ~6 JF). Real UI frames repaint only dirty rectangles (the
`kernel/gfx2/dirty.asm` list, DR_MAX=8, merge+cascade, coverage never
drops) and flood via `fx_fill` at 1.25 JF/screen. Re-run with:

```powershell
.\build.ps1 -Source demos\torture.asm -Capture
```

## Phase 2 — the font engine

`demos/specimen.asm` draws the system font as a type specimen, reflows a
paragraph twice at measured widths, and times 32 passes of a 37-character
pangram at a walking x, so all four pixel phases are hit the way real
text hits them.

| Measure | Raw | Per glyph | Rate |
|---|---|---|---|
| PANGRAM32 (1,184 glyphs) | **12 JF** | 169 µs / ~1,350 cycles | **98.7 glyphs/frame, ~5,900/s** |

What that buys, in the units the UI actually asks in:

| | |
|---|---|
| menu bar, 40 chars | 0.41 frames |
| a full screen, 60 lines × ~112 chars | 68 frames (6,720 glyphs) |

Spike B blitted 160 raw glyphs/frame, so the engine spends ~520 cycles a
glyph on everything that is not the blit: the string walk, the width
lookup, `f_slot_addr`'s divide and multiply, and rebuilding P0..P7 for
every call. That is the obvious place to go if text ever needs to be
faster — a per-glyph table of precomputed bank/offset would kill most of
it — but a menu bar in under half a frame is not asking for it yet.

Re-run with:

```powershell
.\build.ps1 -Source demos\specimen.asm -Capture
```

## Phase 0 verdicts on the three headline risks

1. **2bpp blit performance at 640×480** — retired. Masked text at 160
   glyphs/frame and FX-accelerated fills leave the target UI budgets
   with 3×+ headroom.
2. **VRAM budget** — closes, and with more room than Phase 0 thought.
   The 28.4KB it reserved for glyph caches was a mistake: `gfx2_blitm`
   reads its source from CPU RAM, so the cache lives in banked RAM
   (Phase 2 found this — see `docs/memory-map.md`). VRAM holds the 75KB
   framebuffer, 16KB of menu save-unders, sprites, and the KERNAL mouse
   image at $13000, with 28KB now free for icon sheets.
3. **Event latency** — retired. Chained IRQ costs the KERNAL nothing,
   queue dispatch is ~1 ms, cursor is a zero-latency hardware sprite.

## Gotchas pinned for the kernel (cost real debugging time)

- **KERNAL CHROUT repositions the VERA data ports.** Reading VRAM while
  printing corrupts the read stream (spike B found this). Buffer first,
  print after — and the future kernel never mixes KERNAL text I/O with
  port work at all.
- `X16_Geos/emulator/rom.bin` and `x16_library/emulator/rom.bin` are
  **not** stock R49 (sha256 `298e3e2a…` ≠ release `b81654cc…`).
  CXRF vendors the official release ROM only.
- fx_fill/fx_copy destination alignment: 4 bytes = 16 pixels at 2bpp.
- FX transparent writes skip whole zero BYTES (4 px), useless for
  per-pixel masking — masked blits stay on the CPU RMW path.
