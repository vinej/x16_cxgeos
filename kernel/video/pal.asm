; ca65
; =====================================================================
; CXRF :: kernel/video/pal.asm -- the VERA palette API (banked)
; =====================================================================
; pal_set / pal_load (x16lib video/palette.asm) program VERA's 256-entry
; palette at $1FA00. Most useful to a mode-1 (8bpp) app that wants a few
; custom colours without loading a whole 512-byte block through cx_vload;
; a 12-bit $0RGB colour stores as byte 0 = Green<<4|Blue, byte 1 = Red.
;
; They are cold -- an app programs colours at setup, not per frame -- so
; they ride bank 17 with the other gfx extras and the resident stubs
; far-call them. X16_USE_PALETTE is left OFF in kernel.asm on purpose: it
; would source palette.asm into the resident image through x16_code.asm
; (measured at +87 B, over the resident floor). We source it here instead,
; exactly once, into bank 17 -- the same way engine0 banks bitmap2.
;
;   cx_pal_set  (ABI)  X = index 0-255, A = low (G<<4|B), Y = high (R)
;   cx_pal_load (ABI)  P0/P1 = source, A = first index, X = count 1-128
; =====================================================================

; --- the resident trampolines ----------------------------------------
; cxb_call passes A/X/Y and carry straight through to the banked routine
; and returns to the app; pal_load's source is low RAM (P0/P1), not the
; banked window, so it reads correctly under RAM_BANK = 17.
cx_do_pal_set
    jsr cxb_call
    .byte CX_GFXX_BANK
    .addr pal_set
cx_do_pal_load
    jsr cxb_call
    .byte CX_GFXX_BANK
    .addr pal_load

; --- the routines themselves, in bank 17 -----------------------------
.ifndef CX_NO_OVERLAY
.segment "B17CODE"
.endif

.include "video/palette.asm"

.ifndef CX_NO_OVERLAY
.segment "CODE"
.endif
