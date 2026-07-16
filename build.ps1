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

$name = [IO.Path]::GetFileNameWithoutExtension($Source).ToUpper()
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

# --- run the emulator and capture CHROUT output until DONE -------------
function Invoke-Emulator([string[]]$extraArgs, [int]$timeout) {
    $stdin  = Join-Path $env:TEMP "cxgeos-empty.in"
    $stdout = Join-Path $build "$name-output.txt"
    [IO.File]::WriteAllText($stdin, "")
    if (Test-Path $stdout) { Remove-Item $stdout -Force }

    $emuArgs = @('-rom', $rom, '-prg', $out, '-run', '-warp', '-echo') + $extraArgs
    $proc = Start-Process -FilePath $emu -ArgumentList $emuArgs -NoNewWindow -PassThru `
                          -RedirectStandardInput $stdin -RedirectStandardOutput $stdout

    $deadline = (Get-Date).AddSeconds($timeout)
    $text = ""
    while ($true) {
        Start-Sleep -Milliseconds 200
        if (Test-Path $stdout) {
            $text = (Get-Content $stdout -Raw -ErrorAction SilentlyContinue) -replace "`r", ""
            if ($text -match '(?m)^DONE') { break }
        }
        if ($proc.HasExited) { break }
        if ((Get-Date) -gt $deadline) {
            if (-not $proc.HasExited) { $proc.Kill() }
            Fail "emulator timed out after ${timeout}s -- no DONE line"
        }
    }
    if (-not $proc.HasExited) { $proc.Kill() }
    $proc.WaitForExit()
    return $text
}

if ($Test) {
    Write-Host "x16emu (headless testbench)"

    $fsroot = Join-Path $root "test\fsroot"
    if (-not (Test-Path $fsroot)) { New-Item -ItemType Directory -Path $fsroot | Out-Null }
    Get-ChildItem $fsroot -File | Remove-Item -Force

    $text = Invoke-Emulator @('-fsroot', $fsroot, '-testbench') $TimeoutSec

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
    exit 0
}

if ($Capture) {
    Write-Host "x16emu (windowed, capturing until DONE)"
    $text = Invoke-Emulator @() $TimeoutSec
    Write-Host $text
    exit 0
}

if ($Run) {
    Write-Host "x16emu $out"
    & $emu -rom $rom -prg $out -run -scale $Scale
}
