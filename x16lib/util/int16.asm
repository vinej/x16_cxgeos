;ACME
; =====================================================================
; x16lib :: util/int16.asm -- 16-bit integer arithmetic
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
; Requires X16_USE_NUMBER (i16_to_dec_s builds on u16_to_dec).
;
; The same shape as util/int32.asm, one size down. Values live in named
; two-byte registers the caller writes directly:
;
;       i16_a   the accumulator; most routines read and overwrite it
;       i16_b   the operand
;       i16_r   the remainder left by the divides
;
;       +i16_const i16_a, 1000
;       +i16_const i16_b, 7
;       jsr i16_divmod             ; i16_a = 142, i16_r = 6
;
; Add, subtract, negate, multiply and the left shift are shared between
; signed and unsigned: two's complement makes them identical. Only
; comparison, division, the right shift and decimal output need to know
; which you meant, and those come in pairs.
;
; For the full 32-bit product of two 16-bit values use umul16 in
; util/fixed.asm; i16_mul keeps only the low 16 bits.
; =====================================================================

; (zone: file scope in ca65)

i16_a .byte 0, 0
i16_b .byte 0, 0
i16_r .byte 0, 0

i16_tmp   .byte 0, 0
i16_rem   .byte 0, 0
i16_cnt   .byte 0
i16_root  .byte 0
i16_sign  .byte 0
i16_qsign .byte 0
i16_rsign .byte 0
i16_buf  .res 8, 0             ; "-32768" plus a terminator

; ---------------------------------------------------------------------
; i16_from_u8 -- in: A.  i16_a = A, zero-extended
; i16_from_s8 -- in: A.  i16_a = A, sign-extended
; ---------------------------------------------------------------------
i16_from_u8
    sta i16_a
    stz i16_a+1
    rts

i16_from_s8
    sta i16_a
    and #$80
    beq @positive
    lda #$FF
    sta i16_a+1
    rts
@positive
    stz i16_a+1
    rts

; ---------------------------------------------------------------------
; i16_add -- i16_a += i16_b
; i16_sub -- i16_a -= i16_b
; ---------------------------------------------------------------------
i16_add
    clc
    lda i16_a
    adc i16_b
    sta i16_a
    lda i16_a+1
    adc i16_b+1
    sta i16_a+1
    rts

i16_sub
    sec
    lda i16_a
    sbc i16_b
    sta i16_a
    lda i16_a+1
    sbc i16_b+1
    sta i16_a+1
    rts

; ---------------------------------------------------------------------
; i16_neg -- i16_a = -i16_a
; i16_abs -- i16_a = |i16_a|
; ---------------------------------------------------------------------
i16_neg
    sec
    lda #0
    sbc i16_a
    sta i16_a
    lda #0
    sbc i16_a+1
    sta i16_a+1
    rts

i16_abs
    lda i16_a+1
    bmi i16_neg
    rts

; ---------------------------------------------------------------------
; i16_shl -- i16_a <<= 1
; i16_shr -- i16_a >>= 1, logical (zero fill)
; i16_asr -- i16_a >>= 1, arithmetic (sign fill)
; Carry holds the bit shifted out.
; ---------------------------------------------------------------------
i16_shl
    asl i16_a
    rol i16_a+1
    rts

i16_shr
    lsr i16_a+1
    ror i16_a
    rts

i16_asr
    lda i16_a+1
    asl                         ; sign bit into carry
    ror i16_a+1                 ; ...and back in at the top
    ror i16_a
    rts

; ---------------------------------------------------------------------
; i16_cmpu -- unsigned compare i16_a with i16_b
; i16_cmps -- signed compare
;   out: A = $FF if a < b, 0 if equal, 1 if a > b.  Z set when equal.
;        Neither operand is modified.
; ---------------------------------------------------------------------
i16_cmpu
    lda i16_a+1
    cmp i16_b+1
    bne @differ
    lda i16_a
    cmp i16_b
    bne @differ
    lda #0
    rts
@differ
    bcs @greater
    lda #$FF
    rts
@greater
    lda #1
    rts

i16_cmps
    ; Same-signed operands compare like unsigned ones. Different signs
    ; short-circuit: the negative one is smaller, whatever the bits say.
    lda i16_a+1
    eor i16_b+1
    bpl i16_cmpu                ; signs agree
    lda i16_a+1
    bmi @a_negative
    lda #1                      ; a >= 0, b < 0
    rts
@a_negative
    lda #$FF
    rts

; ---------------------------------------------------------------------
; i16_mul -- i16_a = i16_a * i16_b, modulo 2^16
;
; Shift-and-add. Signed and unsigned agree on the low 16 bits, so this
; serves both; only the discarded overflow differs.
; ---------------------------------------------------------------------
i16_mul
    lda i16_a                   ; tmp = a, then rebuild a as the product
    sta i16_tmp
    lda i16_a+1
    sta i16_tmp+1
    stz i16_a
    stz i16_a+1

    lda #16
    sta i16_cnt
@loop
    lsr i16_b+1                 ; next bit of the multiplier
    ror i16_b
    bcc @no_add

    clc                         ; a += tmp
    lda i16_a
    adc i16_tmp
    sta i16_a
    lda i16_a+1
    adc i16_tmp+1
    sta i16_a+1
@no_add
    asl i16_tmp                 ; tmp <<= 1
    rol i16_tmp+1

    dec i16_cnt
    bne @loop
    rts

