;ACME
; =====================================================================
; x16lib :: test/testlib.asm -- tiny on-target assertion harness
; =====================================================================
; Each test prints "PASS <name>" or "FAIL <name>" through CHROUT, and
; the run ends with "DONE <passes>/<total>" in hex. build.ps1 -Test
; greps stdout: any FAIL, or a pass count that disagrees with the total,
; fails the build.
;
; Uses its own scratch so it can never mask a library bug by sharing
; X16_T0..T7 with the code under test.
; =====================================================================

; (zone: file scope in ca65)

; The harness needs a zero-page pointer of its own for (indirect),y.
; Kept well away from the library's X16_ZP block so a test can never
; pass by accidentally sharing scratch with the code it is checking.
.ifndef T_ZP
T_ZP = $70
.endif
t_ptr = T_ZP              ; 2 bytes: T_ZP, T_ZP+1

t_passes    .byte 0
t_total     .byte 0
t_skips     .byte 0
t_expected  .byte 0

; ---------------------------------------------------------------------
; t_init -- reset counters
; ---------------------------------------------------------------------
t_init
    stz t_passes
    stz t_total
    stz t_skips
    rts

; ---------------------------------------------------------------------
; t_puts -- print a NUL-terminated string.  in: A = lo, X = hi
; ---------------------------------------------------------------------
t_puts
    sta t_ptr
    stx t_ptr+1
    ; A test may hand us the machine with port 1 selected. KERNAL screen
    ; routines assume ADDRSEL = 0 and will corrupt the display (and this
    ; harness's own output) otherwise -- see video/screen.asm.
    vera_addrsel 0
    ldy #0
@loop
    lda (t_ptr),y
    beq @done
    jsr CHROUT
    iny
    bne @loop
@done
    rts

; ---------------------------------------------------------------------
; t_puthex -- print A as two hex digits
; ---------------------------------------------------------------------
t_puthex
    pha
    lsr
    lsr
    lsr
    lsr
    jsr @nibble                 ; high nibble
    pla
    and #$0F                    ; fall through for the low nibble
@nibble
    cmp #10
    bcs @letter
    clc
    adc #'0'
    jmp CHROUT
@letter
    clc
    adc #('A' - 10)
    jmp CHROUT

; ---------------------------------------------------------------------
; t_pass / t_fail -- in: A = name lo, X = name hi
; ---------------------------------------------------------------------
; Each result begins with a CR so the "PASS"/"FAIL" token always starts a
; line, whatever the test under check left on the current one (a test may
; legitimately clear the screen or print into the tilemap). build.ps1
; anchors its regex to the line start, and that anchor is what catches a
; test whose result never got reported.
t_pass
    inc t_passes
    inc t_total
    pha
    phx
    lda #$0D
    jsr CHROUT
    lda #<@word
    ldx #>@word
    jsr t_puts
    plx
    pla
    jsr t_puts
    rts
@word .byte "PASS ", $00

t_fail
    inc t_total
    pha
    phx
    lda #$0D
    jsr CHROUT
    lda #<@word
    ldx #>@word
    jsr t_puts
    plx
    pla
    jsr t_puts
    rts
@word .byte "FAIL ", $00

; ---------------------------------------------------------------------
; t_skip -- in: A = name lo, X = name hi
;
; For a check the target machine genuinely cannot perform, as opposed to
; one that failed. Counted separately and excluded from the pass/total
; in DONE, so a skip can never be mistaken for a pass. Use it only where
; an independent oracle proved the capability is absent -- never to
; paper over a failure.
; ---------------------------------------------------------------------
t_skip
    inc t_skips
    pha
    phx
    lda #$0D
    jsr CHROUT
    lda #<@word
    ldx #>@word
    jsr t_puts
    plx
    pla
    jsr t_puts
    rts
@word .byte "SKIP ", $00

; ---------------------------------------------------------------------
; t_result -- report a test by its outcome.
;   in: A = 0 for pass, non-zero for fail
;       X = name lo, Y = name hi
; ---------------------------------------------------------------------
t_result
    cmp #0
    bne @failed
    txa                         ; A = name lo
    phy
    plx                         ; X = name hi
    jmp t_pass
@failed
    txa
    phy
    plx
    jmp t_fail

; ---------------------------------------------------------------------
; t_summary -- print "DONE <passes>/<total>"
; ---------------------------------------------------------------------
t_summary
    lda #$0D
    jsr CHROUT
    lda #<@done
    ldx #>@done
    jsr t_puts
    lda t_passes
    jsr t_puthex
    lda #'/'
    jsr CHROUT
    lda t_total
    jsr t_puthex

    lda t_skips
    beq @end
    pha
    lda #<@skipped
    ldx #>@skipped
    jsr t_puts
    pla
    jsr t_puthex
@end
    lda #$0D
    jmp CHROUT
@done    .byte "DONE ", $00
@skipped .byte " SKIP ", $00

; ---------------------------------------------------------------------
; t_vcmp_const -- compare a run of VRAM bytes against a constant.
;   in:  A = expected byte, X = count (1..255)
;   pre: port 1 already points at the first byte, with its increment
;   out: A = 0 if every byte matched, 1 otherwise
; ---------------------------------------------------------------------
t_vcmp_const
    sta t_expected
@loop
    lda VERA_DATA1
    cmp t_expected
    bne @bad
    dex
    bne @loop
    lda #0
    rts
@bad
    lda #1
    rts

; (end zone)
