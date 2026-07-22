; ca65
; =====================================================================
; CXRF :: apps/hello_asm/hello.asm -- the assembly hello
; =====================================================================
; The Phase 4 milestone app: built from sdk/ alone, launched by the
; shell, draws through the jump table, and leaves through cx_exit --
; which reloads the shell, closing the loop the whole phase exists to
; prove. Any key returns at once; three seconds return anyway, so the
; loop closes even with nobody at the keyboard.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxrf.inc"

EV_KEY = 5

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    ldx #0
@mk
    lda s_marker,x
    beq @go
    jsr CHROUT
    inx
    bne @mk
@go
    lda #1
    jsr cx_gfx_clear            ; a different paper than the shell's, so
                                ; the handoff is visible from across the
                                ; room
    jsr cx_version              ; the kernel introduces itself: A is the
    clc                         ; version low byte, and under ten it is
    adc #'0'                    ; one digit
    sta s_ver

    lda #<s_hello
    ldx #>s_hello
    ldy #<200
    jsr say
    lda #<s_abi
    ldx #>s_abi
    ldy #<224
    jsr say
    lda #<s_bye
    ldx #>s_bye
    ldy #<260                   ; = 4: say supplies the ninth bit
    jsr say

    jsr cx_ev_init
    jsr cx_ev_frames
    sta frame0

wait
    jsr cx_ev_get
    bcs @tick
    lda X16_P0
    cmp #EV_KEY
    beq bye
@tick
    jsr cx_ev_frames
    sec
    sbc frame0
    cmp #180                    ; three seconds at 60 Hz
    bcc wait
bye
    jmp cx_exit

; say -- A/X = string, Y = the row's low byte. Row 260 needs its ninth
; bit, which rides in on carry: the three rows used here are 200, 224
; and 260, so "Y wrapped" and "the row is past 255" are the same fact.
say
    sty X16_P2
    stz X16_P3
    cpy #200
    bcs @low                    ; 200 and 224 arrive as themselves
    lda #1                      ; 260 arrives as 4
    sta X16_P3
@low
    lda #24
    sta X16_P0
    stz X16_P1
    jmp cx_font_draw

frame0   .byte 0
s_marker .byte "HELLO ASM UP", $0D, 0
s_hello  .byte "hello from ca65, through the jump table.", 0
s_abi    .byte "the kernel says this is ABI version "
s_ver    .byte "?", 0
s_bye    .byte "a key -- or three seconds -- returns to the shell.", 0
