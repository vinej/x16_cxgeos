<#
.SYNOPSIS
    Assemble a CXGEOS program (kernel, spike, test or app) and optionally
    run it. Follows the x16_library build_ca65.ps1 harness contract:
    -Test greps CHROUT output for PASS/FAIL/SKIP/DONE lines.

.EXAMPLE
    .\build.ps1 -Source spikes\spike_a.asm -Run     # windowed
    .\build.ps1 -Source spikes\spike_a.asm -Capture # capture CHROUT output
    .\build.ps1 -Test                               # regression suite, headless
#>
param(
    [string]$Source = "test\runner.asm",
    [string]$Config = "prg.cfg",
    [switch]$Test,
    [switch]$Run,
    [switch]$Capture,      # run windowed with -warp, capture -echo output until DONE
    [switch]$Kernel,       # build the resident image against kernel/kernel.cfg
    [switch]$Apps,         # build AUTOBOOT.X16, the shell and the hellos
    [switch]$Image,        # ...and stage a bootable SD root in build\sdroot
    [switch]$Boot,         # ...and boot it, windowed, from the staged root
    [int]$Scale = 1,
    [int]$TimeoutSec = 90
)

$ErrorActionPreference = "Stop"

function Fail([string]$message) {
    Write-Host $message -ForegroundColor Red
    exit 1
}

$root  = $PSScriptRoot
$emu   = Join-Path $root "emulator\x16emu.exe"
$rom   = Join-Path $root "emulator\rom.bin"
$lib   = Join-Path $root "x16lib"
$build = Join-Path $root "build"

$ca65 = Join-Path $root "cc65\ca65.exe"
$ld65 = Join-Path $root "cc65\ld65.exe"
foreach ($tool in @($ca65, $ld65, $emu, $rom)) {
    if (-not (Test-Path $tool)) { Fail "missing: $tool (see README.md)" }
}
if (-not (Test-Path $build)) { New-Item -ItemType Directory -Path $build | Out-Null }

# -Kernel builds the resident image: the header at $8000, the jump table
# at $8010 and the code at $8200, which are the addresses every app is
# built against. ld65 fails the link if the code overruns $9EFF, so the
# budget enforces itself. See docs/memory-map.md for the ledger.
if ($Kernel) {
    $Source = "kernel\kernel.asm"
    $Config = "kernel\kernel.cfg"
}

function Build-KernelImage {
    $o = Join-Path $build "CXKERNEL.o"
    $p = Join-Path $build "CXKERNEL.PRG"
    Write-Host "ca65  kernel\kernel.asm -> $p"
    & $ca65 --cpu 65C02 -I $lib -I $root -o $o (Join-Path $root "kernel\kernel.asm")
    if ($LASTEXITCODE -ne 0) { Fail "ca65 failed on the kernel" }
    # from the root: kernel.cfg's second output file, build\CXBANKS.BIN,
    # is a path relative to wherever ld65 stands
    Push-Location $root
    & $ld65 -C (Join-Path $root "kernel\kernel.cfg") -m (Join-Path $build "CXKERNEL.map") -o $p $o
    $ldExit = $LASTEXITCODE
    Pop-Location
    if ($ldExit -ne 0) { Fail "ld65 failed on the kernel (over budget?)" }
    Write-Host "      $((Get-Item $p).Length) bytes + $((Get-Item (Join-Path $build 'CXBANKS.BIN')).Length) banked"
}

# -Apps / -Image / -Boot orchestrate several builds; the single-PRG path
# below is for everything else (the default runner, a spike, -Kernel).
$single = -not ($Apps -or $Image -or $Boot)

