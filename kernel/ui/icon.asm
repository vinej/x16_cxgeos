; ca65
; =====================================================================
; CXGEOS :: kernel/ui/icon.asm -- the icon sheet and its renderer
; =====================================================================
; A file's icon is one of a small built-in set (folder, app, font, ...),
; 24x24 in the port's 2bpp format (tools/icongen.py builds the sheet).
; The sheet rides bank 17 (graphics extras); ONE definition serves both
; bitmap modes, the way the CXF font does its glyphs:
;   mode 0  the 2bpp indices ARE the framebuffer colours -> gfx2_blit
;   mode 1  each 2-bit index expands through icon_map to an 8bpp pixel
;   modes 2/3  no bitmap: nothing to draw (WG_ICON refuses there too)
;
; The dispatch is resident and thin. Mode 0 is a straight blit through
; the port. Mode 1's expand rides bank 17 WITH the sheet, so it reads
; the icon from its own bank with no page-switch (a bank-N routine
; cannot page another bank into the window it runs in); the resident
; stub far-calls it.
;
; cx_icon (ABI) and the WG_ICON widget both call cx_do_icon.
;   in: A = icon id (ICON_*), X16_P0/P1 = x, X16_P2/P3 = y
; =====================================================================

ICON_W       = 24
ICON_H       = 24
ICON_ROWB    = ICON_W / 4       ; 6 bytes a row
ICON_BYTES   = ICON_ROWB * ICON_H   ; 144

; the ids the filer maps a file's kind (and known demo names) to; the order
; is the contract with tools/icongen.py and apps/filer
ICON_UP      = 0
ICON_FOLDER  = 1
ICON_APP     = 2
ICON_FONT    = 3
ICON_ACCESSORY = 4
ICON_DATA    = 5
ICON_IMAGE   = 6
ICON_DISK    = 7
ICON_CALC    = 8
ICON_PAINT   = 9
ICON_GAME    = 10
ICON_TEXT    = 11
ICON_SOUND   = 12
ICON_SPRITE  = 13
ICON_TILE    = 14
ICON_TERM    = 15
ICON_GEARS   = 16
ICON_GLOBE   = 17

; ---------------------------------------------------------------------
; cx_do_icon (RESIDENT) -- render icon A at (P0/P1, P2/P3).
; ---------------------------------------------------------------------
cx_do_icon
    ldx cx_vmode
    beq @gfx0                   ; mode 0: the 2bpp desktop
    cpx #1
    beq @gfx1                   ; mode 1: 8bpp
    rts                         ; tiles/text: no bitmap to draw into

; CX_I_SRC = icon_sheet + A*144 (icon_sheet is a bank-17 address; the
; arithmetic is on the value, so no bank is needed here)
@src
    stz CX_I_SRC
    stz CX_I_SRC+1
    tay
    beq @based
@mul
    clc
    lda CX_I_SRC
    adc #ICON_BYTES
    sta CX_I_SRC
    lda CX_I_SRC+1
    adc #0
    sta CX_I_SRC+1
    dey
    bne @mul
@based
    clc
    lda CX_I_SRC
    adc #<icon_sheet
    sta CX_I_SRC
    lda CX_I_SRC+1
    adc #>icon_sheet
    sta CX_I_SRC+1
    rts

; --- mode 0: a straight 2bpp blit through the port -------------------
@gfx0
    jsr @src
    lda RAM_BANK                ; the port's blit reads the source under
    pha                         ; RAM_BANK -- park it on the icon bank
    lda #CX_GFXX_BANK
    sta RAM_BANK
    lda #ICON_ROWB              ; width in 4-pixel byte columns
    sta X16_P4
    lda #ICON_H
    sta X16_P5
    lda CX_I_SRC
    sta X16_P6
    lda CX_I_SRC+1
    sta X16_P7
    lda #0                      ; raster op 0 = opaque copy. MUST be set: the
                                ; blit reads A as its op, and leaving the source
                                ; high byte here means any icon whose sheet
                                ; address has (high & 3) == 2 blits op 2 (AND)
                                ; over paper 0 -> a blank icon (font/game/text/
                                ; globe hit exactly that before this was fixed)
    jsr cxov_blit
    pla
    sta RAM_BANK
    rts

