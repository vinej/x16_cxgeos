; ca65
; =====================================================================
; CXGEOS :: test/menutest/menutest.asm -- the menu engine, driven blind
; =====================================================================
; Runs as AUTORUN.CXA in the boot smoke. Synthetic clicks go down the
; same path a mouse's would (ev_post is the point), so the whole
; machine is exercised headless: the bar region routes the click, the
; engine crosses into bank 2, the drop-down saves the pixels it covers,
; a second click picks an item, the pixels come back, and EV_MENU
; arrives at this app's handler like any other event.
;
; The probe pixel is the save-under's witness: painted before the menu
; opens, covered by the box (asserted mid-flight), identical after.
;
; Verdicts through CHROUT: MENUTEST OK, or MENUTEST FAILED and a halt
; the smoke reads as a timeout.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

EV_MOUSE_DOWN = 2               ; ABI event numbering
EV_MENU       = 7

PROBE_X = 40                    ; inside menu 0's box-to-be, and OFF
PROBE_Y = 32                    ; its text: the items draw in ink 3,
                                ; the same colour as the witness, and a
                                ; probe under a glyph reads 3 for the
                                ; wrong reason (found the hard way)

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    lda #0
    jsr cx_gfx_clear

    lda #PROBE_X                ; the witness
    sta X16_P0
    stz X16_P1
    lda #PROBE_Y
    sta X16_P2
    stz X16_P3
    lda #3
    jsr cx_gfx_pset

    lda #PROBE_X                ; trust nothing: the witness reads back
    sta X16_P0                  ; before anything else happens
    stz X16_P1
    lda #PROBE_Y
    sta X16_P2
    stz X16_P3
    jsr cx_gfx_read
    cmp #3
    beq @probed
    lda #'P'
    jmp fail
@probed

    jsr cx_ev_init              ; events BEFORE the menu: ev_init resets
    lda #<handlers              ; the region stack the bar lives on
    ldx #>handlers
    jsr cx_ev_handlers

    lda #<bar
    ldx #>bar
    jsr cx_menu_set
    bcc @set
    lda #'A'
    jmp fail
@set
    stz X16_P0                  ; the bar's rule line at (0,11): if the
    stz X16_P1                  ; bar never drew, mn_set never really
    lda #11                     ; ran, and the region walk is moot
    sta X16_P2
    stz X16_P3
    jsr cx_gfx_read
    cmp #3
    beq @barred
    sta s_saw
    lda s_saw
    ora #'0'
    sta s_saw
    lda #'Q'
    jmp fail
@barred

    lda #EV_MOUSE_DOWN          ; a click in the bar, over "File"
    ldx #10                     ; x = 10
    ldy #5                      ; y = 5
    jsr click
    jsr drain                   ; dispatch until quiet: the queue also
                                ; holds the hook's first synthetic MOVE,
                                ; and one dispatch would eat that instead

    lda #PROBE_X                ; the witness must be under the box now
    sta X16_P0
    stz X16_P1
    lda #PROBE_Y
    sta X16_P2
    stz X16_P3
    jsr cx_gfx_read
    cmp #0                      ; the box's paper
    beq @covered
    lda RAM_BANK                ; peek the engine before judging
    pha
    lda #2
    sta RAM_BANK
    pla
    sta RAM_BANK
    ldx #0                      ; what IS on the screen: four pixels,
@pix                            ; box corner-ish, box middle, box edge,
    lda pixx,x                  ; far field
    sta X16_P0
    stz X16_P1
    lda pixy,x
    sta X16_P2
    stz X16_P3
    phx
    jsr cx_gfx_read
    plx
    ora #'0'
    sta s_hex,x
    inx
    cpx #4
    bne @pix
    lda #'B'
    jmp fail
@covered

    lda #EV_MOUSE_DOWN          ; a click on item 1, "Quit": row 1 spans
    ldx #14                     ; y 23-32
    ldy #25
    jsr click
    jsr drain                   ; the close, the EV_MENU it posts, all

    lda got_menu
    cmp #$80                    ; menu 0, marked heard
    beq @heard
    lda #'C'
    jmp fail
@heard
    lda got_item
    cmp #1
    beq @item
    lda #'D'
    jmp fail
@item

    lda #PROBE_X                ; the witness, restored to the pixel
    sta X16_P0
    stz X16_P1
    lda #PROBE_Y
    sta X16_P2
    stz X16_P3
    jsr cx_gfx_read
    cmp #3
    beq @ok
    lda #'E'
    jmp fail
@ok
    lda #<s_ok
    ldx #>s_ok
    jsr pmsg
    jmp cx_exit                 ; and the shell must come back

fail
    sta s_which                 ; the stage letter, into the verdict
    lda #<s_bad
    ldx #>s_bad
    jsr pmsg
@halt
    bra @halt

pixx .byte 9, 20, 40, 100
pixy .byte 13, 30, 32, 100

; hexput -- A as two hex digits into s_hex+X.
hexput
    pha
    lsr
    lsr
    lsr
    lsr
    jsr @dig
    sta s_hex,x
    pla
    and #$0F
    jsr @dig
    sta s_hex+1,x
    rts
@dig
    cmp #10
    bcc @num
    adc #'A'-11                 ; carry set: +10 total
    rts
@num
    adc #'0'
    rts

; drain -- dispatch until the queue is quiet. Stray MOVEs from the hook
; go wherever they go; what matters is that everything queued has been
; through the dispatcher when this returns.
drain
    jsr cx_ev_dispatch
    jsr cx_ev_count
    bne drain
    rts

; click -- A = type, X = x low, Y = y low; the rest zero. Down the real
; path via cx_ev_post.
click
    sta X16_P0
    stx X16_P2
    sty X16_P4
    stz X16_P1
    stz X16_P3
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jmp cx_ev_post

on_menu
    lda X16_P1
    sta got_item
    lda X16_P2
    ora #$80                    ; heard, even if menu 0
    sta got_menu
    rts

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

handlers
    .addr 0, 0, 0, 0, 0, 0, 0
    .addr on_menu               ; EV_MENU

got_item .byte $FF
got_menu .byte 0

; the menu tree (docs/formats.md)
bar
    .byte 2
    .addr s_file, file_items
    .addr s_edit, edit_items
file_items
    .byte 2
    .addr s_open, s_quit
edit_items
    .byte 1
    .addr s_one

s_file .byte "File", 0
s_edit .byte "Edit", 0
s_open .byte "Open", 0
s_quit .byte "Quit", 0
s_one  .byte "One", 0

s_ok  .byte "MENUTEST OK", $0D, 0
s_bad   .byte "MENUTEST FAILED "
s_which .byte "? "
s_saw   .byte "- "
s_hex   .byte "........", $0D, 0
