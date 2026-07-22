;ACME
; =====================================================================
; x16lib :: util/bcd.asm -- packed-BCD (decimal-mode) add and subtract
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; Decimal arithmetic through the 65C02's BCD mode, so 8-bit, 16-bit and
; 32-bit packed-BCD values add and subtract the way you read them:
;
;       $0987 + $1111 = $2098          (not the binary $1A98)
;
; Each byte holds two decimal digits, low byte first. The point is to
; skip the costly binary->decimal conversion a game score or clock would
; otherwise need every frame: keep the count in BCD and print its hex
; form, which already reads as decimal.
;
; Values live in named registers, like util/int16.asm and util/int32.asm:
;
;       bcd_a   the accumulator; the add/sub routines overwrite it
;       bcd_b   the operand
;
;       +i32_const bcd_a, $00000987     ; a 4-byte BCD literal reads decimal
;       +i32_const bcd_b, $00001111
;       jsr bcd_add32                   ; bcd_a = $00002098
;
; Signed and unsigned share one routine per width -- decimal ADC/SBC does
; not know the difference, exactly as two's-complement add/sub does not
; in the integer modules. Pick the width; the interpretation is yours.
;
;   bcd_add8/16/32   bcd_a += bcd_b   (8/16/32-bit)
;   bcd_sub8/16/32   bcd_a -= bcd_b
;   bcd_addto        add bcd_b (32-bit) to a value in place, given a pointer
;   bcd_subfrom      subtract bcd_b (32-bit) from a value in place
;
; Add leaves the carry set on overflow past the width; subtract leaves it
; clear on borrow (result went below zero) -- the usual ADC/SBC carry.
;
; INTERRUPTS: these run in decimal mode across the operation. The KERNAL's
; IRQ handler is decimal-safe (it saves and restores the flags and does no
; decimal-sensitive ADC/SBC), so ordinary use is fine. A CUSTOM interrupt
; handler that does its own ADC/SBC must `cld` first, or bracket the call
; in sei/cli -- otherwise it would run those adds in decimal by mistake.
; =====================================================================

; (zone: file scope in ca65)

bcd_a .byte 0, 0, 0, 0
bcd_b .byte 0, 0, 0, 0

; ---------------------------------------------------------------------
; bcd_add8 / bcd_add16 / bcd_add32 -- bcd_a += bcd_b at that width.
;   out: carry set if the sum overflowed the width
; ---------------------------------------------------------------------
bcd_add8
    sed
    clc
    lda bcd_a
    adc bcd_b
    sta bcd_a
    cld
    rts

bcd_add16
    sed
    clc
    lda bcd_a
    adc bcd_b
    sta bcd_a
    lda bcd_a+1
    adc bcd_b+1
    sta bcd_a+1
    cld
    rts

bcd_add32
    sed
    clc
    ldx #0
    ldy #4
@loop
    lda bcd_a,x
    adc bcd_b,x                 ; carry threads through the loop untouched:
    sta bcd_a,x                 ; inx and dey leave it alone, cpx would not
    inx
    dey
    bne @loop
    cld
    rts

; ---------------------------------------------------------------------
; bcd_sub8 / bcd_sub16 / bcd_sub32 -- bcd_a -= bcd_b at that width.
;   out: carry clear if the result went below zero (borrow)
; ---------------------------------------------------------------------
bcd_sub8
    sed
    sec
    lda bcd_a
    sbc bcd_b
    sta bcd_a
    cld
    rts

bcd_sub16
    sed
    sec
    lda bcd_a
    sbc bcd_b
    sta bcd_a
    lda bcd_a+1
    sbc bcd_b+1
    sta bcd_a+1
    cld
    rts

bcd_sub32
    sed
    sec
    ldx #0
    ldy #4
@loop
    lda bcd_a,x
    sbc bcd_b,x
    sta bcd_a,x
    inx
    dey
    bne @loop
    cld
    rts

; ---------------------------------------------------------------------
; bcd_addto -- add bcd_b (32-bit) to a 4-byte BCD value in place.
;   in:  A = value low, X = value high (pointer to 4 bytes, low first)
;   out: carry set on overflow. Saves copying the value through bcd_a.
; ---------------------------------------------------------------------
bcd_addto
    sta X16_T0
    stx X16_T1
    sed
    clc
    ldy #0
    lda (X16_T0),y
    adc bcd_b
    sta (X16_T0),y
    iny
    lda (X16_T0),y
    adc bcd_b+1
    sta (X16_T0),y
    iny
    lda (X16_T0),y
    adc bcd_b+2
    sta (X16_T0),y
    iny
    lda (X16_T0),y
    adc bcd_b+3
    sta (X16_T0),y
    cld
    rts

; ---------------------------------------------------------------------
; bcd_subfrom -- subtract bcd_b (32-bit) from a 4-byte BCD value in place.
;   in:  A = value low, X = value high (pointer to 4 bytes, low first)
;   out: carry clear on borrow.
; ---------------------------------------------------------------------
bcd_subfrom
    sta X16_T0
    stx X16_T1
    sed
    sec
    ldy #0
    lda (X16_T0),y
    sbc bcd_b
    sta (X16_T0),y
    iny
    lda (X16_T0),y
    sbc bcd_b+1
    sta (X16_T0),y
    iny
    lda (X16_T0),y
    sbc bcd_b+2
    sta (X16_T0),y
    iny
    lda (X16_T0),y
    sbc bcd_b+3
    sta (X16_T0),y
    cld
    rts

; (end zone)