; --- mode 1: the expand rides bank 17 with the sheet -----------------
@gfx1
    jsr @src
.ifndef CX_NO_OVERLAY
    jsr cxb_call                ; RAM_BANK -> 17 (the sheet's bank) and back
    .byte CX_GFXX_BANK
    .addr icon_expand
.else
    jsr icon_expand             ; the flat runner links it in CODE
.endif
    rts

; =====================================================================
; bank 17: the mode-1 expand, the colour map, and the sheet
; =====================================================================
.ifndef CX_NO_OVERLAY
.segment "B17CODE"
.endif

; icon_expand -- CX_I_SRC's 24x24 icon to 8bpp at (P0/P1, P2/P3). Reads
; the sheet from THIS bank (RAM_BANK is 17 on entry) and writes the
; 320-stride framebuffer. VRAM address of pixel (x,y) is y*320 + x.
icon_expand
    lda X16_P2                  ; ic_addr = y*64  (3 bytes, y < 240)
    sta ic_a0
    stz ic_a1
    stz ic_a2
    ldx #6
@sh64
    asl ic_a0
    rol ic_a1
    rol ic_a2
    dex
    bne @sh64
    clc                         ; + y*256  (add y into the mid byte)
    lda ic_a1
    adc X16_P2
    sta ic_a1
    lda ic_a2
    adc #0
    sta ic_a2
    clc                         ; + x
    lda ic_a0
    adc X16_P0
    sta ic_a0
    lda ic_a1
    adc X16_P1
    sta ic_a1
    lda ic_a2
    adc #0
    sta ic_a2

    lda #ICON_H
    sta ic_row
@rowloop
    lda #VERA_CTRL_ADDRSEL      ; port 0 at this row, auto-increment 1
    trb VERA_CTRL
    lda ic_a0
    sta VERA_ADDR_L
    lda ic_a1
    sta VERA_ADDR_M
    lda ic_a2
    and #1                      ; bit 16
    ora #(VERA_INC_1 << 4)
    sta VERA_ADDR_H

    ldy #0                      ; the row's 6 packed bytes
@rb
    lda (CX_I_SRC),y
    sta ic_b
    sty ic_by
    ldx #4                     ; 4 pixels, MSB first
@px
    lda #0
    asl ic_b
    rol
    asl ic_b
    rol                         ; A = the 2-bit index
    tay
    lda icon_map,y
    sta VERA_DATA0
    dex
    bne @px
    ldy ic_by
    iny
    cpy #ICON_ROWB
    bne @rb

    clc                         ; next row of the sheet
    lda CX_I_SRC
    adc #ICON_ROWB
    sta CX_I_SRC
    lda CX_I_SRC+1
    adc #0
    sta CX_I_SRC+1
    clc                         ; next framebuffer row: address + 320
    lda ic_a0
    adc #<320
    sta ic_a0
    lda ic_a1
    adc #>320
    sta ic_a1
    lda ic_a2
    adc #0
    sta ic_a2
    dec ic_row
    bne @rowloop
    rts

; the mode-1 colour map: a 2-bit index -> an 8bpp palette entry. The
; default palette's low 16 are the C64 set (1 white, 12 grey, 11 dark
; grey, 0 black), so the sheet reads black-on-white with two greys.
icon_map  .byte 1, 12, 11, 0

ic_a0     .byte 0             ; the expand's scratch (bank-17 local)
ic_a1     .byte 0
ic_a2     .byte 0
ic_b      .byte 0
ic_by     .byte 0
ic_row    .byte 0

icon_sheet
    .incbin "fonts/icons.bin"

.ifndef CX_NO_OVERLAY
.segment "CODE"
.endif
