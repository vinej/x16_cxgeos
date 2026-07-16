# CXGEOS memory map — the live ledger

Every byte of contended address space is accounted for here. Change this
file in the same commit as the code that claims or releases a region.

## Zero page

| Range | Owner | Notes |
|---|---|---|
| $00–$01 | hardware | RAM_BANK / ROM_BANK registers |
| $02–$21 | KERNAL r0–r15 | caller-save scratch; never live across a CXGEOS API call; IRQ callbacks bracket with `irq_save_regs` |
| $22–$31 | x16lib | `X16_P0..P7` + `X16_T0..T7`, fixed as vendored |
| $32–$5F | CXGEOS kernel | allocate only in `kernel/resident/zp.inc` (46 bytes) |
| $60–$7F | application | guaranteed untouched by kernel and IRQ (spikes use it too) |
| $80–$FF | KERNAL/BASIC/DOS | never touch (Phase 8 may audit and reclaim) |

## Low RAM

| Range | Owner | Notes |
|---|---|---|
| $0100–$01FF | CPU stack | kernel ≤48 bytes below caller SP per API call, ≤16 in IRQ |
| $0200–$07FF | KERNAL/DOS | untouched — the X16_Geos project died on this hill: the IRQ handler lives at $038B on stock R49; we never go near it |
| $0801–$7FFF | application | ~30KB, loaded/reset by the kernel loader |
| $8000–$800F | ABI header | magic `CXOS`, ABI version word |
| $8010–$81FF | jump table | 3-byte JMP slots, append-only, address fixed forever |
| $8200–$9EFF | resident kernel | ~7.4KB: gfx2 hot paths, glyph blitter, event core, bank trampoline. Budget enforced by `kernel.cfg` |

## Banked RAM ($A000–$BFFF window, bank register at $00)

| Banks | Owner |
|---|---|
| 0 | KERNAL (reserved) |
| 1 | kernel data: desktop state, theme, font metrics, event overflow |
| 2 | menu/dialog engine (far-called kernel code) |
| 3 | widget toolkit |
| 4 | desktop / file manager |
| 5 | loader + control panel |
| 6–8 | **pre-shifted glyph cache** (see below) + CXF font sources |
| 9 | reserved kernel growth |
| 10–13 | clipboard (typed: text / bitmap-rect, up to 32KB) |
| 14–15 | desk-accessory slots (code + saved state) |
| 16+ | dynamic pool (`bank_alloc`): window backing store, app allocations, file buffers. Sized from MEMTOP at boot (512KB → 48 free banks; 2MB → 240) |

## VRAM (128KB) — the contended resource

| Range | Size | Contents |
|---|---|---|
| $00000–$12BFF | 76,800 | framebuffer 640×480 @2bpp, 160 B/row |
| $12C00–$12FFF | 1,024 | scratch strip (small save-unders, blit staging) |
| $13000–$130FF | 256 | **KERNAL mouse pointer image** (r49 `io.inc: sprite_addr = $13000`; we use the KERNAL mouse driver, so this is spoken for) |
| $13100–$170FF | 16,384 | menu/drop-down save-under strips (`fx_copy` restore) |
| $17100–$1DFFF | 28,416 | icon/pattern sheets, extra save-under (was budgeted for glyph caches — see below) |
| $1E000–$1EFFF | 4,096 | CXGEOS sprite images (extra cursors, drag outlines) |
| $1F000–$1F7FF | 2,048 | KERNAL charset — kept for the panic/debug console |
| $1F800–$1F9BF | 448 | unused by VERA; x16lib `VRAM_FX_SCRATCH` = $1F800 (4 bytes) |
| $1F9C0–$1F9FF | 64 | PSG registers (hardware) |
| $1FA00–$1FBFF | 512 | palette (hardware) |
| $1FC00–$1FFFF | 1,024 | sprite attributes (hardware) |

## The resident budget does not fit yet (Phase 4)

`kernel/kernel.cfg` pins the image and lets ld65 enforce the budget
rather than leaving it a comment someone has to remember. The first
build it enforced, it failed:

| | bytes |
|---|---|
| x16lib (VERA + VERAFX + IRQ + INPUT + SCREEN + LOAD + BANK) | **6,055** |
| CXGEOS kernel code (gfx2 wrappers, font, event, dirty, core) | 2,096 |
| `fonts/pxl8.cxf`, linked into the image | 871 |
| **resident total** | **9,022** |
| budget, `$8200`–`$9EFF` | 7,424 |
| **over by** | **1,598** |