; ---------------------------------------------------------------------
; i16_divmod -- unsigned:  i16_a = i16_a / i16_b,  i16_r = i16_a % i16_b
;   out: carry set if i16_b was zero, in which case nothing is changed
;
; Restoring division: shift the dividend left through the remainder one
; bit at a time, subtracting the divisor whenever it fits.
; ---------------------------------------------------------------------
i16_divmod
    lda i16_b
    ora i16_b+1
    bne @go
    sec                         ; divide by zero
    rts
@go
    stz i16_r
    stz i16_r+1

    lda #16
    sta i16_cnt
@loop
    asl i16_a                   ; dividend out of the top of a...
    rol i16_a+1
    rol i16_r                   ; ...and into the bottom of r
    rol i16_r+1

    sec                         ; trial subtraction r - b
    lda i16_r
    sbc i16_b
    sta i16_tmp
    lda i16_r+1
    sbc i16_b+1
    sta i16_tmp+1
    bcc @next                   ; did not fit: leave r alone

    lda i16_tmp                 ; it fit: keep the difference
    sta i16_r
    lda i16_tmp+1
    sta i16_r+1
    inc i16_a                   ; and set the quotient bit
@next
    dec i16_cnt
    bne @loop
    clc
    rts

; ---------------------------------------------------------------------
; i16_divmod_s -- signed divide, truncating toward zero
;   i16_a = i16_a / i16_b,  i16_r = i16_a % i16_b
;   out: carry set if i16_b was zero
;
; The quotient's sign is the exclusive-or of the operands' signs; the
; remainder takes the sign of the DIVIDEND, which is what C and Forth's
; SM/REM both do. -7 / 2 is -3 remainder -1, not -4 remainder 1.
; ---------------------------------------------------------------------
; Note: i16_divmod_s leaves i16_b holding |i16_b|.
; -32768 has no positive counterpart, so |a| overflows for that one value.
i16_divmod_s
    lda i16_b
    ora i16_b+1
    bne @go
    sec                         ; divide by zero
    rts
@go
    ; Capture both signs BEFORE taking absolute values, or they are gone.
    lda i16_a+1
    sta i16_rsign               ; remainder follows the dividend
    eor i16_b+1
    sta i16_qsign               ; quotient follows sign(a) xor sign(b)

    jsr i16_abs                 ; |a|

    lda i16_b+1                 ; |b|
    bpl @b_positive
    sec
    lda #0
    sbc i16_b
    sta i16_b
    lda #0
    sbc i16_b+1
    sta i16_b+1
@b_positive

    jsr i16_divmod              ; unsigned |a| / |b|; b is nonzero

    lda i16_rsign
    bpl @quotient
    sec                         ; negate the remainder
    lda #0
    sbc i16_r
    sta i16_r
    lda #0
    sbc i16_r+1
    sta i16_r+1
@quotient
    lda i16_qsign
    bpl @done
    jsr i16_neg
@done
    clc
    rts

; ---------------------------------------------------------------------
; i16_sqrt -- floor(sqrt(i16_a)), the ISQRT of FLOAT.TXT
;   out: A = the root (0..255).  Consumes i16_a.
;
; Digit-by-digit binary square root: two bits of the operand enter the
; remainder each round, and the trial subtrahend is 4*root+1.
; ---------------------------------------------------------------------
i16_sqrt
    stz i16_root
    stz i16_rem
    stz i16_rem+1

    ldx #8
@iter
    asl i16_a                   ; two bits of a into the remainder
    rol i16_a+1
    rol i16_rem
    rol i16_rem+1
    asl i16_a
    rol i16_a+1
    rol i16_rem
    rol i16_rem+1

    lda i16_root                ; trial = (root << 2) | 1
    sta i16_tmp
    stz i16_tmp+1
    asl i16_tmp
    rol i16_tmp+1
    asl i16_tmp
    rol i16_tmp+1
    lda i16_tmp
    ora #1
    sta i16_tmp

    asl i16_root                ; root <<= 1, bit 0 clear

    lda i16_rem                 ; rem >= trial ?
    cmp i16_tmp
    lda i16_rem+1
    sbc i16_tmp+1
    bcc @next

    sec                         ; rem -= trial
    lda i16_rem
    sbc i16_tmp
    sta i16_rem
    lda i16_rem+1
    sbc i16_tmp+1
    sta i16_rem+1
    inc i16_root                ; set the new root bit
@next
    dex
    bne @iter

    lda i16_root
    rts

; ---------------------------------------------------------------------
; i16_to_dec   -- unsigned i16_a to decimal
; i16_to_dec_s -- signed i16_a to decimal, with a leading '-'
;   out: A = buffer low, X = buffer high, Y = length; NUL-terminated.
;   Both consume i16_a.
; ---------------------------------------------------------------------
i16_to_dec
    lda i16_a
    sta X16_P0
    lda i16_a+1
    sta X16_P1
    jmp u16_to_dec

i16_to_dec_s
    stz i16_sign
    lda i16_a+1
    bpl @positive

    inc i16_sign                ; negative: print the magnitude
    sec
    lda #0
    sbc i16_a
    sta X16_P0
    lda #0
    sbc i16_a+1
    sta X16_P1
    bra @convert
@positive
    lda i16_a
    sta X16_P0
    lda i16_a+1
    sta X16_P1
@convert
    jsr u16_to_dec              ; digits land in num_buf

    ldx #0
    lda i16_sign
    beq @copy
    lda #'-'
    sta i16_buf
    ldx #1
@copy
    ldy #0
@loop
    lda num_buf,y               ; the terminator is copied too
    sta i16_buf,x
    beq @done
    inx
    iny
    bra @loop
@done
    txa
    tay                         ; Y = length, not counting the terminator
    lda #<i16_buf
    ldx #>i16_buf
    rts

; (end zone)
