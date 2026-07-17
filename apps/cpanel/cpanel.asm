; ca65
; =====================================================================
; CXGEOS :: apps/cpanel/cpanel.asm -- the control panel (Phase 6)
; =====================================================================
; Settings that belong to the machine, not to an app: the theme, and
; the real-time clock. Two radio buttons recolour the desktop live;
; the clock shows itself once a second, and typing a new date and time
; into the five fields (year, month, day, hour, minute) and pressing
; "set clock" writes the RTC through the KERNAL. A full year (2026) or
; a two-digit one (26 -> 2026) both work; out-of-range values refuse.
;
; TAB walks the widgets, ESC leaves. No menu bar: a control panel is
; its own single page. Settings are per-session for now -- there is no
; config file yet, so the desktop wakes up in daylight.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

EV_KEY    = 5
EV_WIDGET = 8

p4ptr = $60                     ; app zero page: parse4's buffer walker

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

    lda #172                    ; a label left-aligned over each field
    sta coly
    lda #40
    sta colx
    lda #<s_yr
    ldx #>s_yr
    jsr lbl
    lda #100
    sta colx
    lda #<s_mo
    ldx #>s_mo
    jsr lbl
    lda #144
    sta colx
    lda #<s_dd
    ldx #>s_dd
    jsr lbl
    lda #188
    sta colx
    lda #<s_hh
    ldx #>s_hh
    jsr lbl
    lda #232
    sta colx
    lda #<s_mm
    ldx #>s_mm
    jsr lbl

    lda #<s_hint                ; ...and the how-to below the fields
    ldx #>s_hint
    ldy #212
    jsr text_at

    jsr CLOCK_GET_DATE_TIME     ; seed the fields with the date/time now
    lda $02                     ; year: r0L is (year-1900)
    cmp #100
    bcc @c19
    sec
    sbc #100
    ldx #'2'
    ldy #'0'
    bra @yy
@c19
    ldx #'1'
    ldy #'9'
@yy
    stx ybuf
    sty ybuf+1
    jsr two_digits
    stx ybuf+2
    sta ybuf+3
    stz ybuf+4
    lda #4
    sta wg_yy + 9

    lda $03                     ; month
    jsr two_digits
    stx obuf
    sta obuf+1
    stz obuf+2
    lda #2
    sta wg_mo + 9
    lda $04                     ; day
    jsr two_digits
    stx dbuf
    sta dbuf+1
    stz dbuf+2
    lda #2
    sta wg_dd + 9
    lda $05                     ; hours
    jsr two_digits
    stx hbuf
    sta hbuf+1
    stz hbuf+2
    lda #2
    sta wg_hh + 9
    lda $06                     ; minutes
    jsr two_digits
    stx mbuf
    sta mbuf+1
    stz mbuf+2
    lda #2
    sta wg_mm + 9

    jsr cx_ev_init
    lda #<widgets
    ldx #>widgets
    jsr cx_wg_set
    lda #1
    jsr cx_mouse_show

    lda #$09                    ; TAB three times: past the two radios to
    jsr cx_wg_key               ; the year field, so a caret shows at once
    lda #$09
    jsr cx_wg_key
    lda #$09
    jsr cx_wg_key

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

lbl                             ; A/X = string; drawn at (colx, coly)
    pha
    lda colx
    sta X16_P0
    stz X16_P1
    lda coly
    sta X16_P2
    stz X16_P3
    pla
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

    lda #<160                   ; a paper patch, then the time -- past
    sta X16_P0                  ; the "clock -- now:" label, clear of the
    lda #>160                   ; fields below
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
    lda #<160
    sta X16_P0
    lda #>160
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
    cmp #7
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
    jsr parsefields             ; carry set = out of range, refused
    bcs @bad
    lda newy                    ; write the new date/time
    sta $02
    lda newo
    sta $03
    lda newd
    sta $04
    lda newh
    sta $05
    lda newm
    sta $06
    stz $07                     ; on the minute
    stz $08
    lda #1
    sta $09                     ; a weekday, so the RTC is happy
    jsr CLOCK_SET_DATE_TIME
    lda #<s_did
    ldx #>s_did
    ldy #226
    jsr text_at
    jmp on_timer
@bad
    lda #<s_nope
    ldx #>s_nope
    ldy #226
    jmp text_at

