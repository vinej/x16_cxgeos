@echo off
REM ===================================================================
REM  CXGEOS -- build the desktop and boot it in the emulator, windowed
REM  with the mouse captured. Double-click this, or run it from a shell.
REM
REM  Needs the repo-local tools in place (not committed; see README.md):
REM    cc65\ca65.exe, cc65\ld65.exe
REM    emulator\x16emu.exe (+ SDL DLLs), emulator\rom.bin (stock R49)
REM  The emulator window stays open until you close it.
REM ===================================================================

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" -Boot

REM Keep the window open so a build error stays readable.
if errorlevel 1 (
    echo.
    echo *** Build or launch failed -- see the messages above. ***
    pause
)
