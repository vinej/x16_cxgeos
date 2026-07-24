@echo off
rem =====================================================================
rem  paint.bat -- launch the STANDALONE PAINT cartridge.
rem
rem  PAINT is baked into the cartridge ROM (bank 37) alongside the whole
rem  CXRF framework, so the cart boots straight into the paint program
rem  with NO SD card at all -- the single-item "ship your own program on a
rem  cartridge" model. Double-click it, or run it from a terminal. Every
rem  path is relative to this file, so it works wherever the repo lives.
rem
rem  The cart is built by:  build.ps1 -Cart -App build\PAINT.CXA
rem  which bakes build\PAINT.CXA into build\cxrf_cart_paint.bin.
rem
rem  Note: with no SD, PAINT's save/load have nowhere to write, and its
rem  EXIT button drops to the X16 BASIC prompt (there is no desktop to
rem  return to without a card). Add  -fsroot build\sdroot  to the x16emu
rem  line below to give it a card for saved images and a shell to return
rem  to -- the framework still comes entirely from the cartridge.
rem =====================================================================
setlocal
cd /d "%~dp0"

set "EMU=emulator\x16emu.exe"
set "ROM=emulator\rom.bin"
set "CART=build\cxrf_cart_paint.bin"

if not exist "%EMU%" (
    echo Emulator not found at %EMU%. See README.md for setup.
    pause
    exit /b 1
)

if not exist "%CART%" (
    echo Cartridge not found. Building it with build.ps1 -Cart -App ...
    powershell -NoProfile -ExecutionPolicy Bypass -File "build.ps1" -Cart -App "build\PAINT.CXA"
    if errorlevel 1 (
        echo Build failed.
        pause
        exit /b 1
    )
)

echo Launching PAINT from the cartridge, ROM banks 32-37 -- no SD card.
echo The emulator captures the mouse so you can draw.
rem -bitmap2 enables VERA_2 so any mode-4 app launched here also works.
"%EMU%" -rom "%ROM%" -cartbin "%CART%" -scale 2 -bitmap2 -capture

endlocal
