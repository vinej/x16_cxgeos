; ca65
; =====================================================================
; CXGEOS :: apps/m1ui/m1ui.asm -- menu + widgets in mode 1 (8bpp)
; =====================================================================
; The full toolkit in the 320x240 256-colour bitmap: a menu bar and a
; panel of widgets, drawn by the same engines that paint the desktop --
; graphical here (a bitmap), the checkboxes and buttons as boxes, sized
; from the mode-1 metrics. Keyboard or mouse; DOWN opens the menu, TAB
; moves the widget focus, SPACE toggles, the Close button or ESC quits.
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
    lda #1                      ; CX_MODE_BMP8
    jsr cx_gfx_mode
    lda #6                      ; a blue field (default palette)
    jsr cx_gfx_clear
    lda #1                      ; white ink for the widget labels (mode 1's
    jsr cx_ink                  ; font honours the ink; mode 0's ignores it)

    lda #<bar
    ldx #>bar
    jsr cx_menu_set
    lda #<widgets
    ldx #>widgets
    jsr cx_wg_set
    lda #1
    jsr cx_mouse_show

    lda #<handlers
    ldx #>handlers
    jsr cx_ev_handlers
    jsr show_form               ; greet with the modal form; File > Form...
    jmp cx_ev_mainloop

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
    jsr cx_panel                ; modal; A = 0 (OK) or 1 (Cancel)
    rts
on_widget                       ; the Close button is index 0
    lda X16_P1
    beq do_exit
    rts
show_dialog
    lda #<alert
    ldx #>alert
    jsr cx_dlg_alert            ; modal; the 8bpp save-under puts it back
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
    .addr s_view, view_items
file_items
    .byte 3
    .addr s_form, s_dlg, s_quit
view_items
    .byte 1
    .addr s_zoom
s_file .byte "File", 0
s_view .byte "View", 0
s_form .byte "Form...", 0
s_dlg  .byte "Dialog...", 0
s_quit .byte "Quit", 0
s_zoom .byte "Zoom", 0

; --- the modal form: a box of widgets with OK / Cancel (320x240) ------
form
    .word 30, 28, 260          ; box x, y, w (pixels)
    .byte 140                  ; box h (fits the mode-1 save-under strip)
    .addr s_ftitle
    .addr form_widgets
    .byte 2
    .addr s_fok, s_fcancel
form_widgets
    .byte 3
    .byte WG_CHECK, 0
    .word 46, 52, 180
    .byte 14, 1, 0
    .addr s_fsound
    .byte 0, 0, 0
    .byte WG_RADIO, 0          ; group 2
    .word 46, 78, 150
    .byte 14, 1, 2
    .addr s_feasy
    .byte 0, 0, 0
    .byte WG_RADIO, 0
    .word 46, 100, 150
    .byte 14, 0, 2
    .addr s_fhard
    .byte 0, 0, 0
s_ftitle  .byte "Preferences", 0
s_fsound  .byte "enable sound", 0
s_feasy   .byte "easy mode", 0
s_fhard   .byte "hard mode", 0
s_fok     .byte "OK", 0
s_fcancel .byte "Cancel", 0

; --- the dialog -------------------------------------------------------
alert
    .byte 2
    .addr s_msg
    .addr s_no, s_yes
s_msg .byte "Apply these settings?", 0
s_no  .byte "no", 0
s_yes .byte "yes", 0

; --- the widgets: one of every type, 16 bytes each --------------------
widgets
    .byte 7
    ; the Close button (index 0), bottom-right
    .byte WG_BUTTON, 0
    .word 220, 208, 84
    .byte 20, 0, 0
    .addr s_close
    .byte 0, 0, 0
    .byte WG_CHECK, 0           ; checkbox
    .word 20, 36, 160
    .byte 14, 1, 0
    .addr s_grid
    .byte 0, 0, 0
    .byte WG_RADIO, 0          ; radio group (group 1)
    .word 20, 66, 150
    .byte 14, 1, 1
    .addr s_small
    .byte 0, 0, 0
    .byte WG_RADIO, 0
    .word 20, 84, 150
    .byte 14, 0, 1
    .addr s_large
    .byte 0, 0, 0
    .byte WG_SCROLL, 0         ; slider (value 0..9, at 3)
    .word 20, 112, 160
    .byte 14, 3, 9
    .addr s_none
    .byte 0, 0, 0
    .byte WG_FIELD, 0          ; edit field (buffer, capacity 20)
    .word 20, 140, 180
    .byte 14, 0, 20
    .addr fieldbuf
    .byte 0, 0, 0
    .byte WG_LIST, 0          ; list (4 rows, row 0 selected)
    .word 195, 36, 115
    .byte 44, 0, 4
    .addr listitems
    .byte 0, 0, 0

fieldbuf  .res 21, 0
listitems .addr s_li0, s_li1, s_li2, s_li3

s_close .byte "Close", 0
s_grid  .byte "show grid", 0
s_small .byte "small icons", 0
s_large .byte "large icons", 0
s_none  .byte "", 0
s_li0   .byte "Northwind", 0
s_li1   .byte "Contoso", 0
s_li2   .byte "Fabrikam", 0
s_li3   .byte "Adventure", 0
s_up    .byte "M1UI UP", $0D, 0
