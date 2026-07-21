# Game guide — tile mode, the three depths, and VRAM vs bank RAM

Mode 2 is the **game** personality: two hardware VERA tile layers at 320×240
with free scrolling, plus the sprites, audio, joysticks and (via
`cx_tile_text`) the whole dialog toolkit. This guide is about the three
choices a tile game actually has to make — **colour depth**, **where the
tileset lives**, and **how it reaches the screen** — and the API that ties
them together. For the low-level VRAM/bank rationale see
[remap.md](remap.md); for the call-by-call reference see
[sdkguide.md](sdkguide.md) / [csdkguide.md](csdkguide.md).

---

## 1. The essentials

```c
cx_mode(CX_MODE_TILE);              /* two tile layers, 320x240, hw scroll  */
cx_tile_setup(0, 4);               /* layer 0 on, at 4bpp (see §2)          */
cx_tile_fill(0, CX_CELL(0, 0));    /* carpet the map with tile 0            */
cx_tile_cell(0, col, row, CX_CELL(idx, pal));   /* one cell                 */
cx_tile_scroll(0, h & 0x0FFF, v & 0x0FFF);      /* move the view (0-4095)   */
```

- **Two layers, 0 and 1** — layer 0 is usually the world, layer 1 an overlay
  (a HUD, a parallax band, or the `cx_tile_text` dialog surface).
- **8×8 tiles, a 64×32 cell map.** The screen shows 40×30 cells, so the map
  is bigger than the view — that headroom is what you scroll into.
- **A cell is one 16-bit word:** tile **index** (0–1023, so **1024 tiles
  max**), a **palette offset** (0–15), and horizontal/vertical **flip** bits.
  Build it with `CX_CELL(index, palette)`, optionally `| CX_CELL_HF |
  CX_CELL_VF`.
- **Scrolling is a register write.** `cx_tile_scroll` moves the whole layer;
  nothing is redrawn. That is the point of tiles — motion is free.

---

## 2. Choosing a depth — 2, 4, or 8 bpp

`cx_tile_setup(layer, bpp)` sets a layer to **2**, **4**, or **8** bits per
pixel. Depth trades colour for size, and size is the whole story in tile mode
because the tileset lives in VRAM:

| bpp | colours / tile | tile size | 1024-tile set | per-tile recolour? |
|---|---|---|---|---|
| **2** | 4 | 16 B | 16 KB | yes — offset picks a 4-colour slot |
| **4** | 16 | 32 B | 32 KB | yes — offset picks a 16-colour sub-palette |
| **8** | 256 | 64 B | 64 KB | no — each pixel indexes the 256 directly |

