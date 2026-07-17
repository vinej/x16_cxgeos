; ca65
; =====================================================================
; CXGEOS :: apps/cpanel/cpanel.asm -- the control panel (Phase 6)
; =====================================================================
; Settings that belong to the machine, not to an app: the theme, and
; the real-time clock. Two radio buttons recolour the desktop live;
; the clock shows itself once a second, and typing new hours/minutes
; into the two fields and pressing "set clock" writes the RTC through
; the KERNAL -- the date is read first and written back untouched.
;
; TAB walks the widgets, ESC leaves. No menu bar: a control panel is
; its own single page. Settings are per-session for now -- there is no
; config file yet, so the desktop wakes up in daylight.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

EV_KEY    = 5
EV_WIDGET = 8

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
    ldy #16
    jsr text_at

    lda #<s_theme
    ldx #>s_theme
    ldy #70
    jsr text_at

    lda #<s_clock
    ldx #>s_clock
    ldy #150
    jsr text_at

    jsr CLOCK_GET_DATE_TIME     ; seed the fields with the time now
    lda $05                     ; r1H = hours
    jsr two_digits
    stx hbuf
    sta hbuf+1
    stz hbuf+2
    lda $06                     ; r2L = minutes
    jsr two_digits
    stx mbuf
    sta mbuf+1
    stz mbuf+2
    lda #2                      ; both fields hold two chars already
    sta wg_hh + 9
    sta wg_mm + 9

    jsr cx_ev_init
    lda #<widgets
    ldx #>widgets
    jsr cx_wg_set
    lda #1
    jsr cx_mouse_show
    lda #60
    jsr cx_ev_timer
    jsr on_timer

    lda #<handlers
    ldx #>handlers
    jsr cx_ev_handlers
    jmp cx_ev_mainloop

; ---------------------------------------------------------------------
text_at                         ; A/X = string, Y = row; column 40
    sty X16_P2
    stz X16_P3
    ldy #40
    sty X16_P0
    stz X16_P1
    jmp cx_font_draw

two_digits                      ; A = 0-59 -> X = tens char, A = units
    ldx #'0'
@tens
    cmp #10
    bcc @units
    sbc #10
    inx
    bra @tens
@units
    adc #'0'
    rts

; on_timer -- the running clock beside the fields, once a second.
on_timer
    jsr CLOCK_GET_DATE_TIME
    lda $05
    jsr two_digits
    stx tbuf
    sta tbuf+1
    lda #':'
    sta tbuf+2
    lda $06
    jsr two_digits
    stx tbuf+3
    sta tbuf+4
    lda #':'
    sta tbuf+5
    lda $07                     ; r2H = seconds
    jsr two_digits
    stx tbuf+6
    sta tbuf+7
    stz tbuf+8

    lda #<300                   ; a paper patch, then the time
    sta X16_P0
    lda #>300
    sta X16_P1
    lda #150
    sta X16_P2
    stz X16_P3
    lda #80
    sta X16_P4
    stz X16_P5
    lda #12
    sta X16_P6
    stz X16_P7
    lda #0
    jsr cx_gfx_rect
    lda #<300
    sta X16_P0
    lda #>300
    sta X16_P1
    lda #150
    sta X16_P2
    stz X16_P3
    lda #<tbuf
    ldx #>tbuf
    jmp cx_font_draw

; ---------------------------------------------------------------------
on_widget
    lda X16_P1                  ; which widget
    beq @day
    cmp #1
    beq @night
    cmp #4
    beq @set
    rts
@day
    lda #<theme_day
    ldx #>theme_day
    jsr cx_theme_set
    jmp cx_wg_draw
@night
    lda #<theme_night
    ldx #>theme_night
    jsr cx_theme_set
    jmp cx_wg_draw
