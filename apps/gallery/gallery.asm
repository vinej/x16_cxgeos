; ca65
; =====================================================================
; CXRF :: apps/gallery/gallery.asm -- the widget gallery (Phase 5b)
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
.include "asmsdk/ca65/cxrf.inc"

; widget indices, defined up here so on_widget's compares resolve
W_BTN   = 0
W_CHK1  = 1
W_CHK2  = 2
W_RAD0  = 3
W_RAD1  = 4
W_RAD2  = 5
W_SCRA  = 6                    ; the 1..10 slider
W_SCRB  = 7                    ; the 1..5 slider
W_FLD   = 8

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
    cxm_gfx_init
    cxm_gfx_clear 0

    cxm_say s_title, 24, 24

    cxm_ev_init
    cxm_menu_set bar
    cxm_wg_set widgets
    cxm_mouse_show 1            ; the arrow (sprite 1)

    jsr draw_sliders            ; the slider captions and their values

    cxm_ev_handlers handlers
    cxm_ev_mainloop

; ---------------------------------------------------------------------
; the handlers
; ---------------------------------------------------------------------
on_widget                       ; P1 = index, P2 = value
    lda X16_P1
    cmp #W_BTN
    beq @btn
    cmp #W_SCRA                 ; a slider moved: repaint its number
    beq @sa
    cmp #W_SCRB
    beq @sb
    rts
@btn                            ; the OK button: leave
    cxm_exit
@sa
    jsr set_a_pos
    lda X16_P2
    jmp showval
@sb
    jsr set_b_pos
    lda X16_P2
    jmp showval

; ---------------------------------------------------------------------
; the sliders' captions (drawn once) and their live numbers.
; ---------------------------------------------------------------------
draw_sliders
    lda #<s_fldl               ; a caption over the text field, at (40, 274)
    sta X16_T0
    lda #>s_fldl
    sta X16_T1
    lda #40
    sta X16_P0
    stz X16_P1
    lda #<274
    sta X16_P2
    lda #>274
    sta X16_P3
    lda X16_T0
    ldx X16_T1
    jsr cx_font_draw

    cxm_say s_sla, 360, 100
    cxm_say s_slb, 360, 160
    jsr set_a_pos               ; the starting numbers, from the records
    lda widgets + 1 + W_SCRA*16 + 9
    jsr showval
    jsr set_b_pos
    lda widgets + 1 + W_SCRB*16 + 9
    jmp showval

set_a_pos
    lda #<490
    sta valx
    lda #>490
    sta valx+1
    lda #100
    sta valy
    stz valy+1
    rts
set_b_pos
    lda #<490
    sta valx
    lda #>490
    sta valx+1
    lda #160
    sta valy
    stz valy+1
    rts

; showval -- A = a slider's 0-based value; draws (A+1), 1..10, at
; (valx, valy) after wiping a small patch.
showval
    clc
    adc #1
    cmp #10
    bcc @one
    lda #'1'                    ; "10", the max
    sta valbuf
    lda #'0'
    sta valbuf+1
    stz valbuf+2
    bra @draw
@one
    clc
    adc #'0'                    ; a single digit (A is 1..9 here)
    sta valbuf
    stz valbuf+1
@draw
    lda valx
    sta X16_P0
    lda valx+1
    sta X16_P1
    lda valy
    sta X16_P2
    lda valy+1
    sta X16_P3
    lda #24
    sta X16_P4
    stz X16_P5
    lda #10
    sta X16_P6
    stz X16_P7
    lda #0
    jsr cx_gfx_rect
    lda valx
    sta X16_P0
    lda valx+1
    sta X16_P1
    lda valy
    sta X16_P2
    lda valy+1
    sta X16_P3
    lda #<valbuf
    ldx #>valbuf
    jmp cx_font_draw

on_menu
    lda X16_P2
    beq @quit                  ; menu 0 (Gallery) has only "quit"
    cmp #1                      ; menu 1 = Themes
    bne @out
    lda X16_P1
    beq @day
    bra @night
