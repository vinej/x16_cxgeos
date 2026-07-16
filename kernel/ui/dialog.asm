; ca65
; =====================================================================
; CXGEOS :: kernel/ui/dialog.asm -- the alert dialog (bank 2)
; =====================================================================
; cx_dlg_alert is SYNCHRONOUS, the GEOS shape: the app calls it, the
; box appears, and the call does not return until a button is chosen --
; the engine runs its own ev_dispatch loop inside. That is what makes a
; dialog one line of app code instead of a state machine.
;
; While the box is up it owns the machine: a full-screen modal region
; eats the mouse, and the handler table is swapped for the engine's own
; so RETURN can stand in for button 0. Both are put back before the
; call returns, and the pixels come back from banks 8-9 through
; vrows_restore -- dialogs are too big for the VRAM strip.
;
; Geometry is fixed and documented (docs/formats.md): the box is
; 400x96, centred; buttons are 72 wide, 16 tall, right-aligned along
; the bottom, button 0 leftmost. Fixed, because a testable dialog is
; one whose button a blind test can click.
; =====================================================================

DG_X0    = 120                  ; the box: 400x96, centred
DG_W     = 400
DG_Y0    = 192
DG_H     = 96
DG_BANK  = 14                   ; save-under: banks 14-15. NOT 8: the
                                ; font cache is banks 6-8 (95 glyphs, 42
                                ; a bank), and a dialog that saved into
                                ; bank 8 ate glyphs 84-94 -- its own
                                ; message text among them. 14-15 are the
                                ; DA slots, and no DA coexists with a
                                ; modal alert.
DG_BTN_W = 72
DG_BTN_H = 16
DG_BTN_Y = DG_Y0 + DG_H - 28    ; = 260
DG_MAXB  = 3

; the slot's resident stub, and the modal region's
cx_do_dlg_alert
    jsr cxb_call
    .byte 2
    .addr $A000 + 5*3
dg_vec
    jsr cxb_call
    .byte 2
    .addr $A000 + 6*3

.segment "B2CODE"

; ---------------------------------------------------------------------
; dg_alert -- A/X = the descriptor: .byte n, .addr message, then n
; button label words (docs/formats.md). Returns A = the chosen button.
; ---------------------------------------------------------------------
dg_alert
    sta CX_M_PTR
    stx CX_M_PTR+1
    ldy #0                      ; parse: count, message, labels
    lda (CX_M_PTR),y
    cmp #DG_MAXB+1
    bcc @nok
    lda #DG_MAXB
@nok
    sta dg_n
    iny
    lda (CX_M_PTR),y
    sta dg_msg
    iny
    lda (CX_M_PTR),y
    sta dg_msg+1
    ldx #0
@labels
    cpx dg_n
    bcs @parsed
    iny
    lda (CX_M_PTR),y
    sta dg_lab,x
    iny
    lda (CX_M_PTR),y
    sta dg_lab+DG_MAXB,x
    inx
    bra @labels
@parsed

    ; the button row starts at x0+W-12 - n*80 + 8 (72 wide, 8 apart)
    lda #0
    sta dg_bx+1
    lda dg_n
    asl                         ; n*80 = n*64 + n*16
    asl
    asl
    asl
    sta dg_t                    ; n*16
    asl
    asl
    adc dg_t                    ; n*80 (n<=3: fits, carry clear)
    sta dg_t
    sec
    lda #<(DG_X0+DG_W-12+8)
    sbc dg_t
    sta dg_bx
    lda #>(DG_X0+DG_W-12+8)
    sbc #0
    sta dg_bx+1

    lda #<DG_Y0                 ; the pixels underneath, into the banks
    sta X16_P0
    stz X16_P1
    lda #DG_H
    sta X16_P2
    lda #DG_BANK
    jsr vrows_save

    ; the box
    lda #<DG_X0
    sta X16_P0
    lda #>DG_X0
    sta X16_P1
    lda #<DG_Y0
    sta X16_P2
    stz X16_P3
    lda #<DG_W
    sta X16_P4
    lda #>DG_W
    sta X16_P5
    lda #DG_H
    sta X16_P6
    stz X16_P7
    lda th_paper
    jsr gfx2_rect
    lda #<DG_X0
    sta X16_P0
    lda #>DG_X0
    sta X16_P1
    lda #<DG_Y0
    sta X16_P2
    stz X16_P3
    lda #<DG_W
    sta X16_P4
    lda #>DG_W
    sta X16_P5
    lda #DG_H
    sta X16_P6
    stz X16_P7
    lda th_frame
    jsr gfx2_frame

    lda #<(DG_X0+12)            ; the message
    sta X16_P0
    lda #>(DG_X0+12)
    sta X16_P1
    lda #<(DG_Y0+12)
    sta X16_P2
    stz X16_P3
    lda dg_msg
    ldx dg_msg+1
    jsr font_draw

    stz dg_i                    ; the buttons
