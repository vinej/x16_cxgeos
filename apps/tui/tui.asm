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
.include "asmsdk/ca65/cxgeos.inc"

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

    cxm_ev_init
    cxm_gfx_mode CX_MODE_TEXT
    jsr paint

    cxm_mouse_show 1
    cxm_ev_handlers handlers
    cxm_ev_mainloop                ; File > Form... opens the modal panel

; paint the whole screen: paper, heading, menu bar, widgets
paint
    cxm_gfx_clear 6
    cxm_say title, 4, 1         ; the heading at (4,1)
    cxm_menu_set bar
    cxm_wg_set widgets
    rts

; --- handlers ---------------------------------------------------------
on_key
    lda X16_P1
    cmp #CX_K_ESC
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
    cxm_panel form              ; modal; returns A = 0 (OK) or 1 (Cancel).
    rts                         ; the widget records hold the values now

on_widget                       ; 0 = Show dialog, 1 = Exit
    lda X16_P1
    beq show_dialog
    cmp #1
    beq do_exit
    rts

show_dialog
    cxm_dlg_alert alert             ; modal; its save-under puts the panel back
    rts
do_exit
    cxm_gfx_mode CX_MODE_GUI    ; back to the desktop's mode BEFORE leaving, so
    cxm_exit                    ; the reload never crosses a mode change

handlers                        ; NULL MOVE DOWN UP DBL KEY TIMER MENU WIDGET JOY
    .addr 0, 0, 0, 0, 0
    .addr on_key
    .addr 0
    .addr on_menu
    .addr on_widget
    .addr 0

; --- the menu bar -----------------------------------------------------
bar
    cxm_menu_bar 2
    cxm_menu s_file, file_items
    cxm_menu s_help, help_items
file_items
    cxm_items 3
    cxm_item s_form
    cxm_item s_dlg
    cxm_item s_quit
help_items
    cxm_items 1
    cxm_item s_about
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
    cxm_panel_hdr 12, 14, 54, 24, s_ftitle, form_widgets, 2   ; box (cells) + 2 buttons
    cxm_item s_fok
    cxm_item s_fcancel
form_widgets
    cxm_wcount form_widgets, form_widgets_end
    cxm_wg_check 16, 18, 30, 1, 1, s_fsound     ; enable sound, on
    cxm_wg_radio 16, 20, 20, 1, 1, 2, s_feasy   ; group 2, easy (on)
    cxm_wg_radio 16, 21, 20, 1, 0, 2, s_fhard   ; group 2, hard
    cxm_wg_field 16, 24, 34, 1, 16, formbuf     ; capacity 16
form_widgets_end:
formbuf   .res 17, 0
s_ftitle  .byte "Preferences", 0
s_fsound  .byte "enable sound", 0
s_feasy   .byte "easy", 0
s_fhard   .byte "hard", 0
s_fok     .byte "OK", 0
s_fcancel .byte "Cancel", 0

; --- the widgets: one of every type, in cell coordinates -------------
widgets
    cxm_wcount widgets, widgets_end
    cxm_wg_button  4, 17, 15, 1, s_bdlg         ; 0: Show dialog
    cxm_wg_button 22, 17,  8, 1, s_bexit        ; 1: Exit
    cxm_wg_check   4,  4, 24, 1, 1, s_wrap      ; 2: checkbox, on
    cxm_wg_radio   4,  6, 16, 1, 1, 1, s_left   ; 3: radio (group 1), on
    cxm_wg_radio   4,  7, 16, 1, 0, 1, s_right  ; 4: radio (group 1)
    cxm_wg_scroll  4,  9, 22, 1, 3, 9           ; 5: slider 0..9, at 3
    cxm_wg_field   4, 11, 24, 1, 20, fieldbuf   ; 6: edit field, capacity 20
    cxm_wg_list   45,  4, 22, 6, 4, listitems   ; 7: list, 4 rows, row 0 selected
widgets_end:

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
    cxm_dialog 2, s_msg
    cxm_item s_no
    cxm_item s_yes
s_msg .byte "Apply these settings?", 0
s_no  .byte "no", 0
s_yes .byte "yes", 0

title .byte "CXGEOS toolkit -- menu, widgets, dialog", 0
s_up  .byte "TUI UP", $0D, 0