@quit
    cxm_exit
@night
    cxm_theme_set theme_night
    bra @repaint
@day
    cxm_theme_set theme_day
@repaint
    jmp cx_wg_draw              ; the toolkit recolours in place
@out
    rts

on_key
    lda X16_P1                  ; the menu bar first: DOWN opens it,
    jsr cx_menu_key             ; arrows walk it, RETURN picks
    bcs @done
    lda X16_P1                  ; then the widgets: TAB moves the focus
    jsr cx_wg_key               ; frame, SPACE toggles, LEFT/RIGHT scroll
@done                           ; leaving is the "exit" button or the
    rts                         ; Gallery menu -- ESC is the app's to use

handlers                        ; NULL MOVE DOWN UP DBL KEY TIMER MENU WIDGET JOY
    .addr 0, 0, 0, 0, 0
    .addr on_key
    .addr 0
    .addr on_menu
    .addr on_widget
    .addr 0                     ; JOY: EV_COUNT (10) vectors, always

; ---------------------------------------------------------------------
; the menu tree
; ---------------------------------------------------------------------
bar
    cxm_menu_bar 2
    cxm_menu s_m0, m0_items
    cxm_menu s_m1, m1_items
m0_items
    cxm_items 1
    cxm_item s_quit
m1_items
    cxm_items 2
    cxm_item s_day
    cxm_item s_night

; ---------------------------------------------------------------------
; the widget list -- one builder per record, count computed from the span.
; The indices W_BTN..W_FLD above must match this order.
; ---------------------------------------------------------------------
widgets
    cxm_wcount widgets, widgets_end
    ;              x    y    w    h                             label
    cxm_wg_button 520, 448, 100, 24,                           s_ok    ; W_BTN, bottom-right
    cxm_wg_check   40, 100, 160, 14, 1,                        s_c1    ; W_CHK1, checked
    cxm_wg_check   40, 122, 160, 14, 0,                        s_c2    ; W_CHK2
    cxm_wg_radio   40, 160, 120, 14, 0, 1,                     s_r0    ; W_RAD0 (group 1)
    cxm_wg_radio   40, 182, 120, 14, 1, 1,                     s_r1    ; W_RAD1, selected
    cxm_wg_radio   40, 204, 120, 14, 0, 1,                     s_r2    ; W_RAD2
    cxm_wg_scroll 360, 116, 200, 16, 2, 9                              ; W_SCRA 1..10, at 3
    cxm_wg_scroll 360, 176, 200, 16, 0, 4                              ; W_SCRB 1..5,  at 1
    cxm_wg_field   40, 290, 300, 16, 24, fieldbuf                      ; W_FLD, capacity 24
widgets_end:

fieldbuf .res 25, 0           ; capacity + the null

s_marker .byte "GALLERY UP", $0D, 0
s_title  .byte "widget gallery -- Themes recolours it live; OK or ESC leaves", 0
s_m0     .byte "Gallery", 0
s_m1     .byte "Themes", 0
s_quit   .byte "quit", 0
s_day    .byte "daylight", 0
s_night  .byte "midnight", 0
s_ok     .byte "exit", 0
s_c1     .byte "wrap long lines", 0
s_c2     .byte "show the ruler", 0
s_r0     .byte "left", 0
s_r1     .byte "centre", 0
s_r2     .byte "right", 0
s_sla    .byte "slider 1-10:", 0
s_slb    .byte "slider 1-5:", 0
s_fldl   .byte "text field (TAB or click, then type):", 0
s_none   .byte 0

valbuf   .byte 0, 0, 0
valx     .word 0
valy     .word 0

theme_day
    cxm_theme_rec $0FFF, $0AAA, $0555, $0000, 0, 1, 3
theme_night
    cxm_theme_rec $0001, $0123, $0356, $0ABC, 0, 1, 3
