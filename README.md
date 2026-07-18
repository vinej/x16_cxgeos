# CXGEOS

A from-scratch, GEOS-inspired graphical desktop OS for the Commander X16.

Not a port. The earlier `X16_Geos` project migrated the original C64 GEOS 2.0
to the X16 and proved the concept — and its ceiling: 320×200, proprietary app
binaries, a patched KERNAL ROM. CXGEOS is the clean break:

- **640×480 @ 4 colors** (VERA layer 0, 2bpp bitmap) — crisp, proportional
  fonts everywhere, color-schemable UI. Since 0.3.0 the desktop is one of
  **four video modes** behind a pluggable graphics port (`cx_mode`, see
  [docs/graphics-port.md](docs/graphics-port.md)) — the same drawing
  calls, reinterpreted per canvas:
  - **mode 0** `CX_MODE_GUI` — the 640×480 4-colour desktop above;
  - **mode 1** `CX_MODE_BMP8` — a 320×240 **256-colour** bitmap with the
    full primitive set (pset/read, spans, rects, lines, patterns, blits)
    and the palette yours to program;
  - **mode 2** `CX_MODE_TILE` — two 64×32 VERA **tile layers** with
    hardware scrolling (`cx_tile_*`), the game personality;
  - **mode 3** `CX_MODE_TEXT` — **80×60 text cells** "like BASIC":
    colour fills, PETSCII **box-glyph frames** (┌─┐│└┘), ruled
    `cx_hline`/`cx_vline`/`cx_line`, and mixed-case `cx_say`.

  Sprites, audio, events, joysticks, files and the **shapes**
  (circle/disc/flood, and ellipses since 0.3.1) work in every mode; the
  widget toolkit, fonts and dialogs are desktop-only and refuse politely
  elsewhere.
- **Stock ROM (R49+)**: boots from the SD card via `AUTOBOOT.X16`, no ROM
  patches, no cartridge required (a cartridge build comes later).
- **Native CMDR-DOS FAT32 files** — no .d64 images, no disk swapping.
- **Apps in any toolchain**: a GEOS-style fixed jump-table ABI with generated
  bindings for 7 assemblers (ACME, ca65, 64tass, KickAssembler, dasm, MADS,
  vasm) and 5 C compilers (cc65, llvm-mos, KickC, Oscar64, vbcc).
- **A documented SDK**: a friendly header-only C wrapper (`csdk/`) over the
  ABI — graphics, text, events, widgets, dialogs, themes, files, clipboard,
  (0.2.0) **audio** (VERA PSG, the YM2151 FM chip, streamed PCM) and
  **hardware sprites**, (0.3.0) **joysticks**, the four video modes
  above, and the mode-agnostic **shapes**, and (0.4.0) **pluggable fonts
  and charsets**, the **asset loaders** (`cx_file_load`, and
  `cx_vload`/`cx_bload` for the VLOAD-shaped binaries every X16 graphics
  tool exports), **mode-1 text** with `cx_ink`, and the **event source
  mask**. Music loads today (ZSM via `cx_bload`); a zsmkit-based player
  is planned, not in yet. Guides in
  [docs/sdkguide.md](docs/sdkguide.md), [docs/csdkguide.md](docs/csdkguide.md)
  and [docs/graphics-port.md](docs/graphics-port.md).
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
docs/             the guides: graphics-port, sdk, csdk, formats, memory-map, perf, ui
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
.\build.ps1 -Test                           # unit suite + the boot smoke, headless
.\build.ps1 -Kernel                         # the resident image, CXKERNEL.PRG
.\build.ps1 -Apps                           # AUTOBOOT.X16, the shell, the hellos
.\build.ps1 -Image                          # ...staged as a bootable root in build\sdroot
.\build.ps1 -Boot                           # ...and booted, windowed, to play with
```

C apps want llvm-mos (found via `LLVM_MOS_HOME`, the sibling
`x16_clib\llvm-mos`, or `C:\llvm-mos`); without it the C hello is
skipped and everything else still builds.

`-Test` ends with the boot smoke: a staged SD root boots for real —
stage-0, kernel, font — and then runs three chains to the shell:
`test\canary\CANARY.CXA` (the **ABI freeze test**: a committed binary
built from the sdk of the day the ABI shipped, run against the kernel
built seconds ago — if a slot ever moves, the past breaks here first),
then each hello, which draws, waits three seconds, and leaves through
`cx_exit`. Do not rebuild the canary casually; that is a release act.

## Vendored x16lib

`x16lib/` is a snapshot of `x16_library/src_ca65/` at **v0.5.0** (4691618:
the engine-agnostic `gfx/shapes.asm` with circle/disc/flood — including
the downward-fill flood fix — plus the new `shape_ellipse` /
`shape_fellipse`, the converter-canonical dialect regeneration, and the
bitmap parity pass with the `X16_BITMAP_MIN` gate). The ellipse routines
ride bank 5 with the rest of the shape machinery; no ABI slots expose
them yet.
Update it by re-copying the tree and noting the new version here.

The kernel gates `X16_USE_BITMAP2`, which since 0.4.1 asks VERAFX for
`_FILL` alone rather than all 2.5 KB of it. That is worth 2,162 bytes of
the resident budget and is why the image fits.

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
- **Phase 4 done** — the ABI, and the machine that honours it.
  `abi/cxgeos.abi` is the manifest: 92 append-only slots (and counting), from which
  `abi/gen_bindings.py` generates the jump table at `$8010` and
  bindings for all 12 toolchains (7 `.inc`, 5 `.h`).
  `kernel/resident/impl.inc` maps each ABI promise to the kernel
  routine behind it, so code can be renamed or moved without an app
  noticing; `.\build.ps1 -Test` fails if `sdk/` has drifted from the
  manifest. On top of it: `AUTOBOOT.X16` boots the kernel and the
  system font off a stock R49 SD root with no ROM patch; the CXAP app
  format (`docs/formats.md`) turns any toolchain's stock PRG into an
  app by prepending 32 bytes (`tools/mkcxap.py`); `cx_app_load`
  validates before it overwrites and refuses with the caller intact;
  `cx_exit` reloads the shell from disk, so the launch-and-return loop
  is closed. Proven headless on every `-Test`: the committed canary
  binary (the ABI freeze test), `apps/hello_asm` (ca65) and
  `apps/hello_c` (llvm-mos, through the sdk's `cx_run()` veneer — see
  `docs/formats.md` for why C must not touch `$22` on that compiler)
  each boot, run, and come back to the shell.

## License

[MIT](LICENSE) © Jean-Yves Vinet. The vendored `x16lib/` tree keeps its own
upstream [x16_library](https://github.com/vinej/x16_library) license; the
stock ROM and the emulator are third-party and not distributed here (see
Building).