; parsefields -- read all five clock fields into newy/newo/newd/newh/
; newm, validating each. Carry set on any bad value. newy comes back as
; (year - 1900): a full year like 2026 minus 1900, or a 2-digit year
; read as 20xx.
parsefields
    lda #<ybuf
    ldx #>ybuf
    jsr parse4                  ; newy = the entered value (0-9999)
    bcs @no
    lda newy+1
    bne @full                   ; >= 256: a full year
    lda newy
    cmp #100
    bcs @full                   ; 100-255: also a full year
    clc                         ; 0-99: a 2-digit year is 20xx
    adc #100
    sta newy
    bra @yok
@full
    sec                         ; year - 1900
    lda newy
    sbc #<1900
    tay
    lda newy+1
    sbc #>1900
    bne @no                     ; outside 1900..2155
    sty newy
@yok
    lda newy
    cmp #200                    ; 1900..2099
    bcs @no
    sta newy

    lda #<obuf                  ; month 1-12
    ldx #>obuf
    jsr parse2
    bcs @no
    beq @no
    cmp #13
    bcs @no
    sta newo
    lda #<dbuf                  ; day 1-31
    ldx #>dbuf
    jsr parse2
    bcs @no
    beq @no
    cmp #32
    bcs @no
    sta newd
    lda #<hbuf                  ; hours 0-23
    ldx #>hbuf
    jsr parse2
    bcs @no
    cmp #24
    bcs @no
    sta newh
    lda #<mbuf                  ; minutes 0-59
    ldx #>mbuf
    jsr parse2
    bcs @no
    cmp #60
    bcs @no
    sta newm
    clc
    rts
@no
    sec
    rts

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

; parse4 -- A/X = a 1-to-4 digit buffer -> newy (word) = the value,
; carry set if it holds a non-digit or is empty.
parse4
    sta p4ptr
    stx p4ptr+1
    stz newy
    stz newy+1
    ldy #0
@l
    lda (p4ptr),y
    beq @end
    jsr digit
    bcs @no
    sta p4d
    jsr mul10w                  ; newy *= 10, then += the digit
    lda newy
    clc
    adc p4d
    sta newy
    bcc @nc
    inc newy+1
@nc
    iny
    cpy #4
    bcc @l
@end
    cpy #0                      ; at least one digit
    beq @no
    clc
    rts
@no
    sec
    rts

; mul10w -- newy = newy * 10 = newy*8 + newy*2
mul10w
    lda newy                    ; p4t = newy * 2
    asl
    sta p4t
    lda newy+1
    rol
    sta p4t+1
    lda newy                    ; newy = newy * 8
    asl
    sta newy
    lda newy+1
    rol
    sta newy+1
    asl newy
    rol newy+1
    asl newy
    rol newy+1
    lda newy                    ; newy = newy*8 + newy*2
    clc
    adc p4t
    sta newy
    lda newy+1
    adc p4t+1
    sta newy+1
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
    .byte 8
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
wg_yy                           ; record 2: year field, 4 chars
    .byte 4, 0
    .word 40, 188, 52
    .byte 16, 0, 5
    .addr ybuf
    .byte 0, 0, 0
wg_mo                           ; record 3: month field
    .byte 4, 0
    .word 100, 188, 36
    .byte 16, 0, 3
    .addr obuf
    .byte 0, 0, 0
wg_dd                           ; record 4: day field
    .byte 4, 0
    .word 144, 188, 36
    .byte 16, 0, 3
    .addr dbuf
    .byte 0, 0, 0
wg_hh                           ; record 5: hours field
    .byte 4, 0
    .word 188, 188, 36
    .byte 16, 0, 3
    .addr hbuf
    .byte 0, 0, 0
wg_mm                           ; record 6: minutes field
    .byte 4, 0
    .word 232, 188, 36
    .byte 16, 0, 3
    .addr mbuf
    .byte 0, 0, 0
wg_set                          ; record 7: the button
    .byte 0, 0
    .word 284, 188, 90
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
s_clock  .byte "clock -- now:", 0
s_yr     .byte "year", 0
s_mo     .byte "mo", 0
s_dd     .byte "dd", 0
s_hh     .byte "hh", 0
s_mm     .byte "mm", 0
s_hint   .byte "TAB or click a field, then set clock", 0
s_day    .byte "daylight", 0
s_night  .byte "midnight", 0
s_set    .byte "set clock", 0
s_did    .byte "clock set.               ", 0
s_nope   .byte "out of range, not set.   ", 0
ybuf     .res 6, 0
obuf     .res 4, 0
dbuf     .res 4, 0
hbuf     .res 4, 0
mbuf     .res 4, 0
tbuf     .res 9, 0
newy     .word 0
newo     .byte 0
newd     .byte 0
newh     .byte 0
newm     .byte 0
p4d      .byte 0
p4t      .word 0
colx     .byte 0               ; lbl's column and row
coly     .byte 0
