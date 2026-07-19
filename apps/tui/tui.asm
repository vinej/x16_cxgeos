; ca65
; =====================================================================
; CXGEOS :: apps/tui/tui.asm -- the whole toolkit in the text TUI
; =====================================================================
; One demo for mode 3 (80x60 cells): a menu bar, a panel of ASCII-classic
; widgets ([X] checks, (*) radios, [buttons]), and a modal dialog you can
; raise from the "Show dialog" button or the File menu. Keyboard or
; mouse throughout -- DOWN opens the menu, TAB moves the widget focus,
; SPACE toggles, click anything. The Exit button, File>Quit, or ESC
; returns to the desktop.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

WG_BUTTON = 0
WG_CHECK  = 1
WG_RADIO  = 2
KEY_ESC   = $1B

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
    jsr paint

    lda #1
    jsr cx_mouse_show
    lda #<handlers
    ldx #>handlers
    jsr cx_ev_handlers
    jmp cx_ev_mainloop

; paint the whole screen: paper, heading, menu bar, widgets
paint
    lda #6
    jsr cx_gfx_clear
    lda #4                      ; the heading at (4,1)
    sta X16_P0
    stz X16_P1
    lda #1
    sta X16_P2
    stz X16_P3
    lda #<title
    ldx #>title
    jsr cx_font_draw
    lda #<bar
    ldx #>bar
    jsr cx_menu_set
    lda #<widgets
    ldx #>widgets
    jmp cx_wg_set

; --- handlers ---------------------------------------------------------
on_key
    lda X16_P1
    cmp #KEY_ESC
    beq do_exit
    lda X16_P1
    jsr cx_menu_key
    bcs @done
    lda X16_P1
    jsr cx_wg_key
@done
    rts

on_menu                         ; File menu (menu 0): 0 = Dialog, 1 = Quit
    lda X16_P2
    bne @done
    lda X16_P1
    beq show_dialog
    cmp #1
    beq do_exit
@done
    rts

on_widget                       ; 0 = Show dialog, 1 = Exit
    lda X16_P1
    beq show_dialog
    cmp #1
    beq do_exit
    rts

show_dialog
    lda #<alert
    ldx #>alert
    jsr cx_dlg_alert            ; modal; its save-under puts the panel back
    rts
do_exit
    jmp cx_exit

handlers                        ; NULL MOVE DOWN UP DBL KEY TIMER MENU WIDGET JOY
    .addr 0, 0, 0, 0, 0
    .addr on_key
    .addr 0
    .addr on_menu
    .addr on_widget
    .addr 0

; --- the menu bar -----------------------------------------------------
bar
    .byte 2
    .addr s_file, file_items
    .addr s_help, help_items
file_items
    .byte 2
    .addr s_dlg, s_quit
help_items
    .byte 1
    .addr s_about
s_file  .byte "File", 0
s_help  .byte "Help", 0
s_dlg   .byte "Dialog...", 0
s_quit  .byte "Quit", 0
s_about .byte "About", 0

; --- the widgets: cell coordinates ------------------------------------
widgets
    .byte 6
    .byte WG_BUTTON, 0          ; 0: Show dialog
    .word 4, 16, 15
    .byte 1, 0, 0
    .addr s_bdlg
    .byte 0, 0, 0
    .byte WG_BUTTON, 0          ; 1: Exit
    .word 22, 16, 8
    .byte 1, 0, 0
    .addr s_bexit
    .byte 0, 0, 0
    .byte WG_CHECK, 0           ; 2
    .word 4, 4, 24
    .byte 1, 1, 0
    .addr s_wrap
    .byte 0, 0, 0
    .byte WG_CHECK, 0           ; 3
    .word 4, 6, 24
    .byte 1, 0, 0
    .addr s_auto
    .byte 0, 0, 0
    .byte WG_RADIO, 0           ; 4
    .word 4, 9, 16
    .byte 1, 1, 1
    .addr s_left
    .byte 0, 0, 0
    .byte WG_RADIO, 0           ; 5
    .word 4, 11, 16
    .byte 1, 0, 1
    .addr s_right
    .byte 0, 0, 0

s_bdlg  .byte "Show dialog", 0
s_bexit .byte "Exit", 0
s_wrap  .byte "wrap long lines", 0
s_auto  .byte "autosave", 0
s_left  .byte "align left", 0
s_right .byte "align right", 0

; --- the dialog -------------------------------------------------------
alert
    .byte 2
    .addr s_msg
    .addr s_no, s_yes
s_msg .byte "Apply these settings?", 0
s_no  .byte "no", 0
s_yes .byte "yes", 0

title .byte "CXGEOS toolkit -- menu, widgets, dialog", 0
s_up  .byte "TUI UP", $0D, 0
