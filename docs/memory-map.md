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
| $8000–$800F | ABI header | magic `CXOS`, ABI version word, slot count, init vector, `cx_hdr_shell` ($800A) desktop-state byte (survives app loads) |
| $8010–$81A4 | jump table | 3-byte JMP slots, append-only, slot *n* at $8010+n·3 forever; 101 slots used ($8010–$813E), reserve caps at 135 (34 free) |
| $81A5–$81A8 | build word | `CX_KBUILD` (`banks.inc`), the reserve's tail; stage-0 checks it against the banked files |
| $81A9–$95FF | resident kernel | ~5.2 KB budget, ~280 B free: event core + IRQ, font hot path, region routing, far-call trampoline, loader, clipboard byte-mover (its orchestration is bank 18), port manager. `kernel.cfg` (ld65) fails on overflow; `mapreport.py` fails under 128 B free |
| $9600–$9EFF | graphics port (OVL) | 2,304-byte window; the current engine image, copied from its bank by `cx_gfx_mode` — or the tile-text dialog port (`OV3T`) swapped in by `cx_tile_text` ([graphics-port.md](graphics-port.md)) |

## Banked RAM ($A000–$BFFF window, bank register at $00) — the budget ledger

8 KB per bank. The kernel's code banks are two files: `CXBANKS.BIN`
(banks 2–5, one KERNAL LOAD) and `CXBANKS2.BIN` (banks 16–19, a second
LOAD), each 32 KB. Data banks sit between them, apps above. `tools/mapreport.py`
prints the *used*/*free* below from every kernel build's map — the numbers
here are the v0.6.0 snapshot; run it for today's.

| Bank(s) | Theme | Segment / owner | Used | Free (reserve) | Grows when you add… |
|---|---|---|---|---|---|
| 0 | KERNAL | reserved | — | — | never (KERNAL's) |
| 1 | kernel data | system font ($A000), desktop state, theme, font metrics, event overflow | — | — | data, not code |
| 2 | **UI core** | `B2CODE`: menus + theme + DA manager + the `b2_table` local jump table | ~1.8 KB | ~6.4 KB | a menu/theme/DA feature |
| 3 | mode-0 image | `OV0CODE` (2bpp GUI engine), copied to the OVL window to run | ~2.2 KB | ~5.9 KB | a bigger mode-0 engine |
| 4 | mode-1 image | `OV1CODE` (8bpp engine) | ~1.8 KB | ~6.4 KB | a bigger mode-1 engine |
| 5 | **dialogs** | `B5CODE`: dialog/alert/prompt/panel + the mode-2/3 and tile-text port images (`OV2/OV3/OV3TCODE`) | ~3.4 KB | ~4.8 KB | a dialog feature; a new small overlay image |
| 6–8 | glyph cache | pre-shifted 2bpp cache (95 glyphs × 192 B, 42/bank) + CXF sources | — | — | a second/larger font (LRU) |
| 9 | desk accessory | the open `.CXD` (`cx_da_open` loads it at $A000) | — | — | data, not kernel code |
| 10–13 | clipboard | typed text / bitmap-rect, up to 32 KB | — | — | data |
| 14–15 | save-under | dialog save-unders / DA saved state | — | — | data |
| 16 | **widgets** | `B16CODE`: the whole toolkit (code + `wg_*` state) + `wg_paint_t`; includes the icon and `WG_HIT` widgets | ~4.1 KB | ~4.1 KB | **a new widget** — and nowhere else |
| 17 | **graphics extras** | `B17CODE`: base shapes (circle/disc/ellipse/flood) + tile machinery + dirty rects + the icon sheet + the palette API | ~4.4 KB | ~3.8 KB | **a new base shape** |
| 18 | **fs / system / audio / sprites** | `B18CODE`: dir walk + `cx_file_load` + `cx_vload`/`cx_bload` + DOS channel + the font cold half (magic/header/cache builder) + `f_magic`; PSG + YM audio (with the carry shims) + hardware sprites (0.8.0); and (0.9.0) the clipboard put/get/type orchestration (its byte-mover stays resident) | ~2.2 KB | ~6.0 KB | an fs/DOS feature; cold system code; audio/sprites |
| 19 | **extra shapes** | `B19CODE` (0.8.0): the dispatched `cx_gfx_shape` family — polygon / fpolygon / arc / pie + the sin/cos table they need | ~4.1 KB | ~4.1 KB | **a new extra shape** |
| 20+ | **the app's** | `cx_bload` targets (refuses < `CX_APP_BANK_FLOOR` = 20), window backing store, allocations, file buffers | — | — | — |

**Each of banks 16–19 opens with an 8-byte signature** (`"CXB"`, bank #,
`CX_KBUILD`, code size) at `$A000`; stage-0 verifies it after loading
`CXBANKS2.BIN`, and `CXBANKS.BIN`'s twin lives at `2:$A040`. A hand-copied
SD card carrying one stale file refuses at boot instead of crashing in a
far call. The app-bank floor was 16 before CXBANKS2 claimed 16–19 (a
pre-1.0 contract change); on 512 KB there are 44 app banks, on 2 MB, 236.

### Growth policy — where a new feature goes

The banks are themed so a new feature touches exactly one, and each has
~5–7 KB of reserve so it does not reshuffle anything:

- **A new widget** → bank 16, beside the toolkit (its state goes there too).
- **A new base shape** → bank 17. **A new tile op** → bank 17.
- **A new fs / DOS / loader routine** → bank 18. Cold system code → bank 18.
  **A new audio voice or sprite feature** → bank 18 (they share it since 0.8.0).
- **A new extra shape** (polygon/arc/pie family) → bank 19, added as another
  `kind` in the `cx_gfx_shape` dispatcher.
- **A menu / theme / desk-accessory feature** → bank 2.
- **A new overlay engine image** → bank 3, 4 or 5 storage (they hold ~6 KB
  free each); the image *runs* in the OVL window, which is the tighter
  limit (2,304 B — the mode-0 image is 2,228, only 76 B of headroom).
- **Resident code** (IRQ / event / hot-path only) → the resident image,
  which keeps ~130 B free; `mapreport.py` fails the build under 128 B.
- **A new ABI slot** → the jump table has 35 free slots (cap 135); see
  `docs/banks.md` for the append + regenerate + canary steps.

When a code bank fills, it borrows reserve from a sibling (change the
`.byte` in the stubs and the bank constant in `banks.inc`), or — past
banks 2–5 + 16–19 — a THIRD `CXBANKS3.BIN` file needs a third boot LOAD
and cartridge copy pass (the `docs/banks.md` "add a bank" playbook).

### The graphics port and its banks 

The resident region `$9600`-`$9EFF` (2,304 bytes) is the graphics PORT:
the current engine image lives there, copied from its bank by `cx_gfx_mode`
([graphics-port.md](graphics-port.md)). Bank 3 = mode 0 (2bpp) image, bank
4 = mode 1 (8bpp) image, bank 5 = the mode-2 and mode-3 images
(`OV2/OV3CODE`) beside the dialog code. The mode-agnostic *shapes* and the
tile *machinery* moved to bank 17 in the restructure, but the tile
*engine image* (OV2) stays in bank 5 storage — `cx_ov_load` reads it from
the linker's `__OV2CODE_LOAD__`. In `CX_MODE_TILE`, VRAM `$00000` holds
the tileset (up to 64 KB at 8bpp) and the two 64x32 maps sit ABOVE it at
`$10000`/`$11000` — the constant mapbase at every depth, so 8bpp's full
1024-tile set has room (v0.9.0, `docs/remap.md`); the bitmap framebuffer
region is free (there is no bitmap). `cx_tile_text` adds a 1bpp **text**
overlay: a fifth port image `OV3T` (bank 5 storage, run in the OVL) draws
menus/widgets/dialogs onto a text map at `$12000` using the KERNAL charset
the tile engine stages at `$1F000`. Double-buffering (`cx_tile_dbuf` /
`cx_tile_flip`) uses shadow maps at `$14000`/`$15000`. The game's own maps
are never touched by the overlay, so lowering it is instant.

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

## The resident budget, and what it cost to fit — *(pre-restructure history)*

> **This section predates v0.6.0.** Its `$8200`/7,424-byte budget and its
> "everything in bank 2" model are how the kernel looked before the memory
> restructure. The live per-bank budget is the ledger at the top of this
> file and [banks.md](banks.md) (`$81A9`–`$95FF` resident, ~130 B free; the
> jump table widened to 135 slots; code themed across banks 2–5 + 16–19).
> Kept for the reasoning it records — the x16lib gate trim, the save-under
> placement — which still holds.

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

Placement (0.4-era): `JUMPHDR` at `$8000`, `JUMPTAB` at `$8010`–`$812C`,
`CODE` at `$8160`. (Post-restructure: `CODE` at `$81A9`, table reserve to
`$81A4` — see the banner at the top of this section.)

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

- **Banking the cold code** is done — `font_cache` (and the CXF magic +
  header parse) run once per font adopt and have no business resident, so
  the pre-1.0 restructure moved them to bank 18. The resident image keeps
  only the draw path; the cold half reads the font through resident peeks
  and writes the cache through a resident poke, because bank-18 code
  cannot page a bank into its own window. That freed 186 bytes, which the
  jump table spent widening from ~110 to 135 slots. Resident now holds
  ~130 free bytes and the table 35 free slots — see the ledger above and
  `docs/banks.md`.

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

### Booting from a cartridge

The same kernel also ships in ROM. `kernel/boot/cart.asm` + `cart.cfg`
build an 80 KB image (`build/cxgeos_cart.bin`, **five cartridge ROM banks
32–36**) that `x16emu -cartbin` loads at bank 32. After hardware init the
stock KERNAL scans ROM bank 32 for `"CX16"` at `$C000` and jumps to
`$C004` with interrupts disabled (Programmer's Reference: Booting from
Cartridges) — so the cart needs neither `AUTOBOOT.X16` nor a ROM patch.

The stub does exactly what stage-0 does, from ROM instead of SD: it copies
the resident image (bank 32) to `$8000`, the font (bank 32) to RAM bank 1,
`CXBANKS.BIN` (banks 33–34) to RAM banks 2–5 and `CXBANKS2.BIN` (banks
35–36) to RAM banks 16–19, then brings the machine to the state BASIC's
cold start would leave (`IOINIT`/`RESTOR`/`CINT`/`cli`) and calls `cx_init`
— the same hand-off as `auto.asm`. `CXKERNEL.PRG`, the banked files and
the ABI are reused unchanged; the kernel runs from the same RAM either way.
The cross-bank copy runs from low RAM (`$0400`) so it can page `ROM_BANK`
out from under bank 32, and it runs twice (a parameterized `bankcopy`, one
call per file).

Kernel-only for now: the desktop, apps and user files still load off the
SD card (the cart's `"CX16"` auto-boot wins over the card's `AUTOBOOT.X16`,
so one card serves both boot paths). `build.ps1 -Cart` builds the image and
`-Cart -Boot` runs it; a cart chain in `-Test` boots it headless to the
desktop. A self-contained cart with the apps embedded is a later phase.

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
