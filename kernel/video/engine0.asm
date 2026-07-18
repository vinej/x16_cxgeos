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

; --- the port manager (CODE, resident) --------------------------------
; cx_ov_load copies an engine image from its bank into the port region:
; interrupts masked (nothing must draw mid-copy), the caller's bank
; restored. Engine n lives in bank CX_OV0_BANK + n.
CX_OV0_BANK = 3
CX_MODES    = 2                 ; how many engines ride the banks today

cx_ov_boot                      ; boot: engine 0 in, mode noted
    stz cx_vmode
    lda #CX_OV0_BANK
    ; falls into cx_ov_load
cx_ov_load                      ; A = the engine's bank
    php
    sei
    tax
    lda RAM_BANK
    pha
    txa
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

; --- cx_gfx_init (slot 2) -- ALWAYS lands in mode 0 -------------------
; The shell (and the panic path, and every 0.x app) calls this to own
; the GUI screen. If an app left another engine in the port, put mode
; 0's back first: whatever happens in a mode, cx_exit -> shell -> here
; restores the desktop.
cx_do_gfx_init
    lda cx_vmode
    beq @go
    jsr cx_ov_boot
@go
    jmp cxov_init

; --- cx_gfx_mode (slot 76) -- A = the mode; carry set if unknown ------
cx_do_gfx_mode
    cmp #CX_MODES
    bcs @bad
    cmp cx_vmode
    beq @done                   ; already there
    pha
    clc
    adc #CX_OV0_BANK            ; engine n rides bank CX_OV0_BANK + n
    jsr cx_ov_load
    pla
    sta cx_vmode
    jsr cxov_init               ; the fresh engine programs VERA
@done
    clc
    rts
@bad
    sec
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
; X16_USE_BITMAP2 gate, the port names alias it (ovl.inc), there is
; nothing to copy, and mode 0 is the only mode.
cx_ov_boot
    rts
cx_do_gfx_init
    jmp gfx2_init
cx_do_gfx_mode
    cmp #1
    bcs @bad
    clc
    rts
@bad
    sec
    rts
.endif

; --- cx_gfx_info (slot 77) -- what canvas is this? --------------------
; A = the mode; P0/P1 = width, P2/P3 = height, P4 = bpp, P5/P6 = bytes
; per row. The one call that lets client code (cx_pic_*, a screenshot
; tool, a future mode) adapt to any engine without knowing its name.
cx_do_gfx_info
    lda cx_vmode
    asl                         ; 8-byte rows in the table
    asl
    asl
    tax
    ldy #0
@copy
    lda cx_minfo,x
    sta X16_P0,y
    inx
    iny
    cpy #7
    bne @copy
    lda cx_vmode
    rts

cx_vmode .byte 0                ; the engine in the port right now
cx_minfo                        ; w.w, h.w, bpp, stride.w (+1 pad) per mode
    .word 640, 480
    .byte 2
    .word 160
    .byte 0
    .word 320, 240
    .byte 8
    .word 320
    .byte 0
