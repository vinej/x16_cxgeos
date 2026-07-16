; ca65
; =====================================================================
; CXGEOS :: apps/gallery/gallery.asm -- the widget gallery (Phase 5b)
; =====================================================================
; The milestone app: a button, two checkboxes, a radio group of three,
; and a scrollbar, all drawn and driven by the kernel's widget toolkit
; through the jump table. A menu with a Themes submenu proves the whole
; toolkit recolours on a theme switch. Built from sdk/ alone.
;
; Widgets report through EV_WIDGET(detail = index, P2 = value); the app
; only has to remember which index is which, which is the point -- the
; toolkit does the drawing, the hit-testing and the state.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

EV_KEY    = 5
EV_MENU   = 7
EV_WIDGET = 8

WG_BUTTON = 0
WG_CHECK  = 1
WG_RADIO  = 2
WG_SCROLL = 3

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    ldx #0
@mk
    lda s_marker,x
    beq @go
    jsr CHROUT
    inx
    bne @mk
@go
    jsr cx_gfx_init
    lda #0
    jsr cx_gfx_clear

    lda #<s_title
    ldx #>s_title
    ldy #<24
    jsr say

    jsr cx_ev_init
    lda #<bar
    ldx #>bar
    jsr cx_menu_set
    lda #<widgets
    ldx #>widgets
    jsr cx_wg_set
    lda #1                      ; the arrow (sprite 1)
    jsr cx_mouse_show

    lda #<handlers
    ldx #>handlers
    jsr cx_ev_handlers
    jmp cx_ev_mainloop

; ---------------------------------------------------------------------
say                             ; A/X = string, Y = row; column 24
    sty X16_P2
    stz X16_P3
    ldy #24
    sty X16_P0
    stz X16_P1
    jmp cx_font_draw

; ---------------------------------------------------------------------
; the handlers
; ---------------------------------------------------------------------
on_widget                       ; P1 = index, P2 = value
    lda X16_P1
    cmp #W_BTN
    beq @btn
    rts
@btn                            ; the OK button: leave
    jmp cx_exit
on_menu
    lda X16_P2                  ; menu 1 = Themes
    cmp #1
    bne @out
    lda X16_P1
    beq @day
    lda #<theme_night
    ldx #>theme_night
    jsr cx_theme_set
    bra @repaint
@day
    lda #<theme_day
    ldx #>theme_day
    jsr cx_theme_set
@repaint
    jmp cx_wg_draw              ; the toolkit recolours in place
@out
    rts

on_key
    lda X16_P1                  ; the menu bar first: DOWN opens it,
    jsr cx_menu_key             ; arrows walk it, RETURN picks
    bcs @done
    lda X16_P1
    cmp #$1B                    ; ESC exits
    bne @done
    jmp cx_exit
@done
    rts

handlers                        ; NULL MOVE DOWN UP DBL KEY TIMER MENU WIDGET
    .addr 0, 0, 0, 0, 0
    .addr on_key
    .addr 0
    .addr on_menu
    .addr on_widget

; ---------------------------------------------------------------------
; the menu tree
; ---------------------------------------------------------------------
bar
    .byte 2
    .addr s_m0, m0_items
    .addr s_m1, m1_items
m0_items
    .byte 1
    .addr s_quit
m1_items
    .byte 2
    .addr s_day
    .addr s_night

; ---------------------------------------------------------------------
; the widget list: count, then 16-byte records
;   type flags x.w y.w w.w h val grp label.w  + 3 pad
; ---------------------------------------------------------------------
W_BTN   = 0
W_CHK1  = 1
W_CHK2  = 2
W_RAD0  = 3
W_RAD1  = 4
W_RAD2  = 5
W_SCR   = 6

widgets
    .byte 7

    ; a push button "OK"
    .byte WG_BUTTON, 0
    .word 40, 60, 80
    .byte 20, 0, 0
    .addr s_ok
    .byte 0, 0, 0

    ; two checkboxes
    .byte WG_CHECK, 0
    .word 40, 100, 160
    .byte 14, 1, 0             ; starts checked
    .addr s_c1
    .byte 0, 0, 0

    .byte WG_CHECK, 0
    .word 40, 122, 160
    .byte 14, 0, 0
    .addr s_c2
    .byte 0, 0, 0

    ; a radio group (group 1), the middle one selected
    .byte WG_RADIO, 0
    .word 40, 160, 120
    .byte 14, 0, 1
    .addr s_r0
    .byte 0, 0, 0

    .byte WG_RADIO, 0
    .word 40, 182, 120
    .byte 14, 1, 1
    .addr s_r1
    .byte 0, 0, 0

    .byte WG_RADIO, 0
    .word 40, 204, 120
    .byte 14, 0, 1
    .addr s_r2
    .byte 0, 0, 0

    ; a horizontal scrollbar, 0..100, at 30
    .byte WG_SCROLL, 0
    .word 40, 250, 300
    .byte 16, 30, 100
    .addr s_none
    .byte 0, 0, 0

s_marker .byte "GALLERY UP", $0D, 0
s_title  .byte "widget gallery -- Themes recolours it live; OK or ESC leaves", 0
s_m0     .byte "Gallery", 0
s_m1     .byte "Themes", 0
s_quit   .byte "quit", 0
s_day    .byte "daylight", 0
s_night  .byte "midnight", 0
s_ok     .byte "OK", 0
s_c1     .byte "wrap long lines", 0
s_c2     .byte "show the ruler", 0
s_r0     .byte "left", 0
s_r1     .byte "centre", 0
s_r2     .byte "right", 0
s_none   .byte 0

theme_day
    .byte $FF, $0F,  $AA, $0A,  $55, $05,  $00, $00
    .byte 0, 1, 3, 0
theme_night
    .byte $01, $00,  $23, $01,  $56, $03,  $BC, $0A
    .byte 0, 1, 3, 0
