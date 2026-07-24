;ACME
; =====================================================================
; x16lib :: util/clip.asm -- Cohen-Sutherland line clipping
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; gfx8l_line and fx_line are documented as non-clipping. This removes
; that sharp edge: give clip_line a segment in 16-bit SIGNED
; coordinates (anywhere within +/-4095) and it either rejects it or
; hands back the visible part, already loaded into the line drawers'
; parameter block:
;
;       ; clipl_x0/y0/x1/y1 = the segment, clip_set = the rectangle
;       jsr clip_line
;       bcs @offscreen              ; nothing visible
;       lda #colour
;       sta X16_P6
;       jsr gfx8l_line              ; or fx_line
;
; The rectangle is inclusive and defaults to the full 320x240 bitmap.
; =====================================================================

; (zone: file scope in ca65)

; the segment, written by the caller (16-bit signed, +/-4095)
clipl_x0 .word 0
clipl_y0 .word 0
clipl_x1 .word 0
clipl_y1 .word 0

; the clip rectangle, inclusive
clip_xmin .word 0
clip_ymin .word 0
clip_xmax .word 319
clip_ymax .word 239

; outcode bits
CLIP_LEFT   = %0001
CLIP_RIGHT  = %0010
CLIP_TOP    = %0100
CLIP_BOTTOM = %1000

; ---------------------------------------------------------------------
; clip_set -- change the rectangle
;   in: X16_P0/P1 = xmin, X16_P2/P3 = ymin,
;       X16_P4/P5 = xmax, X16_P6/P7 = ymax   (inclusive)
; ---------------------------------------------------------------------
clip_set
    lda X16_P0
    sta clip_xmin
    lda X16_P1
    sta clip_xmin+1
    lda X16_P2
    sta clip_ymin
    lda X16_P3
    sta clip_ymin+1
    lda X16_P4
    sta clip_xmax
    lda X16_P5
    sta clip_xmax+1
    lda X16_P6
    sta clip_ymax
    lda X16_P7
    sta clip_ymax+1
    rts

; ---------------------------------------------------------------------
; clip_line -- clip clipl_* against the rectangle
;   out: carry set   = entirely outside, draw nothing
;        carry clear = clipl_* now hold the visible sub-segment, and
;                      X16_P0..P5 are loaded for gfx8l_line / fx_line
; ---------------------------------------------------------------------
clip_line
@loop
    jsr clip_oc0
    sta cp_c0
    jsr clip_oc1
    sta cp_c1
    ora cp_c0
    bne @outside
    jmp @accept                 ; both inside (out of branch range)
@outside
    lda cp_c0
    and cp_c1
    beq @clip_one
    sec                         ; share an outside half-plane: reject
    rts

@clip_one
    ; pull the endpoint with a nonzero code into the work slot
    lda cp_c0
    bne @use0
    lda #1
    sta cp_which
    lda cp_c1
    sta cp_code
    ldx #3
@cp1
    lda clipl_x1,x
    sta cw_x,x
    lda clipl_x0,x
    sta co_x,x
    dex
    bpl @cp1
    jmp @intersect              ; out of branch range
@use0
    stz cp_which
    sta cp_code
    ldx #3
@cp0
    lda clipl_x0,x
    sta cw_x,x
    lda clipl_x1,x
    sta co_x,x
    dex
    bpl @cp0

@intersect
    lda cp_code
    and #CLIP_BOTTOM
    beq @not_bottom
    lda clip_ymax
    sta cp_b
    lda clip_ymax+1
    sta cp_b+1
    jsr clip_cross_y
    bra @store
@not_bottom
    lda cp_code
    and #CLIP_TOP
    beq @not_top
    lda clip_ymin
    sta cp_b
    lda clip_ymin+1
    sta cp_b+1
    jsr clip_cross_y
    bra @store
@not_top
    lda cp_code
    and #CLIP_RIGHT
    beq @not_right
    lda clip_xmax
    sta cp_b
    lda clip_xmax+1
    sta cp_b+1
    jsr clip_cross_x
    bra @store
