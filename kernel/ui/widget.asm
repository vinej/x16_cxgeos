; ca65
; =====================================================================
; CXGEOS :: kernel/ui/widget.asm -- the widget toolkit (bank 2)
; =====================================================================
; A widget is a 16-byte record the APP owns (docs/formats.md). The app
; hands the kernel a list -- a count, then the records -- and the kernel
; draws them and turns clicks on them into EV_WIDGET events. The record
; carries the widget's own state (checked, pressed, scroll position), so
; the kernel writes back into the app's memory; $0801-$7FFF is always
; mapped, so bank-2 code reaches it directly.
;
;   cx_wg_set    A/X = the list. Draws it, pushes a region over its
;                bounding box so clicks route here. One list at a time.
;   cx_wg_draw   redraw the list (after a theme change, say).
;
; A click updates the widget under it, redraws just that widget, and
; posts EV_WIDGET with the widget index in detail (P1) and its value in
; P2. A button is momentary (value 1 on click); a checkbox toggles; a
; radio lights and darkens its group-mates; a scrollbar takes the value
; the click position names. All colours come from the live theme, so the
; toolkit is themable for free.
;
; Deliberately not here yet: keyboard focus, the text field's caret, the
; list view. Those need a focus model the click widgets do not, and ride
; a later pass.
; =====================================================================

WG_BUTTON = 0
WG_CHECK  = 1
WG_RADIO  = 2
WG_SCROLL = 3                   ; horizontal, click-to-position

WG_DISABLED = $01               ; flags bit 0

; record layout, 16 bytes (stride is n<<4)
WG_TYPE  = 0
WG_FLAGS = 1
WG_X     = 2                    ; word
WG_Y     = 4                    ; word
WG_W     = 6                    ; word
WG_H     = 8                    ; byte
WG_VAL   = 9                    ; byte: check 0/1, scroll 0..max
WG_GRP   = 10                   ; byte: radio group id, or scroll max
WG_LBL   = 11                   ; word: the label string
WG_SIZE  = 16

WG_BOX   = 12                   ; the check/radio marker box, a side

; --- the resident stubs ------------------------------------------------
cx_do_wg_set
    jsr cxb_call
    .byte 2
    .addr $A000 + 8*3
cx_do_wg_draw
    jsr cxb_call
    .byte 2
    .addr $A000 + 9*3
wg_vec
    jsr cxb_call
    .byte 2
    .addr $A000 + 10*3

.segment "B2CODE"

; ---------------------------------------------------------------------
; wg_set -- A/X = the widget list. Parks it, draws it, and pushes a
; region over the bounding box of all the widgets so their clicks come
; back to wg_hit. Carry set only if the region stack is full.
; ---------------------------------------------------------------------
wg_set
    sta wg_list                 ; indirect reads go through CX_M_PTR, a
    stx wg_list+1               ; zero-page pointer -- wg_list itself is
    sta CX_M_PTR                ; bank-2 RAM and cannot be dereferenced
    stx CX_M_PTR+1
    ldy #0
    lda (CX_M_PTR),y            ; the count
    sta wg_n

    jsr wg_draw_all

    ; the bounding box, for the region: min x0/y0, max x1/y1 over the
    ; list. A widget's own click test is exact; this is just the gate.
    lda #$FF
    sta wg_bx0
    sta wg_bx0+1
    sta wg_by0
    sta wg_by0+1
    stz wg_bx1
    stz wg_bx1+1
    stz wg_by1
    stz wg_by1+1

    stz wg_i
@bb
    lda wg_i
    cmp wg_n
    bcc @bbcont                 ; the body is long: branch to it, jmp out
    jmp @bbdone
@bbcont
    jsr wg_rec                  ; CX_M_PTR = record wg_i

    ldy #WG_X                   ; min x0
    lda (CX_M_PTR),y
    sta wg_t
    iny
    lda (CX_M_PTR),y
    sta wg_t+1
    lda wg_t
    cmp wg_bx0
    lda wg_t+1
    sbc wg_bx0+1
    bcs @nx0
    lda wg_t
    sta wg_bx0
    lda wg_t+1
    sta wg_bx0+1
@nx0
    ldy #WG_Y                   ; min y0
    lda (CX_M_PTR),y
    sta wg_t2
    iny
    lda (CX_M_PTR),y
    sta wg_t2+1
    lda wg_t2
    cmp wg_by0
    lda wg_t2+1
    sbc wg_by0+1
    bcs @ny0
    lda wg_t2
    sta wg_by0
    lda wg_t2+1
    sta wg_by0+1
