; ca65
; =====================================================================
; CXGEOS :: kernel/kernel.asm -- the resident image
; =====================================================================
; Everything that lives at $8000 and stays there. Built by
;
;   .\build.ps1 -Kernel        -> build\CXKERNEL.PRG
;
; against kernel/kernel.cfg, which pins the header at $8000, the jump
; table at $8010 and this code at $8200. An app owns $0801-$7FFF and
; reaches all of it through the table.
;
; The image is a PRG with a $8000 load address, so the boot stub loads
; it with one fs_load and jumps to the init vector in the header. Nothing
; here relocates: the addresses ARE the ABI.
;
; The resident budget is 7,424 bytes ($8200-$9EFF). ld65 fails the build
; if this overflows -- the budget enforces itself rather than being a
; comment someone has to remember.
; =====================================================================

.include "x16.asm"
.include "kernel/resident/zp.inc"

X16_USE_BITMAP2 = 1             ; the screen: pulls in VERA and VERAFX
X16_USE_IRQ     = 1             ; the event system's raster hook
X16_USE_INPUT   = 1             ; ...and its mouse and keyboard
X16_USE_SCREEN  = 1             ; cx_exit hands the text screen back
X16_USE_LOAD    = 1             ; the loader
X16_USE_BANK    = 1             ; the glyph cache's banks

.segment "LOADADDR"
    .word $8000

.segment "CODE"

; cx_init and the rest of the resident odds and ends live in core.asm,
; so that anything linking the jump table gets them -- the header points
; at cx_init, and a test that links the table would not otherwise
; resolve it.
.include "kernel/resident/core.asm"
.include "kernel/gfx2/dirty.asm"
.include "kernel/font/font.asm"
.include "kernel/event/event.asm"

; The system font. It is 871 bytes of the resident budget, and it earns
; them: a kernel that had to read its own font off the SD card could not
; put a message on the screen when the read failed.
cx_sysfont
    .incbin "fonts/pxl8.cxf"

.include "kernel/resident/jumptab.asm"
.include "x16_code.asm"
