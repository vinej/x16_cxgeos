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
on_menu                         ; a Quit pick (menu 0, item 1) exits
    lda X16_P2
    bne @done
    lda X16_P1
    cmp #1
    beq do_exit
@done
    rts
on_widget                       ; the Close button is index 0
    lda X16_P1
    beq do_exit
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
    .byte 2
    .addr s_open, s_quit
view_items
    .byte 1
    .addr s_zoom
s_file .byte "File", 0
s_view .byte "View", 0
s_open .byte "Open", 0
s_quit .byte "Quit", 0
s_zoom .byte "Zoom", 0

; --- the widgets: 5 records, 16 bytes each ----------------------------
widgets
    .byte 5
    ; the Close button (index 0), bottom-right
    .byte WG_BUTTON, 0
    .word 220, 208, 84
    .byte 20, 0, 0
    .addr s_close
    .byte 0, 0, 0
    ; two checkboxes
    .byte WG_CHECK, 0
    .word 20, 40, 170
    .byte 14, 1, 0
    .addr s_grid
    .byte 0, 0, 0
    .byte WG_CHECK, 0
    .word 20, 62, 170
    .byte 14, 0, 0
    .addr s_snap
    .byte 0, 0, 0
    ; a radio group (group 1)
    .byte WG_RADIO, 0
    .word 20, 100, 150
    .byte 14, 1, 1
    .addr s_small
    .byte 0, 0, 0
    .byte WG_RADIO, 0
    .word 20, 122, 150
    .byte 14, 0, 1
    .addr s_large
    .byte 0, 0, 0

s_close .byte "Close", 0
s_grid  .byte "show grid", 0
s_snap  .byte "snap to grid", 0
s_small .byte "small icons", 0
s_large .byte "large icons", 0
s_up    .byte "M1UI UP", $0D, 0
