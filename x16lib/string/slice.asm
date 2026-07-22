;ACME
; =====================================================================
; x16lib :: string/slice.asm -- copying pieces of a string
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; Copy the left end, the right end, or an interior run of a source string
; into a target buffer, NUL-terminated. The source is passed in A (low) /
; X (high) and the target in X16_P0/P1; you must make the target buffer
; big enough and keep the lengths within the source -- there are no
; bounds checks.
;
;       lda #<name : ldx #>name          ; "COMMANDER"
;       lda #<buf : sta X16_P0
;       lda #>buf : sta X16_P1
;       ldy #3 : jsr str_left            ; buf = "COM"
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; str_left -- copy the first `length` characters.
;   in: A = source low, X = source high, X16_P0/P1 = target, Y = length
; ---------------------------------------------------------------------
str_left
    sta X16_T0
    stx X16_T1
    lda #0
    sta (X16_P0),y              ; terminate the target at [length]
    cpy #0
    beq @done
@loop
    dey
    lda (X16_T0),y
    sta (X16_P0),y
    cpy #0
    bne @loop
@done
    rts

; ---------------------------------------------------------------------
; str_right -- copy the last `length` characters.
;   in: A = source low, X = source high, X16_P0/P1 = target, Y = length
; ---------------------------------------------------------------------
str_right
    sty X16_T2                  ; length
    sta X16_T0
    stx X16_T1
    ldy #0                      ; measure the source
@len
    lda (X16_T0),y
    beq @gotlen
    iny
    bne @len
@gotlen
    tya                         ; source += (total - length)
    sec
    sbc X16_T2
    clc
    adc X16_T0
    sta X16_T0
    bcc @nc
    inc X16_T1
@nc
    ldy X16_T2                  ; then it is just a left-copy of `length`
    lda #0
    sta (X16_P0),y
    cpy #0
    beq @done
@loop
    dey
    lda (X16_T0),y
    sta (X16_P0),y
    cpy #0
    bne @loop
@done
    rts

; ---------------------------------------------------------------------
; str_slice -- copy `length` characters starting at `start`.
;   in: A = source low, X = source high, X16_P0/P1 = target,
;       X16_P2 = start, Y = length
; ---------------------------------------------------------------------
str_slice
    sta X16_T0
    stx X16_T1
    lda X16_T0                  ; source += start
    clc
    adc X16_P2
    sta X16_T0
    bcc @nc
    inc X16_T1
@nc
    lda #0
    sta (X16_P0),y              ; terminate the target at [length]
    cpy #0
    beq @done
@loop
    dey
    lda (X16_T0),y
    sta (X16_P0),y
    cpy #0
    bne @loop
@done
    rts

; ---------------------------------------------------------------------
; str_rtrim -- drop trailing whitespace, in place.
;   in: A = low, X = high.  out: Y = the new length
; Whitespace is space, TAB, CR, LF, shift-CR (141) and shift-space (160),
; the same set as str_isspace.
; ---------------------------------------------------------------------
str_rtrim
    sta X16_T0
    stx X16_T1
    ldy #0
@len
    lda (X16_T0),y
    beq @back
    iny
    bne @len
@back
    cpy #0
    beq @cut                    ; empty, or every char was whitespace
    dey
    lda (X16_T0),y
    jsr slice_slice_isws
    bcs @back                   ; whitespace: keep stepping back
    iny                         ; keep the last non-whitespace character
@cut
    lda #0
    sta (X16_T0),y
    rts

; ---------------------------------------------------------------------
; str_ltrim -- drop leading whitespace, shifting the rest down, in place.
;   in: A = low, X = high.  out: Y = the new length
; ---------------------------------------------------------------------
str_ltrim
    sta X16_T0
    stx X16_T1
    ldy #0
@skip
    lda (X16_T0),y
    beq @blank                  ; ran off the end: all whitespace
    jsr slice_slice_isws
    bcc @found
    iny
    bne @skip
@found
    cpy #0
    beq @nolead                 ; nothing to strip
    tya                         ; T2/T3 = source = string + first-kept index
    clc
    adc X16_T0
    sta X16_T2
    lda X16_T1
    adc #0
    sta X16_T3
    ldy #0
@shift
    lda (X16_T2),y
    sta (X16_T0),y
    beq @done
    iny
    bne @shift
@done
    rts
@nolead
    ldy #0                      ; unchanged; count its length for the caller
@nll
    lda (X16_T0),y
    beq @nldone
    iny
    bne @nll
@nldone
    rts
@blank
    lda #0                      ; all whitespace -> empty string
    sta (X16_T0)
    ldy #0
    rts

; ---------------------------------------------------------------------
; str_trim -- drop whitespace from both ends, in place.
;   in: A = low, X = high.  out: Y = the new length
; ---------------------------------------------------------------------
str_trim
    sta X16_T6
    stx X16_T7
    jsr str_rtrim
    lda X16_T6
    ldx X16_T7
    jmp str_ltrim

; whitespace test: A = char -> carry set if whitespace. Preserves A, X, Y.
slice_slice_isws
    cmp #32
    beq slice_isws_yes
    cmp #13
    beq slice_isws_yes
    cmp #10
    beq slice_isws_yes
    cmp #9
    beq slice_isws_yes
    cmp #141
    beq slice_isws_yes
    cmp #160
    beq slice_isws_yes
    clc
    rts
slice_isws_yes
    sec
    rts

; (end zone)