if ($single) {
    $name = [IO.Path]::GetFileNameWithoutExtension($Source).ToUpper()
    if ($Kernel) { $name = "CXKERNEL" }
    $obj  = Join-Path $build "$name.o"
    $out  = Join-Path $build "$name.PRG"
    $map  = Join-Path $build "$name.map"

    Write-Host "ca65  $Source -> $out"
    & $ca65 --cpu 65C02 -I $lib -I $root -o $obj (Join-Path $root $Source)
    if ($LASTEXITCODE -ne 0) { Fail "ca65 assembly failed" }
    & $ld65 -C (Join-Path $root $Config) -m $map -o $out $obj
    if ($LASTEXITCODE -ne 0) { Fail "ld65 link failed" }

    $size = (Get-Item $out).Length
    Write-Host "      $size bytes"
}

# --- run the emulator and capture CHROUT output until a pattern --------
function Invoke-Emulator([string[]]$emuArgs, [int]$timeout, [string]$until, [string]$tag) {
    $stdin  = Join-Path $env:TEMP "cxgeos-empty.in"
    $stdout = Join-Path $build "$tag-output.txt"
    [IO.File]::WriteAllText($stdin, "")
    if (Test-Path $stdout) { Remove-Item $stdout -Force }

    $emuArgs = @('-rom', $rom) + $emuArgs + @('-warp', '-echo')
    $proc = Start-Process -FilePath $emu -ArgumentList $emuArgs -NoNewWindow -PassThru `
                          -RedirectStandardInput $stdin -RedirectStandardOutput $stdout

    $deadline = (Get-Date).AddSeconds($timeout)
    $text = ""
    while ($true) {
        Start-Sleep -Milliseconds 200
        if (Test-Path $stdout) {
            $text = (Get-Content $stdout -Raw -ErrorAction SilentlyContinue) -replace "`r", ""
            if ($text -match $until) { break }
        }
        if ($proc.HasExited) { break }
        if ((Get-Date) -gt $deadline) {
            if (-not $proc.HasExited) { try { $proc.Kill() } catch {} }
            Fail "emulator timed out after ${timeout}s -- nothing matched '$until'"
        }
    }
    # the process may win the race and exit between the check and the
    # kill; either way it is gone, which is all that was wanted
    if (-not $proc.HasExited) { try { $proc.Kill() } catch {} }
    $proc.WaitForExit()
    return $text
}

# --- the apps: assemble a PRG, wrap it as a CXAP ------------------------
function Build-Prg([string]$src, [string]$prgName) {
    $o = Join-Path $build "$prgName.o"
    $p = Join-Path $build "$prgName.PRG"
    Write-Host "ca65  $src -> $p"
    & $ca65 --cpu 65C02 -I $lib -I $root -o $o (Join-Path $root $src)
    if ($LASTEXITCODE -ne 0) { Fail "ca65 failed on $src" }
    & $ld65 -C (Join-Path $root "prg.cfg") -o $p $o
    if ($LASTEXITCODE -ne 0) { Fail "ld65 failed on $src" }
    return $p
}

