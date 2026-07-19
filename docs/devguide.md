# CXGEOS developer guide — VS Code setup & deployment

This guide sets up a Visual Studio Code workspace for writing a CXGEOS
application, building it, and deploying it to the emulator (or a real SD
card). It assumes you have the repository checked out and the toolchain
in place (see [README.md](../README.md) → Building).

A CXGEOS *application* is a small 65C02 program wrapped as a **`.CXA`**
file. The desktop lists `.CXA` files and launches one when you open it;
the app talks to the kernel entirely through a fixed **jump table** (the
ABI), draws through the graphics port, and returns to the desktop with
`cx_exit`. You never link the kernel into your app — you call it.

### Which toolchain?

Because an app only calls fixed addresses, the ABI is language-neutral,
and `abi/gen_bindings.py` emits a binding header for a **spread of
assemblers and C compilers**. They live under `sdk/`:

| | Bindings shipped in `sdk/` | Fully supported today |
|---|---|---|
| **Assembly** (7) | `ca65`, `acme`, `64tass`, `kick`, `dasm`, `mads`, `vasm` | **all** — each header is just address constants; you set the parameter block and `jsr` the slot, identical logic in any of them |
| **C** (5) | `llvm` (llvm-mos), `cc65`, `kickc`, `oscar64`, `vbcc` | **llvm-mos only** |

For assembly, pick whichever dialect you already use — swap the include
in the examples below (`sdk/include_ca65/…` → `sdk/include_acme/…`, etc.)
and assemble with that tool. This guide uses **ca65**, the dialect the
sample apps and `build.ps1` are written in.

For C, use **llvm-mos**. Its header carries the friendly `cx_*` calls,
and the `csdk/` wrappers (a typed `cx_event`, `cx_rect`, `cx_say`, …) are
llvm-mos-only. The other four C headers are, for now, **partial stubs** —
the slot constants plus a bare `cx_call(slot)` that runs no-argument
slots but cannot yet pass the `A` register — so they are not a complete
API. Assembly, or C on llvm-mos, are the two paths covered below.

---

## 1. Prerequisites

These live in the repo but are never committed (the `.gitignore` keeps
them out); install them once per machine.

| Tool | Where CXGEOS looks for it | From |
|---|---|---|
| `ca65.exe`, `ld65.exe` | `cc65\` at the repo root | [cc65](https://cc65.github.io/) |
| `x16emu.exe` + SDL DLLs | `emulator\` | [x16-emulator](https://github.com/X16Community/x16-emulator) |
| `rom.bin` | `emulator\rom.bin` | **stock R49 only** ([x16-rom r49](https://github.com/X16Community/x16-rom/releases/tag/r49)) — see the README warning about GEOS-modified ROMs |
| `python` (3.x) | on `PATH` | for `mkcxap.py` (the `.CXA` wrapper) |
| `mos-cx16-clang` | `%LLVM_MOS_HOME%\bin`, `..\x16_clib\llvm-mos\bin`, or `C:\llvm-mos\bin` | [llvm-mos](https://github.com/llvm-mos/llvm-mos-sdk) — **C apps only** |

If you only write assembly you don't need llvm-mos. The build script
skips the C apps when it can't find it.

The build is driven by **`build.ps1`** (PowerShell). A quick sanity
check from the repo root:

```powershell
.\build.ps1 -Image     # builds the kernel + all apps, stages build\sdroot
.\build.ps1 -Boot      # ...and boots the desktop, windowed, to click around
```

---

## 2. Where an app lives

The SDK headers (`sdk/`), the C wrapper (`csdk/`), and the assembly HAL
(`x16lib/`) are resolved by **include path relative to the repo root**.
The simplest, fully-supported flow is to develop your app *inside the
tree*, next to the sample apps:

```
apps/
  myapp/
    myapp.asm      (or myapp.c)
