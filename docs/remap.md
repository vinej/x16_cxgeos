# VRAM + banked-RAM restructure — 8bpp tiles and a flexible layout

**Status: IMPLEMENTED (v0.9.0).** All of this shipped: the tile maps moved to
`$10000`, `cx_tile_setup` gained a `bpp` param, `cx_tile_text`'s restore is
bpp-aware, and `cx_vram_stream` / `cx_tile_load` / `cx_tile_dbuf` /
`cx_tile_flip` are live ABI v4 slots. `apps/tiles8` exercises the whole 8bpp
stream+flip chain (in the boot smoke). It captures two things:

1. A **VRAM remap** that unifies all three video modes into one layout and, in
   particular, lets **tile mode (mode 2) run at 8bpp with the full 1024-tile
   set** — which the current layout cannot fit.
2. A **banked-RAM plan** for holding the (now much larger) 8bpp tile/asset
   library and streaming it onto the VRAM "stage".
3. **One new developer primitive — `cx_vram_stream`** (bank → VRAM, §3.7) — the
   missing piece that makes the warehouse→stage flow a one-liner, plus a
   `cx_tile_load` convenience over it.

Nothing here changes mode 0 or the existing 4bpp tile behaviour unless an app
opts in — the defaults stay exactly as they are today.

**Decided out of scope (this round):** *no new bitmap depths for mode 1.* At
320×240 the VRAM-footprint reason for low bpp evaporates (even 8bpp is only
75 KB), 8bpp is the simplest and often fastest to draw (1 byte = 1 pixel, no
masking), and CXGEOS already has it. 4bpp would be a whole new pixel engine for
no payoff at this resolution; 2bpp has only narrow niche uses. So **mode 1 stays
8bpp-only** — the bpp knob that actually earns its keep is the tile one, because
tiles are where VRAM is contended (the 64 KB 8bpp set). See §5 for the reasoning.

---

## 0. The one hardware rule everything follows

- **VERA displays only from its own 128 KB of VRAM.** The CPU's banked RAM
  (`$A000–$BFFF` window, up to 2 MB) is *invisible* to the video hardware.
- **There is no blitter/DMA.** Every RAM↔VRAM move is a CPU byte-loop through
  the VERA data port. Cost scales with **bytes**, and bytes = pixels × bpp/8.
- Therefore: what the scan-out reads each frame **must** be in VRAM; everything
  else can live in banked RAM and be **streamed in on demand** (a per-swap
  cost, never a per-frame cost).

Reference numbers (measured, see [perf.md](perf.md)): frame = 133,333 cycles;
CPU port copy ≈ 9 cycles/byte; VERA-FX fill ≈ 2.3 cycles/byte.

---

## 1. What the modes support after this change

| mode | resolution | depths | note |
|---|---|---|---|
| 0 (desktop) | 640×480 bitmap | **2bpp** | unchanged; 4bpp is impossible (see §5) |
| 1 (image) | 320×240 bitmap | **8bpp** | unchanged; 2/4bpp deliberately not added (see §5) |
| 2 (tiles) | 320×240 tiles | **2 / 4 / 8bpp** | 8bpp is the reason for the remap |

The only mode gaining a depth is **mode 2 (tiles) → 8bpp**. Everything else is
unchanged.

---

## 2. VRAM restructure

### 2.1 The principle — two zones, split at `$13000`

Only one mode is active at a time, so VRAM divides into:

- **Canvas** (`$00000–$12FFF`, 76 KB) — the *current mode's* picture. Its
  meaning changes per mode (framebuffer vs tileset+maps); it is transient.
- **System** (`$13000–$1FFFF`, 52 KB) — persistent across modes: the mouse
  pointer, sprites, charset, save-under/scratch, and the fixed VERA hardware
  registers.