@not_right
    lda clip_xmin
    sta cp_b
    lda clip_xmin+1
    sta cp_b+1
    jsr clip_cross_x

@store
    ; write the moved endpoint back and go around again
    lda cp_which
    bne @st1
    ldx #3
@sb0
    lda cw_x,x
    sta clipl_x0,x
    dex
    bpl @sb0
    jmp @loop
@st1
    ldx #3
@sb1
    lda cw_x,x
    sta clipl_x1,x
    dex
    bpl @sb1
    jmp @loop

@accept
    lda clipl_x0                ; load the drawers' parameter block
    sta X16_P0
    lda clipl_x0+1
    sta X16_P1
    lda clipl_y0
    sta X16_P2
    lda clipl_x1
    sta X16_P3
    lda clipl_x1+1
    sta X16_P4
    lda clipl_y1
    sta X16_P5
    clc
    rts

; --- outcodes ---------------------------------------------------------
; A = outcode of (clipl_x0, clipl_y0) / (clipl_x1, clipl_y1)
clip_oc0
    ldx #0                      ; offset of endpoint 0's fields
    bra clip_outcode
clip_oc1
    ldx #4
clip_outcode
    stz cp_oc
    ; x < xmin?
    lda clipl_x0,x
    cmp clip_xmin
    lda clipl_x0+1,x
    sbc clip_xmin+1
    bvc @ocx1
    eor #$80
@ocx1
    bpl @ocx2                   ; x >= xmin
    lda #CLIP_LEFT
    tsb cp_oc
    bra @ocy                    ; can't also be right of xmax
@ocx2
    ; xmax < x?
    lda clip_xmax
    cmp clipl_x0,x
    lda clip_xmax+1
    sbc clipl_x0+1,x
    bvc @ocx3
    eor #$80
@ocx3
    bpl @ocy
    lda #CLIP_RIGHT
    tsb cp_oc
@ocy
    ; y < ymin?
    lda clipl_y0,x
    cmp clip_ymin
    lda clipl_y0+1,x
    sbc clip_ymin+1
    bvc @ocy1
    eor #$80
@ocy1
    bpl @ocy2
    lda #CLIP_TOP
    tsb cp_oc
    bra @ocdone
@ocy2
    ; ymax < y?
    lda clip_ymax
    cmp clipl_y0,x
    lda clip_ymax+1
    sbc clipl_y0+1,x
    bvc @ocy3
    eor #$80
@ocy3
    bpl @ocdone
    lda #CLIP_BOTTOM
    tsb cp_oc
@ocdone
    lda cp_oc
    rts

; --- intersections ----------------------------------------------------
; Move the work endpoint onto the horizontal boundary cp_b:
;   cw_x += (co_x - cw_x) * (cp_b - cw_y) / (co_y - cw_y);  cw_y = cp_b
clip_cross_y
    sec                         ; numerator 1: dx = co_x - cw_x
    lda co_x
    sbc cw_x
    sta cp_m1
    lda co_x+1
    sbc cw_x+1
    sta cp_m1+1
    sec                         ; numerator 2: cp_b - cw_y
    lda cp_b
    sbc cw_y
    sta cp_m2
    lda cp_b+1
    sbc cw_y+1
    sta cp_m2+1
    sec                         ; denominator: dy = co_y - cw_y
    lda co_y
    sbc cw_y
    sta cp_m3
    lda co_y+1
    sbc cw_y+1
    sta cp_m3+1
    jsr clip_muldiv                 ; cp_q = m1 * m2 / m3, signed
    clc
    lda cw_x
    adc cp_q
    sta cw_x
    lda cw_x+1
    adc cp_q+1
    sta cw_x+1
    lda cp_b
    sta cw_y
    lda cp_b+1
    sta cw_y+1
    rts

