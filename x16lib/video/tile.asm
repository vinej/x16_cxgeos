;ACME
; =====================================================================
; x16lib :: video/tile.asm -- tilemap cells and layer configuration
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; The tile_* routines address layer 1, which in the default text modes
; is the text screen. They read L1_CONFIG and L1_MAPBASE at run time
; rather than assuming a screen mode, so they keep working after
; screen_set_mode.
;
; The KERNAL's default text setup is L1_CONFIG = $60 (map 128x64, 1bpp)
; with MAPBASE = $D8, i.e. the map at $1B000. A cell is two bytes:
; screen code, then colour attribute (fg | bg<<4).
;
; tile_setptr leaves ADDRSEL = 0, so it is safe to call the KERNAL
; afterwards -- see the note in video/screen.asm.
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; layer_index -- turn a layer number into the register offset.
;   in:  X = layer (0 or 1)
;   out: X = 0 or 7   (L1_CONFIG is 7 bytes past L0_CONFIG)
;   Preserves A.
; ---------------------------------------------------------------------
layer_index
    cpx #0
    beq @zero
    ldx #(VERA_L1_CONFIG - VERA_L0_CONFIG)
    rts
@zero
    ldx #0
    rts

; ---------------------------------------------------------------------
; layer_on / layer_off
;   in:  A = layer (0 or 1)
; ---------------------------------------------------------------------
layer_on
    tax
    vera_dcsel 0
    lda #VERA_VIDEO_LAYER0_EN
    cpx #0
    beq @go
    lda #VERA_VIDEO_LAYER1_EN
@go
    tsb VERA_DC_VIDEO
    rts

layer_off
    tax
    vera_dcsel 0
    lda #VERA_VIDEO_LAYER0_EN
    cpx #0
    beq @go
    lda #VERA_VIDEO_LAYER1_EN
@go
    trb VERA_DC_VIDEO
    rts

; ---------------------------------------------------------------------
; layer_set_config  -- in: X = layer, A = config byte
;   map height (7:6) | map width (5:4) | T256C (3) | bitmap (2) | bpp (1:0)
; layer_set_mapbase -- in: X = layer, A = VRAM address >> 9  (512-aligned)
; layer_set_tilebase-- in: X = layer, A = base>>11<<2 | tile size bits
; ---------------------------------------------------------------------
layer_set_config
    pha
    jsr layer_index
    pla
    sta VERA_L0_CONFIG,x
    rts

layer_set_mapbase
    pha
    jsr layer_index
    pla
    sta VERA_L0_MAPBASE,x
    rts

layer_set_tilebase
    pha
    jsr layer_index
    pla
    sta VERA_L0_TILEBASE,x
    rts

; ---------------------------------------------------------------------
; layer_scroll_x / layer_scroll_y -- 12-bit hardware scroll
;   in:  X = layer, X16_P0/P1 = value (0-4095)
; ---------------------------------------------------------------------
layer_scroll_x
    jsr layer_index
    lda X16_P0
    sta VERA_L0_HSCROLL_L,x
    lda X16_P1
    and #$0F
    sta VERA_L0_HSCROLL_H,x
    rts

layer_scroll_y
    jsr layer_index
    lda X16_P0
    sta VERA_L0_VSCROLL_L,x
    lda X16_P1
    and #$0F
    sta VERA_L0_VSCROLL_H,x
    rts

; ---------------------------------------------------------------------
; tile_setptr -- point data port 0 at a layer-1 tilemap cell.
;   in:  X = column, Y = row
;
; address = (L1_MAPBASE << 9) + (row * mapwidth + col) * 2
;
; mapwidth is 32 << ((L1_CONFIG >> 4) & 3), always a power of two, so
; (row * mapwidth) * 2 is just row shifted left by 6 + that field. The
; product needs 17 bits, hence the three-byte shift.
; ---------------------------------------------------------------------
tile_setptr
    stx X16_T4                  ; column
    sty X16_T5                  ; row

    lda VERA_L1_CONFIG
    lsr
    lsr
    lsr
    lsr
    and #$03                    ; map width code 0..3
    clc
    adc #6
    tax                         ; shift count 6..9

    stz X16_T1
    stz X16_T2
    lda X16_T5
    sta X16_T0
@shift
    asl X16_T0
    rol X16_T1
    rol X16_T2
    dex
    bne @shift

    ; + column * 2  (up to 9 bits)
    lda X16_T4
    asl
    sta X16_T6
    lda #0
    rol
    sta X16_T7

    clc
    lda X16_T0
    adc X16_T6
    sta X16_T0
    lda X16_T1
    adc X16_T7
    sta X16_T1
    lda X16_T2
    adc #0
    sta X16_T2

    ; + mapbase, which is (register << 9): low byte is always zero.
    lda VERA_L1_MAPBASE
    asl                         ; carry = VRAM address bit 16
    sta X16_T6
    lda #0
    rol
    sta X16_T7

    clc
    lda X16_T1
    adc X16_T6
    sta X16_T1
    lda X16_T2
    adc X16_T7
    sta X16_T2

    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL               ; ADDRSEL = 0, DCSEL untouched
    lda X16_T0
    sta VERA_ADDR_L
    lda X16_T1
    sta VERA_ADDR_M
    lda X16_T2
    and #VERA_ADDR_H_BANK
    ora #(VERA_INC_1 << 4)
    sta VERA_ADDR_H
    rts

; ---------------------------------------------------------------------
; tile_put -- write one cell
;   in:  X = column, Y = row, X16_P0 = screen code, X16_P1 = attribute
; ---------------------------------------------------------------------
tile_put
    jsr tile_setptr
    lda X16_P0
    sta VERA_DATA0
    lda X16_P1
    sta VERA_DATA0
    rts

; ---------------------------------------------------------------------
; tile_get -- read one cell
;   in:  X = column, Y = row
;   out: A = screen code, X = attribute
; ---------------------------------------------------------------------
tile_get
    jsr tile_setptr
    lda VERA_DATA0
    tay
    lda VERA_DATA0
    tax
    tya
    rts

; (end zone)
