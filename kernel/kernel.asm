; ca65
; =====================================================================
; CXRF :: kernel/kernel.asm -- the resident image
; =====================================================================
; Everything that lives at $8000 and stays there. Built by
;
;   .\build.ps1 -Kernel        -> build\CXKERNEL.PRG
;
; against kernel/kernel.cfg, which pins the header at $8000, the jump
; table at $8010 (135 slots reserved) and this code at $81A9. An app
; owns $0801-$7FFF and reaches all of it through the table.
;
; The image is a PRG with a $8000 load address, so the boot stub loads
; it with one fs_load and jumps to the init vector in the header. Nothing
; here relocates: the addresses ARE the ABI.
;
; The resident budget is ~5.2 KB ($81A9-$95FF); $9600-$9EFF is the
; graphics-port OVL window (kernel/video/ovl.inc), not code. ld65 fails
; the build if the budget overflows, and tools/mapreport.py fails it if
; the free margin drops under 128 bytes -- the budget enforces itself
; rather than being a comment someone has to remember. (The start moved
; up from $8160 when the jump table widened to 135 slots, paid for by
; banking the font cold half; see docs/banks.md.)
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
; The fine gates (x16_library 0.6.1) take each module's core and leave out
; the parts CXRF never calls: VERA_CORE drops vera_copy, IRQ_CORE drops
; vsync_wait, INPUT_CORE drops key_wait/key_peek, SCREEN_CORE drops
; get_mode/border/get_cursor/charset/puts. IRQ_SPRCOL is the collision
; CAPTURE (the handler accumulate + irq_sprcol_mask) that cx_spr_collide
; reads -- CXRF enables VERA_IEN and polls the mask itself, so it skips
; the IRQ_SPRCOL_API (install/remove/sprite_collisions/callback).
X16_USE_VERA_CORE   = 1         ; vera_fill (engine clears), not vera_copy
X16_USE_VERAFX_FILL = 1         ; fx_fill (engine rects)
X16_USE_VERAFX_COPY = 1         ; menu save-under: fx_copy moves the rows
X16_USE_IRQ_CORE    = 1         ; the event system's raster hook, no vsync
X16_USE_IRQ_SPRCOL  = 1         ; sprite-collision capture for cx_spr_collide
X16_USE_INPUT_CORE  = 1         ; mouse/joystick/key_get, no key_wait/peek
X16_USE_SCREEN_CORE = 1         ; mode 3 (text) draws through the KERNAL
                                ; console; 8bpp gfx_init needs screen_set_mode

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
.include "kernel/resident/vstream.asm"
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
.include "kernel/ui/icon.asm"
.include "kernel/ui/da.asm"
.include "kernel/audio/audio.asm"
.include "kernel/video/sprite.asm"
.include "kernel/video/engine0.asm"
.include "kernel/video/engine1.asm"
.include "kernel/video/shapes.asm"
.include "kernel/video/tiles.asm"
.include "kernel/video/pal.asm"
.include "kernel/video/text.asm"
.include "kernel/video/ov3t.asm"
; the fs/system modules ride bank 18 now (dir/fileload/assets/dosglue);
; dirty.asm rides bank 17. Only menu.asm + theme.asm + da.asm are left
; in B2CODE, and menu.asm is first among them (it owns the local table)
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
