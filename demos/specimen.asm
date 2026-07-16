; ca65
; =====================================================================
; CXGEOS :: demos/specimen.asm -- the Phase 2 milestone
; =====================================================================
; The system font on the real screen: a type specimen, a paragraph
; reflowed at two measured widths, and the number the phase exists to
; produce -- glyphs per second, drawn the way the OS will draw them.
;
;   .\build.ps1 -Source demos\specimen.asm -Capture   # the numbers
;   .\build.ps1 -Source demos\specimen.asm -Run       # look at it
; =====================================================================

.include "x16.asm"
.include "kernel/resident/zp.inc"

X16_USE_BITMAP2 = 1
X16_USE_NUMBER  = 1

STR_PTR  = $60                  ; app zero page
BENCH_T0 = $62
REP      = $64
LINE_Y   = $65
WRAP_X   = $66                  ; 16-bit: the column the reflow breaks at
WORD_P   = $68

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    jsr gfx2_init
    lda #0                      ; white paper
    jsr gfx2_clear

    lda #<sp_banner
    ldx #>sp_banner
    jsr print_str

    lda #<pxl8                  ; adopt the font: this builds the cache
    ldx #>pxl8
    jsr font_set
    bcc @font_ok
    lda #<sp_badfont
    ldx #>sp_badfont
    jsr print_str
    bra @spin
@font_ok

    jsr draw_specimen

    jsr timer_alive
    bcs @timer_ok
    lda #<sp_skip
    ldx #>sp_skip
    jsr print_str
    bra @done
@timer_ok

    ; --- the number: 32 passes of the pangram at a walking x, so every
    ; --- phase is exercised the way real text hits them
    jsr RDTIM
    sta BENCH_T0
    stx BENCH_T0+1
    lda #32
    sta REP
@bench
    lda REP                     ; x = 8 + (rep & 3): all four phases
    and #3
    clc
    adc #8
    sta X16_P0
    stz X16_P1
    lda #<440
    sta X16_P2
    lda #>440
    sta X16_P3
    lda #<sp_pangram
    ldx #>sp_pangram
    jsr font_draw
    dec REP
    bne @bench
    jsr RDTIM
    sec
    sbc BENCH_T0
    sta X16_P0
    txa
    sbc BENCH_T0+1
    sta X16_P1

    lda #<sp_bench
    ldx #>sp_bench
    jsr print_str
    jsr u16_to_dec
    jsr print_str
    lda #<sp_jf
    ldx #>sp_jf
    jsr print_str

@done
    lda #<sp_done
    ldx #>sp_done
    jsr print_str
@spin
    bra @spin

; ---------------------------------------------------------------------
; draw_specimen -- what the font actually looks like.
; ---------------------------------------------------------------------
draw_specimen
    lda #10
    sta LINE_Y

    lda #<sp_title
    ldx #>sp_title
    jsr line

    lda #<sp_rule
    ldx #>sp_rule
    jsr line

    lda #<sp_upper
    ldx #>sp_upper
    jsr line
    lda #<sp_lower
    ldx #>sp_lower
    jsr line
    lda #<sp_digits
    ldx #>sp_digits
    jsr line
    lda #<sp_punct
    ldx #>sp_punct
    jsr line

    lda #<sp_rule
    ldx #>sp_rule
    jsr line

    ; the same paragraph twice, reflowed to two different measures --
    ; the proof that font_measure is load-bearing and not decorative
    lda #<sp_wide
    ldx #>sp_wide
    jsr line
    lda #<600
    sta WRAP_X
    lda #>600
    sta WRAP_X+1
    jsr reflow

    lda #<sp_narrow
    ldx #>sp_narrow
    jsr line
    lda #<260
    sta WRAP_X
    lda #>260
    sta WRAP_X+1
    jsr reflow

    lda #<sp_label
    ldx #>sp_label
    jsr line
    rts

; one line at x=8, y=LINE_Y, then down 10 rows
line
    sta WORD_P
    stx WORD_P+1
    lda #8
    sta X16_P0
    stz X16_P1
    lda LINE_Y
    sta X16_P2
    stz X16_P3
    lda WORD_P
    ldx WORD_P+1
    jsr font_draw
    lda LINE_Y
    clc
    adc #10
    sta LINE_Y
    rts

; ---------------------------------------------------------------------
; reflow -- draw sp_words, breaking at WRAP_X.
;
; Every word is measured before it is drawn, and the pen only moves if
; it fits. That is the whole point of a proportional font: the layout
; has to ask, because nothing about a string's length predicts its width.
; ---------------------------------------------------------------------
reflow
    lda #<sp_words
    sta WORD_P
    lda #>sp_words
    sta WORD_P+1
    lda #8
    sta X16_P0
    stz X16_P1

