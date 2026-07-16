; ca65
; =====================================================================
; x16lib :: util/math.asm -- game math (ca65 edition)
; =====================================================================
; Port of src_acme/util/math.asm. ca65 has no floating point in
; expressions, so the sine and arctangent tables ACME computes at
; assembly time are inlined here as literals -- generated from the
; identical formulas:
;   sin:  int(sin(i*pi/128) * 127.0 + 128.5) - 128     (i = 0..255)
;   atan: int(atan(i/32) * 128.0/pi + 0.5)             (i = 0..32)
; The ACME build remains the reference; the shared test suite pins
; both to the same anchor values.
; =====================================================================

; ---------------------------------------------------------------------
; rnd_seed -- in: A = low, X = high. Zero is nudged to 1.
; rnd8  -- out: A = the next pseudo-random byte (X = high byte)
; rnd16 -- out: A = low, X = high
; ---------------------------------------------------------------------
rnd_seed
    sta rnd_state
    stx rnd_state+1
    ora rnd_state+1
    bne @done
    inc rnd_state               ; zero stays zero forever
@done
    rts

rnd8                            ; same routine; read A, ignore X
rnd16
    lda rnd_state+1
    lsr
    lda rnd_state
    ror
    eor rnd_state+1
    sta rnd_state+1             ; x ^= x >> 9
    ror
    eor rnd_state
    sta rnd_state               ; x ^= x << 7
    eor rnd_state+1
    sta rnd_state+1             ; x ^= x << 8
    lda rnd_state
    ldx rnd_state+1
    rts

rnd_state .word $2A56

; ---------------------------------------------------------------------
; sin8 / cos8   -- in: A = angle 0-255.  out: A = -127..127 signed
; sin8u / cos8u -- in: A = angle 0-255.  out: A = 1..255 unsigned
; Preserve X; clobber Y.
; ---------------------------------------------------------------------
sin8
    tay
    lda math_sintab,y
    rts

cos8
    clc
    adc #64                     ; cos(a) = sin(a + 90 degrees)
    tay
    lda math_sintab,y
    rts

sin8u
    tay
    lda math_sintab,y
    clc
    adc #128
    rts

cos8u
    clc
    adc #64
    tay
    lda math_sintab,y
    clc
    adc #128
    rts

math_sintab
    .byte $00, $03, $06, $09, $0c, $10, $13, $16, $19, $1c, $1f, $22, $25, $28, $2b, $2e
    .byte $31, $33, $36, $39, $3c, $3f, $41, $44, $47, $49, $4c, $4e, $51, $53, $55, $58
    .byte $5a, $5c, $5e, $60, $62, $64, $66, $68, $6a, $6b, $6d, $6f, $70, $71, $73, $74
    .byte $75, $76, $78, $79, $7a, $7a, $7b, $7c, $7d, $7d, $7e, $7e, $7e, $7f, $7f, $7f
    .byte $7f, $7f, $7f, $7f, $7e, $7e, $7e, $7d, $7d, $7c, $7b, $7a, $7a, $79, $78, $76
    .byte $75, $74, $73, $71, $70, $6f, $6d, $6b, $6a, $68, $66, $64, $62, $60, $5e, $5c
    .byte $5a, $58, $55, $53, $51, $4e, $4c, $49, $47, $44, $41, $3f, $3c, $39, $36, $33
    .byte $31, $2e, $2b, $28, $25, $22, $1f, $1c, $19, $16, $13, $10, $0c, $09, $06, $03
    .byte $00, $fd, $fa, $f7, $f4, $f0, $ed, $ea, $e7, $e4, $e1, $de, $db, $d8, $d5, $d2
    .byte $cf, $cd, $ca, $c7, $c4, $c1, $bf, $bc, $b9, $b7, $b4, $b2, $af, $ad, $ab, $a8
    .byte $a6, $a4, $a2, $a0, $9e, $9c, $9a, $98, $96, $95, $93, $91, $90, $8f, $8d, $8c
    .byte $8b, $8a, $88, $87, $86, $86, $85, $84, $83, $83, $82, $82, $82, $81, $81, $81
    .byte $81, $81, $81, $81, $82, $82, $82, $83, $83, $84, $85, $86, $86, $87, $88, $8a
    .byte $8b, $8c, $8d, $8f, $90, $91, $93, $95, $96, $98, $9a, $9c, $9e, $a0, $a2, $a4
    .byte $a6, $a8, $ab, $ad, $af, $b2, $b4, $b7, $b9, $bc, $bf, $c1, $c4, $c7, $ca, $cd
    .byte $cf, $d2, $d5, $d8, $db, $de, $e1, $e4, $e7, $ea, $ed, $f0, $f4, $f7, $fa, $fd