@ny0
    jsr wg_x1y1                 ; wg_t = x1, wg_t2 = y1 (exclusive-1)
    lda wg_bx1                  ; max x1
    cmp wg_t
    lda wg_bx1+1
    sbc wg_t+1
    bcs @nx1
    lda wg_t
    sta wg_bx1
    lda wg_t+1
    sta wg_bx1+1
@nx1
    lda wg_by1                  ; max y1
    cmp wg_t2
    lda wg_by1+1
    sbc wg_t2+1
    bcs @ny1
    lda wg_t2
    sta wg_by1
    lda wg_t2+1
    sta wg_by1+1
@ny1
    inc wg_i
    jmp @bb                     ; the body is over a page: far loop-back
@bbdone

    lda wg_bx0
    sta X16_P0
    lda wg_bx0+1
    sta X16_P1
    lda wg_by0
    sta X16_P2
    lda wg_by0+1
    sta X16_P3
    lda wg_bx1
    sta X16_P4
    lda wg_bx1+1
    sta X16_P5
    lda wg_by1
    sta X16_P6
    lda wg_by1+1
    sta X16_P7
    lda #<wg_vec
    ldx #>wg_vec
    jmp rg_push

; ---------------------------------------------------------------------
; wg_draw -- the ABI redraw entry.
; ---------------------------------------------------------------------
wg_draw
    jmp wg_draw_all

wg_draw_all
    stz wg_i
@loop
    lda wg_i
    cmp wg_n
    bcs @done
    jsr wg_rec
    jsr wg_paint
    inc wg_i
    bra @loop
@done
    rts

; ---------------------------------------------------------------------
; wg_rec -- CX_M_PTR = record wg_i: list + 1 + i*16.
; ---------------------------------------------------------------------
wg_rec
    lda wg_i                    ; i*16, i < 16 so it fits a byte
    asl
    asl
    asl
    asl
    sec                         ; +1 for the count byte
    adc wg_list
    sta CX_M_PTR
    lda wg_list+1
    adc #0
    sta CX_M_PTR+1
    rts

; ---------------------------------------------------------------------
; wg_x1y1 -- from the record at CX_M_PTR: wg_t = x + w - 1, wg_t2 = y +
; h - 1. The inclusive far corner, for the bounding box and hit test.
; ---------------------------------------------------------------------
wg_x1y1
    clc
    ldy #WG_X
    lda (CX_M_PTR),y
    ldy #WG_W
    adc (CX_M_PTR),y
    sta wg_t
    ldy #WG_X+1
    lda (CX_M_PTR),y
    ldy #WG_W+1
    adc (CX_M_PTR),y
    sta wg_t+1
    lda wg_t                    ; -1
    bne @xnz
    dec wg_t+1
@xnz
    dec wg_t
    clc
    ldy #WG_Y
    lda (CX_M_PTR),y
    ldy #WG_H
    adc (CX_M_PTR),y
    sta wg_t2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta wg_t2+1
    lda wg_t2
    bne @ynz
    dec wg_t2+1
@ynz
    dec wg_t2
    rts

; =====================================================================
; painting -- one widget, from its record at CX_M_PTR
; =====================================================================
wg_paint
    ldy #WG_TYPE
    lda (CX_M_PTR),y
    cmp #WG_BUTTON              ; the painters are pages apart: jmp, not
    bne @nb                     ; branch, to reach them
    jmp wg_p_button
@nb
    cmp #WG_SCROLL
    bne @nt
    jmp wg_p_scroll
@nt
    jmp wg_p_toggle             ; check and radio share a box and a label

; a push button: a framed box, its label centred, filled with the
; highlight when pressed (WG_VAL != 0).
wg_p_button
    jsr wg_load_box             ; P0..P7 = x,y,w,h
    ldy #WG_VAL
    lda (CX_M_PTR),y
    beq @paper
    lda th_hi
    bra @fill
@paper
    lda th_paper