```

Every build command below is run **with the repo root as the working
directory**, so `-I x16lib` and `-I .` make `x16.asm`,
`sdk/include_ca65/cxgeos.inc`, and `csdk/cxsdk.h` resolve. (Out-of-tree
apps work too — copy `sdk/`, `csdk/`, and `x16lib/` into your project and
point `-I` at them — but in-tree is the path this guide walks.)

Open the **repo root** as your VS Code workspace folder (`File → Open
Folder…`), not `apps/myapp` — the include paths and tasks depend on it.

---

## 3. VS Code setup

Create a `.vscode/` folder in the repo root with the four files below.
(They are safe to keep out of version control if you prefer — add
`.vscode/` to your local excludes.)

### 3.1 Recommended extensions — `.vscode/extensions.json`

```json
{
  "recommendations": [
    "ms-vscode.powershell",
    "ms-vscode.cpptools"
  ]
}
```

- **PowerShell** (`ms-vscode.powershell`) — runs `build.ps1` and the
  tasks.
- **C/C++** (`ms-vscode.cpptools`) — IntelliSense for C apps (see 3.3).
- **6502 / ca65 syntax** — optional but nice: search the Marketplace for
  *"ca65"* or *"6502"* and pick a syntax-highlighting extension you like,
  then let the file association in 3.2 route `.asm` to it.

VS Code will offer to install the recommendations when you open the
folder.

### 3.2 Editor settings — `.vscode/settings.json`

```json
{
  "files.associations": {
    "*.asm": "ca65",
    "*.inc": "ca65"
  },
  "files.eol": "\n",
  "[c]": { "editor.tabSize": 4 },
  "[asm]": { "editor.tabSize": 4 }
}
```

Set the `ca65` language id to whatever your chosen syntax extension
registers (some use `asm-collection`, `6502`, etc.); if you installed
none, drop the `files.associations` block.

### 3.3 C IntelliSense — `.vscode/c_cpp_properties.json`

So the C/C++ extension resolves `cx_*` calls and `<cbm.h>`. Point
`compilerPath` at your llvm-mos clang.

```json
{
  "version": 4,
  "configurations": [
    {
      "name": "cx16-llvm-mos",
      "includePath": [
        "${workspaceFolder}",
        "${workspaceFolder}/sdk/include_llvm",
        "${workspaceFolder}/csdk"
      ],
      "compilerPath": "C:/llvm-mos/bin/mos-cx16-clang.bat",
      "cStandard": "c17",
      "intelliSenseMode": "clang-x64",
      "defines": []
    }
  ]
}
```

(IntelliSense only reads headers; it doesn't need to actually target the
6502. If clang-as-a-batch confuses the extension, leave `compilerPath`
empty — the `includePath` alone is enough for the `cx_*` symbols.)

### 3.4 Build & run tasks — `.vscode/tasks.json`

These cover the whole loop. `Ctrl+Shift+B` runs the default (a full
build); `Terminal → Run Task…` lists the rest. The per-app tasks build
**the file you have open** and drop the `.CXA` into `build\sdroot`.

```json
{
  "version": "2.0.0",
  "options": { "cwd": "${workspaceFolder}" },
  "tasks": [
    {
      "label": "CXGEOS: Full build + stage (kernel, apps, sdroot)",
      "type": "shell",
      "command": ".\\build.ps1 -Image",
      "problemMatcher": [],
      "group": { "kind": "build", "isDefault": true }
    },
    {
      "label": "CXGEOS: Test (unit suite + boot smoke)",
      "type": "shell",
      "command": ".\\build.ps1 -Test",
      "problemMatcher": []
    },
    {
      "label": "CXGEOS: Build this ASM app -> sdroot",
      "type": "shell",
      "command": "& '${workspaceFolder}\\cc65\\ca65.exe' --cpu 65C02 -I x16lib -I . -o 'build\\${fileBasenameNoExtension}.o' '${relativeFile}'; if ($?) { & '${workspaceFolder}\\cc65\\ld65.exe' -C prg.cfg -o 'build\\${fileBasenameNoExtension}.PRG' 'build\\${fileBasenameNoExtension}.o' }; if ($?) { python tools\\mkcxap.py 'build\\${fileBasenameNoExtension}.PRG' \"build\\sdroot\\$('${fileBasenameNoExtension}'.ToUpper()).CXA\" --name '${fileBasenameNoExtension}' }",
      "problemMatcher": []
    },
    {
      "label": "CXGEOS: Build this C app -> sdroot",
      "type": "shell",
      "command": "& \"$($env:LLVM_MOS_HOME + '\\bin\\mos-cx16-clang.bat')\" -Os -mreserve-zp=90 -I . -o 'build\\${fileBasenameNoExtension}.PRG' '${relativeFile}'; if ($?) { python tools\\mkcxap.py 'build\\${fileBasenameNoExtension}.PRG' \"build\\sdroot\\$('${fileBasenameNoExtension}'.ToUpper()).CXA\" --name '${fileBasenameNoExtension}' }",
      "problemMatcher": []
    },
    {
      "label": "CXGEOS: Run desktop (fsroot)",
      "type": "shell",
      "command": "& '${workspaceFolder}\\emulator\\x16emu.exe' -rom emulator\\rom.bin -fsroot build\\sdroot -scale 2 -capture",
      "problemMatcher": []
    }
  ]
}
```

Notes:
- The ASM/C app tasks assume `build\sdroot` already exists — run **Full
  build + stage** once first (it builds the kernel and stages the SD
  root). After that, rebuilding just your app is fast.
- `-mreserve-zp=90` in the C task matches the kernel's zero-page
  contract; keep it. If `LLVM_MOS_HOME` isn't set, replace
  `$($env:LLVM_MOS_HOME + '\\bin\\...')` with the full path to
  `mos-cx16-clang.bat`.
- The `.CXA` name passed to `mkcxap` (`--name`) is what the desktop
  shows; it is stored in **16 bytes**, so keep it short.

---

## 4. Anatomy of an app

### 4.1 Assembly skeleton

```asm
; apps/myapp/myapp.asm
.include "x16.asm"                       ; the X16 HAL (via -I x16lib)
.include "sdk/include_ca65/cxgeos.inc"   ; the ABI: cx_* jump-table addresses

