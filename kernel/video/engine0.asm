; ca65
; =====================================================================
; CXGEOS :: kernel/video/engine0.asm -- mode 0: 640x480 @ 2bpp (the GUI)
; =====================================================================
; The first engine image behind the graphics port (ovl.inc). The image
; is the fixed 13-entry vector, then x16lib's bitmap2 module, compiled
; to RUN at the overlay region but STORED in bank 3 (kernel.cfg's
; OV0CODE segment). cx_ov_boot copies it in at kernel init, before
; anything can draw; a later cx_gfx_mode(0) does the same copy.
;
; bitmap2.asm is .included HERE, inside OV0CODE, so the X16_USE_BITMAP2
; gate stays OFF in kernel.asm -- x16_code.asm must not also place the
; module in the resident image. Its helpers (vera_fill, fx_fill) stay
; resident via the X16_USE_VERA / X16_USE_VERAFX_FILL gates.
;
; Internal kernel callers (font, widgets, menus, dialogs) keep naming
; gfx2_* directly: those labels ARE overlay run addresses now, correct
; whenever mode 0's image is resident -- and the toolkit is mode-0-only
; by contract. Only the ABI slots go through the vector, so an app
; always reaches the CURRENT engine.
; =====================================================================

.ifndef CX_NO_OVERLAY

; --- the boot copy (CODE, resident) ----------------------------------
; Copy mode 0's image from bank 3 into the port region. Whole pages,
; interrupts masked (nothing must draw mid-copy), the caller's bank
; restored.
CX_OV0_BANK = 3

cx_ov_boot
    php
    sei
    lda RAM_BANK
    pha
    lda #CX_OV0_BANK
    sta RAM_BANK
    lda #<$A000                 ; src walker in T0/T1, dst in T2/T3
    sta X16_T0
    lda #>$A000
    sta X16_T1
    lda #<CX_OVL
    sta X16_T2
    lda #>CX_OVL
    sta X16_T3
    ldx #>CX_OVL_SIZE           ; the whole pages first...
@page
    ldy #0
@byte
    lda (X16_T0),y
    sta (X16_T2),y
    iny
    bne @byte
    inc X16_T1
    inc X16_T3
    dex
    bne @page
.if <CX_OVL_SIZE <> 0
    ldy #0                      ; ...then the partial tail -- never a
@tail                           ; byte past OVL: $9F00 is I/O
    lda (X16_T0),y
    sta (X16_T2),y
    iny
    cpy #<CX_OVL_SIZE
    bne @tail
.endif
    pla
    sta RAM_BANK
    plp
    rts

; --- the engine image (OV0CODE: run = OVL, load = bank 3) ------------
.segment "OV0CODE"

ov0_vector                      ; the port's entry vector, slot order
    jmp gfx2_init
    jmp gfx2_clear
    jmp gfx2_pset
    jmp gfx2_read
    jmp gfx2_hline
    jmp gfx2_vline
    jmp gfx2_rect
    jmp gfx2_frame
    jmp gfx2_line
    jmp gfx2_pattern_set
    jmp gfx2_pattern_rect
    jmp gfx2_blit
    jmp gfx2_blitm

.assert ov0_vector = CX_OVL, error, "OV0CODE must start at CX_OVL -- kernel.cfg and ovl.inc disagree"

.include "gfx/bitmap2.asm"

.segment "CODE"

.else
; the runner links flat: the engine is already in CODE via x16_code's
; X16_USE_BITMAP2 gate, the port names alias it (ovl.inc), and there is
; nothing to copy.
cx_ov_boot
    rts
.endif