The KERNAL mouse-pointer sprite is pinned at **`$13000`** (r49's driver
hardcodes it), and — conveniently — both the 75 KB `640×480@2bpp` framebuffer
*and* the 76 KB `8bpp tiles+maps` fit exactly below it. So `$13000` is the
natural boundary between the two zones.

### 2.2 System zone — identical in every mode

| range | size | contents | fixed? |
|---|---|---|---|
| `$13000–$130FF` | 256 B | KERNAL mouse pointer sprite | **yes** (driver) |
| `$13100–$1DFFF` | ~44 KB | bitmap-mode **save-unders** / tile-mode **free scratch** (double-buffer shadows, extra sprite frames) | no |
| `$1E000–$1EFFF` | 4 KB | CXGEOS sprite images (cursors, drag outlines) | no |
| `$1F000–$1F7FF` | 2 KB | charset (text/tile-text overlays + panic console) | semi |
| `$1F800–$1F9BF` | 448 B | VERA FX scratch | no |
| `$1F9C0–$1F9FF` | 64 B | PSG audio registers | **yes** (HW) |
| `$1FA00–$1FBFF` | 512 B | palette | **yes** (HW) |
| `$1FC00–$1FFFF` | 1 KB | sprite attributes | **yes** (HW) |

### 2.3 Canvas zone — repurposed per mode (`$00000–$12FFF`)

**Mode 0 — desktop, 640×480 @2bpp** (unchanged from today)

| range | size | contents |
|---|---|---|
| `$00000–$12BFF` | 75 KB | framebuffer |
| `$12C00–$12FFF` | 1 KB | blit / scratch strip |

**Mode 1 — bitmap app, 320×240 @2/4/8bpp** (unchanged from today)

| range | size | contents |
|---|---|---|
| `$00000–…` | 19 KB (2bpp) / 37.5 KB (4bpp) / 75 KB (8bpp) | framebuffer |
| remainder → `$12FFF` | free | 2nd buffer for **double-buffering at ≤4bpp** (2×37.5 KB fits; 8bpp cannot) |

**Mode 2 — tile game @2/4/8bpp** — *this is the remap*

| range | size | contents |
|---|---|---|
| `$00000–$0FFFF` | up to 64 KB | **tileset** — 1024 tiles: 16 KB@2bpp / 32 KB@4bpp / 64 KB@8bpp |
| `$10000–$10FFF` | 4 KB | layer 0 map |
| `$11000–$11FFF` | 4 KB | layer 1 map |
| `$12000–$12FFF` | 4 KB | text-overlay map (`cx_tile_text`) |

### 2.4 The actual change

Only the **tile maps move**, so the 8bpp tileset has room to reach `$0FFFF`:

| map | today | proposed | mapbase reg (addr » 9) |
|---|---|---|---|
| layer 0 | `$08000` | `$10000` | `$40` → `$80` |
| layer 1 | `$09000` | `$11000` | `$48` → `$88` |
| text overlay | `$0A000` | `$12000` | `$50` → `$90` |

**Fix the maps at `$10000` for *all* tile depths**, not just 8bpp. Then the
engine's mapbase is a constant and only the config byte + tileset size vary
with depth — one code path for 2/4/8bpp. The tileset simply grows from
`$00000` upward as depth increases; at 2bpp it uses only `$00000–$03FFF`,
leaving the rest free.

Config byte (VERA `Lx_CONFIG`, low 2 bits = depth):

| depth | config byte | tile bytes (8×8) |
|---|---|---|
| 2bpp | `$11` | 16 |
| 4bpp | `$12` (current) | 32 |
| 8bpp | `$13` | 64 |

### 2.5 Reachability (so this is not theoretical)

- mapbase = value « 9, max `$1FE00` → `$10000/$11000/$12000` = `$80/$88/$90` ✓
- tilebase = value « 11, max `$1F800` → tileset `$00000` = 0 ✓, charset
  `$1F000` reachable ✓

---

## 3. Banked-RAM restructure

