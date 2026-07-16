; ca65
; =====================================================================
; CXGEOS :: demos/evmon.asm -- the Phase 3 milestone
; =====================================================================
; The event system with a face on it: every kind of event the kernel
; produces, shown live, rendered with the font engine and dispatched
; through the mainloop an app will use.
;
; This is the first program shaped like a CXGEOS app rather than a demo:
; a table of handlers and a call to ev_mainloop. Nothing polls, nothing
; loops waiting. The pointer is the KERNAL's hardware sprite, so it
; tracks the hand no matter what the log is doing.
;
; Fields are redrawn in place rather than scrolled. A scrolling log would
; fx_copy the whole width per line per event -- tens of KB, several
; frames -- and the queue would back up behind its own display. One rect
; and a few glyphs per event keeps the monitor honest about the thing it
; is monitoring.
;
;   .\build.ps1 -Source demos\evmon.asm -Run
;
; Move the mouse, click, double-click, type. ESC quits.
; =====================================================================

.include "x16.asm"
.include "kernel/resident/zp.inc"

X16_USE_BITMAP2 = 1
X16_USE_IRQ     = 1
X16_USE_INPUT   = 1
X16_USE_NUMBER  = 1
X16_USE_SCREEN  = 1             ; only to hand the text screen back on ESC

ROW_H      = 12
ROW0_Y     = 70
LABEL_X    = 16
VAL_X      = 130
CNT_X      = 380
FIELD_W    = 340                ; erased before each redraw

; one row per event type, in EV_* order, then two of our own
R_NULL     = 0
R_MOVE     = 1
R_DOWN     = 2
R_UP       = 3
R_DBL      = 4
R_KEY      = 5
R_TIMER    = 6
R_QUEUE    = 7
R_ROWS     = 8

STR_PTR    = $60
TMP        = $62
ROW        = $64

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    jsr gfx2_init
    lda #0
    jsr gfx2_clear

    lda #<pxl8
    ldx #>pxl8
    jsr font_set
    bcs @bail

    jsr draw_chrome

    lda VERA_DC_VIDEO           ; the KERNAL's pointer is a hardware
    ora #VERA_VIDEO_SPRITES_EN  ; sprite: it costs nothing and never
    sta VERA_DC_VIDEO           ; lags, whatever the fields are doing
    jsr mouse_show

    jsr ev_init
    lda #<handlers
    ldx #>handlers
    jsr ev_handlers
    lda #60                     ; a tick a second -- proof the clock
    jsr ev_timer                ; arrives as an event, not a poll

    jmp ev_mainloop             ; and never come back
@bail
    rts

; ---------------------------------------------------------------------
; the handlers: one per type, exactly the table ev_dispatch indexes.
; ---------------------------------------------------------------------
handlers
    .word on_null               ; EV_NULL
    .word on_move               ; EV_MOUSE_MOVE
    .word on_down               ; EV_MOUSE_DOWN
    .word on_up                 ; EV_MOUSE_UP
    .word on_dbl                ; EV_DBLCLICK
    .word on_key                ; EV_KEY
    .word on_timer              ; EV_TIMER

; Idle. An app does its background work here. This one counts, and the
; count only reaches the screen on a tick -- redrawing it every idle
; pass would be a busy loop wearing a monitor's clothes.
on_null
    inc idle
    bne @done
    inc idle+1
    bne @done
    inc idle+2
@done
    rts

on_move
    lda #R_MOVE
    jmp show_pos

on_down
    lda #R_DOWN
    jmp show_pos

on_up
    lda #R_UP
    jmp show_pos

on_dbl
    lda #R_DBL
    jmp show_pos

; A key. ESC leaves; anything else shows its code and, if it has one,
; its glyph.
on_key
    lda X16_P1
    cmp #$1B                    ; ESC
    bne @live
    jmp quit
