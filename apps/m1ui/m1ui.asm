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
.include "asmsdk/ca65/cxgeos.inc"

FONTCAP   = 1024                ; the font buffer (pxl8 is 871 bytes)
nptr      = $60                 ; app zero page: the filename walker

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
    cxm_gfx_mode CX_MODE_BMP8
    cxm_gfx_clear 6                 ; a blue field (default palette)
    cxm_ink 1                   ; white ink for the widget labels (mode 1's
                                ; font honours the ink; mode 0's ignores it)

    lda #<s_pxl6                ; a 6px font -- the desktop's 8px pxl8 doubles
    ldx #>s_pxl6                ; to 16 screen px at mode 1's 2:1 scale. Set
    jsr load_font               ; IN mode 1: font_set skips the mode-0 glyph
                                ; cache there, so the desktop's font is safe

    cxm_menu_set bar
    cxm_wg_set widgets
    cxm_mouse_show 1

    cxm_ev_handlers handlers
    cxm_ev_mainloop                ; File > Form... opens the modal panel

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
    cxm_panel form              ; modal; A = 0 (OK) or 1 (Cancel)
    rts
on_widget                       ; the Close button is index 0
    lda X16_P1
    beq do_exit
    rts
show_dialog
    cxm_dlg_alert alert             ; modal; the 8bpp save-under puts it back
    rts
do_exit
    cxm_gfx_mode CX_MODE_GUI    ; back to the desktop's mode BEFORE leaving, so
                                ; the reload never crosses a mode change (which
                                ; left a stray event landing on the wrong file)
    cxm_exit                    ; the loader restores the system font for the
                                ; desktop (kernel/fs/loader.asm)

; load_font -- A/X = a NUL-terminated .CXF filename; reads it into fontbuf
; and adopts it. Silently keeps the current font if the file is missing.
load_font
    sta nptr
    stx nptr+1
    ldy #0
@len
    lda (nptr),y
    beq @got
    iny
    bne @len
@got
    phy
    lda #<fontbuf
    sta X16_P0
    lda #>fontbuf
    sta X16_P1
    lda #<FONTCAP
    sta X16_P2
    lda #>FONTCAP
    sta X16_P3
    lda nptr
    ldx nptr+1
    ply
    jsr cx_file_load
    bcs @done                   ; not there / too big -> keep the current font
    cxm_font_set fontbuf
@done
    rts

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
    cxm_menu s_view, view_items
file_items
    cxm_items 3
    cxm_item s_form
    cxm_item s_dlg
    cxm_item s_quit
view_items
    cxm_items 1
    cxm_item s_zoom
s_file .byte "File", 0
s_view .byte "View", 0
s_form .byte "Form...", 0
s_dlg  .byte "Dialog...", 0
s_quit .byte "Quit", 0
s_zoom .byte "Zoom", 0

; --- the modal form: a box of widgets with OK / Cancel (320x240) ------
form
    cxm_panel_hdr 30, 28, 260, 140, s_ftitle, form_widgets, 2  ; box + 2 buttons
    cxm_item s_fok
    cxm_item s_fcancel
form_widgets
    cxm_wcount form_widgets, form_widgets_end
    cxm_wg_check 46,  52, 180, 14, 1, s_fsound      ; enable sound, on
    cxm_wg_radio 46,  78, 150, 14, 1, 2, s_feasy    ; group 2, easy (on)
    cxm_wg_radio 46, 100, 150, 14, 0, 2, s_fhard    ; group 2, hard
form_widgets_end:
s_ftitle  .byte "Preferences", 0
s_fsound  .byte "enable sound", 0
s_feasy   .byte "easy mode", 0
s_fhard   .byte "hard mode", 0
s_fok     .byte "OK", 0
s_fcancel .byte "Cancel", 0

; --- the dialog -------------------------------------------------------
alert
    cxm_dialog 2, s_msg
    cxm_item s_no
    cxm_item s_yes
s_msg .byte "Apply these settings?", 0
s_no  .byte "no", 0
s_yes .byte "yes", 0

; --- the widgets: one of every type, 16 bytes each --------------------
widgets
    cxm_wcount widgets, widgets_end
    cxm_wg_button 220, 208,  84, 20, s_close        ; Close (index 0), bottom-right
    cxm_wg_check   20,  36, 160, 14, 1, s_grid      ; show grid, on
    cxm_wg_radio   20,  66, 150, 14, 1, 1, s_small  ; group 1, small (on)
    cxm_wg_radio   20,  84, 150, 14, 0, 1, s_large  ; group 1, large
    cxm_wg_scroll  20, 112, 160, 14, 3, 9           ; slider 0..9, at 3
    cxm_wg_field   20, 140, 180, 14, 20, fieldbuf   ; edit field, capacity 20
    cxm_wg_list   195,  36, 115, 44, 4, listitems   ; list, 4 rows, row 0 selected
widgets_end:

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
s_pxl6  .byte "PXL6.CXF", 0
fontbuf .res FONTCAP, 0
