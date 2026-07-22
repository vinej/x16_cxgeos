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
.include "sdk/include_ca65/cxrf.inc"

EV_KEY    = 5
EV_MENU   = 7
EV_WIDGET = 8

WG_BUTTON = 0
WG_CHECK  = 1
WG_RADIO  = 2
WG_SCROLL = 3
WG_FIELD  = 4

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

    jsr draw_sliders            ; the slider captions and their values

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
    cmp #W_SCRA                 ; a slider moved: repaint its number
    beq @sa
    cmp #W_SCRB
    beq @sb
    rts
@btn                            ; the OK button: leave
    jmp cx_exit
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

    lda #<s_sla
    ldx #>s_sla
    ldy #100
    jsr text360
    lda #<s_slb
    ldx #>s_slb
    ldy #160
    jsr text360
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

; text360 -- A/X = string, Y = row; drawn at column 360
text360
    sta X16_T0
    stx X16_T1
    sty X16_P2
    stz X16_P3
    lda #<360
    sta X16_P0
    lda #>360
    sta X16_P1
    lda X16_T0
    ldx X16_T1
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
    jmp cx_exit
@night
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
widgets
    .byte 9

    ; the exit button, bottom-right of the screen
    .byte WG_BUTTON, 0
    .word 520, 448, 100
    .byte 24, 0, 0
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

    ; a slider valued 1..10 (WG_VAL 0..9, shown as +1), starting at 3
    .byte WG_SCROLL, 0
    .word 360, 116, 200
    .byte 16, 2, 9            ; val 2 (=3), max 9 (=10)
    .addr s_none
    .byte 0, 0, 0

    ; a slider valued 1..5, starting at 1
    .byte WG_SCROLL, 0
    .word 360, 176, 200
    .byte 16, 0, 4            ; val 0 (=1), max 4 (=5)
    .addr s_none
    .byte 0, 0, 0

    ; a text field: buffer + capacity. Tab to it, then type.
    .byte WG_FIELD, 0
    .word 40, 290, 300
    .byte 16, 0, 24            ; length 0, capacity 24
    .addr fieldbuf
    .byte 0, 0, 0

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
    .byte $FF, $0F,  $AA, $0A,  $55, $05,  $00, $00
    .byte 0, 1, 3, 0
theme_night
    .byte $01, $00,  $23, $01,  $56, $03,  $BC, $0A
    .byte 0, 1, 3, 0
