; ca65
; =====================================================================
; CXGEOS :: test/canary/canary.asm -- the ABI freeze test
; =====================================================================
; This app was built ONCE, from the sdk/ of the day the ABI shipped,
; and the binary -- test/canary/CANARY.CXA -- is committed. The boot
; smoke test runs that committed binary against every freshly built
; kernel: if a slot ever moves, is reordered, or changes its contract,
; the canary is the app from the past that breaks, before any app from
; the wild does.
;
; DO NOT REBUILD IT casually. Rebuilding regenerates it from the
; current sdk/, which erases exactly the history it exists to hold. The
; binary is rebuilt only when the ABI version legitimately advances,
; and that rebuild is a release act, noted in the commit.
;
; It touches every subsystem the table exposes: version, gfx, font,
; dirty rects, events, and -- by being launched at all -- the loader.
; Verdicts go through CHROUT for the -echo harness: CANARY OK, or
; CANARY FAILED and a dead stop, which the smoke test reads as a
; timeout and a red build.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

EV_KEY = 5

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    jsr cx_version              ; must be at least the version this
    cmp #CX_ABI_VERSION         ; canary was built against
    bcs @vok
    jmp bad
@vok

    jsr cx_gfx_init             ; the screen
    lda #0
    jsr cx_gfx_clear
    lda #<64
    sta X16_P0
    stz X16_P1
    lda #<64
    sta X16_P2
    stz X16_P3
    lda #<100
    sta X16_P4
    stz X16_P5
    lda #<40
    sta X16_P6
    stz X16_P7
    lda #2
    jsr cx_gfx_rect

    lda #<70                    ; the font, over the rect
    sta X16_P0
    stz X16_P1
    lda #<76
    sta X16_P2
    stz X16_P3
    lda #<s_name
    ldx #>s_name
    jsr cx_font_draw

    jsr cx_dirty_reset          ; dirty rects: one in, one counted
    lda #<64
    sta X16_P0
    stz X16_P1
    lda #<64
    sta X16_P2
    stz X16_P3
    lda #<100
    sta X16_P4
    stz X16_P5
    lda #<40
    sta X16_P6
    stz X16_P7
    jsr cx_dirty_add
    jsr cx_dirty_count
    cmp #1
    bne bad

    jsr cx_ev_init              ; events: post one, get the same one
    lda #EV_KEY
    sta X16_P0
    lda #'C'
    sta X16_P1
    ldx #2
@zero
    stz X16_P0,x
    inx
    cpx #8
    bne @zero
    jsr cx_ev_post
    jsr cx_ev_get
    bcs bad
    lda X16_P0
    cmp #EV_KEY
    bne bad
    lda X16_P1
    cmp #'C'
    bne bad

    lda #<s_ok
    ldx #>s_ok
    jsr pmsg
    jmp cx_exit                 ; ...and the exit path is part of the
                                ; test: the shell must come back

bad
    lda #<s_bad
    ldx #>s_bad
    jsr pmsg
@halt
    bra @halt                   ; the smoke test reads this as timeout

pmsg
    sta $02
    stx $03
    ldy #0
@loop
    lda ($02),y
    beq @done
    jsr CHROUT
    iny
    bne @loop
@done
    rts

s_name .byte "CANARY", 0
s_ok   .byte "CANARY OK", $0D, 0
s_bad  .byte "CANARY FAILED", $0D, 0
