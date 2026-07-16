;ACME
; =====================================================================
; x16lib :: util/bits.asm -- bit and nibble helpers
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; catnib -- in: A = high nibble, X = low nibble.  out: A = (A<<4)|X
; ---------------------------------------------------------------------
catnib
    and #$0F
    asl
    asl
    asl
    asl
    sta X16_T0
    txa
    and #$0F
    ora X16_T0
    rts

; ---------------------------------------------------------------------
; hinib / lonib -- in: A = byte.  out: A = that nibble, in bits 3:0
; ---------------------------------------------------------------------
hinib
    lsr
    lsr
    lsr
    lsr
    rts

lonib
    and #$0F
    rts

; ---------------------------------------------------------------------
; bit_set / bit_clr -- in: X16_PTR0 = address, A = mask
; bit_put          -- in: X16_PTR0 = address, A = mask,
;                        X != 0 to set, X = 0 to clear
; ---------------------------------------------------------------------
bit_set
    ldy #0
    ora (X16_PTR0),y
    sta (X16_PTR0),y
    rts

bit_clr
    eor #$FF
    ldy #0
    and (X16_PTR0),y
    sta (X16_PTR0),y
    rts

bit_put
    cpx #0
    beq bit_clr
    bra bit_set

; ---------------------------------------------------------------------
; bit_test -- in: X16_PTR0 = address, A = mask
;             out: Z clear if any masked bit is set
; ---------------------------------------------------------------------
bit_test
    ldy #0
    and (X16_PTR0),y
    rts

; (end zone)