.segment "LOADADDR"
    .word $0801                          ; the PRG load address
.segment "CODE"
    basic_stub                           ; emits the "10 SYS ..." BASIC line

main
    lda #6
    jsr cx_gfx_clear                     ; paint the screen (colour 6)

    lda #<msg
    ldx #>msg
    ldy #200
    ; ...set the pen and call cx_font_draw, etc...

    jmp cx_exit                          ; return to the desktop (never rts)

msg .byte "hello, cxgeos", 0
```

- `cx_*` names come from `sdk/include_ca65/cxgeos.inc`; each is just the
  fixed address of a `jmp` in the kernel's table. Arguments go in `A`/`X`
  and the parameter block `X16_P0..X16_P7` (zero page), per the ABI.
- **`cx_exit` is the only clean way out** — it reloads the desktop. Never
  fall off the end or `rts`.
- Real examples: [apps/hello_asm/hello.asm](../apps/hello_asm/hello.asm)
  (minimal), [apps/gallery/gallery.asm](../apps/gallery/gallery.asm)
  (menus + widgets), [apps/tui/tui.asm](../apps/tui/tui.asm) (the full
  toolkit), [apps/gameloop/gameloop.asm](../apps/gameloop/gameloop.asm) (a
  game that owns the raster IRQ and borrows the events for a dialog).

A GUI app that uses the event loop follows this shape:

```asm
    jsr cx_ev_init
    lda #<bar / ldx #>bar   / jsr cx_menu_set
    lda #<widgets / ldx #>widgets / jsr cx_wg_set
    lda #1 / jsr cx_mouse_show
    lda #<handlers / ldx #>handlers / jsr cx_ev_handlers
    jmp cx_ev_mainloop      ; the kernel dispatches menu/widget/key events
