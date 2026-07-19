; ca65
; =====================================================================
; CXGEOS :: kernel/ui/dialog.asm -- the alert and prompt dialogs (bank 2)
; =====================================================================
; cx_dlg_alert and cx_dlg_prompt are SYNCHRONOUS, the GEOS shape: the
; app calls, the box appears, and the call does not return until the
; user decides -- the engine runs its own ev_dispatch loop inside. That
; is what makes a dialog one line of app code instead of a state
; machine.
;
; While a box is up it owns the machine: a full-screen modal region
; eats the mouse, and the handler table is swapped for the engine's own
; so keys reach the dialog. Both are put back before the call returns,
; and the pixels come back from banks 14-15 through vrows_restore --
; dialogs are too big for the VRAM strip.
;
; The alert offers up to three buttons and returns the chosen one; the
; prompt adds a one-line editor above ok/cancel buttons and edits the
; caller's buffer in place -- RETURN (or ok) accepts, ESC (or cancel)
; declines with the carry.
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

DG_FLD_Y = DG_Y0 + 34           ; the prompt's field: frame at 226,
DG_FLD_W = DG_W - 24            ; 376 wide, 18 tall
DG_PMAX  = 38                   ; the editor's hard cap (the field fits it)

; the slots' resident stubs, and the modal region's
cx_do_dlg_alert
    jsr cxb_call
    .byte 2
    .addr $A000 + 5*3
dg_vec
    jsr cxb_call
    .byte 2
    .addr $A000 + 6*3
cx_do_dlg_prompt
    jsr cxb_call
    .byte 2
    .addr $A000 + 14*3

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
    jsr dg_geom
    jsr dg_boxup
    jsr dg_buttons
    lda #<dg_table
    ldx #>dg_table
    jmp dg_wait                 ; A = the chosen button

; ---------------------------------------------------------------------
; dg_prompt -- A/X = message, X16_P0/P1 = a NUL-terminated buffer (its
; content is the seed and is edited IN PLACE), X16_P2 = the buffer's
; capacity. Returns A = the final length; carry set means cancelled
; (ESC or the cancel button) -- the buffer holds whatever was typed
; either way. RETURN or the ok button accepts.
; ---------------------------------------------------------------------
dg_prompt
    sta dg_msg
    stx dg_msg+1
    lda X16_P0
    sta dg_buf
    lda X16_P1
    sta dg_buf+1
    ldx X16_P2                  ; capacity -> greatest length, capped to
    dex                         ; what the field can show
    cpx #DG_PMAX+1
    bcc @cap
    ldx #DG_PMAX
@cap
    stx dg_max

    jsr dg_bufzp                ; the seed's length, clamped and
    ldy #0                      ; re-terminated
@sl
    lda (CX_M_PTR),y
    beq @sld
    iny
    cpy dg_max
    bcc @sl
@sld
    sty dg_len
    lda #0
    sta (CX_M_PTR),y

    lda #2                      ; ok | cancel
    sta dg_n
    lda #<dg_s_ok
    sta dg_lab
    lda #>dg_s_ok
    sta dg_lab+DG_MAXB
    lda #<dg_s_cancel
    sta dg_lab+1
    lda #>dg_s_cancel
    sta dg_lab+DG_MAXB+1
    jsr dg_geom
    jsr dg_boxup
    jsr dg_buttons

    lda dg_fx                   ; the field's frame: fx, fy, fw, dgbh tall
    sta X16_P0
    lda dg_fx+1
    sta X16_P1
    lda dg_fy
    sta X16_P2
    lda dg_fy+1
    sta X16_P3
    lda dg_fw
    sta X16_P4
    lda dg_fw+1
    sta X16_P5
    lda cxov_m_dgbh
    sta X16_P6
    stz X16_P7
    lda th_frame
    jsr cxov_frame
    jsr dg_field                ; the seed text and the caret

    lda #<dg_ptable
    ldx #>dg_ptable
    jsr dg_wait                 ; 0 = ok, 1 = cancel
    cmp #1
    lda dg_len                  ; carry: set only when dg_done was >= 1
    rts