@live
    sta key_code

    lda #R_KEY
    jsr field_start
    lda key_code
    stz TMP+1
    jsr put_dec
    lda #<t_sp
    ldx #>t_sp
    jsr put_text

    lda key_code                ; printable? show the glyph too
    cmp #$20
    bcc @count
    cmp #$7F
    bcs @count
    sta key_str
    lda #<t_quote
    ldx #>t_quote
    jsr put_text
    lda #<key_str
    ldx #>key_str
    jsr put_text
    lda #<t_quote
    ldx #>t_quote
    jsr put_text
@count
    lda #R_KEY
    jmp bump

; The clock, and the numbers that only make sense once a second.
on_timer
    lda #R_TIMER
    jsr field_start
    inc ticks
    lda ticks
    stz TMP+1
    jsr put_dec
    lda #<t_secs
    ldx #>t_secs
    jsr put_text

    lda #R_QUEUE                ; queue depth and anything it lost
    jsr field_start
    jsr ev_count
    stz TMP+1
    jsr put_dec
    lda #<t_deep
    ldx #>t_deep
    jsr put_text
    lda ev_lost
    stz TMP+1
    jsr put_dec
    lda #<t_lost
    ldx #>t_lost
    jsr put_text

    lda #R_NULL                 ; idle passes, in thousands
    jsr field_start
    lda idle+1                  ; >> 8 is close enough to a thousand for
    sta X16_P0                  ; a number that only says "not starving"
    lda idle+2
    sta X16_P1
    jsr u16_to_dec
    jsr put_text
    lda #<t_kidle
    ldx #>t_kidle
    jsr put_text

    lda #R_TIMER
    jmp bump

quit
    jsr ev_stop
    jsr mouse_hide
    lda #$80                    ; hand the text screen back to BASIC
    jsr screen_set_mode
    rts

; ---------------------------------------------------------------------
; show_pos -- A = row; print "x,y" from the record, then count it.
;
; The position comes out of the record, not from asking the mouse again:
; the log then says what the event said, even if the hand has moved on.
; ---------------------------------------------------------------------
show_pos
    pha
    jsr field_start
    lda X16_P2
    sta TMP
    lda X16_P3
    sta TMP+1
    lda X16_P4
    sta TMP+2
    lda X16_P5
    sta TMP+3

    lda TMP                     ; x: its high byte is already in TMP+1
    jsr put_dec16
    lda #<t_comma
    ldx #>t_comma
    jsr put_text
    lda TMP+3                   ; y: move its high byte into place
    sta TMP+1
    lda TMP+2
    jsr put_dec16
    pla
    jmp bump

; ---------------------------------------------------------------------
; the fields
; ---------------------------------------------------------------------

; field_start -- A = row: erase its value area and put the pen at it.
field_start
    sta ROW
    jsr row_y                   ; X16_P2/P3 = the row's y

    lda #<VAL_X                 ; erase what was there
    sta X16_P0
    lda #>VAL_X
    sta X16_P1
    lda #<FIELD_W
    sta X16_P4
    lda #>FIELD_W
    sta X16_P5
    lda #8                      ; the font's height
    sta X16_P6
    stz X16_P7
    lda #0
    jsr gfx2_rect

    lda #<VAL_X
    sta pen
    lda #>VAL_X
    sta pen+1
    rts

; put_text -- A/X = string; draw at the pen and advance it. Appending to
; a proportional line means the pen font_draw hands back IS the next x.
put_text
    sta TMP+4
    stx TMP+5
    lda pen
    sta X16_P0
    lda pen+1
    sta X16_P1
    jsr row_y
    lda TMP+4
    ldx TMP+5
    jsr font_draw
    lda X16_P0
    sta pen
    lda X16_P1
    sta pen+1
    rts

; put_dec -- A = byte (TMP+1 = 0), in decimal
put_dec
    sta X16_P0
    stz X16_P1
    jsr u16_to_dec
    jmp put_text

; put_dec16 -- A = low, TMP+1 = high
put_dec16
    sta X16_P0
    lda TMP+1
    sta X16_P1
    jsr u16_to_dec
    jmp put_text

