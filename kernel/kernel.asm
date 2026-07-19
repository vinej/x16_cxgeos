; ca65
; =====================================================================
; CXGEOS :: kernel/kernel.asm -- the resident image
; =====================================================================
; Everything that lives at $8000 and stays there. Built by
;
;   .\build.ps1 -Kernel        -> build\CXKERNEL.PRG
;
; against kernel/kernel.cfg, which pins the header at $8000, the jump
; table at $8010 and this code at $8160. An app owns $0801-$7FFF and
; reaches all of it through the table.
;
; The image is a PRG with a $8000 load address, so the boot stub loads
; it with one fs_load and jumps to the init vector in the header. Nothing
; here relocates: the addresses ARE the ABI.
;
; The resident budget is 5,280 bytes ($8160-$95FF); $9600-$9EFF is the
; graphics-port OVL window (kernel/video/ovl.inc), not code. ld65 fails
; the build if the budget overflows -- it enforces itself rather than
; being a comment someone has to remember.
; =====================================================================

.include "x16.asm"
.include "kernel/resident/zp.inc"
.include "kernel/resident/banks.inc"

; Only what is called. A gate here is 76 to 2,502 bytes of a 5,280-byte
; budget, and x16lib is one translation unit -- what a gate pulls in,
; the image carries whether anything calls it or not. SCREEN, LOAD and
; BANK were 821 bytes between them and nothing called any of them:
; cx_exit inlines the four instructions it wanted from SCREEN, the
; loader that will want LOAD does not exist yet, and font.asm writes
; RAM_BANK itself rather than going through BANK. Add them back when
; something calls them, not before.
; NOT X16_USE_BITMAP2: the 2bpp engine no longer lives in the resident
; image -- kernel/video/engine0.asm compiles it into the bank-3 overlay
; image behind the graphics port (kernel/video/ovl.inc). Its resident
; helpers stay gated in:
X16_USE_VERA        = 1         ; vera_fill (engine clears)
X16_USE_VERAFX_FILL = 1         ; fx_fill (engine rects)
X16_USE_VERAFX_COPY = 1         ; menu save-under: fx_copy moves the rows
X16_USE_IRQ     = 1             ; the event system's raster hook
X16_USE_INPUT   = 1             ; ...and its mouse and keyboard
X16_USE_SCREEN  = 1             ; the KERNAL console: mode 3 (text) draws
                                ; through it, and the 8bpp gfx_init needs
                                ; screen_set_mode

.include "kernel/video/ovl.inc"

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
.include "kernel/resident/clip.asm"
.include "kernel/fs/loader.asm"
.include "kernel/font/font.asm"
.include "kernel/ui/region.asm"
.include "kernel/ui/menu.asm"
; menu.asm FIRST among the bank-2 contributors: it owns the local jump
; table, and B2CODE fills in include order -- a file ahead of it would
; shove the table off $A000 and every stub with it
.include "kernel/ui/theme.asm"
.include "kernel/ui/dialog.asm"
.include "kernel/ui/widget.asm"
.include "kernel/ui/da.asm"
.include "kernel/audio/audio.asm"
.include "kernel/video/sprite.asm"
.include "kernel/video/engine0.asm"
.include "kernel/video/engine1.asm"
.include "kernel/video/shapes.asm"
.include "kernel/video/tiles.asm"
.include "kernel/video/text.asm"
; dir.asm and dirty.asm AFTER menu.asm's B2CODE (their banked bodies
; must not shove the local jump table off $A000)
.include "kernel/fs/dir.asm"
.include "kernel/fs/fileload.asm"
.include "kernel/fs/assets.asm"
.include "kernel/gfx2/dirty.asm"
.include "kernel/fs/dosglue.asm"
.include "kernel/event/event.asm"
.include "kernel/audio/pcm.asm"

; The system font is NOT here. It ships as PXL8.CXF on the SD card, and
; the boot loader puts it at CX_SYSFONT_BANK:$A000 before calling
; cx_init -- 871 bytes the resident budget gets back. If the loader
; forgets it, cx_init says so with carry while the machine is still in
; text mode, and the boot stub prints the complaint with the KERNAL.

.include "kernel/resident/jumptab.asm"
.include "kernel/resident/banksig.asm"
.include "x16_code.asm"