@fill
    jsr gfx2_rect
    jsr wg_load_box
    lda th_frame
    jsr gfx2_frame
    ; the label, roughly centred: x + (w - width)/2, y + (h-8)/2
    jsr wg_label_ptr            ; X16_T0 = label
    lda X16_T0
    ldx X16_T0+1
    jsr font_measure            ; P0/P1 = text width
    ldy #WG_W                   ; (w - tw)/2
    lda (CX_M_PTR),y
    sec
    sbc X16_P0
    ldy #WG_W+1
    lda (CX_M_PTR),y
    sbc X16_P1
    ; A:carry now high byte; assume small -- take (w-tw) in wg_t
    sta wg_t+1
    lda (CX_M_PTR),y            ; recompute low cleanly
    ldy #WG_W
    lda (CX_M_PTR),y
    sec
    sbc X16_P0
    sta wg_t
    lsr wg_t+1                  ; /2
    ror wg_t
    clc                         ; + x
    ldy #WG_X
    lda (CX_M_PTR),y
    adc wg_t
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc wg_t+1
    sta X16_P1
    ldy #WG_Y                   ; y + (h-8)/2, h is small so approx +2
    lda (CX_M_PTR),y
    clc
    adc #2
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P3
    lda X16_T0
    ldx X16_T0+1
    jmp font_draw

; a checkbox / radio: a small marker box on the left, then the label.
; checked = the box filled with the frame colour.
wg_p_toggle
    ldy #WG_X                   ; the marker box: x, y, WG_BOX square
    lda (CX_M_PTR),y
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    sta X16_P1
    ldy #WG_Y
    lda (CX_M_PTR),y
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    sta X16_P3
    lda #WG_BOX
    sta X16_P4
    stz X16_P5
    lda #WG_BOX
    sta X16_P6
    stz X16_P7
    lda th_paper                ; clear it
    jsr gfx2_rect
    jsr wg_toggle_box
    lda th_frame
    jsr gfx2_frame
    ldy #WG_VAL                 ; checked: an inner filled square
    lda (CX_M_PTR),y
    beq @label
    ldy #WG_X
    lda (CX_M_PTR),y
    clc
    adc #3
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P1
    ldy #WG_Y
    lda (CX_M_PTR),y
    clc
    adc #3
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P3
    lda #WG_BOX-6
    sta X16_P4
    stz X16_P5
    lda #WG_BOX-6
    sta X16_P6
    stz X16_P7
    lda th_frame
    jsr gfx2_rect
@label
    ldy #WG_X                   ; the label, WG_BOX+6 to the right
    lda (CX_M_PTR),y
    clc
    adc #WG_BOX+6
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P1
    ldy #WG_Y
    lda (CX_M_PTR),y
    clc
    adc #2
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P3
    jsr wg_label_ptr
    lda X16_T0
    ldx X16_T0+1
    jmp font_draw

; a horizontal scrollbar: a framed trough, and a thumb whose left edge
; is val/max across the inner width. A short fixed thumb width.
WG_THUMB = 16
wg_p_scroll
    jsr wg_load_box             ; the trough
    lda th_paper
    jsr gfx2_rect
    jsr wg_load_box
    lda th_frame
    jsr gfx2_frame
    jsr wg_thumb_x              ; X16_P0/P1 = the thumb's left
    ldy #WG_Y
    lda (CX_M_PTR),y
    clc
    adc #2
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P3
    lda #WG_THUMB
    sta X16_P4
    stz X16_P5
    ldy #WG_H
    lda (CX_M_PTR),y
    sec
    sbc #4
    sta X16_P6
    stz X16_P7
    lda th_hi
    jsr gfx2_rect
    rts

; ---------------------------------------------------------------------
; wg_thumb_x -- X16_P0/P1 = the scrollbar thumb's left x:
;   x + 2 + (val * (innerw - thumb)) / max
; innerw = w - 4. Kept 8-bit where it can be: val and max are bytes.
; ---------------------------------------------------------------------
wg_thumb_x
    ldy #WG_W                   ; innerw - thumb = w - 4 - THUMB
    lda (CX_M_PTR),y
    sec
    sbc #(4 + WG_THUMB)
    sta wg_t
    ldy #WG_W+1
    lda (CX_M_PTR),y
    sbc #0
    sta wg_t+1                  ; span in wg_t (16-bit)

    ldy #WG_VAL                 ; val * span, 8x16 -> keep 16
    lda (CX_M_PTR),y
    sta wg_mul
    stz wg_res
    stz wg_res+1
    ldx #8
@m
    lsr wg_mul
    bcc @m2
    clc
    lda wg_res
    adc wg_t
    sta wg_res
    lda wg_res+1
    adc wg_t+1
    sta wg_res+1
@m2
    asl wg_t
    rol wg_t+1
    dex
    bne @m
    ; divide by max (WG_GRP), a byte, via repeated subtract on the high
    ; part -- max <= 255 and the product <= span*255, so do a simple
    ; 16/8 restoring divide
    ldy #WG_GRP
    lda (CX_M_PTR),y
    sta wg_div
    beq @zero                   ; max 0: pin the thumb left
    jsr wg_div16
    ; wg_res = quotient
    clc
    ldy #WG_X
    lda (CX_M_PTR),y
    adc #2
    adc wg_res
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc #0
    adc wg_res+1
    sta X16_P1
    rts