; ---------------------------------------------------------------------
; dg_geom -- dg_bx = button 0's left edge from dg_n: the row is
; right-aligned, x0+W-12 - n*80 + 8 (72 wide, 8 apart).
; ---------------------------------------------------------------------
dg_geom
    sec                         ; dg_x0 = (cur_w - dgw) >> 1  (centred)
    lda cx_cur_w
    sbc cxov_m_dgw
    sta dg_x0
    lda cx_cur_w+1
    sbc cxov_m_dgw+1
    sta dg_x0+1
    lsr dg_x0+1
    ror dg_x0
    sec                         ; dg_y0 = (cur_h - dgh) >> 1
    lda cx_cur_h
    sbc cxov_m_dgh
    sta dg_y0
    lda cx_cur_h+1
    sbc #0
    sta dg_y0+1
    lsr dg_y0+1
    ror dg_y0

    clc                         ; dg_bty = dg_y0 + dgh - dgbh - dgpad
    lda dg_y0
    adc cxov_m_dgh
    sta dg_bty
    lda dg_y0+1
    adc #0
    sta dg_bty+1
    ldx cxov_m_dgbh             ; - dgbh, then - dgpad
    jsr dg_bty_sub
    ldx cxov_m_dgpad
    jsr dg_bty_sub

    clc                         ; dg_bx = dg_x0 + dgw - dgpad - dgbw
    lda dg_x0                   ;         - (n-1)*dgbsp  (right-aligned)
    adc cxov_m_dgw
    sta dg_bx
    lda dg_x0+1
    adc cxov_m_dgw+1
    sta dg_bx+1
    ldx cxov_m_dgpad
    jsr dg_bx_sub
    ldx cxov_m_dgbw
    jsr dg_bx_sub
    ldx dg_n                    ; (n-1) times dgbsp
    dex
    beq @bxdone
@sp
    phx
    ldx cxov_m_dgbsp
    jsr dg_bx_sub
    plx
    dex
    bne @sp
@bxdone

    clc                         ; the prompt field: fx = x0 + dgpad
    lda dg_x0
    adc cxov_m_dgpad
    sta dg_fx
    lda dg_x0+1
    adc #0
    sta dg_fx+1
    clc                         ; fy = y0 + dgfldy
    lda dg_y0
    adc cxov_m_dgfldy
    sta dg_fy
    lda dg_y0+1
    adc #0
    sta dg_fy+1
    sec                         ; fw = dgw - 2*dgpad
    lda cxov_m_dgw
    sbc cxov_m_dgpad
    sta dg_fw
    lda cxov_m_dgw+1
    sbc #0
    sta dg_fw+1
    sec
    lda dg_fw
    sbc cxov_m_dgpad
    sta dg_fw
    lda dg_fw+1
    sbc #0
    sta dg_fw+1
    rts

dg_bty_sub                      ; dg_bty -= X
    sec
    txa
    sta dg_t
    lda dg_bty
    sbc dg_t
    sta dg_bty
    lda dg_bty+1
    sbc #0
    sta dg_bty+1
    rts
dg_bx_sub                       ; dg_bx -= X
    sec
    txa
    sta dg_t
    lda dg_bx
    sbc dg_t
    sta dg_bx
    lda dg_bx+1
    sbc #0
    sta dg_bx+1
    rts

; ---------------------------------------------------------------------
; dg_boxup -- save the pixels into the banks, then the box, its frame,
; and the message at +12,+12.
; ---------------------------------------------------------------------
dg_boxup
    lda dg_y0                   ; save the rows the box covers, through
    sta X16_P0                  ; the port -- mode 0 to banks 14-15, mode
    lda dg_y0+1                 ; 3 to text cells
    sta X16_P1
    lda cxov_m_dgh
    sta X16_P2
    jsr cxov_rsave

    jsr dg_box_pxy             ; the box: x0,y0,dgw,dgh
    lda cxov_m_dgw
    sta X16_P4
    lda cxov_m_dgw+1
    sta X16_P5
    lda cxov_m_dgh
    sta X16_P6
    stz X16_P7
    lda th_paper
    jsr cxov_rect
    jsr dg_box_pxy
    lda cxov_m_dgw
    sta X16_P4
    lda cxov_m_dgw+1
    sta X16_P5
    lda cxov_m_dgh
    sta X16_P6
    stz X16_P7
    lda th_frame
    jsr cxov_frame

    jsr dg_msg_at              ; the message, inset from the box corner
    lda th_paper               ; on the box paper: ink to contrast in text
    jsr mn_ink
    lda dg_msg
    ldx dg_msg+1
    jmp cxov_text

; dg_box_pxy -- P0/P1 = dg_x0, P2/P3 = dg_y0 (the box corner)
dg_box_pxy
    lda dg_x0
    sta X16_P0
    lda dg_x0+1
    sta X16_P1
    lda dg_y0
    sta X16_P2
    lda dg_y0+1
    sta X16_P3
    rts

; dg_msg_at -- P0/P1 = dg_x0+dgpad, P2/P3 = dg_y0+dgpad
dg_msg_at
    clc
    lda dg_x0
    adc cxov_m_dgpad
    sta X16_P0
    lda dg_x0+1
    adc #0
    sta X16_P1
    clc
    lda dg_y0
    adc cxov_m_dgpad
    sta X16_P2
    lda dg_y0+1
    adc #0
    sta X16_P3
    rts

; ---------------------------------------------------------------------
; dg_buttons -- frame and label buttons 0..dg_n-1 along the bottom.
; ---------------------------------------------------------------------
dg_buttons
    stz dg_i
