; ca65
; =====================================================================
; CXGEOS :: apps/mtext/mtext.asm -- the menu toolkit in the text TUI
; =====================================================================
; A launchable demo: switch to mode 3 (80x60 cells), set a menu bar, and
; drive it by keyboard OR mouse -- the same menu engine that paints the
; desktop paints CELLS here, laid out from the port's per-mode metrics.
; DOWN opens a menu; arrows walk it; RETURN picks; ESC (or any pick)
; returns to the desktop.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

KEY_ESC = $1B

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    ldx #0
@pr
    lda s_up,x
    beq @prd
    jsr $FFD2
    inx
    bra @pr
@prd

    jsr cx_ev_init
    lda #3                      ; CX_MODE_TEXT
    jsr cx_gfx_mode
    lda #6
    jsr cx_gfx_clear

    lda #<hint                  ; a one-line hint
    ldx #>hint
    sta X16_TPTR0
    stx X16_TPTR0+1
    lda #2
    sta X16_P0
    stz X16_P1
    lda #58
    sta X16_P2
    stz X16_P3
    lda X16_TPTR0
    ldx X16_TPTR0+1
    jsr cx_font_draw

    lda #<bar
    ldx #>bar
    jsr cx_menu_set
    lda #1
    jsr cx_mouse_show

    lda #<handlers
    ldx #>handlers
    jsr cx_ev_handlers
    jmp cx_ev_mainloop

on_key
    lda X16_P1
    cmp #KEY_ESC
    beq do_exit
    lda X16_P1
    jsr cx_menu_key
    rts
on_menu                         ; any pick returns to the desktop
do_exit
    jmp cx_exit

handlers                        ; NULL MOVE DOWN UP DBL KEY TIMER MENU WIDGET JOY
    .addr 0, 0, 0, 0, 0
    .addr on_key
    .addr 0
    .addr on_menu
    .addr 0, 0

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
hint    .byte "DOWN opens a menu, arrows walk it, RETURN picks, ESC exits", 0
s_up    .byte "MTEXT UP", $0D, 0
