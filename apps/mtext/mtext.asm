; ca65
; =====================================================================
; CXGEOS :: apps/mtext/mtext.asm -- the menu toolkit in the text TUI
; =====================================================================
; The mode-generic toolkit, proven: switch to mode 3 (80x60 cells), set
; a menu bar, and open the first drop-down from the keyboard. Every
; draw goes through the graphics port, so the same menu engine that
; paints pixels on the desktop paints CELLS here -- a real text-mode
; menu, laid out from the port's per-mode metrics.
;
; It holds the open menu in a loop so a screenshot can see it.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

KEY_DOWN = $11

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    ldx #0                      ; announce (the -echo stream sees this)
@pr
    lda s_up,x
    beq @prd
    jsr CHROUT
    inx
    bra @pr
@prd

    jsr cx_ev_init              ; the region stack the bar rides on
    lda #<handlers
    ldx #>handlers
    jsr cx_ev_handlers

    lda #3                      ; CX_MODE_TEXT: the 80x60 text canvas
    jsr cx_gfx_mode

    lda #6                      ; a paper to sit the menu on
    jsr cx_gfx_clear

    lda #<bar                   ; the bar, drawn in cells
    ldx #>bar
    jsr cx_menu_set

    lda #KEY_DOWN               ; open menu 0 -- the drop-down in cells
    jsr cx_menu_key

@hold
    bra @hold                   ; hold the open menu for the capture

; NULL MOVE DOWN UP DBL KEY TIMER MENU WIDGET JOY -- EV_COUNT = 10
handlers
    .addr h_rts, h_rts, h_rts, h_rts, h_rts
    .addr h_rts, h_rts, h_rts, h_rts, h_rts
h_rts
    rts

bar
    .byte 2
    .addr s_file, file_items
    .addr s_edit, edit_items
file_items
    .byte 3
    .addr s_open, s_save, s_quit
edit_items
    .byte 2
    .addr s_copy, s_paste

s_file  .byte "File", 0
s_edit  .byte "Edit", 0
s_open  .byte "Open", 0
s_save  .byte "Save", 0
s_quit  .byte "Quit", 0
s_copy  .byte "Copy", 0
s_paste .byte "Paste", 0
s_up    .byte "MTEXT UP", $0D, 0
