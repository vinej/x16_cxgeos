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

## The resident budget, and what it cost to fit

`kernel/kernel.cfg` pins the image and lets ld65 enforce the budget
rather than leaving it a comment someone has to remember. The first
build it judged, it failed — and the failure was worth having.

| | at first | after 0.4.1 | now |
|---|---|---|---|
| x16lib | 6,055 | 3,893 | **3,072** |
| CXGEOS kernel code | 2,096 | 2,096 | 3,650 (+3,944 in bank 2) |
| `fonts/pxl8.cxf` | 871 | 871 | **0 — on the SD card** |
| **resident total** | **9,022** | **6,728** | **6,525** (+4,314 in bank 2) |
| budget, `$8200`–`$9EFF` | 7,424 | 7,424 | 7,424 |
| | **over by 1,598** | 696 spare | **899 spare** |

(The resident figure grew through Phase 4c's loader and shell-returning
cx_exit, Phase 5a's region stack and far-call trampoline, and Phase 5b's
theme record and vrows save-under helper — while the menu, theme and
dialog ENGINES' 1,749 bytes went to bank 2, exactly what the trampoline
exists for. `CXBANKS.BIN` is the second file the kernel build emits, and
stage-0 loads it to bank 2 at boot; when bank 3 exists it appends there
and the one LOAD keeps working.)

Two save-under stores, because two things get covered and they are not
the same size:

- **Menus** → the VRAM strip at `$13100` (`fx_copy`, `_FILL`/`_COPY`
  gated). Full rows, up to the drop-down's height. NOT `$12C00`: the
  KERNAL mouse pointer image is at `$13000`, and a strip based there is
  written through the moment a menu opens over an arrow.
- **Dialogs** → banked RAM, banks **14-15** (`vrows_save`/`restore`,
  resident because bank-2 code cannot stream into another bank through
  the window it executes from). A 400×96 alert is 15,360 bytes, past one
  bank; 14-15 are the DA slots, and no desk accessory shares the screen
  with a modal alert. NOT banks 6-8 — those are the font cache, and a
  dialog that saved there ate its own message glyphs.

Placement is proven: `JUMPHDR` at `$8000`, `JUMPTAB` at `$8010`–`$806C`
(93 bytes = 31 slots × 3), `CODE` at `$8200`.

**Two thirds of the image was the library, and most of it was unused.**
Measured, one gate at a time, when it first failed to fit:

| gate | bytes | what CXGEOS calls from it | now |
|---|---|---|---|
| VERA | 143 | `vera_fill`, via gfx2 | kept |
| **VERAFX** | **2,502** | **`fx_fill`, via gfx2 — and nothing else** | **`_FILL` alone: 340** |
| BITMAP2 (gfx2 itself) | 2,149 | all of it | kept |
| IRQ | 400 | all five routines | kept |
| INPUT | 39 | `mouse_get`/`show`/`hide` | kept |
| SCREEN | 121 | `screen_set_mode`, in `cx_exit` alone | **dropped** |
| LOAD | 76 | nothing yet | **dropped** |
| BANK | 624 | nothing — `font.asm` writes `RAM_BANK` itself | **dropped** |

The 320×240 8bpp module was never linked: the gates select correctly.
The problem was granularity. x16lib is one translation unit, so a gated
module links whole — `X16_USE_VERAFX` existed to give gfx2 `fx_fill` and
handed over `fx_mult`, `fx_copy`, `fx_transp`, `fx_affine`, `fx_line`
and `fx_triangle` with it.

**Fixed upstream, in x16lib 0.4.1:** VERAFX now has parts, and BITMAP2
asks for `_FILL` alone. Worth 2,162 bytes here, and worth it to every X16
program that wanted a fast fill and paid for a rotozoom sampler to get
one. `X16_USE_VERAFX` still means all of it, so nothing that existed
broke. A CXGEOS-local trimmed copy would have worked and been the wrong
answer: the vendored tree is a clean snapshot on purpose, and the next
re-vendor would have silently undone it.

**Then the gates nothing called went**, for another 821: `cx_exit`
inlines the four instructions it wanted out of SCREEN, and LOAD and BANK
were being carried for a loader that does not exist. They come back when
something calls them. The rule the numbers argue for: **a gate is not
free, and in a single translation unit it is not lazy either** — what it
pulls in, the image carries whether anything calls it or not.

### What is left, and why

- **The font blob is out** (Phase 4c): it ships as `PXL8.CXF` and the
  boot loader puts it at `CX_SYSFONT_BANK`:`$A000` — bank 1, the kernel
  data bank — before calling `cx_init`. The font engine captures the
  bank at `font_set` and switches to it for every source read (header,
  rows while caching, widths at draw time), so a font may live in low
  RAM or in one banked window, up to 8 KB. `cx_init` judges the font
  *before* switching video modes: if the loader forgot it, the carry
  comes back while the machine can still print with the KERNAL.

  (An earlier note here claimed the blob had to stay resident so a
  kernel whose font failed to load could still report it. That was
  wrong: the KERNAL charset is kept at VRAM `$1F000` for exactly that
  panic console, and it needs nothing of ours.)

- **Banking the cold code** is still right — `font_cache` runs once at
  boot and has no business resident — but with 1,512 spare it is now a
  choice rather than a debt.

## The boot chain (Phase 4c)

Stock ROM runs `AUTOBOOT.X16` from the SD root — that is the entire
boot hook, and the reason CXGEOS needs no ROM patch. Stage-0 LOADs
`CXKERNEL.PRG` to $8000 (the file's own header address), checks the
`CXOS` magic, LOADs `PXL8.CXF` headerless to bank 1:$A000, calls the
init vector at $8008, then hands off: `AUTORUN.CXA` if the disk has one
(the boot smoke test's hook), else `cx_exit` — which IS "go to the
shell". Every stage-0 failure ends at a printed message and BASIC.

Addresses the loader owns:

- **$0400–$041F** — the CXAP header staging area. Judged here before
  the payload is allowed to overwrite the caller. Below app space, in
  RAM the KERNAL leaves alone; costs the resident budget nothing.
- **$0801–$7FFF** — app space, and the loader's hard ceiling. A payload
  that would reach $8000 is stopped: one byte further is the kernel's
  header, and $8010 is the jump table every app depends on. (An early
  draft said $9F00, "where I/O starts" — wrong by 7,936 bytes; the
  kernel lives in them.)
- **Bank 1** (`CX_SYSFONT_BANK`) — the kernel data bank. First tenant:
  the system font at $A000, put there by stage-0, read by the font
  engine for as long as the font is live. The theme record comes next
  (Phase 5).

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
