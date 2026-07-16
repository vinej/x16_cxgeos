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
| 6–7 | system font glyph sources + icon sheets (ZX0-unpacked at boot) |
| 8–9 | reserved kernel growth |
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
| $17100–$1DFFF | 28,416 | glyph caches (pre-shifted ×4 phases) + icon/pattern sheets |
| $1E000–$1EFFF | 4,096 | CXGEOS sprite images (extra cursors, drag outlines) |
| $1F000–$1F7FF | 2,048 | KERNAL charset — kept for the panic/debug console |
| $1F800–$1F9BF | 448 | unused by VERA; x16lib `VRAM_FX_SCRATCH` = $1F800 (4 bytes) |
| $1F9C0–$1F9FF | 64 | PSG registers (hardware) |
| $1FA00–$1FBFF | 512 | palette (hardware) |
| $1FC00–$1FFFF | 1,024 | sprite attributes (hardware) |

Rules of thumb proven in Phase 0:

- `fx_fill`/`fx_copy` destinations must be 4-byte aligned (16 pixels).
- FX transparency is byte-granular (4 px) — masked blits are CPU RMW
  through DATA1(read)/DATA0(write); see `docs/perf.md` for the cost.
- KERNAL CHROUT (and the screen editor generally) repositions the VERA
  data ports: **never interleave KERNAL text output with port work.**
- The KERNAL IRQ handler saves/restores VERA state, so chained handlers
  and mainline port use are safe across interrupts (spike C proof).