@button
    lda dg_i
    cmp dg_n
    bcs @drawn
    jsr dg_btn_x                ; X16_P0/P1 = button dg_i's left edge
    lda X16_P0
    sta dg_t                    ; kept for the label
    lda X16_P1
    sta dg_t+1
    lda dg_bty
    sta X16_P2
    lda dg_bty+1
    sta X16_P3
    lda cxov_m_dgbw
    sta X16_P4
    stz X16_P5
    lda cxov_m_dgbh
    sta X16_P6
    stz X16_P7
    lda th_frame
    jsr cxov_frame
    clc                         ; the label: barx in, bandpad down
    lda dg_t
    adc cxov_m_barx
    sta X16_P0
    lda dg_t+1
    adc #0
    sta X16_P1
    clc
    lda dg_bty
    adc cxov_m_bandpad
    sta X16_P2
    lda dg_bty+1
    adc #0
    sta X16_P3
    lda th_paper                ; the label sits on the box paper: in
    jsr mn_ink                  ; text mode it inks to contrast (mn_ink,
    ldx dg_i                    ; shared with the menu, same bank)
    lda dg_lab,x
    pha
    lda dg_lab+DG_MAXB,x
    tax
    pla
    jsr cxov_text
    inc dg_i
    bra @button
@drawn
    rts

; ---------------------------------------------------------------------
; dg_wait -- A/X = the handler table to rule under. Pushes the modal
; region, swaps the handlers, dispatches until something sets dg_done,
; puts everything back and restores the pixels. A = dg_done.
; ---------------------------------------------------------------------
dg_wait
    sta dg_tab
    stx dg_tab+1

    stz X16_P0                  ; the machine is the dialog's now: the
    stz X16_P1                  ; whole canvas, in this mode's units
    stz X16_P2
    stz X16_P3
    lda cx_cur_w
    sec
    sbc #1
    sta X16_P4
    lda cx_cur_w+1
    sbc #0
    sta X16_P5
    lda cx_cur_h
    sec
    sbc #1
    sta X16_P6
    lda cx_cur_h+1
    sbc #0
    sta X16_P7
    lda #<dg_vec
    ldx #>dg_vec
    jsr rg_push

    lda CX_E_HND                ; ...keys included
    sta dg_oldh
    lda CX_E_HND+1
    sta dg_oldh+1
    lda dg_tab
    ldx dg_tab+1
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
    lda dg_y0                   ; the pixels (or cells) back, through the
    sta X16_P0                  ; port -- whichever mode saved them
    lda dg_y0+1
    sta X16_P1
    lda cxov_m_dgh
    sta X16_P2
    jsr cxov_rrest

    lda dg_done
    rts

; ---------------------------------------------------------------------
; dg_field -- the prompt's editor row: interior back to paper, the
; buffer's text, and a caret at the pen.
; ---------------------------------------------------------------------
dg_field
    lda dg_fx                   ; the interior back to paper: one unit in
    clc                         ; from the field frame
    adc #1
    sta X16_P0
    lda dg_fx+1
    adc #0
    sta X16_P1
    lda dg_fy
    clc
    adc #1
    sta X16_P2
    lda dg_fy+1
    adc #0
    sta X16_P3
    sec                         ; width = fw - 2 (off both frames)
    lda dg_fw
    sbc #2
    sta X16_P4
    lda dg_fw+1
    sbc #0
    sta X16_P5
    lda cxov_m_dgbh            ; height = dgbh - 2 (inside the frame)
    sec
    sbc #2
    sta X16_P6
    stz X16_P7
    lda th_paper
    jsr cxov_rect

    lda dg_fx                   ; the text: two units in, on the interior
    clc
    adc #2
    sta X16_P0
    lda dg_fx+1
    adc #0
    sta X16_P1
    lda dg_fy
    clc
    adc #1
    sta X16_P2
    lda dg_fy+1
    adc #0
    sta X16_P3
    lda th_paper                ; contrast in text mode
    jsr mn_ink
    lda dg_buf
    ldx dg_buf+1
    jsr cxov_text               ; the pen comes back in P0/P1

    inc X16_P0                  ; the caret, a cell after the text
    bne @nc
    inc X16_P1
@nc
    lda dg_fy
    clc
    adc #1
    sta X16_P2
    lda dg_fy+1
    adc #0
    sta X16_P3
    lda #1                      ; a one-unit block: a thin bar in pixels,
    sta X16_P4                  ; a full caret cell in text
    stz X16_P5
    lda cxov_m_dgbh
    sec
    sbc #2
    sta X16_P6
    stz X16_P7
    lda th_frame
    jmp cxov_rect