```

A **game** that wants the raster IRQ for smooth motion inverts this: it
installs its own per-frame handler with `cx_ev_raster`, reads input
directly (`cx_joy_get`, `GETIN`), and never starts the sampler. To ask
the user something it borrows the events for one modal dialog, then takes
the line back — the kernel saves the game's handler across the borrow:

```asm
    lda #<game_irq / ldx #>game_irq / jsr cx_ev_raster   ; own the line
gloop
    jsr GETIN               ; play, reading input directly; game_irq animates
    cmp #KEY_OPTIONS / bne * + ...
    ; --- pause to ask something ---
    jsr cx_ev_init          ; borrow: the kernel samples (game_irq saved)
    lda #<panel / ldx #>panel / jsr cx_panel     ; a modal dialog
    jsr cx_ev_stop          ; the line returns to game_irq; play resumes
```

See [apps/gameloop/gameloop.asm](../apps/gameloop/gameloop.asm) for the
whole thing (the field pulses under the game's IRQ and freezes while the
panel is up). A top-of-frame handler is fully restored; a mid-screen
raster split re-arms its scanline after `cx_ev_stop`.

### 4.2 C skeleton (llvm-mos)

```c
/* apps/myapp/myapp.c */
#include <cbm.h>
#include "sdk/include_llvm/cxgeos.h"   /* the generated ABI */
#include "csdk/cxsdk.h"               /* friendly cx_* wrappers + cx_event */

