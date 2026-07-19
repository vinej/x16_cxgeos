@echo off
rem =====================================================================
rem  run-cart.bat -- launch the CXGEOS cartridge build in the emulator.
rem
rem  Double-click it, or run it from a terminal. Every path is relative
rem  to this file, so it works wherever the repo lives. The kernel boots
rem  from the cartridge (ROM banks 32-36); the apps still load from the
rem  staged SD root in build\sdroot.
rem =====================================================================
setlocal
cd /d "%~dp0"

set "EMU=emulator\x16emu.exe"
set "ROM=emulator\rom.bin"
set "CART=build\cxgeos_cart.bin"
set "SD=build\sdroot"

if not exist "%EMU%" (
    echo Emulator not found at %EMU%. See README.md for setup.
    pause
    exit /b 1
)

if not exist "%CART%" (
    echo Cartridge image not found. Building it with build.ps1 -Cart ...
    powershell -NoProfile -ExecutionPolicy Bypass -File "build.ps1" -Cart
    if errorlevel 1 (
        echo Build failed.
        pause
        exit /b 1
    )
)

echo Launching CXGEOS from the cartridge, ROM banks 32-36...
echo The emulator captures the mouse for the desktop pointer.
"%EMU%" -rom "%ROM%" -cartbin "%CART%" -fsroot "%SD%" -scale 1 -capture

endlocal