@set
    ; parse the two fields; nonsense is refused with a note
    lda #<hbuf
    ldx #>hbuf
    jsr parse2
    bcs @bad
    cmp #24
    bcs @bad
    sta newh
    lda #<mbuf
    ldx #>mbuf
    jsr parse2
    bcs @bad
    cmp #60
    bcs @bad
    sta newm
    jsr CLOCK_GET_DATE_TIME     ; the date stays whatever it was
    lda newh
    sta $05                     ; r1H = hours
    lda newm
    sta $06                     ; r2L = minutes
    stz $07                     ; r2H = seconds: on the minute
    jsr CLOCK_SET_DATE_TIME
    lda #<s_did
    ldx #>s_did
    ldy #220
    jsr text_at
    jmp on_timer
@bad
    lda #<s_nope
    ldx #>s_nope
    ldy #220
    jmp text_at

; parse2 -- A/X = a one- or two-digit buffer -> A = its value, carry
; set if it is not a number.
parse2
    sta X16_T0
    stx X16_T1
    ldy #0
    lda (X16_T0),y
    jsr digit
    bcs @no
    sta X16_T2                  ; first digit
    iny
    lda (X16_T0),y
    beq @one                    ; a single digit stands alone
    jsr digit
    bcs @no
    pha
    lda X16_T2                  ; tens*10 + units
    asl
    asl
    adc X16_T2
    asl
    sta X16_T2
    pla
    clc
    adc X16_T2
    clc
    rts
@one
    lda X16_T2
    clc
    rts
@no
    sec
    rts

digit                           ; A = a char -> A = 0-9, carry if not
    sec
    sbc #'0'
    cmp #10
    bcs @no
    clc
    rts
@no
    sec
    rts

on_key
    lda X16_P1
    jsr cx_wg_key
    bcs @done
    lda X16_P1
    cmp #$1B                    ; ESC: back to the desktop
    bne @done
    jmp cx_exit
@done
    rts

handlers                        ; NULL MOVE DOWN UP DBL KEY TIMER MENU WIDGET
    .addr 0, 0, 0, 0, 0
    .addr on_key
    .addr on_timer
    .addr 0
    .addr on_widget

; ---------------------------------------------------------------------
widgets
    .byte 5
wg_day                          ; record 0: radio, group 1, selected
    .byte 2, 0
    .word 40, 90, 140
    .byte 12, 1, 1
    .addr s_day
    .byte 0, 0, 0
wg_night                        ; record 1: radio, group 1
    .byte 2, 0
    .word 40, 110, 140
    .byte 12, 0, 1
    .addr s_night
    .byte 0, 0, 0
wg_hh                           ; record 2: hours field, 2 chars
    .byte 4, 0
    .word 40, 176, 40
    .byte 16, 0, 3
    .addr hbuf
    .byte 0, 0, 0
wg_mm                           ; record 3: minutes field
    .byte 4, 0
    .word 96, 176, 40
    .byte 16, 0, 3
    .addr mbuf
    .byte 0, 0, 0
wg_set                          ; record 4: the button
    .byte 0, 0
    .word 152, 176, 90
    .byte 16, 0, 0
    .addr s_set
    .byte 0, 0, 0

theme_day
    .byte $FF, $0F,  $AA, $0A,  $55, $05,  $00, $00
    .byte 0, 1, 3, 0
theme_night
    .byte $01, $00,  $48, $02,  $56, $03,  $BC, $0A
    .byte 0, 1, 3, 0

s_marker .byte "CPANEL UP", $0D, 0
s_title  .byte "control panel -- TAB walks, ESC leaves", 0
s_theme  .byte "theme", 0
s_clock  .byte "clock  (hours, minutes, then set)", 0
s_day    .byte "daylight", 0
s_night  .byte "midnight", 0
s_set    .byte "set clock", 0
s_did    .byte "clock set.          ", 0
s_nope   .byte "that is not a time. ", 0
hbuf     .res 4, 0
mbuf     .res 4, 0
tbuf     .res 9, 0
newh     .byte 0
newm     .byte 0