The placement itself is proven: `JUMPHDR` lands at `$8000`, `JUMPTAB` at
`$8010`–`$806C` (93 bytes = 31 slots × 3), `CODE` at `$8200`.

**Two thirds of the image is the library, and most of that is unused.**
x16lib is one translation unit, so a gated module links whole — there is
nothing for ld65 to strip. Measured, one gate at a time:

| gate | bytes | what CXGEOS calls from it |
|---|---|---|
| VERA | 143 | `vera_fill`, via gfx2 |
| **VERAFX** | **2,502** | **`fx_fill`, via gfx2 — and nothing else** |
| BITMAP2 (gfx2 itself) | 2,149 | all of it |
| IRQ | 400 | all five routines |
| INPUT | 39 | `mouse_get`/`show`/`hide` |
| SCREEN | 121 | `screen_set_mode`, in `cx_exit` alone |
| LOAD | 76 | nothing yet |
| BANK | 624 | nothing — `font.asm` writes `RAM_BANK` itself |

The 320×240 8bpp module is *not* linked: the gates do work. The problem
is granularity, not selection. `X16_USE_VERAFX` exists to give gfx2
`fx_fill` and hands over `fx_mult`, `fx_copy`, `fx_transp`, `fx_affine`,
`fx_line` and `fx_triangle` with it — the last two are 400 lines
between them.

**Measured, not estimated:** a `verafx.asm` trimmed to
`fx_off`/`fx_mult`/`fx_fill`/`fx_clear` builds the same kernel **2,162
bytes** smaller. That alone takes the image to 6,860 and it fits, with
564 to spare. Dropping the three gates nothing calls (SCREEN, LOAD,
BANK: 821) and banking the font blob (871) would leave 2,256 spare.

So the fix is upstream and it is small: **split VERAFX into sub-gates**
in x16_library — fill, copy, mult, the line/triangle drawers, the affine
sampler — with `X16_USE_VERAFX` still meaning all of them, so nothing
that exists today breaks. Every X16 program that wanted a fast fill and
paid 2.5 KB for a rotozoom sampler gets the saving, not just CXGEOS.
x16_clib has the same shape and would benefit the same way: its archive
strips at `.o` granularity, and `verafx.o` is one object.

A CXGEOS-local trimmed copy of the library would work and is the wrong
answer: the vendored tree is a clean snapshot on purpose, and the next
re-vendor would silently undo it.

Banking the cold code is still worth doing — `font_cache` runs once at
boot and has no business resident — but it is no longer urgent, and it
should not be done to pay for somebody else's `fx_triangle`.

## The glyph cache lives in banked RAM, not VRAM

Phase 0 budgeted the pre-shifted glyph caches into VRAM at `$17100`.
That was wrong, and Phase 2 caught it: `gfx2_blitm` reads its source
through `(X16_PTR3),y` — **CPU RAM**. A VRAM cache would need a second
blitm that streams the source through a data port, which costs the read
port the masked write already uses.

So the cache sits in banked RAM, and the 28 KB of VRAM goes back to
icon sheets and save-unders.

| | |
|---|---|
| One glyph | 4 phases × 3 columns × 8 rows × 2 bytes (mask, data) = **192 bytes** |
| Full ASCII (95 glyphs) | 18,240 bytes = **banks 6, 7, 8** |
| Per bank | 42 glyphs (8,064 bytes), so no glyph straddles a boundary |
| Glyph `i` | bank `6 + i/42`, offset `$A000 + (i%42)*192` |

Every phase is cached because text lands at arbitrary x; caching all 95
up front costs three banks and removes eviction from the draw path
entirely. A second face, or a larger one, is what makes LRU worth
building — not the system font.

Rules of thumb proven in Phase 0:

- `fx_fill`/`fx_copy` destinations must be 4-byte aligned (16 pixels).
- FX transparency is byte-granular (4 px) — masked blits are CPU RMW
  through DATA1(read)/DATA0(write); see `docs/perf.md` for the cost.
- KERNAL CHROUT (and the screen editor generally) repositions the VERA
  data ports: **never interleave KERNAL text output with port work.**
- The KERNAL IRQ handler saves/restores VERA state, so chained handlers
  and mainline port use are safe across interrupts (spike C proof).