@zero
    ldy #WG_X
    lda (CX_M_PTR),y
    clc
    adc #2
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P1
    rts

; wg_div16 -- wg_res (16) / wg_div (8) -> wg_res, remainder discarded.
wg_div16
    lda #0
    sta wg_rem
    ldx #16
@d
    asl wg_res
    rol wg_res+1
    rol wg_rem
    lda wg_rem
    cmp wg_div
    bcc @d2
    sbc wg_div
    sta wg_rem
    inc wg_res
@d2
    dex
    bne @d
    rts

; ---------------------------------------------------------------------
; helpers to load a record's box into the parameter block
; ---------------------------------------------------------------------
wg_load_box                     ; P0..P7 = x, y, w, h (h high byte 0)
    ldy #WG_X
    lda (CX_M_PTR),y
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    sta X16_P1
    ldy #WG_Y
    lda (CX_M_PTR),y
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    sta X16_P3
    ldy #WG_W
    lda (CX_M_PTR),y
    sta X16_P4
    ldy #WG_W+1
    lda (CX_M_PTR),y
    sta X16_P5
    ldy #WG_H
    lda (CX_M_PTR),y
    sta X16_P6
    stz X16_P7
    rts

wg_toggle_box                   ; P0..P7 = the WG_BOX marker square
    ldy #WG_X
    lda (CX_M_PTR),y
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    sta X16_P1
    ldy #WG_Y
    lda (CX_M_PTR),y
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    sta X16_P3
    lda #WG_BOX
    sta X16_P4
    stz X16_P5
    lda #WG_BOX
    sta X16_P6
    stz X16_P7
    rts

wg_label_ptr                    ; X16_T0 = the record's label pointer
    ldy #WG_LBL
    lda (CX_M_PTR),y
    sta X16_T0
    ldy #WG_LBL+1
    lda (CX_M_PTR),y
    sta X16_T0+1
    rts

; =====================================================================
; hitting -- wg_vec's handler. A DOWN inside a widget acts on it.
; =====================================================================
wg_hit
    lda X16_P0
    cmp #EV_MOUSE_DOWN
    beq @press
    rts
@press
    ; which widget? walk the list, first whose box contains the point.
    stz wg_i
@find
    lda wg_i
    cmp wg_n
    bcs @none
    jsr wg_rec
    ldy #WG_FLAGS               ; a disabled widget is not hit
    lda (CX_M_PTR),y
    and #WG_DISABLED
    bne @next
    jsr wg_inside
    bcs @got
@next
    inc wg_i
    bra @find
@got
    jmp wg_act
@none
    rts

; wg_inside -- carry set if the event point (P2..P5) is in record
; CX_M_PTR's box.
wg_inside
    ldy #WG_X                   ; x >= wx
    lda X16_P2
    cmp (CX_M_PTR),y
    ldy #WG_X+1
    lda X16_P3
    sbc (CX_M_PTR),y
    bcc @no
    jsr wg_x1y1                 ; wg_t = x1, wg_t2 = y1
    lda wg_t                    ; x <= x1
    cmp X16_P2
    lda wg_t+1
    sbc X16_P3
    bcc @no
    ldy #WG_Y                   ; y >= wy
    lda X16_P4
    cmp (CX_M_PTR),y
    ldy #WG_Y+1
    lda X16_P5
    sbc (CX_M_PTR),y
    bcc @no
    lda wg_t2                   ; y <= y1
    cmp X16_P4
    lda wg_t2+1
    sbc X16_P5
    bcc @no
    sec
    rts
@no
    clc
    rts

; wg_act -- the widget at wg_i / CX_M_PTR was pressed. Update it,
; redraw it, and post EV_WIDGET(index, value).
wg_act
    ldy #WG_TYPE
    lda (CX_M_PTR),y
    cmp #WG_CHECK
    beq @toggle
    cmp #WG_RADIO
    beq @radio
    cmp #WG_SCROLL
    beq @scroll
    ; button: value 1, momentary; redraw pressed then released
    lda #1
    ldy #WG_VAL
    sta (CX_M_PTR),y
    jsr wg_paint
    lda #0
    ldy #WG_VAL
    sta (CX_M_PTR),y
    jsr wg_paint
    lda #1                      ; report "clicked"
    bra @post