; ---------------------------------------------------------------------
; atan2 -- the angle of a vector
;   in:  A = dx, X = dy  (signed bytes)
;   out: A = angle 0-255 (0 = +x/east, 64 = +y/down-screen)
; ---------------------------------------------------------------------
atan2
    stz at_negx
    tay                         ; |dx|, remembering the sign
    bpl @dx_pos
    inc at_negx
    eor #$FF
    clc
    adc #1
@dx_pos
    sta at_ax
    txa                         ; |dy|
    stz at_negy
    bpl @dy_pos
    inc at_negy
    eor #$FF
    clc
    adc #1
@dy_pos
    sta at_ay

    ; base angle 0..64 within the positive quadrant
    cmp at_ax
    beq @diag
    bcc @shallow
    lda at_ax                   ; steep: base = 64 - atan(ax/ay)
    ldx at_ay
    jsr math_ratio32
    tay
    sec
    lda #64
    sbc math_atantab,y
    bra @quad
@diag
    ora at_ax
    bne @is45
    lda #0                      ; atan2(0,0): call it east
    rts
@is45
    lda #32                     ; exactly 45 degrees
    bra @quad
@shallow
    lda at_ay                   ; shallow: base = atan(ay/ax)
    ldx at_ax
    jsr math_ratio32
    tay
    lda math_atantab,y

@quad
    ; fold the base angle into the right quadrant
    ldy at_negx
    beq @dx_ok
    eor #$FF                    ; dx < 0: angle = 128 - base
    clc
    adc #129
@dx_ok
    ldy at_negy
    beq @done
    eor #$FF                    ; dy < 0: angle = -angle
    clc
    adc #1
@done
    rts

; A = (A * 32) / X, for A <= X and X nonzero. Result 0..32.
math_ratio32
    stx at_den
    sta at_num+1                ; num = A * 256...
    stz at_num
    ldx #3
@shift
    lsr at_num+1                ; ...then >> 3 = A * 32
    ror at_num
    dex
    bne @shift
    lda #0                      ; 16-bit / 8-bit restoring divide
    ldx #16
@div
    asl at_num
    rol at_num+1
    rol
    cmp at_den
    bcc @no
    sbc at_den
    inc at_num
@no
    dex
    bne @div
    lda at_num                  ; the quotient
    rts

at_ax   .byte 0
at_ay   .byte 0
at_negx .byte 0
at_negy .byte 0
at_num  .word 0
at_den  .byte 0

math_atantab                    ; round(atan(t/32) * 256/2pi), t = 0..32
    .byte $00, $01, $03, $04, $05, $06, $08, $09, $0a, $0b, $0c, $0d, $0f, $10, $11, $12
    .byte $13, $14, $15, $16, $17, $18, $19, $19, $1a, $1b, $1c, $1d, $1d, $1e, $1f, $1f
    .byte $20

; ---------------------------------------------------------------------
; lerp8 -- linear interpolation between two unsigned bytes
;   in:  X16_P0 = a, X16_P1 = b, A = t (0 = a ... 255 = b)
;   out: A = the interpolated value; t=0 is exactly a, t=255 exactly b
; ---------------------------------------------------------------------
lerp8
    sta lp_t
    lda X16_P1
    cmp X16_P0
    bcc @down
    sbc X16_P0                  ; carry set: a clean subtract
    jsr math_scale_t
    clc
    adc X16_P0
    rts
@down
    lda X16_P0                  ; b < a: interpolate downwards
    sec
    sbc X16_P1
    jsr math_scale_t
    sta lp_d
    sec
    lda X16_P0
    sbc lp_d
    rts

; A = (A * (lp_t + 1)) >> 8
math_scale_t
    sta lp_d
    lda lp_t
    cmp #$FF
    beq @whole                  ; t+1 = 256: the answer is d itself
    inc a                       ; n = t+1, fits a byte
    sta lp_n
    lda #0
    ldx #8
@mul
    lsr lp_n
    bcc @skip
    clc
    adc lp_d
@skip
    ror
    dex
    bne @mul
    rts
@whole
    lda lp_d
    rts

lp_t .byte 0
lp_n .byte 0
lp_d .byte 0