function Build-Apps {
    $py = (Get-Command python -ErrorAction Stop).Source
    $mkcxap = Join-Path $root "tools\mkcxap.py"

    $boot = Build-Prg "kernel\boot\auto.asm" "AUTOBOOT"
    Copy-Item $boot (Join-Path $build "AUTOBOOT.X16") -Force

    foreach ($app in @(
        @{ src = "apps\filer\filer.asm";        prg = "SHELL";    name = "Desktop" },
        @{ src = "apps\hello_asm\hello.asm";    prg = "HELLO1";   name = "Hello (asm)" },
        @{ src = "test\menutest\menutest.asm";  prg = "MENUTEST"; name = "Menu test" },
        @{ src = "apps\gallery\gallery.asm";     prg = "GALLERY";  name = "Widget gallery" }
    )) {
        $p = Build-Prg $app.src $app.prg
        & $py $mkcxap $p (Join-Path $build "$($app.prg).CXA") --name $app.name
        if ($LASTEXITCODE -ne 0) { Fail "mkcxap failed on $($app.prg)" }
    }

    # hello_c wants llvm-mos; a machine without it still builds the rest
    $mosbin = $null
    $candidates = @()
    if ($env:LLVM_MOS_HOME) { $candidates += (Join-Path $env:LLVM_MOS_HOME "bin") }
    $candidates += "C:\quartus\projects\x16_clib\llvm-mos\bin", "C:\llvm-mos\bin"
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "mos-cx16-clang.bat")) { $mosbin = $c; break }
    }
    if ($mosbin) {
        $prg = Join-Path $build "HELLO2.PRG"
        Write-Host "llvm  apps\hello_c\hello.c -> $prg"
        # -mreserve-zp=90 keeps clang's whole-program pass out of $26-$7F,
        # all of which belongs to the kernel or to the app ZP convention;
        # the sdk header's cx_run() handles the $22-$25 collision with the
        # compiler's own soft stack pointer. (The soft stack itself sits at
        # $9F00 growing down with ~1.9KB of free zone before kernel code --
        # a proper linker cap on RAM is SDK-packaging work, noted there.)
        & (Join-Path $mosbin "mos-cx16-clang.bat") -Os -mreserve-zp=90 -I $root -o $prg (Join-Path $root "apps\hello_c\hello.c")
        if ($LASTEXITCODE -ne 0) { Fail "mos-cx16-clang failed on hello.c" }
        & $py $mkcxap $prg (Join-Path $build "HELLO2.CXA") --name "Hello (C)"
        if ($LASTEXITCODE -ne 0) { Fail "mkcxap failed on HELLO2" }
    } else {
        Write-Host "llvm-mos not found: skipping apps\hello_c" -ForegroundColor Yellow
    }
}

# --- stage everything a bootable disk needs -----------------------------
function Stage-SdRoot {
    $sdroot = Join-Path $build "sdroot"
    if (Test-Path $sdroot) { Remove-Item $sdroot -Recurse -Force }
    New-Item -ItemType Directory -Path $sdroot | Out-Null
    Copy-Item (Join-Path $build "AUTOBOOT.X16")  $sdroot
    Copy-Item (Join-Path $build "CXKERNEL.PRG")  $sdroot
    Copy-Item (Join-Path $build "CXBANKS.BIN")   $sdroot
    Copy-Item (Join-Path $root  "fonts\pxl8.cxf") (Join-Path $sdroot "PXL8.CXF")
    Copy-Item (Join-Path $build "SHELL.CXA")     $sdroot
    Copy-Item (Join-Path $build "HELLO1.CXA")    $sdroot
    Copy-Item (Join-Path $build "GALLERY.CXA")   $sdroot
    if (Test-Path (Join-Path $build "HELLO2.CXA")) {
        Copy-Item (Join-Path $build "HELLO2.CXA") $sdroot
    }
    return $sdroot
}

