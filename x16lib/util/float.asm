;ACME
; =====================================================================
; x16lib :: util/float.asm -- floating point, via the ROM's FP library
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; The X16 ROM already carries a complete C128/C65-compatible floating
; point library in BANK_BASIC, reachable through a stable jump table at
; $FE00. This module is a binding, not a reimplementation: several
; thousand lines of 6502 we do not have to write, test, or carry.
;
; Everything works on FAC, the floating accumulator in zero page. A
; float in memory is 5 bytes (FP_SIZE); reserve them with .res 5, 0.
;
;       f_from_s16 / f_store  fvar_a       ; fvar_a = 10.0
;       f_from_s16 / f_store  fvar_b       ; fvar_b = 4.0
;       f_load  fvar_a
;       f_div   fvar_b                     ; FAC = 2.5
;       f_to_str                           ; A/X -> "2.5"
;
; Pointer arguments are A = low byte, Y = high byte, matching the ROM.
;
; --- on operand order ------------------------------------------------
; The ROM's fp_fsub and fp_fdiv are backwards from what jumptab.s claims:
; both load ARG from memory and then subtract or divide FAC INTO it, so
; you get `mem - FAC` and `mem / FAC`. f_sub and f_div below present the
; intuitive direction by stashing FAC in ARG first and running the
; ARG-first form. f_rsub and f_rdiv expose the raw order, which is what
; you want for `1/x` and similar.
;
; --- cost ------------------------------------------------------------
; Every call crosses a ROM bank via jsrfar, which is not free. For hot
; per-frame maths prefer util/fixed.asm (8.8) or util/int32.asm.
; =====================================================================

; (zone: file scope in ca65)

; A caller's operand address, stashed across the bank crossings. Must be
; in zero page: f_to_str_trim dereferences it with (zp),y. Nothing here
; calls another library routine, so borrowing the shared scratch pointer
; cannot collide with anything.
f_ptr = X16_TPTR0

; ---------------------------------------------------------------------
; f_zero -- FAC = 0
; f_neg  -- FAC = -FAC
; f_abs  -- FAC = |FAC|
; f_int  -- FAC = int(FAC), truncating toward negative infinity
; ---------------------------------------------------------------------
f_zero
    jsrfar fp_zerofc, BANK_BASIC
    rts

; fp_negop is the true unary minus. fp_negfac, despite its name, is an
; internal helper of the ROM's add/subtract path that two's-complements
; the mantissa in place -- calling it on a normalised FAC denormalises
; it (5.0 comes back as garbage that reads about -2.5).
f_neg
    jsrfar fp_negop, BANK_BASIC
    rts

f_abs
    jsrfar fp_abs, BANK_BASIC
    rts

f_int
    jsrfar fp_int, BANK_BASIC
    rts

; ---------------------------------------------------------------------
; f_sgn -- out: A = $FF if FAC < 0, 0 if zero, 1 if positive
; ---------------------------------------------------------------------
f_sgn
    jsrfar fp_sign, BANK_BASIC
    rts

; ---------------------------------------------------------------------
; f_from_u8  -- in: A = 0..255.            FAC = A
; f_from_s16 -- in: A = low, X = high.     FAC = the signed value
; f_to_s16   -- out: A = low, X = high.    Rounds toward zero.
;
; fp_givayf wants the high byte in A and the low byte in Y, the reverse
; of this library's usual A = low convention, so swap on the way in.
; fp_ayint leaves the result big-endian in FACMO (high) and FACLO (low).
;
; f_from_u8 goes through givayf with a zero high byte: the ROM's
; fp_float converts a SIGNED byte, so 200 through it would come out
; as -56.
; ---------------------------------------------------------------------
f_from_u8
    tay                         ; Y = low byte
    lda #0                      ; A = high byte: zero-extend
    jsrfar fp_givayf, BANK_BASIC
    rts

f_from_s16
    sta f_ptr                   ; stash the low byte
    txa                         ; A = high
    ldy f_ptr                   ; Y = low
    jsrfar fp_givayf, BANK_BASIC
    rts

f_to_s16
    jsrfar fp_ayint, BANK_BASIC
    lda FP_FACLO
    ldx FP_FACMO
    rts

; ---------------------------------------------------------------------
; f_load  -- in: A/Y = address.  FAC = the 5-byte float there
; f_store -- in: A/Y = address.  Store round(FAC) there
;
; fp_movmf takes its pointer in X/Y rather than A/Y. Only this one does.
; ---------------------------------------------------------------------
f_load
    jsrfar fp_movfm, BANK_BASIC
    rts

f_store
    tax
    jsrfar fp_movmf, BANK_BASIC
    rts

; ---------------------------------------------------------------------
; f_add  -- in: A/Y = address.   FAC = FAC + mem
; f_mul  -- in: A/Y = address.   FAC = FAC * mem
; Both commute, so the ROM's order does not matter.
; ---------------------------------------------------------------------
f_add
    jsrfar fp_fadd, BANK_BASIC
    rts

