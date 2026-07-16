; ca65 -- the minimal mouse question: enable the KERNAL mouse in plain
; text mode, poll MOUSE_GET, and print the position whenever it changes.
; If the emulator feeds the host mouse at all, sweeping the cursor over
; the window prints a trail of coordinates; if it truly does not, this
; prints "MOUSE UP 0000 0000" once and nothing more.
.include "x16.asm"

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    lda #1                      ; show the default pointer. The size must
    ldx #80                     ; be REAL: X=0 skips the max-coordinate
    ldy #60                     ; setup entirely (r49 ps2mouse.s) and the
    jsr MOUSE_CONFIG            ; pointer stays clamped to 0,0

    lda #0
    sta lastx
    sta lastx+1
    sta lasty
    sta lasty+1

    ldx #0
@hdr
    lda t_up,x
    beq @first
    jsr CHROUT
    inx
    bne @hdr
@first
    jsr show                    ; the starting 0000 0000

@poll
    ldx #$70                    ; position lands at $70-$73
    jsr MOUSE_GET
    lda $70
    cmp lastx
    bne @moved
    lda $71
    cmp lastx+1
    bne @moved
    lda $72
    cmp lasty
    bne @moved
    lda $73
    cmp lasty+1
    beq @poll
@moved
    lda $70
    sta lastx
    lda $71
    sta lastx+1
    lda $72
    sta lasty
    lda $73
    sta lasty+1
    jsr show
    bra @poll

show                            ; "xxxx yyyy" + CR from lastx/lasty
    lda lastx+1
    jsr hex
    lda lastx
    jsr hex
    lda #' '
    jsr CHROUT
    lda lasty+1
    jsr hex
    lda lasty
    jsr hex
    lda #$0D
    jmp CHROUT

hex
    pha
    lsr
    lsr
    lsr
    lsr
    jsr nib
    pla
nib
    and #$0F
    cmp #10
    bcc @d
    adc #6
@d
    adc #'0'
    jmp CHROUT

lastx .word 0
lasty .word 0
t_up  .byte "MOUSE UP ", 0