if ($Test) {
    # The ABI first: sdk/ and the jump table are generated from
    # abi/cxgeos.abi, and a suite that passed against a stale sdk/ would
    # be testing something no app is built with. --check writes nothing
    # and fails if anything would change.
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) {
        & $py.Source (Join-Path $root "abi\gen_bindings.py") --check
        if ($LASTEXITCODE -ne 0) { Fail "abi: sdk/ is out of date" }
        & $py.Source (Join-Path $root "abi\gen_bindings.py") --selftest | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "abi: gen_bindings.py selftest failed" }
        & $py.Source (Join-Path $root "tools\fontconv.py") --selftest | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "fontconv: selftest failed" }
        & $py.Source (Join-Path $root "tools\mkcxap.py") --selftest | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "mkcxap: selftest failed" }
        Write-Host "abi + fontconv + mkcxap: host checks pass"
    } else {
        Write-Host "python not found: skipping the host checks" -ForegroundColor Yellow
    }

    Write-Host "x16emu (headless testbench)"

    $fsroot = Join-Path $root "test\fsroot"
    if (-not (Test-Path $fsroot)) { New-Item -ItemType Directory -Path $fsroot | Out-Null }
    Get-ChildItem $fsroot -File | Remove-Item -Force

    # The loader tests open these through real DOS. BADAPP wears the
    # wrong magic; NEWAPP is a well-formed CXAP that demands ABI $7FFF.
    $badapp = [byte[]]([Text.Encoding]::ASCII.GetBytes("XXAP") + @(0) * 28 + @(0x01, 0x08, 0xEA))
    [IO.File]::WriteAllBytes((Join-Path $fsroot "BADAPP.CXA"), $badapp)
    $newapp = [byte[]]([Text.Encoding]::ASCII.GetBytes("CXAP") + @(0xFF, 0x7F, 0x01, 0x08) + @(0) * 24 + @(0x01, 0x08, 0xEA))
    [IO.File]::WriteAllBytes((Join-Path $fsroot "NEWAPP.CXA"), $newapp)

    $text = Invoke-Emulator @('-prg', $out, '-run', '-fsroot', $fsroot, '-testbench') $TimeoutSec '(?m)^DONE' $name

    $passes = ([regex]::Matches($text, '(?m)^PASS ([A-Z0-9_]+)')).Count
    $fails  = [regex]::Matches($text, '(?m)^FAIL ([A-Z0-9_]+)')
    $skips  = [regex]::Matches($text, '(?m)^SKIP ([A-Z0-9_]+)')
    $done   = [regex]::Match($text, '(?m)^DONE ([0-9A-F]{2})/([0-9A-F]{2})')

    foreach ($f in $fails) { Write-Host ("  FAIL {0}" -f $f.Groups[1].Value) -ForegroundColor Red }
    foreach ($s in $skips) { Write-Host ("  SKIP {0}" -f $s.Groups[1].Value) -ForegroundColor Yellow }

    if (-not $done.Success) { Fail "test run produced no DONE line" }

    $reportedPass  = [Convert]::ToInt32($done.Groups[1].Value, 16)
    $reportedTotal = [Convert]::ToInt32($done.Groups[2].Value, 16)

    if ($reportedTotal -eq 0) { Fail "no tests ran" }
    if ($passes -ne $reportedPass) {
        Fail "output is inconsistent: $passes PASS lines but DONE says $reportedPass"
    }
    if ($fails.Count -gt 0 -or $reportedPass -ne $reportedTotal) {
        Fail "$($reportedTotal - $reportedPass) of $reportedTotal tests failed"
    }

    $summary = "      $reportedPass/$reportedTotal tests passed"
    if ($skips.Count -gt 0) { $summary += ", $($skips.Count) skipped (not runnable headless)" }
    Write-Host $summary -ForegroundColor Green

    # ---- the boot smoke: the whole chain, end to end -------------------
    # A staged SD root boots for real: AUTOBOOT.X16 loads the kernel and
    # the font, cx_init comes up, and AUTORUN.CXA -- the COMMITTED canary
    # binary, built from the sdk of the day the ABI shipped -- runs
    # against the kernel built ten lines ago. That is the ABI freeze
    # test. The canary leaves through cx_exit, which reloads the shell,
    # so one boot proves stage-0, the loader's success path, the frozen
    # ABI, and the exit path, in order, or times out red.
    Write-Host "x16emu (boot smoke: stage-0 -> kernel -> canary -> shell)"
    Build-KernelImage
    Build-Apps
    $sdroot = Stage-SdRoot
    $canary = Join-Path $root "test\canary\CANARY.CXA"
    if (-not (Test-Path $canary)) { Fail "test\canary\CANARY.CXA is missing -- the ABI freeze test needs the committed binary" }
    Copy-Item $canary (Join-Path $sdroot "AUTORUN.CXA")

    $text = Invoke-Emulator @('-fsroot', $sdroot) $TimeoutSec '(?m)^CXGEOS SHELL' "boot"
    if ($text -notmatch '(?m)^CANARY OK') {
        if ($text -match '(?m)^CANARY FAILED') { Fail "boot smoke: the frozen canary FAILED against this kernel -- the ABI moved" }
        Fail "boot smoke: the canary never reported"
    }
    Write-Host "      boot: kernel up, frozen canary OK, shell up" -ForegroundColor Green

    # The hellos close their own loop -- three seconds with no key and
    # they leave through cx_exit -- so each can play AUTORUN and be
    # proven headless: boot, run, exit, and the shell comes back.
    $hellos = @(
        @{ cxa = "HELLO1.CXA";   up = "HELLO ASM UP" },
        @{ cxa = "MENUTEST.CXA"; up = "MENUTEST OK" }
    )
    if (Test-Path (Join-Path $build "HELLO2.CXA")) {
        $hellos += @{ cxa = "HELLO2.CXA"; up = "HELLO C UP" }
    }
    foreach ($h in $hellos) {
        Copy-Item (Join-Path $build $h.cxa) (Join-Path $sdroot "AUTORUN.CXA") -Force
        $text = Invoke-Emulator @('-fsroot', $sdroot) $TimeoutSec '(?m)^CXGEOS SHELL' "boot-$($h.cxa)"
        # not ^-anchored: -echo renders a control byte ahead of the text
        # as \X0F, so the marker is not at column 0
        if ($text -notmatch [regex]::Escape($h.up)) { Fail "boot smoke: $($h.cxa) never came up" }
        Write-Host "      boot: $($h.cxa) up, timed exit, shell up" -ForegroundColor Green
    }

    # The SD-image path: fold the staged root into one FAT32 image and
    # boot it through -sdcard, the way a real card boots (the ROM's
    # CMDR-DOS reads AUTOBOOT.X16 off the FAT). No AUTORUN, so it lands
    # straight in the desktop and "CXGEOS SHELL" alone proves the image.
    Remove-Item (Join-Path $sdroot "AUTORUN.CXA") -Force -ErrorAction SilentlyContinue
    $img = Join-Path $build "cxgeos_smoke.img"
    $files = Get-ChildItem $sdroot -File | ForEach-Object { $_.FullName }
    & python (Join-Path $root "tools\mksd.py") $img @files | Out-Null
    if ($LASTEXITCODE) { Fail "boot smoke: mksd.py failed to build the image" }
    $text = Invoke-Emulator @('-sdcard', $img) $TimeoutSec '(?m)^CXGEOS SHELL' "boot-sdcard"
    if ($text -notmatch '(?m)^CXGEOS SHELL') { Fail "boot smoke: the SD image never reached the desktop" }
    Remove-Item $img -Force -ErrorAction SilentlyContinue
    Write-Host "      boot: FAT32 image via -sdcard, desktop up" -ForegroundColor Green
    exit 0
}