; ---------------------------------------------------------------------
; dg_btn_x -- X16_P0/P1 = the left edge of button dg_i: dg_bx + i*80.
; ---------------------------------------------------------------------
dg_btn_x
    lda dg_bx                   ; button 0, then + i * the button pitch
    sta X16_P0
    lda dg_bx+1
    sta X16_P1
    ldx dg_i
    beq @done
@add
    clc
    lda X16_P0
    adc cxov_m_dgbsp
    sta X16_P0
    lda X16_P1
    adc #0
    sta X16_P1
    dex
    bne @add
@done
    rts

; ---------------------------------------------------------------------
; dg_hit -- the modal region's handler. A press on a button decides;
; anywhere else is ignored: a dialog demands an answer.
; ---------------------------------------------------------------------
dg_hit
    lda X16_P0
    cmp #EV_MOUSE_DOWN
    bne @out
    sec                         ; y - dg_bty in [0, dgbh)?
    lda X16_P4
    sbc dg_bty
    sta dg_t
    lda X16_P5
    sbc dg_bty+1
    bne @out                    ; a different page: above or well below
    lda dg_t
    cmp cxov_m_dgbh
    bcs @out

    sec                         ; which button: (x - dg_bx) / dgbsp
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
    cmp cxov_m_dgbsp
    bcc @rem
    sbc cxov_m_dgbsp            ; carry set from cmp
    inx
    bra @div
@rem
    cmp cxov_m_dgbw             ; in the gap between buttons: nothing
    bcs @out
    cpx dg_n
    bcs @out
    stx dg_done
@out
    rts

; ---------------------------------------------------------------------
; dg_key -- the alert's key handler: RETURN is button 0. This runs as
; a plain bank-2 address, no stub: the whole dialog loop executes under
; bank 2, so the vector is reachable as it stands.
; ---------------------------------------------------------------------
dg_key
    lda X16_P1
    cmp #$0D
    bne @out
    stz dg_done
@out
    rts

; ---------------------------------------------------------------------
; dg_pkey -- the prompt's key handler: a one-line editor. RETURN is ok,
; ESC is cancel, DEL trims, printable $20..$7E appends while it fits.
; ---------------------------------------------------------------------
dg_pkey
    lda X16_P1
    cmp #$0D                    ; RETURN: ok
    bne @nret
    stz dg_done
    rts
@nret
    cmp #$1B                    ; ESC: cancel
    bne @nesc
    lda #1
    sta dg_done
    rts
@nesc
    cmp #$14                    ; DEL (CBM) trims the last char
    beq @bs
    cmp #$08                    ; ...and plain backspace too
    beq @bs
    cmp #$20                    ; printable types
    bcc @out
    cmp #$7F
    bcs @out
    ldy dg_len                  ; room?
    cpy dg_max
    bcs @out
    sta dg_t
    jsr dg_bufzp
    lda dg_t
    sta (CX_M_PTR),y            ; buffer[len] = char, re-terminated
    iny
    lda #0
    sta (CX_M_PTR),y
    sty dg_len
    jmp dg_field
@bs
    ldy dg_len
    beq @out
    dey
    jsr dg_bufzp
    lda #0
    sta (CX_M_PTR),y
    sty dg_len
    jmp dg_field
@out
    rts

dg_bufzp                        ; CX_M_PTR = the caller's buffer
    lda dg_buf
    sta CX_M_PTR
    lda dg_buf+1
    sta CX_M_PTR+1
    rts

dg_table                        ; NULL..DBLCLICK ride the region; keys
    .addr 0, 0, 0, 0, 0         ; come here; TIMER, MENU and WIDGET are
    .addr dg_key                ; nobody's while a dialog is up
    .addr 0, 0, 0

dg_ptable
    .addr 0, 0, 0, 0, 0
    .addr dg_pkey
    .addr 0, 0, 0

; --- dialog state -------------------------------------------------------
dg_p    .word 0
dg_n    .byte 0
dg_msg  .word 0
dg_lab  .res DG_MAXB*2, 0       ; lows, then highs
dg_bx   .word 0                 ; button 0's left edge
dg_x0   .word 0                 ; the box origin, centred from the metrics
dg_y0   .word 0                 ; and cx_cur_w/h (mode 0 lands 120,192)
dg_bty  .word 0                 ; the button row's y
dg_fx   .word 0                 ; the prompt field: x, y, width
dg_fy   .word 0
dg_fw   .word 0
dg_done .byte 0
dg_i    .byte 0
dg_t    .byte 0, 0
dg_t2   .byte 0
dg_oldh .word 0
dg_tab  .word 0
dg_buf  .word 0                 ; the prompt: the caller's buffer...
dg_len  .byte 0                 ; ...its length so far...
dg_max  .byte 0                 ; ...and the most it may hold
dg_s_ok     .byte "ok", 0
dg_s_cancel .byte "cancel", 0

.segment "CODE"
