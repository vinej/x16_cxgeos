;ACME
; =====================================================================
; x16lib :: audio/adpcm.asm -- IMA ADPCM decoding (4:1 compression)
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; The natural partner to the PCM streamer: IMA ADPCM stores 16-bit
; samples as 4-bit deltas, so a second of 16-bit mono at 16 kHz is
; 8 KB instead of 32 -- one RAM bank per second, streamable from disk.
;
; This is the canonical IMA/DVI algorithm (the one in WAV files, with
; the LOW nibble of each byte first). Decoder state is exposed:
; adpcm_pred and adpcm_index -- IMA WAV block headers carry initial
; values for both; store them before decoding a block's payload.
;
;       jsr adpcm_init              ; predictor 0, index 0
;       ...set X16_P0..P5...
;       jsr adpcm_block             ; n bytes in -> 2n samples out
; =====================================================================

; (zone: file scope in ca65)

adpcm_pred  .word 0             ; the predictor (signed 16-bit sample)
adpcm_index .byte 0             ; step table index 0-88

; ---------------------------------------------------------------------
; adpcm_init -- reset the decoder (predictor 0, step index 0)
; ---------------------------------------------------------------------
adpcm_init
    stz adpcm_pred
    stz adpcm_pred+1
    stz adpcm_index
    rts

; ---------------------------------------------------------------------
; adpcm_nibble -- decode one 4-bit code
;   in:  A = the code (0-15)
;   out: A = sample low, X = sample high (signed 16-bit; also left in
;        adpcm_pred). Clobbers Y.
; ---------------------------------------------------------------------
adpcm_nibble
    sta ad_n
    lda adpcm_index             ; step = steptab[index]
    asl
    tay
    lda adpcm_steps,y
    sta ad_sh
    lda adpcm_steps+1,y
    sta ad_sh+1

    ; diff = step>>3 (+ step if bit2) (+ step>>1 if bit1) (+ step>>2
    ; if bit0); max 1.875 * 32767 = 61436, which fits 16 bits unsigned
    stz ad_diff
    stz ad_diff+1
    lda ad_n
    and #4
    beq @no4
    lda ad_sh
    sta ad_diff
    lda ad_sh+1
    sta ad_diff+1
@no4
    lsr ad_sh+1
    ror ad_sh
    lda ad_n
    and #2
    beq @no2
    jsr adpcm_add_sh
@no2
    lsr ad_sh+1
    ror ad_sh
    lda ad_n
    and #1
    beq @no1
    jsr adpcm_add_sh
@no1
    lsr ad_sh+1
    ror ad_sh
    jsr adpcm_add_sh                 ; the unconditional step>>3

    ; predictor +/- diff, in 24 bits, saturated to 16
    lda adpcm_pred              ; sign-extend the predictor
    sta ad_p
    lda adpcm_pred+1
    sta ad_p+1
    stz ad_p+2
    bpl @ext_ok
    dec ad_p+2                  ; $FF
@ext_ok
    lda ad_n
    and #8
    bne @minus
    clc
    lda ad_p
    adc ad_diff
    sta ad_p
    lda ad_p+1
    adc ad_diff+1
    sta ad_p+1
    lda ad_p+2
    adc #0
    sta ad_p+2
    bra @clamp
@minus
    sec
    lda ad_p
    sbc ad_diff
    sta ad_p
    lda ad_p+1
    sbc ad_diff+1
    sta ad_p+1
    lda ad_p+2
    sbc #0
    sta ad_p+2

@clamp
    ; a legal 16-bit value has p+2 = $00 with p+1 bit7 clear, or
    ; p+2 = $FF with p+1 bit7 set; anything else saturates
    lda ad_p+2
    beq @maybe_pos
    cmp #$FF
    beq @maybe_neg
    bra @sat                    ; way out of range
@maybe_pos
    lda ad_p+1
    bpl @in_range
    bra @sat_pos
@maybe_neg
    lda ad_p+1
    bmi @in_range
    bra @sat_neg
@sat
    lda ad_p+2
    bmi @sat_neg
@sat_pos
    lda #$FF
    sta ad_p
    lda #$7F
    sta ad_p+1
    bra @in_range
@sat_neg
    stz ad_p
    lda #$80
    sta ad_p+1
@in_range
    lda ad_p
    sta adpcm_pred
    lda ad_p+1
    sta adpcm_pred+1

    ; index += indextab[n & 7], clamped to 0..88
    lda ad_n
    and #7
    tay
    lda adpcm_index
    clc
    adc adpcm_idxtab,y
    bpl @not_neg
    lda #0
@not_neg
    cmp #89
    bcc @idx_ok
    lda #88
@idx_ok
    sta adpcm_index

    lda adpcm_pred
    ldx adpcm_pred+1
    rts

adpcm_add_sh
    clc
    lda ad_diff
    adc ad_sh
    sta ad_diff
    lda ad_diff+1
    adc ad_sh+1
    sta ad_diff+1
    rts

; ---------------------------------------------------------------------
; adpcm_block -- decode a run of bytes to 16-bit little-endian samples
;   in:  X16_P0/P1 = source (ADPCM bytes)
;        X16_P2/P3 = destination (4 bytes out per byte in)
;        X16_P4/P5 = SOURCE byte count
;
; Low nibble first, as in IMA WAV blocks. The parameter block is
; consumed (pointers advance). Decoder state carries across calls, so
; feeding a block in slices is fine.
; ---------------------------------------------------------------------
adpcm_block
@loop
    lda X16_P4
    ora X16_P5
    beq @done

    ldy #0
    lda (X16_P0),y
    pha
    and #$0F                    ; low nibble first
    jsr adpcm_emit
    pla
    lsr
    lsr
    lsr
    lsr
    jsr adpcm_emit

    inc X16_P0
    bne @next
    inc X16_P1
@next
    lda X16_P4
    bne @declo
    dec X16_P5
@declo
    dec X16_P4
    bra @loop
@done
    rts

; decode nibble A, append the sample to the output pointer
adpcm_emit
    jsr adpcm_nibble
    ldy #0
    sta (X16_P2),y
    txa
    iny
    sta (X16_P2),y
    clc
    lda X16_P2
    adc #2
    sta X16_P2
    bcc @ok
    inc X16_P3
@ok
    rts

ad_n    .byte 0
ad_sh   .word 0
ad_diff .word 0
ad_p    .res 3, 0

adpcm_idxtab
    .byte $FF, $FF, $FF, $FF, 2, 4, 6, 8

adpcm_steps
    .word 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31
    .word 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143
    .word 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658
    .word 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024
    .word 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899
    .word 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767

; (end zone)
