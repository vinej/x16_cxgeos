;ACME
; =====================================================================
; x16lib :: util/int32.asm -- 32-bit integer arithmetic
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; The DOUBLE.TXT surface, in assembly. Values are 32 bits, little-endian,
; and live in two named registers the caller writes directly:
;
;       i32_a   the accumulator; most routines read and overwrite it
;       i32_b   the operand
;       i32_r   the remainder left by i32_divmod
;
; They are four-byte buffers rather than parameter-block arguments
; because a 32-bit binary operation needs eight bytes of input, and the
; block only holds eight in total.
;
;       +i32_const i32_a, 1000000
;       +i32_const i32_b, 7
;       jsr i32_divmod              ; i32_a = 142857, i32_r = 1
;
; Signed and unsigned share the same add, subtract, multiply and shift:
; two's complement makes them identical. Only comparison, division and
; decimal output need to know.
; =====================================================================

; (zone: file scope in ca65)

; +i32_const lives in core/macros.asm, because ACME needs a macro defined
; before it is called and this file is sourced last.

i32_a .byte 0, 0, 0, 0
i32_b .byte 0, 0, 0, 0
i32_r .byte 0, 0, 0, 0

i32_tmp .byte 0, 0, 0, 0
i32_cnt .byte 0

; ---------------------------------------------------------------------
; i32_from_u16 -- in: A = low, X = high.   i32_a = A/X, zero-extended
; i32_from_s16 -- in: A = low, X = high.   i32_a = A/X, sign-extended
; i32_to_s16   -- out: A = low, X = high   (the top two bytes are lost)
; ---------------------------------------------------------------------
i32_from_u16
    sta i32_a
    stx i32_a+1
    stz i32_a+2
    stz i32_a+3
    rts

i32_from_s16
    sta i32_a
    stx i32_a+1
    txa
    and #$80
    beq @positive
    lda #$FF                    ; negative: fill the top with ones
    sta i32_a+2
    sta i32_a+3
    rts
@positive
    stz i32_a+2
    stz i32_a+3
    rts

i32_to_s16
    ldx i32_a+1
    lda i32_a
    rts

; ---------------------------------------------------------------------
; i32_add -- i32_a += i32_b
; i32_sub -- i32_a -= i32_b
; ---------------------------------------------------------------------
i32_add
    clc
    lda i32_a
    adc i32_b
    sta i32_a
    lda i32_a+1
    adc i32_b+1
    sta i32_a+1
    lda i32_a+2
    adc i32_b+2
    sta i32_a+2
    lda i32_a+3
    adc i32_b+3
    sta i32_a+3
    rts

i32_sub
    sec
    lda i32_a
    sbc i32_b
    sta i32_a
    lda i32_a+1
    sbc i32_b+1
    sta i32_a+1
    lda i32_a+2
    sbc i32_b+2
    sta i32_a+2
    lda i32_a+3
    sbc i32_b+3
    sta i32_a+3
    rts

; ---------------------------------------------------------------------
; i32_neg -- i32_a = -i32_a
; i32_abs -- i32_a = |i32_a|
; ---------------------------------------------------------------------
i32_neg
    sec
    lda #0
    sbc i32_a
    sta i32_a
    lda #0
    sbc i32_a+1
    sta i32_a+1
    lda #0
    sbc i32_a+2
    sta i32_a+2
    lda #0
    sbc i32_a+3
    sta i32_a+3
    rts

i32_abs
    lda i32_a+3
    bmi i32_neg
    rts

; ---------------------------------------------------------------------
; i32_shl -- i32_a <<= 1
; i32_shr -- i32_a >>= 1, logical (zero fill)
; i32_asr -- i32_a >>= 1, arithmetic (sign fill)
; Carry holds the bit shifted out.
; ---------------------------------------------------------------------
i32_shl
    asl i32_a
    rol i32_a+1
    rol i32_a+2
    rol i32_a+3
    rts

i32_shr
    lsr i32_a+3
    ror i32_a+2
    ror i32_a+1
    ror i32_a
    rts

i32_asr
    lda i32_a+3
    asl                         ; sign bit into carry
    ror i32_a+3                 ; ...and back in at the top
    ror i32_a+2
    ror i32_a+1
    ror i32_a
    rts

; ---------------------------------------------------------------------
; i32_cmpu -- unsigned compare i32_a with i32_b
; i32_cmps -- signed compare
;   out: A = $FF if a < b, 0 if equal, 1 if a > b
;        Z set when equal.  Neither operand is modified.
; ---------------------------------------------------------------------
i32_cmpu
    lda i32_a+3
    cmp i32_b+3
    bne @differ
    lda i32_a+2
    cmp i32_b+2
    bne @differ
    lda i32_a+1
    cmp i32_b+1
    bne @differ
    lda i32_a
    cmp i32_b
    bne @differ
    lda #0                      ; equal
    rts
@differ
    bcs @greater
    lda #$FF
    rts
@greater
    lda #1
    rts

