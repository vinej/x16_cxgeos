; ca65
; =====================================================================
; CXRF :: apps/da_notes/notes.asm -- the notes desk accessory
; =====================================================================
; The first DA: a one-line scratchpad floating over whatever is
; running. Type into it; DEL trims; ESC hands the screen back through
; cx_da_close, and the host is exactly as it was -- that restore IS
; the demo.
;
; Assembled at $A000 (da.cfg), loaded into bank 9 by the DA manager,
; entered only through the two header vectors. Everything it calls is
; a resident ABI slot, each of which puts RAM_BANK back before
; returning -- a DA must never switch banks itself: this code IS the
; $A000 window.
;
; The note lives inside this image, so it survives while the DA stays
; loaded and vanishes when something reloads bank 9. A note that
; outlives the session wants the clipboard, and the clipboard cannot
; yet read a banked source (its copy loop maps the data banks into the
; same window this buffer sits in) -- that is written down as the
; first job of the editor milestone, not quietly worked around here.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxrf.inc"

EV_KEY = 5

.segment "LOADADDR"
    .word $A000
.segment "CODE"

    .byte "CXDA"                ; $A000: what the manager trusts
    jmp on_open                 ; $A004
    jmp on_event                ; $A007

; ---------------------------------------------------------------------
on_open
    lda #<s_title
    ldx #>s_title
    ldy #188
    jsr say
    lda #<s_help
    ldx #>s_help
    ldy #252
    jsr say
    jmp redraw

on_event
    lda X16_P0
    cmp #EV_KEY
    bne @out                    ; a click in the window: nothing yet
    lda X16_P1
    cmp #$1B                    ; ESC: give the screen back
    bne @nesc
    jmp cx_da_close
@nesc
    cmp #$14                    ; DEL trims
    beq @bs
    cmp #$08
    beq @bs
    cmp #$20                    ; printable types
    bcc @out
    cmp #$7F
    bcs @out
    ldy nlen
    cpy #NMAX
    bcs @out
    sta note,y
    iny
    lda #0
    sta note,y
    sty nlen
    bra redraw
@bs
    ldy nlen
    beq @out
    dey
    lda #0
    sta note,y
    sty nlen
    bra redraw
@out
    rts

redraw                          ; the writing line, repainted
    lda #<152
    sta X16_P0
    lda #>152
    sta X16_P1
    lda #<216
    sta X16_P2
    stz X16_P3
    lda #<336
    sta X16_P4
    lda #>336
    sta X16_P5
    lda #16
    sta X16_P6
    stz X16_P7
    lda #0
    jsr cx_gfx_rect

    lda #<note
    ldx #>note
    ldy #218
    jsr say

    inc X16_P0                  ; the caret rides the returned pen
    bne @nc
    inc X16_P1
@nc
    lda #<218
    sta X16_P2
    stz X16_P3
    lda #2
    sta X16_P4
    stz X16_P5
    lda #12
    sta X16_P6
    stz X16_P7
    lda #3
    jmp cx_gfx_rect

say                             ; A/X = string, Y = row; centred in the
                                ; window (DA_X0 140 + DA_W/2 180 = x 320)
    sta t_str
    stx t_str+1
    sty t_row
    lda t_str                   ; measure it: P0/P1 = the pixel width
    ldx t_str+1
    jsr cx_font_measure
    lsr X16_P1                  ; width / 2
    ror X16_P0
    sec                         ; x = 320 - width/2
    lda #<320
    sbc X16_P0
    sta X16_P0
    lda #>320
    sbc X16_P1
    sta X16_P1
    lda t_row
    sta X16_P2
    stz X16_P3
    lda t_str
    ldx t_str+1
    jmp cx_font_draw

t_str .word 0
t_row .byte 0

s_title .byte "notes -- a desk accessory, floating over the desktop", 0
s_help  .byte "type; DEL trims; ESC closes and the desktop is intact", 0

NMAX = 40
nlen .byte 0
note .res NMAX+1, 0