**The palette offset (the cell's `pal` field, 0–15)** is a per-cell recolour.
At 2/4bpp a tile's pixel value is *added to* `offset × 16` before it hits the
256-entry palette, so the **same tile art draws in a different palette slot**
per cell — one grey-brick tile becomes red, blue or green bricks by changing
only the cell's `pal`. At 8bpp each pixel already names one of all 256
colours, so that trick goes away; 8bpp buys raw colour, not cheap variety.

**Which to pick:**

- **2bpp** — puzzle/arcade/retro games with a tight palette. Smallest tileset
  (16 KB), fastest `cx_tile_fill`, most VRAM left for everything else. Lean on
  the palette offset for variety.
- **4bpp — the default sweet spot.** 16 colours a tile *times* 16 palette
  slots covers most games richly, and a full set is only 32 KB. `apps/tiles`
  and `apps/tiledlg` are 4bpp.
- **8bpp** — photographic/heavily-shaded art, gradients, 256-colour tiles.
  Costs the full 64 KB and usually needs the bank-RAM streaming of §4.
  `apps/tiles8` is 8bpp.

Depth is per layer: layer 0 can be 8bpp and layer 1 (a simple HUD) 2bpp.
Only the config byte and the tileset's size change with depth — the maps,
`cx_tile_cell/fill/scroll` and everything else are identical.

---

## 3. VRAM in tile mode — the stage

Tile mode uses **no bitmap framebuffer**, so the big low region is yours for
tiles and maps. The layout (constant at every depth — the tileset simply
grows downward-to-up as depth rises):

| VRAM | size | contents |
|---|---|---|
| `$00000` | ≤ 64 KB | **the tileset** (16/32/64 KB at 2/4/8bpp) |
| `$10000` | 4 KB | layer 0 map (64×32 cells) |
| `$11000` | 4 KB | layer 1 map |
| `$12000` | 4 KB | `cx_tile_text` overlay map |
| `$13000` | — | (mouse pointer, system) |
| `$14000`/`$15000` | 8 KB | double-buffer shadow maps (§6) |
| `$1E000` | 4 KB | sprite images |
| `$1F000` | 2 KB | charset (for text overlays) |

The one hard limit is the **1024-tile index** (10 bits): even at 2bpp you can
address at most 1024 distinct tiles. Everything else is comfortable — at 8bpp
the 64 KB set + 12 KB of maps fit exactly below the system region.

**Uploading a small tileset — directly:**

```c
unsigned char tiles[64];                    /* two 4bpp 8x8 tiles, 32 B each */
/* ...fill tiles[]... */
cx_vram_write(CX_TILE_IMG, tiles, sizeof tiles);   /* CX_TILE_IMG = $00000  */
```

That is fine up to a few KB. For a big 8bpp set, don't hold 64 KB of art in
your program's low RAM — use bank RAM (§4).

---

## 4. Bank RAM — the warehouse

**The rule that shapes everything: VERA displays only from VRAM.** Banked RAM
(the `$A000–$BFFF` window, up to 2 MB) is invisible to the video hardware, so
it can't hold *live* tiles — but it's the perfect **warehouse** for the whole
asset library, from which you stage the active set into VRAM.

Your app owns **bank 20 and up**:

| machine | app banks | free |
|---|---|---|
| 512 KB (base) | 20–63 | 352 KB |
| 2 MB (max) | 20–255 | **1.84 MB** |

At 8bpp a tile is 64 B (128 per bank), so a full 1024-tile set is **8 banks**.
Even the 512 KB minimum holds several tilesets; at 2 MB the warehouse is ~14×
all of VRAM. The flow:

```
SD card ──cx_bload (once, at load)──▶ banked RAM (banks 20+, the whole pack)
                                          │  cx_tile_load, per level (~75 ms/64 KB)
                                          ▼
                                    VRAM $00000  (the live tileset)
                                          │  hardware scan-out, every frame
                                          ▼
                                       screen
```

**Staging a tileset from banks to VRAM:**

```c
cx_bload("TILES8.BIN", 20, ...);              /* SD -> banks 20..27, once   */
/* ...on entering a level... */
cx_tile_load(0x00000UL, 20, 1024, 8);         /* banks -> VRAM tileset (8bpp)*/
cx_vram_stream(0x10000UL, 32, 4096);          /* a level map -> the L0 map   */
```

- **`cx_tile_load(vram_dst, first_bank, count, bpp)`** streams `count` tiles
  (it knows a tile is 8·bpp bytes) from consecutive banks into the tileset,
  chunking internally.
- **`cx_vram_stream(vram_dst, bank, count)`** is the raw byte mover under it —
  any bank→VRAM copy (maps, sprite frames, alternate palettes), rolling
  `RAM_BANK` across the 8 KB window for you.

**Cost:** a bank→VRAM copy is ~9 cycles/byte, so a full 64 KB tileset is
~4–5 frames (~75 ms). Perfect for a **level load or screen transition**; far
too slow **per frame**. During play you never re-stream pixels — you animate
by **swapping a cell's tile index** (2 bytes) and scroll with the registers.

---

## 5. Recipes

**A small tile game (2/4bpp, no streaming).** Generate or `cx_vram_write` a
handful of tiles, carpet the map, scroll. See `apps/tiles`:

```c
cx_mode(CX_MODE_TILE);
cx_vram_write(CX_TILE_IMG, tiles, sizeof tiles);
cx_tile_setup(0, 4);
cx_tile_fill(0, CX_CELL(0, 0));
for (;;) { /* read input */ cx_tile_scroll(0, h & 0x0FFF, v & 0x0FFF); }
```

**A big 8bpp game (bank warehouse).** `cx_bload` the pack once, `cx_tile_load`
per level. See `apps/tiles8` for the full self-contained example.

**A pause / dialog over the world.** `cx_tile_text(1, 1)` flips layer 1 to a
text overlay on which the *entire* toolkit — `cx_tile_puts`, `cx_rect` /
`cx_say` in cells, and the modal `cx_alert` / `cx_panel` — draws over the
still-visible game; `cx_tile_text(1, 0)` restores the game map instantly (it
was never touched). See `apps/tiletext` and `apps/tiledlg`.

**Per-frame animation you rebuild in software.** If you rewrite a lot of the
map each frame, use the double buffer so the scan-out never catches a
half-built frame — §6.

---

## 6. Double-buffering (tear-free)

Scrolling and cell pokes rarely need a double buffer. But if you **rebuild a
large part of the map every frame** (a full-screen effect, a wholesale map
change), enable one so the picture never tears:

```c
cx_ev_init();                      /* REQUIRED: cx_tile_flip waits for vblank */
cx_tile_dbuf(0, 1);                /* now cx_tile_cell/fill draw a HIDDEN map  */
for (;;) {
    /* ...draw the whole next frame into the hidden map... */
    cx_tile_flip(0);               /* present it at vblank; draw the other now */
}
```

- **`cx_tile_dbuf(layer, on)`** points drawing at a hidden shadow map
  (`$14000`/`$15000`); the shown map is untouched until you flip.
- **`cx_tile_flip(layer)`** waits for vblank, swaps which map the layer shows
  (one `MAPBASE` write, tear-free), and redirects drawing to the now-hidden
  one. It also paces you to 60 Hz — it's your `present()`.
- **Gotcha:** the flip (and `cx_frames()` / any frame timing) rides the event
  IRQ's frame counter, which only advances after **`cx_ev_init`**. Call it
  first, or the flip hangs. Draw a full frame *after* enabling the buffer and
  *before* the first flip.

The shadow maps cost 8 KB of VRAM (from the free tile-mode scratch); a
single-buffered game pays nothing.

---

## 7. Limits & gotchas, at a glance

- **1024 tiles max**, any depth (the 10-bit cell index).
- **Depth is set per layer** by `cx_tile_setup(layer, bpp)`; default/other
  values fall back to 4bpp.
- **8bpp drops per-tile palette recolour** — its pixels index the palette
  directly.
- **VERA can't read bank RAM** — big tilesets must be *streamed* to VRAM, once
  per level, never per frame.
- **`cx_tile_flip` and `cx_frames()` need `cx_ev_init`** running first.
- **Don't re-stream to animate.** Swap the cell's tile *index* (2 B) and use
  the scroll registers; keep pixel streaming for level loads.

## See also

- [remap.md](remap.md) — the VRAM + bank layout and why the maps sit at
  `$10000`.
- [sdkguide.md](sdkguide.md) / [csdkguide.md](csdkguide.md) — the per-call
  reference.
- `apps/tiles` (4bpp scroller), `apps/tiles8` (8bpp + streaming + double
  buffer), `apps/tiletext` / `apps/tiledlg` (dialogs on tiles).
