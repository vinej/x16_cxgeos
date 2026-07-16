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
nothing for ld65 to strip. `X16_USE_BITMAP2` needs `fx_fill` and gets
`fx_mult`, `fx_line`, `fx_triangle`, `fx_copy`, `fx_affine` with it.
Measured: `BITMAP2` alone is 4,795; `+IRQ +INPUT` is 5,234;
`+SCREEN +LOAD +BANK` is 6,055.

Four ways out, and the choice is an architecture decision, not a tidy-up:

1. **Bank the cold code**, which is what the plan always said the
   resident was: gfx2's hot paths, the glyph blitter, the event core and
   the bank trampoline — *not* the whole font engine (`font_cache` runs
   once at boot), *not* the dirty-rect list, *not* gfx2's line and
   pattern code. Needs the trampoline, which Phase 4 owes anyway.
2. **Finer gates upstream.** `X16_USE_VERAFX_FILL` beside
   `X16_USE_VERAFX` would give the whole ecosystem the saving, not just
   CXGEOS. It is the honest fix for the cause rather than the symptom.
3. **Drop what is not called yet** (`SCREEN`, `LOAD`, `BANK`: 821 bytes)
   and **move the font blob to a bank** (871). That reaches 7,330 — it
   fits, with 94 bytes spare, which is not a budget so much as a dare.
4. **Move the boundary.** The app's `$0801`–`$7FFF` is 30 KB; the kernel
   could take more of it. The table's address is a promise, the code's
   is not.

(1) and (2) are the real answers and they compose. (3) buys a week and
costs the next person a day. Nothing is decided here.

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