; Move the work endpoint onto the vertical boundary cp_b:
;   cw_y += (co_y - cw_y) * (cp_b - cw_x) / (co_x - cw_x);  cw_x = cp_b
clip_cross_x
    sec
    lda co_y
    sbc cw_y
    sta cp_m1
    lda co_y+1
    sbc cw_y+1
    sta cp_m1+1
    sec
    lda cp_b
    sbc cw_x
    sta cp_m2
    lda cp_b+1
    sbc cw_x+1
    sta cp_m2+1
    sec
    lda co_x
    sbc cw_x
    sta cp_m3
    lda co_x+1
    sbc cw_x+1
    sta cp_m3+1
    jsr clip_muldiv
    clc
    lda cw_y
    adc cp_q
    sta cw_y
    lda cw_y+1
    adc cp_q+1
    sta cw_y+1
    lda cp_b
    sta cw_x
    lda cp_b+1
    sta cw_x+1
    rts

; cp_q = (cp_m1 * cp_m2) / cp_m3, all signed 16-bit. With inputs
; within +/-4095 the product fits 24 bits and the quotient 16.
clip_muldiv
    stz cp_sgn
    lda cp_m1+1                 ; strip the three signs
    bpl @m1p
    inc cp_sgn
    jsr clip_neg1
@m1p
    lda cp_m2+1
    bpl @m2p
    inc cp_sgn
    sec
    lda #0
    sbc cp_m2
    sta cp_m2
    lda #0
    sbc cp_m2+1
    sta cp_m2+1
@m2p
    lda cp_m3+1
    bpl @m3p
    inc cp_sgn
    sec
    lda #0
    sbc cp_m3
    sta cp_m3
    lda #0
    sbc cp_m3+1
    sta cp_m3+1
@m3p
    ; 16x16 -> 32 shift-add multiply: prod = m1 * m2 (umul16's shape,
    ; with the adc carry rolling down through the rotate)
    stz cp_prod+2
    stz cp_prod+3
    ldx #16
@mul
    lsr cp_m2+1
    ror cp_m2
    bcc @noadd
    lda cp_prod+2
    clc
    adc cp_m1
    sta cp_prod+2
    lda cp_prod+3
    adc cp_m1+1
    bra @rot
@noadd
    lda cp_prod+3               ; carry is already clear
@rot
    ror
    sta cp_prod+3
    ror cp_prod+2
    ror cp_prod+1
    ror cp_prod
    dex
    bne @mul

    ; 32 / 16 restoring divide: quotient into cp_prod
    stz cp_rem
    stz cp_rem+1
    ldx #32
@div
    asl cp_prod
    rol cp_prod+1
    rol cp_prod+2
    rol cp_prod+3
    rol cp_rem
    rol cp_rem+1
    sec
    lda cp_rem
    sbc cp_m3
    tay
    lda cp_rem+1
    sbc cp_m3+1
    bcc @nofit
    sta cp_rem+1
    sty cp_rem
    inc cp_prod
@nofit
    dex
    bne @div

    lda cp_prod
    sta cp_q
    lda cp_prod+1
    sta cp_q+1
    lda cp_sgn                  ; odd number of negatives: negate
    lsr
    bcc @posq
    sec
    lda #0
    sbc cp_q
    sta cp_q
    lda #0
    sbc cp_q+1
    sta cp_q+1
@posq
    rts

clip_neg1
    sec
    lda #0
    sbc cp_m1
    sta cp_m1
    lda #0
    sbc cp_m1+1
    sta cp_m1+1
    rts

; the work endpoint (being moved) and the opposite (fixed) endpoint --
; kept as x,y word pairs so indexed 4-byte copies can move them
cw_x .word 0
cw_y .word 0
co_x .word 0
co_y .word 0

cp_c0    .byte 0
cp_c1    .byte 0
cp_code  .byte 0
cp_which .byte 0
cp_oc    .byte 0
cp_b     .word 0
cp_m1    .word 0
cp_m2    .word 0
cp_m3    .word 0
cp_q     .word 0
cp_sgn   .byte 0
cp_prod  .res 4, 0
cp_rem   .word 0

; (end zone)