i32_cmps
    ; Same-signed operands compare like unsigned values. Different signs
    ; short-circuit: the negative one is the smaller, whatever the bits.
    lda i32_a+3
    eor i32_b+3
    bpl i32_cmpu                ; signs agree
    lda i32_a+3
    bmi @a_negative
    lda #1                      ; a >= 0, b < 0
    rts
@a_negative
    lda #$FF
    rts

; ---------------------------------------------------------------------
; i32_mul -- i32_a = i32_a * i32_b, modulo 2^32
;
; Shift-and-add. Signed and unsigned agree on the low 32 bits, so this
; serves both; only the discarded overflow differs.
; ---------------------------------------------------------------------
i32_mul
    lda i32_a                   ; tmp = a, then rebuild a as the product
    sta i32_tmp
    lda i32_a+1
    sta i32_tmp+1
    lda i32_a+2
    sta i32_tmp+2
    lda i32_a+3
    sta i32_tmp+3
    stz i32_a
    stz i32_a+1
    stz i32_a+2
    stz i32_a+3

    lda #32
    sta i32_cnt
@loop
    lsr i32_b+3                 ; next bit of the multiplier
    ror i32_b+2
    ror i32_b+1
    ror i32_b
    bcc @no_add

    clc                         ; a += tmp
    lda i32_a
    adc i32_tmp
    sta i32_a
    lda i32_a+1
    adc i32_tmp+1
    sta i32_a+1
    lda i32_a+2
    adc i32_tmp+2
    sta i32_a+2
    lda i32_a+3
    adc i32_tmp+3
    sta i32_a+3
@no_add
    asl i32_tmp                 ; tmp <<= 1
    rol i32_tmp+1
    rol i32_tmp+2
    rol i32_tmp+3

    dec i32_cnt
    bne @loop
    rts

; ---------------------------------------------------------------------
; i32_divmod -- unsigned:  i32_a = i32_a / i32_b,  i32_r = i32_a % i32_b
;   out: carry set if i32_b was zero, in which case nothing is changed
;
; Restoring division: shift the dividend left through the remainder one
; bit at a time, subtracting the divisor whenever it fits.
; ---------------------------------------------------------------------
i32_divmod
    lda i32_b                   ; divide by zero?
    ora i32_b+1
    ora i32_b+2
    ora i32_b+3
    bne @go
    sec
    rts
@go
    stz i32_r
    stz i32_r+1
    stz i32_r+2
    stz i32_r+3

    lda #32
    sta i32_cnt
@loop
    asl i32_a                   ; shift dividend out of the top of a...
    rol i32_a+1
    rol i32_a+2
    rol i32_a+3
    rol i32_r                   ; ...and into the bottom of r
    rol i32_r+1
    rol i32_r+2
    rol i32_r+3

    sec                         ; trial subtraction r - b
    lda i32_r
    sbc i32_b
    sta i32_tmp
    lda i32_r+1
    sbc i32_b+1
    sta i32_tmp+1
    lda i32_r+2
    sbc i32_b+2
    sta i32_tmp+2
    lda i32_r+3
    sbc i32_b+3
    sta i32_tmp+3
    bcc @restore                ; it did not fit: leave r alone

    lda i32_tmp                 ; it fit: keep the difference
    sta i32_r
    lda i32_tmp+1
    sta i32_r+1
    lda i32_tmp+2
    sta i32_r+2
    lda i32_tmp+3
    sta i32_r+3
    inc i32_a                   ; and set the quotient bit
@restore
    dec i32_cnt
    bne @loop
    clc
    rts

; ---------------------------------------------------------------------
; i32_to_dec -- unsigned i32_a to decimal, no leading zeros
;   out: A = buffer low, X = buffer high, Y = length
;        NUL-terminated, so screen_puts can print it directly.
;   Consumes i32_a and i32_b.
;
; Repeated division by ten, digits emitted least significant first and
; then reversed in place.
; ---------------------------------------------------------------------
i32_to_dec
    ldy #0
    sty i32_digits
@divide
    i32_const i32_b, 10
    jsr i32_divmod
    lda i32_r                   ; remainder is the next digit
    clc
    adc #'0'
    ldy i32_digits
    sta i32_buf,y
    inc i32_digits

    lda i32_a                   ; quotient zero yet?
    ora i32_a+1
    ora i32_a+2
    ora i32_a+3
    bne @divide

    ; Reverse the digits in place.
    ldx #0
    ldy i32_digits
    dey
@reverse
    stx i32_lo
    sty i32_hi
    cpx i32_hi
    bcs @done                   ; pointers met or crossed
    lda i32_buf,x
    pha
    lda i32_buf,y
    sta i32_buf,x
    pla
    sta i32_buf,y
    inx
    dey
    bra @reverse
@done
    ldy i32_digits
    lda #0
    sta i32_buf,y               ; terminate; Y is the length
    lda #<i32_buf
    ldx #>i32_buf
    rts

i32_buf    .res 12, 0          ; "4294967295" plus a terminator
i32_digits .byte 0
i32_lo     .byte 0
i32_hi     .byte 0

; (end zone)