@word
    ldy #0                      ; end of the list?
    lda (WORD_P),y
    beq @done

    lda X16_P0                  ; park the pen: measure clobbers P0/P1
    pha
    lda X16_P1
    pha
    lda WORD_P
    ldx WORD_P+1
    jsr font_measure            ; P0/P1 = this word's width
    pla
    sta X16_T1                  ; pen high
    pla
    sta X16_T0                  ; pen low

    clc                         ; would the pen pass WRAP_X?
    lda X16_T0
    adc X16_P0
    sta X16_T2
    lda X16_T1
    adc X16_P1
    sta X16_T3
    cmp WRAP_X+1
    bne @cmp_hi
    lda X16_T2
    cmp WRAP_X
@cmp_hi
    bcc @fits

    lda #8                      ; no: new line
    sta X16_T0
    stz X16_T1
    lda LINE_Y
    clc
    adc #10
    sta LINE_Y
@fits
    lda X16_T0
    sta X16_P0
    lda X16_T1
    sta X16_P1
    lda LINE_Y
    sta X16_P2
    stz X16_P3
    lda WORD_P
    ldx WORD_P+1
    jsr font_draw               ; out: P0/P1 = the pen, one past the word

    ; step over this word's NUL to the next
    ldy #0
@skip
    lda (WORD_P),y
    beq @stepped
    iny
    bne @skip
@stepped
    iny
    tya
    clc
    adc WORD_P
    sta WORD_P
    bcc @word
    inc WORD_P+1
    bra @word

@done
    lda LINE_Y
    clc
    adc #10
    sta LINE_Y
    rts

; ---------------------------------------------------------------------
timer_alive
    jsr RDTIM
    sta BENCH_T0
    ldx #0
    ldy #0
@spin
    jsr RDTIM
    cmp BENCH_T0
    bne @alive
    dex
    bne @spin
    dey
    bne @spin
    clc
    rts
@alive
    sec
    rts

print_str
    sta STR_PTR
    stx STR_PTR+1
    ldy #0
@loop
    lda (STR_PTR),y
    beq @done
    jsr CHROUT
    iny
    bne @loop
@done
    rts

; ---------------------------------------------------------------------
sp_banner  .byte $0D, "CXGEOS SPECIMEN: PXL8", $0D, 0
sp_bench   .byte "PANGRAM32 ", 0
sp_jf      .byte " JF", $0D, 0
sp_skip    .byte "SKIP TIMER DEAD", $0D, 0
sp_badfont .byte "FAIL BAD CXF", $0D, 0
sp_done    .byte "DONE", $0D, 0

sp_title  .byte "pxl8 8px - the X16's own ISO charset, made proportional", 0
sp_rule   .byte "----------------------------------------------------------", 0
sp_upper  .byte "ABCDEFGHIJKLMNOPQRSTUVWXYZ", 0
sp_lower  .byte "abcdefghijklmnopqrstuvwxyz", 0
sp_digits .byte "0123456789", 0
; ca65 has no escapes inside a string: the quote, the backslash and the
; backtick go in as bytes.
sp_punct  .byte "!", $22, "#$%&'()*+,-./:;<=>?@[", $5C, "]^_", $60, "{|}~", 0
sp_wide   .byte "Reflowed to 600px:", 0
sp_narrow .byte "The same words to 260px:", 0
sp_label  .byte "Widths 2-8px, average 5.7. Monospace 8 would be 29% wider.", 0
sp_pangram .byte "Sphinx of black quartz, judge my vow.", 0

; the paragraph, one NUL-terminated word after another, ending in a
; second NUL
sp_words
    .byte "Every ", 0, "word ", 0, "here ", 0, "is ", 0, "measured ", 0
    .byte "before ", 0, "it ", 0, "is ", 0, "drawn, ", 0, "because ", 0
    .byte "nothing ", 0, "about ", 0, "a ", 0, "string's ", 0, "length ", 0
    .byte "predicts ", 0, "its ", 0, "width ", 0, "once ", 0, "the ", 0
    .byte "glyphs ", 0, "stop ", 0, "being ", 0, "boxes ", 0, "of ", 0
    .byte "the ", 0, "same ", 0, "size.", 0
    .byte 0

pxl8
    .incbin "fonts/pxl8.cxf"

; ---------------------------------------------------------------------
.include "kernel/font/font.asm"
.include "x16_code.asm"
