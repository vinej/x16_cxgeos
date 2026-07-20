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
WG_SCROLL = 3
WG_FIELD  = 4
WG_LIST   = 5
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
    jmp cx_ev_mainloop          ; File > Form... opens the modal panel

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

on_menu                         ; File (0): 0 = Form, 1 = Dialog, 2 = Quit
    lda X16_P2
    bne @done
    lda X16_P1
    beq show_form
    cmp #1
    beq show_dialog
    cmp #2
    beq do_exit
@done
    rts

show_form
    lda #<form
    ldx #>form
    jsr cx_panel                ; modal; returns A = 0 (OK) or 1 (Cancel).
    rts                         ; the widget records hold the values now

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
    .byte 3
    .addr s_form, s_dlg, s_quit
help_items
    .byte 1
    .addr s_about
s_file  .byte "File", 0
s_help  .byte "Help", 0
s_form  .byte "Form...", 0
s_dlg   .byte "Dialog...", 0
s_quit  .byte "Quit", 0
s_about .byte "About", 0

; --- the modal form: a box of widgets with OK / Cancel ----------------
; Cells, like the rest of this mode. The widgets sit inside the box; the
; panel draws the two buttons along the bottom itself.
form
    .word 12, 14, 54           ; box x, y, w (cells)
    .byte 24                   ; box h
    .addr s_ftitle
    .addr form_widgets
    .byte 2
    .addr s_fok, s_fcancel
form_widgets
    .byte 4
    .byte WG_CHECK, 0
    .word 16, 18, 30
    .byte 1, 1, 0
    .addr s_fsound
    .byte 0, 0, 0
    .byte WG_RADIO, 0          ; group 2 (its own group in this list)
    .word 16, 20, 20
    .byte 1, 1, 2
    .addr s_feasy
    .byte 0, 0, 0
    .byte WG_RADIO, 0
    .word 16, 21, 20
    .byte 1, 0, 2
    .addr s_fhard
    .byte 0, 0, 0
    .byte WG_FIELD, 0
    .word 16, 24, 34
    .byte 1, 0, 16
    .addr formbuf
    .byte 0, 0, 0
formbuf   .res 17, 0
s_ftitle  .byte "Preferences", 0
s_fsound  .byte "enable sound", 0
s_feasy   .byte "easy", 0
s_fhard   .byte "hard", 0
s_fok     .byte "OK", 0
s_fcancel .byte "Cancel", 0

; --- the widgets: one of every type, in cell coordinates -------------
widgets
    .byte 8
    .byte WG_BUTTON, 0          ; 0: Show dialog
    .word 4, 17, 15
    .byte 1, 0, 0
    .addr s_bdlg
    .byte 0, 0, 0
    .byte WG_BUTTON, 0          ; 1: Exit
    .word 22, 17, 8
    .byte 1, 0, 0
    .addr s_bexit
    .byte 0, 0, 0
    .byte WG_CHECK, 0           ; 2: checkbox
    .word 4, 4, 24
    .byte 1, 1, 0
    .addr s_wrap
    .byte 0, 0, 0
    .byte WG_RADIO, 0           ; 3: radio (group 1)
    .word 4, 6, 16
    .byte 1, 1, 1
    .addr s_left
    .byte 0, 0, 0
    .byte WG_RADIO, 0           ; 4: radio
    .word 4, 7, 16
    .byte 1, 0, 1
    .addr s_right
    .byte 0, 0, 0
    .byte WG_SCROLL, 0          ; 5: slider (value 0..9, at 3)
    .word 4, 9, 22
    .byte 1, 3, 9
    .addr s_none
    .byte 0, 0, 0
    .byte WG_FIELD, 0           ; 6: edit field (buffer, capacity 20)
    .word 4, 11, 24
    .byte 1, 0, 20
    .addr fieldbuf
    .byte 0, 0, 0
    .byte WG_LIST, 0           ; 7: list (4 rows, row 0 selected)
    .word 45, 4, 22
    .byte 6, 0, 4
    .addr listitems
    .byte 0, 0, 0

fieldbuf  .res 21, 0
listitems .addr s_li0, s_li1, s_li2, s_li3

s_bdlg  .byte "Show dialog", 0
s_bexit .byte "Exit", 0
s_wrap  .byte "wrap long lines", 0
s_left  .byte "align left", 0
s_right .byte "align right", 0
s_none  .byte "", 0
s_li0   .byte "Northwind", 0
s_li1   .byte "Contoso", 0
s_li2   .byte "Fabrikam", 0
s_li3   .byte "Adventure Works", 0

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
