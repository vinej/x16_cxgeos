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

`x16lib/` is a snapshot of `x16_library/src_ca65/` at commit `e2c9425`
("Add vasm as a seventh first-class assembler dialect"). Update it by
re-copying the tree and noting the new commit here.

## Status

Phase 0 — bootstrap and risk spikes (2bpp fill rate, masked glyph blit,
event latency). See `docs/perf.md` for measured numbers and the phase plan
in `CLAUDE.md`.