### 3.1 The role split

- **VRAM = the stage.** Only the *live* tileset + maps (the §2.3 mode-2
  layout). At 8bpp that is the 64 KB set currently on screen.
- **Banked RAM = the warehouse.** The app's *full* asset library — every
  tileset, every level map, sprite-frame libraries, alternate palettes —
  loaded from SD once, then streamed to VRAM per level/transition.

VERA cannot read banked RAM, so the warehouse never displays anything
directly; it feeds the stage.

### 3.2 What's free for an app

CXGEOS reserves banks 0–19 ([banks.inc](../kernel/resident/banks.inc):
`CX_APP_BANK_FLOOR = 20`). Apps own bank 20 upward:

| machine RAM | app banks | free |
|---|---|---|
| 512 KB (base) | 20–63 (44 banks) | 352 KB |
| 2 MB (max) | 20–255 (236 banks) | **1.84 MB** |

Even the minimum is 5× a full 64 KB tileset; at 2 MB the warehouse is ~14× the
size of *all* VRAM.

### 3.3 8bpp asset sizing (8 KB per bank)

| asset | size | per bank |
|---|---|---|
| one 8bpp tile (8×8) | 64 B | 128 tiles |
| full 1024-tile 8bpp set | 64 KB | **8 banks** |
| one tilemap (64×32) | 4 KB | 2 maps |
| 16×16 8bpp sprite frame | 256 B | 32 frames |

### 3.4 Sample bank layout for an 8bpp tile game

Illustrative — the app carves its own free space; the only fixed fact is
"one 8bpp tileset = 8 banks".

| banks | size | contents | streams to |
|---|---|---|---|
| 20–27 | 64 KB | master 8bpp tileset (1024 tiles) | VRAM `$00000` |
| 28–31 | 32 KB | alternate tilesets (level themes) | `$00000` on theme change |
| 32–39 | 64 KB | level maps (big scrolling world / many screens) | VRAM `$10000/$11000` |
| 40–47 | 64 KB | sprite-frame library (256 frames) | VRAM `$1E000` (active set) |
| 48–55 | 64 KB | next-level staging / double-buffer sources | — |
| 56–255 | ~1.6 MB | more levels, music, cutscene data… | — |

### 3.5 The gap in today's API

The data-movement paths that exist:

| path | how | who |
|---|---|---|
| SD → VRAM | `cx_vload` (slot 90) | KERNAL VLOAD |
| SD → bank | `cx_bload` (slot 91) | KERNAL BVLOAD |
| low RAM → VRAM | `cx_vram_write` | **C-only** helper (pokes the VERA port) |
| RAM ↔ bank | the clipboard byte-mover | clipboard only, not general |

**There is no bank → VRAM path** — exactly the warehouse→stage step an 8bpp
game needs every level. An app *can* hand-roll it (map a bank at `$A000`, poke
the VERA port, roll `RAM_BANK` every 8 KB), but it is fiddly and has a trap:

- **8 KB window crossing.** A 64 KB tileset is 8 banks; `RAM_BANK` must bump
  every 8 KB. Maps and the sprite set stream the same way.
- **Self-unmap hazard.** The copy loop must not execute *from* the bank it is
  paging (the `vrows_save` / clipboard lesson). App code lives in low RAM so an
  app-side loop is safe, but a kernel helper gets it right once for everyone.
- **Cost.** ~9 cycles/byte → a full 64 KB tileset ≈ 590 K cycles ≈ **~4–5
  frames (~75 ms)**: fine for a **level-load / screen transition**, far too slow
  per-frame. During play, animate by **swapping the tile *index* in a cell**
  (2 bytes), not by re-streaming pixels, and scroll with the hardware registers.

So this proposal adds the missing primitive — see §3.7.

### 3.6 The flow, end to end