if ($Apps -or $Image -or $Boot) {
    Build-KernelImage
    Build-Apps
    if ($Image -or $Boot) {
        $sdroot = Stage-SdRoot
        Write-Host "sdroot: $sdroot"
        Get-ChildItem $sdroot | ForEach-Object { Write-Host ("      {0,-14} {1,6} bytes" -f $_.Name, $_.Length) }
    }
    if ($Image) {
        # ...and fold the same files into one bootable FAT32 image, so a
        # real SD card (or -sdcard) boots identically to -fsroot.
        $img = Join-Path $build "cxgeos_sd.img"
        $files = Get-ChildItem $sdroot -File | ForEach-Object { $_.FullName }
        & python (Join-Path $root "tools\mksd.py") $img @files
        if ($LASTEXITCODE) { throw "mksd.py failed" }
        Write-Host "image: $img"
    }
    if ($Boot) {
        # -capture: x16emu does not feed the host mouse to the guest
        # without it, so the pointer would sit frozen. Interactive only;
        # the headless smoke never needs it.
        Write-Host "x16emu (booting the staged root; -capture for the mouse)"
        & $emu -rom $rom -fsroot $sdroot -scale $Scale -capture
    }
    exit 0
}

if ($Capture) {
    Write-Host "x16emu (windowed, capturing until DONE)"
    $text = Invoke-Emulator @('-prg', $out, '-run') $TimeoutSec '(?m)^DONE' $name
    Write-Host $text
    exit 0
}

if ($Run) {
    Write-Host "x16emu $out"
    & $emu -rom $rom -prg $out -run -scale $Scale
}
