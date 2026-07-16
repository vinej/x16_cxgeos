;ACME
; =====================================================================
; x16lib :: util/fixed.asm -- 16x16 multiply and 8.8 fixed point
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
; =====================================================================

; (zone: file scope in ca65)

; Scratch, private to this module.
fx_prod     .byte 0, 0, 0, 0    ; 32-bit product
fx_mcand    .byte 0, 0          ; multiplicand
fx_mplier   .byte 0, 0          ; multiplier (consumed)
fx_sign     .byte 0

; ---------------------------------------------------------------------
; umul16 -- unsigned 16 x 16 -> 32
;   in:  X16_P0/P1 = a, X16_P2/P3 = b
;   out: X16_P4..P7 = product, low byte first
; ---------------------------------------------------------------------
umul16
    lda X16_P0
    sta fx_mcand
    lda X16_P1
    sta fx_mcand+1
    lda X16_P2
    sta fx_mplier
    lda X16_P3
    sta fx_mplier+1

    stz fx_prod+2
    stz fx_prod+3
    ldx #16
@shift
    lsr fx_mplier+1
    ror fx_mplier               ; low bit of the multiplier into carry
    bcc @noadd
    lda fx_prod+2
    clc
    adc fx_mcand
    sta fx_prod+2
    lda fx_prod+3
    adc fx_mcand+1              ; A = new high byte, carry = overflow
    bra @rotate
@noadd
    lda fx_prod+3               ; carry is already clear
@rotate
    ror                         ; carry rolls down through the product
    sta fx_prod+3
    ror fx_prod+2
    ror fx_prod+1
    ror fx_prod
    dex
    bne @shift

    lda fx_prod
    sta X16_P4
    lda fx_prod+1
    sta X16_P5
    lda fx_prod+2
    sta X16_P6
    lda fx_prod+3
    sta X16_P7
    rts

; ---------------------------------------------------------------------
; mul88 -- signed 8.8 fixed-point multiply:  r = (a * b) >> 8
;   in:  X16_P0/P1 = a, X16_P2/P3 = b   (both signed 8.8)
;   out: X16_P0/P1 = r                  (signed 8.8)
;
; Lets sprites move at fractional speeds: hold the position in 8.8, add
; an 8.8 velocity each frame, and take the high byte as the pixel.
;
;   384 ($0180 = 1.5) * 512 ($0200 = 2.0) = 768 ($0300 = 3.0)
; ---------------------------------------------------------------------
mul88
    stz fx_sign

    lda X16_P1                  ; sign of a
    bpl @a_positive
    inc fx_sign
    jsr @negate_a
@a_positive
    lda X16_P3                  ; sign of b
    bpl @b_positive
    inc fx_sign
    jsr @negate_b
@b_positive

    jsr umul16                  ; P4..P7 = |a| * |b|

    lda X16_P5                  ; >> 8 : take bytes 1 and 2
    sta X16_P0
    lda X16_P6
    sta X16_P1

    lda fx_sign
    lsr                         ; odd number of negatives -> negate
    bcc @done
    jsr @negate_a
@done
    rts

@negate_a
    sec
    lda #0
    sbc X16_P0
    sta X16_P0
    lda #0
    sbc X16_P1
    sta X16_P1
    rts

@negate_b
    sec
    lda #0
    sbc X16_P2
    sta X16_P2
    lda #0
    sbc X16_P3
    sta X16_P3
    rts

; (end zone)
