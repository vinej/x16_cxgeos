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

; Only what is called. A gate here is 76 to 2,502 bytes of a 7,424-byte
; budget, and x16lib is one translation unit -- what a gate pulls in,
; the image carries whether anything calls it or not. SCREEN, LOAD and
; BANK were 821 bytes between them and nothing called any of them:
; cx_exit inlines the four instructions it wanted from SCREEN, the
; loader that will want LOAD does not exist yet, and font.asm writes
; RAM_BANK itself rather than going through BANK. Add them back when
; something calls them, not before.
X16_USE_BITMAP2 = 1             ; the screen; asks VERAFX for _FILL alone
X16_USE_VERAFX_COPY = 1         ; menu save-under: fx_copy moves the rows
X16_USE_IRQ     = 1             ; the event system's raster hook
X16_USE_INPUT   = 1             ; ...and its mouse and keyboard

.segment "LOADADDR"
    .word $8000

.segment "CODE"

; cx_init and the rest of the resident odds and ends live in core.asm,
; so that anything linking the jump table gets them -- the header points
; at cx_init, and a test that links the table would not otherwise
; resolve it.
.include "kernel/resident/core.asm"
.include "kernel/resident/farcall.asm"
.include "kernel/resident/vrows.asm"
.include "kernel/fs/loader.asm"
.include "kernel/fs/dir.asm"
.include "kernel/gfx2/dirty.asm"
.include "kernel/font/font.asm"
.include "kernel/ui/region.asm"
.include "kernel/ui/menu.asm"
; menu.asm FIRST among the bank-2 contributors: it owns the local jump
; table, and B2CODE fills in include order -- a file ahead of it would
; shove the table off $A000 and every stub with it
.include "kernel/ui/theme.asm"
.include "kernel/ui/dialog.asm"
.include "kernel/ui/widget.asm"
.include "kernel/event/event.asm"

; The system font is NOT here. It ships as PXL8.CXF on the SD card, and
; the boot loader puts it at CX_SYSFONT_BANK:$A000 before calling
; cx_init -- 871 bytes the resident budget gets back. If the loader
; forgets it, cx_init says so with carry while the machine is still in
; text mode, and the boot stub prints the complaint with the KERNAL.

.include "kernel/resident/jumptab.asm"
.include "x16_code.asm"
