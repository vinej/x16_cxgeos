;ACME
; =====================================================================
; x16lib :: string/ctype.asm -- single-character classification
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; Character predicates, each taking the character in A and returning the
; answer in the carry (set = yes). Digits, hex digits and whitespace mean
; the same thing in PETSCII and ISO, so they have one routine each; the
; case-sensitive ones (upper / letter / print) come in a PETSCII form and
; an _iso form, because the two encodings place the letters differently.
;
;       lda mychar
;       jsr str_isdigit
;       bcs it_is_a_digit
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; str_isdigit -- carry set if A is '0'..'9'
; ---------------------------------------------------------------------
str_isdigit
    cmp #'0'
    bcc @no
    cmp #'9'+1
    bcs @no
    sec
    rts
@no
    clc
    rts

; ---------------------------------------------------------------------
; str_isxdigit -- carry set if A is a hex digit (0-9, A-F, a-f)
; ---------------------------------------------------------------------
str_isxdigit
    cmp #'0'
    bcc @no
    cmp #'9'+1
    bcc @yes
    cmp #'A'
    bcc @no
    cmp #'F'+1
    bcc @yes
    cmp #'a'
    bcc @no
    cmp #'f'+1
    bcc @yes
@no
    clc
    rts
@yes
    sec
    rts

; ---------------------------------------------------------------------
; str_islower -- carry set if A is 'a'..'z' (97-122). Same either encoding.
; ---------------------------------------------------------------------
str_islower
    cmp #'a'
    bcc @no
    cmp #'z'+1
    bcs @no
    sec
    rts
@no
    clc
    rts

; ---------------------------------------------------------------------
; str_isupper -- PETSCII: the two upper-case ranges, 97-122 and 193-218
; ---------------------------------------------------------------------
str_isupper
    cmp #97
    bcc @no
    cmp #122+1
    bcc @yes
    cmp #193
    bcc @no
    cmp #218+1
    bcc @yes
@no
    clc
    rts
@yes
    sec
    rts

; ---------------------------------------------------------------------
; str_isupper_iso -- ISO: 'A'..'Z' (65-90)
; ---------------------------------------------------------------------
str_isupper_iso
    cmp #'A'
    bcc @no
    cmp #'Z'+1
    bcs @no
    sec
    rts
@no
    clc
    rts

; ---------------------------------------------------------------------
; str_isletter -- PETSCII: a lower- or upper-case letter
; ---------------------------------------------------------------------
str_isletter
    jsr str_islower
    bcs @yes
    jmp str_isupper
@yes
    rts

; ---------------------------------------------------------------------
; str_isletter_iso -- ISO: a lower- or upper-case letter
; ---------------------------------------------------------------------
str_isletter_iso
    jsr str_islower
    bcs @yes
    jmp str_isupper_iso
@yes
    rts

; ---------------------------------------------------------------------
; str_isspace -- carry set if A is space, CR, LF, TAB, shift-CR or
; shift-space (32, 13, 10, 9, 141, 160)
; ---------------------------------------------------------------------
str_isspace
    cmp #32
    beq @yes
    cmp #13
    beq @yes
    cmp #9
    beq @yes
    cmp #10
    beq @yes
    cmp #141
    beq @yes
    cmp #160
    beq @yes
    clc
    rts
@yes
    sec
    rts

; ---------------------------------------------------------------------
; str_isprint -- PETSCII printable: 32-127 or 160-255
; ---------------------------------------------------------------------
str_isprint
    cmp #160
    bcs @yes
    cmp #32
    bcc @no
    cmp #128
    bcs @no
    sec
    rts
@no
    clc
    rts
@yes
    sec
    rts

; ---------------------------------------------------------------------
; str_isprint_iso -- ISO printable: 32-126 or 160-255
; ---------------------------------------------------------------------
str_isprint_iso
    cmp #160
    bcs @yes
    cmp #32
    bcc @no
    cmp #127
    bcs @no
    sec
    rts
@no
    clc
    rts
@yes
    sec
    rts

; (end zone)