```
SD card ──(cx_bload, slow, once at startup)──▶ banked RAM (banks 20+, the pack)
                                                   │
                                                   │ cx_vram_stream — §3.7
                                                   │ ~75 ms / 64 KB, on level change
                                                   ▼
                                             VRAM $00000  (the live 8bpp tileset)
                                                   │  hardware scan-out, every frame
                                                   ▼
                                                screen
```

### 3.7 New feature — `cx_vram_stream` (bank → VRAM) + `cx_tile_load`

**`cx_vram_stream` — a new ABI slot.** Copies `count` bytes from banked RAM
into VRAM, rolling `RAM_BANK` across 8 KB boundaries. Its copy loop is
**resident** (low RAM) so it can flip `RAM_BANK` without unmapping itself —
the same discipline the clipboard byte-mover already uses, and small (~40 B).

Proposed contract (P-block, matching `cx_vload`'s style):

| in | meaning |
|---|---|
| `P0/P1` | VRAM destination (low 16 bits) |
| `P2` | VRAM destination bit 16 (0 = `$00000–$0FFFF`, 1 = `$10000–$1FFFF`) |
| `P3` | first source bank (data starts at that bank's `$A000`; keep assets bank-aligned) |
| `P4/P5` | byte count (rolls into `P3+1`, `P3+2`… as it crosses 8 KB) |

Reciprocal of `cx_vload`: same VRAM addressing, source is a bank instead of a
file. Reachable from every language (it's an ABI slot), unlike `cx_vram_write`.

**`cx_tile_load` — a csdk convenience** on top of it, so a game needn't do the
tile-size arithmetic:

A tile is **8·bpp** bytes (8bpp = 64, 4bpp = 32, 2bpp = 16), so a full
1024-tile 8bpp set is 64 KB — one byte past the 16-bit count. `cx_tile_load`
therefore streams in 32 KB (bank-aligned) chunks so each `cx_vram_stream` call
stays inside the count:

```c
static void cx_tile_load(unsigned long vram_dst, unsigned char first_bank,
                         unsigned count, unsigned char bpp) {
    unsigned long bytes = (unsigned long)count * bpp * 8;      /* 8*bpp per tile */
    while (bytes) {
        unsigned chunk = (bytes > 0x8000UL) ? 0x8000 : (unsigned)bytes;
        cx_vram_stream(vram_dst, first_bank, chunk);
        vram_dst   += chunk;
        first_bank += (unsigned char)(chunk >> 13);           /* banks consumed */
        bytes      -= chunk;
    }
}
```

**Worked example — the sample layout of §3.4, in an 8bpp game:**

```c
/* --- startup: fill the warehouse from SD, once (banks per §3.4) --- */
cx_bload("TILES.BIN", 20, ...);          /* 64 KB master tileset  -> banks 20–27 */
cx_bload("MAPS.BIN",  32, ...);          /* level maps            -> banks 32+    */
cx_bload("SPRITES.BIN", 40, ...);        /* sprite-frame library  -> banks 40+    */

cx_tile_setup(0, 8);                     /* mode 2, layer 0, 8bpp (proposed param) */

/* --- on level start: stage the active set onto VRAM (the remap addresses) --- */
cx_tile_load(0x00000, 20, 1024, 8);      /* banks 20–27 -> tileset $00000 (64 KB) */
cx_vram_stream(0x10000, 32, 4096);       /* level-0 map -> layer-0 map  $10000     */

/* --- play: scroll + poke cells; NEVER re-stream pixels per frame --- */
for (;;) {
    cx_tile_scroll(0, camera_x, camera_y);      /* hardware scroll, tear-free  */
    cx_tile_cell(0, col, row, animated_index);  /* animate by index swap, 2 B  */
    /* on level change: cx_tile_load(...) the next theme, cx_vram_stream the map */
}
```

That is the whole 8bpp developer story: **`cx_bload` once, `cx_tile_load` /
`cx_vram_stream` per level, and per-frame is just scroll + cell pokes.**

---

## 4. Tile double-buffering — a kernel feature (`cx_tile_flip`)

A tilemap is only 4 KB, so a shadow map is nearly free, and the flip is a single
`MAPBASE` register write at vblank — far cheaper than any bitmap flip. This is
worth doing in the kernel so apps don't reinvent the vblank timing. **Decided:
provide `cx_tile_flip`.**

- **Shadow maps** live in the tile-mode scratch (`$13100–$1DFFF`, free in tile
  mode): **L0' at `$14000`, L1' at `$15000`** (mapbase `$A0`/`$A8`), 4 KB each.
  A double-buffered game spends 8 KB of that scratch; a single-buffered one
  spends none.
- **Opt-in per layer** (`cx_tile_dbuf(layer, on)`, or implied by the first
  `cx_tile_flip`). While on, `cx_tile_cell` / `cx_tile_fill` write to the
  **hidden** ("draw") map; the shown one is untouched, so the scan-out never
  catches a half-built frame.
- **`cx_tile_flip(layer)`** waits for the next vblank, swaps the layer's
  `MAPBASE` (shown ↔ draw), and redirects subsequent cell writes to the
  now-hidden map. One call per frame ≈ a `present()` that also paces to 60 Hz.
  It waits on `irq_frame_count`, which the event IRQ ticks on VSYNC, so
  **`cx_ev_init` must have been called first** (as it must for `cx_frames()`
  too) — otherwise the counter never advances and the flip hangs.
- Single-buffered (**default**) is unchanged: draw == shown, no scratch used,
  `cx_tile_flip` unused.

**Mode-1 (8bpp) cannot double-buffer** — two 75 KB buffers = 150 KB > VRAM.
That's fine for its job (static images / an occasionally-updated canvas, not
per-frame software animation — that's what mode 2's tiles + sprites are for).

---

## 5. Constraints and caveats

- **Mode 0 at 4bpp is impossible.** 640×480 @4bpp = 153,600 B > 128 KB total
  VRAM — the framebuffer alone exceeds all of VRAM. 2bpp is the ceiling at
  640×480; for 16/256 colors, drop to 320×240 (mode 1). No remap changes this.
- **Mode 1 stays 8bpp — 2bpp/4bpp deliberately not added.** At 320×240 all
  three depths fit VRAM, so the footprint argument that forces low bpp at
  640×480 doesn't apply. 8bpp is then the natural pick: simplest to draw (1
  byte = 1 pixel, no read-modify-write masking), 256 colors "for free" since
  the VRAM is there, and it already exists. **4bpp** would need a brand-new
  nibble-packing engine (~a second `ov1`-sized image; no code to reuse — CXGEOS
  only has 2bpp `gfx2` and 8bpp `ov1`) for essentially no benefit here. **2bpp**
  is cheap to add later (reuse `gfx2` with a 320-wide init + a `cx_minfo` row),
  but its only real wins — double-buffering and per-frame full-screen software
  redraw — are cases you'd serve with mode 2 (tiles + sprites) anyway. So both
  are left out; revisit 2bpp only if a concrete app needs it.
- **8bpp palette semantics differ.** In 2/4bpp the cell's palette-offset nibble
  picks one of 16 sub-palettes (per-tile recolour). In 8bpp each pixel indexes
  the full 256-entry palette directly, so that per-tile trick effectively goes
  away.
- **`cx_tile_text` restore must become bpp-aware.** Today the overlay's "off"
  path restores a hardcoded 4bpp (`$12`). It must put back the layer's *actual*
  depth (`$11/$12/$13`), which means storing per-layer bpp state. Its text map
  moves to `$12000`; the charset stays at `$1F000`.
- **8bpp asset size.** Tiles are 2× the bytes of 4bpp — bigger SD footprint,
  longer streams, more warehouse banks. This is exactly why the banked-RAM
  warehouse matters at 8bpp.
- **Bank count scales with installed RAM** (512 KB → 44 app banks, 2 MB → 236);
  an app that assumes 2 MB must degrade gracefully on 512 KB.

---

## 6. Code deltas (summary of what will actually change)

| area | change | cost |
|---|---|---|
| [tiles.asm](../kernel/video/tiles.asm) `tile2_setup` | take a **bpp** param; write config `$11/$12/$13` instead of hardcoded `$12` | tiny |
| [tiles.asm](../kernel/video/tiles.asm) `t2_mapb` | mapbase `$40/$48` → `$80/$88` (maps to `$10000/$11000`) | tiny |
| [tiles.asm](../kernel/video/tiles.asm) `cx_tile_text` | text map → `$12000` (`$90`); restore the layer's real bpp, not `$12`; store per-layer bpp | small |
| ABI / SDK | `cx_tile_setup(layer, bpp)` — bpp in `X` (`cxb_call` passes X through), default 4bpp so nothing existing changes; wrappers across csdk / asmsdk / prog8 | 0 slots (rides X) |
| **ABI (new slot)** | **`cx_vram_stream`** (§3.7) — bank → VRAM, bank-aligned source, rolls `RAM_BANK` across 8 KB; a **resident** copy loop (~40 B) + thin orchestration; appended slot | ~40 B resident + 1 slot |
| **ABI (new slot)** | **`cx_tile_flip(layer)`** (§4) — waits for vblank, swaps `MAPBASE` shown↔draw, redirects cell writes to the hidden map; plus `cx_tile_dbuf(layer, on)` to enable it and reserve the `$14000/$15000` shadows | 1–2 slots (bank 17, beside the tile machinery) |
| SDK | `cx_tile_load` (csdk convenience over `cx_vram_stream`, §3.7) + plain `cx_vram_stream` / `cx_tile_flip` / `cx_tile_dbuf` wrappers across csdk / asmsdk / prog8 | — |
| docs | flip this file's status; update the VRAM ledger in [memory-map.md](memory-map.md); the tile ledger comment in tiles.asm; add the new calls to the SDK guides | — |

Budget: appended ABI slots — `cx_vram_stream` (~40 resident B for its
byte-mover) and `cx_tile_flip`/`cx_tile_dbuf` (bank 17, no resident cost); the
`bpp` param rides `cx_tile_setup`'s `X`. Resident budget has ~267 B free.
Defaults preserve all current behaviour — mode 0, mode 1, and 4bpp tiles are
untouched, and a single-buffered tile game is unaffected.

*Not in this round:* mode-1 2bpp/4bpp (§5), and mode-1 double-buffering (can't
fit at 8bpp, §4).

---

## 7. Decisions (resolved)

All design questions are settled — this section records the calls made.

1. **`cx_vram_stream` — bank-aligned source** (§3.7). Assets are whole files
   `cx_bload`ed to a bank, so they start on a bank boundary; a start-offset
   param can be added later if a non-aligned case ever needs it.
2. **Maps fixed at `$10000` for *all* tile depths** (§2.4), not just 8bpp — one
   constant mapbase, only the config byte and tileset size vary with depth.
3. **`cx_tile_flip` is a kernel feature** (§4) — shadow map in the tile scratch
   + a vblank `MAPBASE` swap, opt-in per layer via `cx_tile_dbuf`.
4. **bpp rides `cx_tile_setup`'s `X` param** (default 4bpp, no new slot for it);
   **mode 1 stays 8bpp-only** (§5).

**Ready to implement.** Suggested order: (a) tile map relocation + `bpp` param +
`cx_tile_text` restore; (b) `cx_vram_stream` + `cx_tile_load`; (c) `cx_tile_dbuf`
/ `cx_tile_flip`; (d) an 8bpp tile demo app exercising all three, SDK wrappers,
and docs — each step build-tested and gif-verified.
