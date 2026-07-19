; ca65
; =====================================================================
; CXGEOS :: apps/wtext/wtext.asm -- widgets in the text TUI
; =====================================================================
; The widget toolkit through the port: in mode 3 the same widget list
; renders ASCII-classic -- [X]/[ ] checks, (*)/( ) radios, [button]s,
; [field]s -- from the record's cell coordinates, with the clicks
; hitting the same record box. Holds for a screenshot.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

WG_BUTTON = 0
WG_CHECK  = 1
WG_RADIO  = 2
WG_FIELD  = 4
WG_LIST   = 5

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
    lda #<handlers
    ldx #>handlers
    jsr cx_ev_handlers

    lda #3                      ; CX_MODE_TEXT
    jsr cx_gfx_mode
    lda #6
    jsr cx_gfx_clear

    lda #4                      ; a heading at (4,1), via cx_say
    sta X16_P0
    stz X16_P1
    lda #1
    sta X16_P2
    stz X16_P3
    lda #<title
    ldx #>title
    jsr cx_font_draw

    lda #<wlist
    ldx #>wlist
    jsr cx_wg_set

@hold
    bra @hold

handlers
    .addr h_rts, h_rts, h_rts, h_rts, h_rts
    .addr h_rts, h_rts, h_rts, h_rts, h_rts
h_rts
    rts

; --- the widget list: 5 records, 16 bytes each ------------------------
wlist
    .byte 5
w_chk1
    .byte WG_CHECK, 0
    .word 4, 4, 24
    .byte 1, 1, 0
    .word s_wrap
    .byte 0, 0, 0
w_chk2
    .byte WG_CHECK, 0
    .word 4, 6, 24
    .byte 1, 0, 0
    .word s_auto
    .byte 0, 0, 0
w_rad1
    .byte WG_RADIO, 0
    .word 4, 9, 16
    .byte 1, 1, 0
    .word s_left
    .byte 0, 0, 0
w_rad2
    .byte WG_RADIO, 0
    .word 4, 11, 16
    .byte 1, 0, 0
    .word s_right
    .byte 0, 0, 0
w_btn
    .byte WG_BUTTON, 0
    .word 4, 14, 10
    .byte 1, 0, 0
    .word s_exit
    .byte 0, 0, 0

title  .byte "Preferences", 0
s_wrap .byte "wrap long lines", 0
s_auto .byte "autosave", 0
s_left .byte "align left", 0
s_right .byte "align right", 0
s_exit .byte "exit", 0
s_up   .byte "WTEXT UP", $0D, 0