int main(void) {
    cx_event ev;
    unsigned char frame0;

    cx_clear(2);
    cx_say("hello from C", 24, 200);

    cx_ev_init();
    frame0 = cx_frames();
    for (;;) {
        if (cx_poll(&ev) && ev.type == CX_ET_KEY) break;
        if ((unsigned char)(cx_frames() - frame0) >= 180) break;
    }
    cx_exit();                 /* never returns */
    return 0;                  /* unreachable, keeps the compiler happy */
}
```

- The **csdk** (`csdk/cxsdk.h`) turns the raw ABI into named calls
  (`cx_rect`, `cx_say`, `cx_poll`, a typed `cx_event`) so you don't hand-
  pack the parameter block. See [apps/hello_c/hello.c](../apps/hello_c/hello.c)
  and [apps/calc/calc.c](../apps/calc/calc.c).
- Build with `-Os -mreserve-zp=90`. The csdk header plants a constructor
  that moves the C soft stack out of the kernel's way — include it and
  don't fight it.

### 4.3 What the kernel gives you

- The full slot list (every `cx_*` you can call): **`abi/cxgeos.abi`**.
- Descriptor byte-layouts (menu bar, widget list, dialog, the modal
  **panel**): **[docs/formats.md](formats.md)**.
- Graphics modes, the toolkit, save-under, banks: **[docs/ui.md](ui.md)**
  and the in-repo demos.

---

## 5. Build → deploy → run

### 5.1 The one-time base

```powershell
.\build.ps1 -Image
```

This builds the kernel image (`CXKERNEL.PRG` + `CXBANKS.BIN`), all the
sample apps, and stages a bootable SD root in **`build\sdroot`** (plus a
FAT32 image `build\cxgeos_sd.img`). You need `build\sdroot` present
before your app has somewhere to land. Re-run it only when the **kernel
or the SDK** changes — not on every app edit.

### 5.2 Build your app into the SD root

Assembly (equivalent to the VS Code task, run from the repo root):

```powershell
cc65\ca65.exe --cpu 65C02 -I x16lib -I . -o build\myapp.o apps\myapp\myapp.asm
cc65\ld65.exe -C prg.cfg -o build\MYAPP.PRG build\myapp.o
python tools\mkcxap.py build\MYAPP.PRG build\sdroot\MYAPP.CXA --name "My App"
```

C:

```powershell
& "$env:LLVM_MOS_HOME\bin\mos-cx16-clang.bat" -Os -mreserve-zp=90 -I . -o build\MYAPP.PRG apps\myapp\myapp.c
python tools\mkcxap.py build\MYAPP.PRG build\sdroot\MYAPP.CXA --name "My App"
```

`mkcxap.py` wraps the plain PRG in the `CXAP` header the loader checks
(magic, entry point, minimum ABI version). That header is why a `.CXA`
can't be run with `-prg` directly — it's launched *by the kernel*.

### 5.3 Run it

Boot the kernel with your SD root and launch the app from the desktop:

```powershell
emulator\x16emu.exe -rom emulator\rom.bin -fsroot build\sdroot -scale 2 -capture
```

- `-fsroot build\sdroot` serves that folder as the SD card — fastest
  iteration (no image rebuild).
- `-capture` grabs the host mouse so the pointer works; `-scale 2` for a
  larger window.
- In the desktop, open **MY APP** to launch it. `cx_exit` brings you back.

**Auto-launch while iterating:** wrap your app as `AUTORUN.CXA` in the SD
root and the kernel runs it straight after boot, skipping the desktop —
ideal for a tight edit/run loop on one app:

```powershell
python tools\mkcxap.py build\MYAPP.PRG build\sdroot\AUTORUN.CXA --name "My App"
emulator\x16emu.exe -rom emulator\rom.bin -fsroot build\sdroot -capture
```

Delete `build\sdroot\AUTORUN.CXA` to get the desktop back.

### 5.4 Onto a real SD card

`build\sdroot` *is* the card layout. Either copy its contents to a
FAT32-formatted card, or build the single image and write that:

```powershell
.\build.ps1 -Image          # produces build\cxgeos_sd.img
```

Boot the emulator from the image exactly like real hardware would:

```powershell
emulator\x16emu.exe -rom emulator\rom.bin -sdcard build\cxgeos_sd.img -capture
```

A real Commander X16 boots the same image off a physical card.

---

## 6. The inner loop

Once `build\sdroot` exists, a normal edit cycle is two steps:

1. **`CXGEOS: Build this ASM app -> sdroot`** (or the C task) — rebuilds
   only your `.CXA`.
2. **`CXGEOS: Run desktop (fsroot)`** — boots and lets you launch it.

Bind them if you like, or make a compound task that runs the build then
the run. The kernel stays as-is, so this is seconds, not a full rebuild.

To keep the whole project honest before you commit, run
**`CXGEOS: Test`** (`.\build.ps1 -Test`): the unit suite plus a real boot
smoke (stage-0 → kernel → the frozen ABI canary → the desktop). If you
only touched your own app it won't be exercised there — but a green
suite proves you didn't disturb the kernel or the ABI.

---

## 7. Verifying without a human at the keyboard

The kernel and apps print progress with plain `CHROUT`, so the emulator's
`-echo` streams it to the terminal — handy for scripted checks. And for
*seeing* a GUI headlessly, capture a GIF and read a frame:

```powershell
emulator\x16emu.exe -rom emulator\rom.bin -fsroot build\sdroot -warp -echo -gif build\run.gif
```

Have your app print a one-line marker on startup (like the samples'
`"MYAPP UP"`), wait for it in the `-echo` output, then extract a frame
from `run.gif` as a PNG to inspect. This is exactly how the toolkit
demos are regression-checked.

---

## 8. Gotchas

- **Work from the repo root.** The `-I x16lib -I .` include paths and the
  tasks' `cwd` all assume it. Opening `apps/myapp` as the folder breaks
  them.
- **`cx_exit`, always.** Returning to the desktop is a kernel call, not
  an `rts`. Falling off the end hangs the machine.
- **The `.CXA` name is 16 bytes.** `mkcxap --name` longer than that is
  truncated.
- **Rebuild the kernel only when needed.** App edits don't require
  `-Image`; that's for kernel/SDK changes. But if you *do* change the ABI
  (`abi/cxgeos.abi`), regenerate the headers with
  `python abi\gen_bindings.py` and rebuild everything.
- **`build\` is disposable.** It's regenerated and git-ignored; don't put
  sources there.
```
