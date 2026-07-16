# CXGEOS

A from-scratch, GEOS-inspired graphical desktop OS for the Commander X16.

Not a port. The earlier `X16_Geos` project migrated the original C64 GEOS 2.0
to the X16 and proved the concept — and its ceiling: 320×200, proprietary app
binaries, a patched KERNAL ROM. CXGEOS is the clean break:

- **640×480 @ 4 colors** (VERA layer 0, 2bpp bitmap) — crisp, proportional
  fonts everywhere, color-schemable UI.
- **Stock ROM (R49+)**: boots from the SD card via `AUTOBOOT.X16`, no ROM
  patches, no cartridge required (a cartridge build comes later).
- **Native CMDR-DOS FAT32 files** — no .d64 images, no disk swapping.
- **Apps in any toolchain**: a GEOS-style fixed jump-table ABI with generated
  bindings for 7 assemblers (ACME, ca65, 64tass, KickAssembler, dasm, MADS,
  vasm) and 5 C compilers (cc65, llvm-mos, KickC, Oscar64, vbcc).
- Foundationed on [x16lib](https://github.com/vinej/x16_library): the kernel
  vendors the ca65 edition (`x16lib/`, byte-identical to the ACME reference,
  same on-target test suite).

## Layout

```
kernel/           the OS: boot, resident core, gfx2, fonts, events, ui, shell, fs
x16lib/           vendored x16_library src_ca65 tree (pinned; see below)
abi/              jump-table manifest + binding generator
sdk/              GENERATED bindings + app skeletons (committed)
apps/             system applications and desk accessories
spikes/           Phase 0 throwaway risk prototypes (perf numbers in docs/perf.md)
tools/            font converter, SD-image builder, cartridge packer
test/             on-target regression suites (x16lib runner pattern)
docs/             memory-map.md (the RAM/VRAM ledger), perf.md, abi.md, formats.md
```

## Building

Repo-local tools, never committed:

- `cc65\ca65.exe` + `cc65\ld65.exe` — from [cc65](https://cc65.github.io/)
- `emulator\x16emu.exe` + SDL DLLs — from
  [x16-emulator](https://github.com/X16Community/x16-emulator)
- `emulator\rom.bin` — **the official stock R49 ROM only**, from the
  [x16-rom r49 release](https://github.com/X16Community/x16-rom/releases/tag/r49),
  sha256 `b81654cc8c87ed96e3ffc7c8e7c312c9f3b7b870c7bb34de61e61eac931b819a`.
  Do NOT copy `rom.bin` from the sibling `X16_Geos` or `x16_library`
  projects: those carry a GEOS-modified ROM under the stock name
  (sha256 `298e3e2a…`). CXGEOS's whole premise is running on stock ROM.

```powershell
.\build.ps1 -Source spikes\spike_a.asm      # assemble one program
.\build.ps1 -Source spikes\spike_a.asm -Run # ... and run it windowed
.\build.ps1 -Test                           # regression suite, headless
```

## Vendored x16lib

`x16lib/` is a snapshot of `x16_library/src_ca65/` at commit `5303131`
("Add gfx2: a 640x480@2bpp bitmap module, across all 7 dialects").
Update it by re-copying the tree and noting the new commit here.

## Status

- Phase 0 done — bootstrap and risk spikes all green with measured
  numbers (`docs/perf.md`): fx_fill 1.25 frames/screen, 160 masked
  glyphs/frame, 22–31 scanline event dispatch.
- **Phase 1 done** — the 2bpp primitives live upstream now, as
  x16_library's `gfx2` module (`X16_USE_BITMAP2`: init, clear, pset,
  read, hline/vline, rect/frame, line, patterns, blits). Byte-identical
  across all 7 assembler dialects, and ported to all 5 of x16_clib's C
  toolchains — shipped as **x16lib 0.4.0** and **x16clib 0.3.0**.
  CXGEOS consumes it through `x16lib/`. The kernel-side dirty-rectangle
  list is in (`kernel/gfx2/dirty.asm`: merge + cascade, coverage never
  drops) and the torture demo runs (`demos/torture.asm`: every primitive
  in one scene, 40 JF — the perf regression gate in `docs/perf.md`).
- **Phase 2 in progress** — the font engine. CXF (`docs/formats.md`),
  `tools/fontconv.py` (BDF→CXF, 14 host tests), and `pxl8`: the X16's
  own public-domain ISO charset made proportional by trimming each
  cell's blank columns — 95 glyphs, 871 bytes, widths 2–8px averaging
  5.7, so text is ~29% shorter than the 8-pixel grid.
  `kernel/font/font.asm` caches every glyph pre-shifted to all four
  pixel phases in banked RAM and draws through `gfx2_blitm`: **98.7
  glyphs/frame**, a 40-character menu bar in 0.41 frames; bold (a
  double strike) and underline cost nothing when off. See
  `demos/specimen.asm`. Still to come: a second face, which is when
  the cache needs eviction rather than three fixed banks.
- **Phase 3 done** — the event system. A raster hook at scanline 0
  samples the mouse, decodes its button edges, drains the keyboard and
  ticks a timer; each becomes a typed record in a 16-deep queue, and
  `ev_dispatch` hands it to the app's handler for that type. An app is
  a table of vectors and a call to `ev_mainloop`. Buttons and keys are
  never dropped silently (a full queue counts the loss); mouse moves
  coalesce so the pointer cannot lag behind the hand. Milestone:
  `demos/evmon.asm`.
- **Phase 4 in progress** — the ABI. `abi/cxgeos.abi` is the manifest:
  31 append-only slots, from which `abi/gen_bindings.py` generates the
  jump table at `$8010` and bindings for all 12 toolchains (7 `.inc`,
  5 `.h`). `kernel/resident/impl.inc` maps each ABI promise to the
  kernel routine behind it, so code can be renamed or moved without an
  app noticing. `.uild.ps1 -Test` fails if `sdk/` has drifted from
  the manifest. Still to come: `AUTOBOOT.X16`, the CXAP app format,
  and the loader.