; bump -- A = row: its counter, drawn at CNT_X
bump
    sta ROW
    tax
    inc counts_lo,x
    bne @show
    inc counts_hi,x
@show
    jsr row_y
    lda #<CNT_X
    sta X16_P0
    lda #>CNT_X
    sta X16_P1
    lda #100                    ; erase the old count
    sta X16_P4
    stz X16_P5
    lda #8
    sta X16_P6
    stz X16_P7
    lda #0
    jsr gfx2_rect

    lda #<CNT_X
    sta pen
    lda #>CNT_X
    sta pen+1
    ldx ROW
    lda counts_lo,x
    sta X16_P0
    lda counts_hi,x
    sta X16_P1
    jsr u16_to_dec
    jmp put_text

; row_y -- X16_P2/P3 = ROW's y. Preserves A.
row_y
    pha
    lda ROW
    sta TMP+6
    lda #0
    sta TMP+7
    ldx #ROW_H                  ; row * ROW_H
    stz X16_P2
    stz X16_P3
@mul
    clc
    lda X16_P2
    adc TMP+6
    sta X16_P2
    bcc @nc
    inc X16_P3
@nc
    dex
    bne @mul
    clc
    lda X16_P2
    adc #<ROW0_Y
    sta X16_P2
    lda X16_P3
    adc #>ROW0_Y
    sta X16_P3
    pla
    rts

; ---------------------------------------------------------------------
draw_chrome
    lda #FONT_BOLD
    jsr font_style
    lda #LABEL_X
    sta X16_P0
    stz X16_P1
    lda #14
    sta X16_P2
    stz X16_P3
    lda #<t_title
    ldx #>t_title
    jsr font_draw
    lda #0
    jsr font_style

    lda #LABEL_X
    sta X16_P0
    stz X16_P1
    lda #30
    sta X16_P2
    stz X16_P3
    lda #<t_help
    ldx #>t_help
    jsr font_draw

    stz X16_P0                  ; a rule under the header
    stz X16_P1
    lda #48
    sta X16_P2
    stz X16_P3
    lda #<640
    sta X16_P4
    lda #>640
    sta X16_P5
    lda #2
    sta X16_P6
    stz X16_P7
    lda #2
    jsr gfx2_rect

    stz ROW                     ; the labels, one per row
@label
    jsr row_y
    lda #LABEL_X
    sta X16_P0
    stz X16_P1
    lda ROW
    asl
    tax
    lda labels,x
    pha
    lda labels+1,x
    tax
    pla
    jsr font_draw
    inc ROW
    lda ROW
    cmp #R_ROWS
    bne @label
    rts

; ---------------------------------------------------------------------
labels
    .word t_null, t_move, t_down, t_up, t_dbl, t_key, t_tick, t_queue

t_title  .byte "CXGEOS event monitor", 0
t_help   .byte "Move the mouse, click, double-click, type. ESC quits.", 0
t_null   .byte "idle", 0
t_move   .byte "move", 0
t_down   .byte "down", 0
t_up     .byte "up", 0
t_dbl    .byte "DOUBLE", 0
t_key    .byte "key", 0
t_tick   .byte "tick", 0
t_queue  .byte "queue", 0
t_comma  .byte ",", 0
t_sp     .byte " ", 0
t_quote  .byte $22, 0
t_secs   .byte " s", 0
t_deep   .byte " deep, lost ", 0
t_lost   .byte "", 0
t_kidle  .byte " x256 passes", 0

key_code .byte 0
key_str  .byte 0, 0             ; one character, NUL-terminated
ticks    .byte 0
idle     .res 3, 0
pen      .word 0
counts_lo .res R_ROWS, 0
counts_hi .res R_ROWS, 0

pxl8
    .incbin "fonts/pxl8.cxf"

; ---------------------------------------------------------------------
.include "kernel/font/font.asm"
.include "kernel/event/event.asm"
.include "x16_code.asm"
