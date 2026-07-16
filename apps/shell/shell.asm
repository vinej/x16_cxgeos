; ca65
; =====================================================================
; CXGEOS :: apps/shell/shell.asm -- the Phase 4 stub shell
; =====================================================================
; The first program the boot chain lands in, and deliberately the
; dumbest thing that closes the loop: draw a menu, wait for a key,
; launch what it names. Phase 6 replaces it with the resident desktop;
; the launch-and-return lifecycle it exercises is permanent.
;
; It is also the first app built ONLY from sdk/ -- everything it does
; goes through the jump table, and it must, because whatever can't is
; a hole in the ABI.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

EV_KEY = 5                      ; event types are ABI, numbered in
                                ; abi/cxgeos.abi's event section notes

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    ; The marker goes through CHROUT, which the -echo harness can see
    ; whatever the video mode shows. On real hardware it lands on the
    ; text layer nobody is displaying, and costs nothing.
    ldx #0
@mk
    lda s_marker,x
    beq @go
    jsr CHROUT
    inx
    bra @mk
@go
    jsr cx_gfx_init
    lda #0
    jsr cx_gfx_clear

    ; the frame, then the menu
    lda #<8
    sta X16_P0
    stz X16_P1
    lda #<8
    sta X16_P2
    stz X16_P3
    lda #<624
    sta X16_P4
    lda #>624
    sta X16_P5
    lda #<464
    sta X16_P6
    lda #>464
    sta X16_P7
    lda #3
    jsr cx_gfx_frame

    lda #<s_title
    ldx #>s_title
    ldy #24
    jsr say
    lda #<s_one
    ldx #>s_one
    ldy #64
    jsr say
    lda #<s_two
    ldx #>s_two
    ldy #84
    jsr say

    jsr cx_ev_init
    lda #<handlers
    ldx #>handlers
    jsr cx_ev_handlers
    jmp cx_ev_mainloop

; ---------------------------------------------------------------------
; say -- A/X = string, Y = the row. Column 24, because a stub shell
; needs exactly one margin.
; ---------------------------------------------------------------------
say
    sty X16_P2
    stz X16_P3
    ldy #24
    sty X16_P0
    stz X16_P1
    jmp cx_font_draw

on_key
    lda X16_P1
    cmp #'1'
    beq @one
    cmp #'2'
    beq @two
    rts
@one
    lda #<s_h1
    ldx #>s_h1
    ldy #s_h1_len
    jsr cx_app_load             ; returns only on failure
    bra @sorry
@two
    lda #<s_h2
    ldx #>s_h2
    ldy #s_h2_len
    jsr cx_app_load
@sorry
    lda #<s_missing
    ldx #>s_missing
    ldy #124
    jmp say

handlers                        ; EV_NULL, MOVE, DOWN, UP, DBLCLICK,
    .addr 0, 0, 0, 0, 0         ; KEY, TIMER
    .addr on_key
    .addr 0

s_marker  .byte "CXGEOS SHELL", $0D, 0
s_title   .byte "CXGEOS 0.1", 0
s_one     .byte "1  hello, from assembly", 0
s_two     .byte "2  hello, from C", 0
s_missing .byte "that app is not on this disk", 0
s_h1      .byte "HELLO1.CXA"
s_h1_len = * - s_h1
s_h2      .byte "HELLO2.CXA"
s_h2_len = * - s_h2
