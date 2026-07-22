;ACME
; =====================================================================
; x16lib :: string/string.asm -- 0-terminated string fundamentals
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; The core of the string library: measure, copy, append, compare, hash.
; Strings are NUL-terminated and passed by pointer in A (low) / X (high),
; the same convention as screen_puts / ser_puts. A second string (the
; target of a copy, the other side of a compare) goes in X16_P0/P1.
; Lengths are bytes, so strings are at most 255 characters (plus the NUL);
; there are no bounds checks -- make your target buffers big enough.
;
;       lda #<hello : ldx #>hello
;       jsr str_length                ; Y = 5
;       lda #<src : ldx #>src
;       lda #<dst : sta X16_P0
;       lda #>dst : sta X16_P1
;       jsr str_copy                  ; dst = src, Y = length
;
; The case, search, slice and classification routines live in their own
; files (X16_USE_STRING_CASE / _FIND / _SLICE / _CTYPE).
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; str_length -- in: A = low, X = high.  out: Y = length (A clobbered)
; Counts up to the first NUL. A string of 256+ bytes reports 0.
; ---------------------------------------------------------------------
str_length
    sta X16_T0
    stx X16_T1
    ldy #0
@loop
    lda (X16_T0),y
    beq @done
    iny
    bne @loop
@done
    rts

; ---------------------------------------------------------------------
; str_copy -- copy a string, overwriting the target.
;   in:  A = source low, X = source high, X16_P0/P1 = target
;   out: Y = length copied
; ---------------------------------------------------------------------
str_copy
    sta X16_T0
    stx X16_T1
    ldy #0
@loop
    lda (X16_T0),y
    sta (X16_P0),y              ; copies the NUL too, then stops
    beq @done
    iny
    bne @loop
@done
    rts

; ---------------------------------------------------------------------
; str_ncopy -- copy at most maxlength bytes, then NUL-terminate.
;   in:  A = source low, X = source high, X16_P0/P1 = target,
;        Y = maxlength
;   out: Y = length of the target string
; ---------------------------------------------------------------------
str_ncopy
    sta X16_T0
    stx X16_T1
    sty X16_T2                  ; maxlength
    ldy #0
@loop
    cpy X16_T2
    beq @cap                    ; hit the cap
    lda (X16_T0),y
    sta (X16_P0),y
    beq @done                   ; copied the NUL
    iny
    bne @loop
@cap
    lda #0
    sta (X16_P0),y              ; terminate at the cap
@done
    rts

; ---------------------------------------------------------------------
; str_append -- append a suffix to a target string.
;   in:  A = target low, X = target high, X16_P0/P1 = suffix
;   out: A = length of the resulting string
; ---------------------------------------------------------------------
str_append
    jsr str_length              ; T0/T1 = target, Y = its length
    sty X16_T2
    tya                         ; T0/T1 += length -> the append point
    clc
    adc X16_T0
    sta X16_T0
    bcc @nc
    inc X16_T1
@nc
    ldy #0
@loop
    lda (X16_P0),y              ; copy the suffix in
    sta (X16_T0),y
    beq @done
    iny
    bne @loop
@done
    tya                         ; result length = target + suffix
    clc
    adc X16_T2
    rts

; ---------------------------------------------------------------------
; str_nappend -- append, but never let the target exceed maxlength.
;   in:  A = target low, X = target high, X16_P0/P1 = suffix,
;        Y = maxlength
;   out: A = length of the resulting string (unchanged if it would
;        overflow the cap)
; ---------------------------------------------------------------------
str_nappend
    sty X16_T3                  ; maxlength
    jsr str_length              ; T0/T1 = target, Y = its length
    sty X16_T2                  ; current length
    cpy X16_T3
    bcs @toosmall               ; length >= max: no room, leave it be
    lda X16_T3                  ; room = max - length
    sec
    sbc X16_T2
    sta X16_T3
    lda X16_T2                  ; T0/T1 += length -> the append point
    clc
    adc X16_T0
    sta X16_T0
    bcc @nc
    inc X16_T1
@nc
    ldy #0
@loop
    cpy X16_T3                  ; stop at the room limit
    beq @cap
    lda (X16_P0),y
    sta (X16_T0),y
    beq @done
    iny
    bne @loop
@cap
    lda #0
    sta (X16_T0),y              ; terminate at the cap
@done
    tya                         ; result length = old length + appended
    clc
    adc X16_T2
    rts
@toosmall
    lda X16_T2                  ; unchanged length
    rts

; ---------------------------------------------------------------------
; str_compare -- compare two strings, case-sensitively, for sorting.
;   in:  A = string1 low, X = string1 high, X16_P0/P1 = string2
;   out: A = $FF (-1) if string1 < string2, 0 if equal, 1 if greater
; ---------------------------------------------------------------------
str_compare
    sta X16_T0
    stx X16_T1
    ldy #0
@loop
    lda (X16_T0),y              ; string1 char
    beq @s1end
    cmp (X16_P0),y              ; vs string2 char
    bne @diff
    iny
    bne @loop
    lda #0                      ; ran the whole page: equal
    rts
@s1end
    lda (X16_P0),y              ; string1 ended; string2 too?
    beq @equal
    lda #$FF                    ; string1 is the shorter -> before
    rts
@diff
    bcs @greater                ; carry from cmp: set if s1 >= s2
    lda #$FF
    rts
@greater
    lda #1
    rts
@equal
    lda #0
    rts

; ---------------------------------------------------------------------
; str_hash -- an 8-bit rolling hash of the string.
;   in:  A = low, X = high.  out: A = hash
;   hash(-1) = 179; hash(i) = rol(hash(i-1)) XOR string[i]
; ---------------------------------------------------------------------
str_hash
    sta X16_T0
    stx X16_T1
    lda #179
    sta X16_T2
    ldy #0
    clc
@loop
    lda (X16_T0),y
    beq @done
    rol X16_T2
    eor X16_T2
    sta X16_T2
    iny
    bne @loop
@done
    lda X16_T2
    rts

; (end zone)