@button
    lda dg_i
    cmp dg_n
    bcs @drawn
    jsr dg_btn_x                ; X16_P0/P1 = button dg_i's left edge
    lda X16_P0
    sta dg_t                    ; kept for the label
    lda X16_P1
    sta dg_t+1
    lda #<DG_BTN_Y
    sta X16_P2
    lda #>DG_BTN_Y
    sta X16_P3
    lda #DG_BTN_W
    sta X16_P4
    stz X16_P5
    lda #DG_BTN_H
    sta X16_P6
    stz X16_P7
    lda th_frame
    jsr gfx2_frame
    clc                         ; the label, inset
    lda dg_t
    adc #8
    sta X16_P0
    lda dg_t+1
    adc #0
    sta X16_P1
    lda #<(DG_BTN_Y+4)
    sta X16_P2
    lda #>(DG_BTN_Y+4)
    sta X16_P3
    ldx dg_i
    lda dg_lab,x
    pha
    lda dg_lab+DG_MAXB,x
    tax
    pla
    jsr font_draw
    inc dg_i
    bra @button
@drawn

    stz X16_P0                  ; the machine is the dialog's now
    stz X16_P1
    stz X16_P2
    stz X16_P3
    lda #<639
    sta X16_P4
    lda #>639
    sta X16_P5
    lda #<479
    sta X16_P6
    lda #>479
    sta X16_P7
    lda #<dg_vec
    ldx #>dg_vec
    jsr rg_push

    lda CX_E_HND                ; ...keys included
    sta dg_oldh
    lda CX_E_HND+1
    sta dg_oldh+1
    lda #<dg_table
    ldx #>dg_table
    jsr ev_handlers

    lda #$FF
    sta dg_done
@wait
    jsr ev_dispatch
    lda dg_done
    bmi @wait

    lda dg_oldh                 ; the machine back: handlers, region,
    ldx dg_oldh+1               ; pixels, in that order
    jsr ev_handlers
    jsr rg_pop
    lda #<DG_Y0
    sta X16_P0
    stz X16_P1
    lda #DG_H
    sta X16_P2
    lda #DG_BANK
    jsr vrows_restore

    lda dg_done
    rts

; ---------------------------------------------------------------------
; dg_btn_x -- X16_P0/P1 = the left edge of button dg_i: dg_bx + i*80.
; ---------------------------------------------------------------------
dg_btn_x
    lda dg_i
    asl
    asl
    asl
    asl
    sta dg_t2                   ; i*16
    asl
    asl
    adc dg_t2                   ; i*80
    clc
    adc dg_bx
    sta X16_P0
    lda dg_bx+1
    adc #0
    sta X16_P1
    rts

; ---------------------------------------------------------------------
; dg_hit -- the modal region's handler. A press on a button decides;
; anywhere else is ignored: an alert demands an answer.
; ---------------------------------------------------------------------
dg_hit
    lda X16_P0
    cmp #EV_MOUSE_DOWN
    bne @out
    lda X16_P5                  ; the button row lives at y 260-275:
    cmp #>DG_BTN_Y              ; high byte 1...
    bne @out
    lda X16_P4
    sec
    sbc #<DG_BTN_Y              ; ...low 4-19
    bcc @out
    cmp #DG_BTN_H
    bcs @out

    sec                         ; which button: (x - dg_bx) / 80
    lda X16_P2
    sbc dg_bx
    sta dg_t
    lda X16_P3
    sbc dg_bx+1
    bcc @out                    ; left of the row
    bne @out                    ; way right of it (diff >= 256)
    lda dg_t
    ldx #0
@div
    cmp #80
    bcc @rem
    sbc #80
    inx
    bra @div
@rem
    cmp #DG_BTN_W               ; in the gap between buttons: nothing
    bcs @out
    cpx dg_n
    bcs @out
    stx dg_done
@out
    rts

; ---------------------------------------------------------------------
; dg_key -- the swapped table's key handler: RETURN is button 0. This
; runs as a plain bank-2 address, no stub: the whole dialog loop
; executes under bank 2, so the vector is reachable as it stands.
; ---------------------------------------------------------------------
dg_key
    lda X16_P1
    cmp #$0D
    bne @out
    stz dg_done
@out
    rts

dg_table                        ; NULL..DBLCLICK ride the region; keys
    .addr 0, 0, 0, 0, 0         ; come here; TIMER and MENU are nobody's
    .addr dg_key                ; while an alert is up
    .addr 0, 0

; --- dialog state -------------------------------------------------------
dg_p    .word 0
dg_n    .byte 0
dg_msg  .word 0
dg_lab  .res DG_MAXB*2, 0       ; lows, then highs
dg_bx   .word 0                 ; button 0's left edge
dg_done .byte 0
dg_i    .byte 0
dg_t    .byte 0, 0
dg_t2   .byte 0
dg_oldh .word 0

.segment "CODE"