f_mul
    jsrfar fp_fmult, BANK_BASIC
    rts

; ---------------------------------------------------------------------
; f_sub -- in: A/Y = address.   FAC = FAC - mem
; f_div -- in: A/Y = address.   FAC = FAC / mem
;
; The ROM only offers mem-first. Move FAC into ARG, load mem into FAC,
; then use the ARG-first entry, which computes ARG (op) FAC.
; ---------------------------------------------------------------------
f_sub
    sta f_ptr
    sty f_ptr+1
    jsrfar fp_movef, BANK_BASIC        ; ARG = FAC
    lda f_ptr
    ldy f_ptr+1
    jsrfar fp_movfm, BANK_BASIC        ; FAC = mem
    jsrfar fp_fsubt, BANK_BASIC        ; FAC = ARG - FAC
    rts

f_div
    sta f_ptr
    sty f_ptr+1
    jsrfar fp_movef, BANK_BASIC        ; ARG = FAC
    lda f_ptr
    ldy f_ptr+1
    jsrfar fp_movfm, BANK_BASIC        ; FAC = mem
    jsrfar fp_fdivt, BANK_BASIC        ; FAC = ARG / FAC
    rts

; ---------------------------------------------------------------------
; f_rsub -- in: A/Y = address.   FAC = mem - FAC
; f_rdiv -- in: A/Y = address.   FAC = mem / FAC   (the reciprocal form)
; The ROM's native order, one bank crossing instead of three.
; ---------------------------------------------------------------------
f_rsub
    jsrfar fp_fsub, BANK_BASIC
    rts

f_rdiv
    jsrfar fp_fdiv, BANK_BASIC
    rts

; ---------------------------------------------------------------------
; f_pow  -- in: A/Y = address.   FAC = FAC ^ mem
; f_rpow -- in: A/Y = address.   FAC = mem ^ FAC   (the ROM's order)
; ---------------------------------------------------------------------
f_pow
    sta f_ptr
    sty f_ptr+1
    jsrfar fp_movef, BANK_BASIC        ; ARG = FAC
    lda f_ptr
    ldy f_ptr+1
    jsrfar fp_movfm, BANK_BASIC        ; FAC = mem
    jsrfar fp_fpwrt, BANK_BASIC        ; FAC = ARG ^ FAC
    rts

f_rpow
    jsrfar fp_fpwr, BANK_BASIC
    rts

; ---------------------------------------------------------------------
; f_cmp -- in: A/Y = address
;          out: A = $FF if FAC < mem, 0 if equal, 1 if FAC > mem
; ---------------------------------------------------------------------
f_cmp
    jsrfar fp_fcomp, BANK_BASIC
    rts

; ---------------------------------------------------------------------
; Transcendentals. Each replaces FAC. sin, cos, tan and atan destroy ARG.
; ---------------------------------------------------------------------
f_sqrt
    jsrfar fp_sqr, BANK_BASIC
    rts

f_ln
    jsrfar fp_log, BANK_BASIC
    rts

f_exp
    jsrfar fp_exp, BANK_BASIC
    rts

f_sin
    jsrfar fp_sin, BANK_BASIC
    rts

f_cos
    jsrfar fp_cos, BANK_BASIC
    rts

f_tan
    jsrfar fp_tan, BANK_BASIC
    rts

f_atan
    jsrfar fp_atn, BANK_BASIC
    rts

; ---------------------------------------------------------------------
; f_to_str -- out: A = low, X = high of a NUL-terminated string
;
; The ROM writes it to FP_FBUFFR ($0100 -- the bottom of the stack page,
; which BASIC also uses for this). Copy it out before you push anything
; deep, and before the next f_to_str overwrites it.
;
; Positive numbers get a leading space, exactly as BASIC's PRINT shows
; them; f_to_str_trim skips it.
; ---------------------------------------------------------------------
f_to_str
    jsrfar fp_fout, BANK_BASIC
    pha                         ; the ROM returns A = low, Y = high
    tya
    tax                         ; X = high
    pla                         ; A = low
    rts

f_to_str_trim
    jsr f_to_str
    sta f_ptr
    stx f_ptr+1
    ldy #0
    lda (f_ptr),y
    cmp #32                     ; a leading space
    bne @done
    inc f_ptr                   ; skip the sign space
    bne @done
    inc f_ptr+1
@done
    lda f_ptr
    ldx f_ptr+1
    rts

; ---------------------------------------------------------------------
; f_from_str -- parse a decimal string into FAC
;   in: A/Y = address, X = length
;
; fp_val wants X = address LOW, Y = address high, A = length. Note the
; low byte in X: jumptab.s writes the argument as "float_X:float_Y", which
; everywhere else in that file means high:low, but the code is
; `stx index / sty index+1` -- low first. The comment is wrong.
; ---------------------------------------------------------------------
f_from_str
    sta f_ptr                   ; address low
    txa                         ; A = length
    ldx f_ptr                   ; X = address low; Y is already the high byte
    jsrfar fp_val, BANK_BASIC
    rts

; (end zone)
