;ACME
; =====================================================================
; x16lib :: string/case.asm -- upper/lower case conversion
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; Whole-string (in place) and single-character case folding, in both
; encodings. PETSCII and ISO place the letters at different codes, so the
; two encodings genuinely swap: PETSCII "lower" is numerically ISO "upper"
; and vice versa -- that is not a bug, it is the charset. The whole-string
; routines return the string length in Y. The compare routines fold both
; sides before comparing and return -1/0/1 like str_compare.
;
;       lda #<name : ldx #>name : jsr str_upper     ; NAME, in place
;       lda mychar : jsr str_lowerchar              ; A = folded char
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; str_lowerchar / str_lowerchar_iso -- fold one character to lower case
; str_upperchar / str_upperchar_iso -- ...to upper case.  in/out: A
; ---------------------------------------------------------------------
str_lowerchar
    and #$7f
    cmp #97
    bcc @done
    cmp #123
    bcs @done
    and #%11011111
@done
    rts

str_lowerchar_iso
    cmp #65
    bcc @done
    cmp #91
    bcs @done
    ora #$20
@done
    rts

str_upperchar
    cmp #65
    bcc @done
    cmp #91
    bcs @done
    ora #%00100000
@done
    rts

str_upperchar_iso
    cmp #97
    bcc @done
    cmp #123
    bcs @done
    and #%11011111
@done
    rts

; ---------------------------------------------------------------------
; str_lower / str_lower_iso -- fold a whole string to lower case in place.
; str_upper / str_upper_iso -- ...to upper case.
;   in: A = low, X = high.  out: Y = length
; ---------------------------------------------------------------------
str_lower
    sta X16_T0
    stx X16_T1
    ldy #0
@loop
    lda (X16_T0),y
    beq @done
    jsr str_lowerchar
    sta (X16_T0),y
    iny
    bne @loop
@done
    rts

str_lower_iso
    sta X16_T0
    stx X16_T1
    ldy #0
@loop
    lda (X16_T0),y
    beq @done
    jsr str_lowerchar_iso
    sta (X16_T0),y
    iny
    bne @loop
@done
    rts

str_upper
    sta X16_T0
    stx X16_T1
    ldy #0
@loop
    lda (X16_T0),y
    beq @done
    jsr str_upperchar
    sta (X16_T0),y
    iny
    bne @loop
@done
    rts

str_upper_iso
    sta X16_T0
    stx X16_T1
    ldy #0
@loop
    lda (X16_T0),y
    beq @done
    jsr str_upperchar_iso
    sta (X16_T0),y
    iny
    bne @loop
@done
    rts

; ---------------------------------------------------------------------
; str_compare_nocase / str_compare_nocase_iso -- case-insensitive compare.
;   in:  A = string1 low, X = string1 high, X16_P0/P1 = string2
;   out: A = $FF (-1) if string1 < string2, 0 if equal, 1 if greater
; ---------------------------------------------------------------------
str_compare_nocase
    sta X16_T0
    stx X16_T1
    ldy #0
@loop
    lda (X16_T0),y
    beq @s1end
    jsr str_lowerchar
    sta X16_T2
    lda (X16_P0),y
    jsr str_lowerchar
    cmp X16_T2
    bne @diff
    iny
    bne @loop
    lda #0
    rts
@diff
    bcc @greater                ; folded s2 < folded s1 -> string1 sorts after
    lda #$FF
    rts
@greater
    lda #1
    rts
@s1end
    lda (X16_P0),y
    beq @same
    lda #$FF
    rts
@same
    lda #0
    rts

str_compare_nocase_iso
    sta X16_T0
    stx X16_T1
    ldy #0
@loop
    lda (X16_T0),y
    beq @s1end
    jsr str_lowerchar_iso
    sta X16_T2
    lda (X16_P0),y
    jsr str_lowerchar_iso
    cmp X16_T2
    bne @diff
    iny
    bne @loop
    lda #0
    rts
@diff
    bcc @greater
    lda #$FF
    rts
@greater
    lda #1
    rts
@s1end
    lda (X16_P0),y
    beq @same
    lda #$FF
    rts
@same
    lda #0
    rts

; (end zone)