@toggle
    ldy #WG_VAL                 ; flip 0<->1
    lda (CX_M_PTR),y
    eor #1
    sta (CX_M_PTR),y
    jsr wg_paint
    ldy #WG_VAL
    lda (CX_M_PTR),y
    bra @post
@radio
    jsr wg_radio_set            ; light this, darken the group
    lda #1
    bra @post
@scroll
    jsr wg_scroll_to            ; A = the new value
    bra @post

@post
    sta X16_P2                  ; value in P2
    lda wg_i
    sta X16_P1                  ; index in detail
    lda #EV_WIDGET
    sta X16_P0
    stz X16_P3
    stz X16_P4
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jmp ev_post

; wg_radio_set -- the radio at wg_i wins its group: it goes to 1, every
; other radio sharing its WG_GRP goes to 0, and each changed one is
; repainted. Leaves wg_i / CX_M_PTR on the winner.
wg_radio_set
    ldy #WG_GRP
    lda (CX_M_PTR),y
    sta wg_grp
    lda wg_i
    sta wg_win

    stz wg_i
@scan
    lda wg_i
    cmp wg_n
    bcs @done
    jsr wg_rec
    ldy #WG_TYPE
    lda (CX_M_PTR),y
    cmp #WG_RADIO
    bne @nxt
    ldy #WG_GRP
    lda (CX_M_PTR),y
    cmp wg_grp
    bne @nxt
    lda wg_i                    ; the winner -> 1, else -> 0
    cmp wg_win
    beq @on
    lda #0
    bra @setv
@on
    lda #1
@setv
    ldy #WG_VAL
    sta (CX_M_PTR),y
    jsr wg_paint
@nxt
    inc wg_i
    bra @scan
@done
    lda wg_win                  ; restore wg_i / CX_M_PTR to the winner
    sta wg_i
    jmp wg_rec

; wg_scroll_to -- the click x names a value: (px - x - 2) * max /
; (innerw - thumb), clamped. A = the value, also stored and redrawn.
wg_scroll_to
    sec                         ; px - (x + 2)
    lda X16_P2
    ldy #WG_X
    sbc (CX_M_PTR),y
    sta wg_t
    lda X16_P3
    ldy #WG_X+1
    sbc (CX_M_PTR),y
    sta wg_t+1
    lda wg_t                    ; - 2 more
    sec
    sbc #2
    sta wg_t
    lda wg_t+1
    sbc #0
    sta wg_t+1
    bpl @pos
    lda #0                      ; left of the trough: value 0
    bra @store
@pos
    ; value = rel * max / span, span = innerw - thumb = w - 4 - THUMB
    ldy #WG_W
    lda (CX_M_PTR),y
    sec
    sbc #(4 + WG_THUMB)
    sta wg_div
    ldy #WG_W+1
    lda (CX_M_PTR),y
    sbc #0
    bne @slow                   ; span >= 256: rare; pin to max-ish
    lda wg_div
    beq @max                    ; degenerate span
    ; rel (wg_t) * max
    ldy #WG_GRP
    lda (CX_M_PTR),y
    sta wg_mul
    lda wg_t                    ; rel is small; keep low byte
    sta wg_res
    stz wg_res+1
    ; res = rel * max
    lda #0
    sta wg_acc
    sta wg_acc+1
    ldx #8
@ml
    lsr wg_mul
    bcc @ml2
    clc
    lda wg_acc
    adc wg_res
    sta wg_acc
    lda wg_acc+1
    adc wg_res+1
    sta wg_acc+1
@ml2
    asl wg_res
    rol wg_res+1
    dex
    bne @ml
    lda wg_acc                  ; / span
    sta wg_res
    lda wg_acc+1
    sta wg_res+1
    jsr wg_div16
    lda wg_res
    ldy #WG_GRP                 ; clamp to max
    cmp (CX_M_PTR),y
    bcc @store
@max
    ldy #WG_GRP
    lda (CX_M_PTR),y
    bra @store
@slow
    ldy #WG_GRP
    lda (CX_M_PTR),y
@store
    ldy #WG_VAL
    sta (CX_M_PTR),y
    pha
    jsr wg_paint
    pla
    rts

; --- bank 2 state ------------------------------------------------------
wg_list  .word 0
wg_n     .byte 0
wg_i     .byte 0
wg_t     .word 0
wg_t2    .word 0
wg_bx0   .word 0
wg_by0   .word 0
wg_bx1   .word 0
wg_by1   .word 0
wg_grp   .byte 0
wg_win   .byte 0
wg_mul   .byte 0
wg_div   .byte 0
wg_rem   .byte 0
wg_res   .word 0
wg_acc   .word 0

.segment "CODE"
