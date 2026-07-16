; ca65
; =====================================================================
; CXGEOS :: kernel/gfx2/dirty.asm -- the dirty-rectangle list
; =====================================================================
; The redraw ledger: UI code records what it touched, the end-of-frame
; compositor walks the list instead of repainting the screen. This is
; OS-side (not x16lib) because merge policy and capacity are tied to
; CXGEOS's window model.
;
; Rects are stored as inclusive corners (x0,y0)-(x1,y1), 16-bit each,
; in parallel lo/hi arrays for indexed access. Capacity DR_MAX; adding
; never fails and never drops a pixel:
;
;   - a new rect that overlaps OR touches (within 1px) an existing one
;     is unioned with it, the survivor re-scanned against the rest
;     (a grown rect may swallow neighbours -- the cascade),
;   - on a full list the oldest slot is folded into the newcomer and
;     the cascade rerun; coverage only ever grows.
;
; One translation unit, x16lib shape: .include after x16.asm. Uses
; X16_T0/T1 as scratch, module vars otherwise. No zero page claimed.
;
;   dr_reset    --
;   dr_add      in: X16_P0/P1 = x, P2/P3 = y, P4/P5 = w, P6/P7 = h
;               (empty rects -- w or h of 0 -- are ignored)
;   dr_count    out: A = number of rects
;   dr_get      in: A = index; out: P0/P1 = x0, P2/P3 = y0,
;               P4/P5 = x1, P6/P7 = y1 (inclusive corners)
; =====================================================================

DR_MAX = 8

dr_reset
    stz dr_n
    rts

dr_count
    lda dr_n
    rts

dr_get
    tax
    lda dr_x0l,x
    sta X16_P0
    lda dr_x0h,x
    sta X16_P1
    lda dr_y0l,x
    sta X16_P2
    lda dr_y0h,x
    sta X16_P3
    lda dr_x1l,x
    sta X16_P4
    lda dr_x1h,x
    sta X16_P5
    lda dr_y1l,x
    sta X16_P6
    lda dr_y1h,x
    sta X16_P7
    rts

; ---------------------------------------------------------------------
dr_add
    lda X16_P4                  ; empty rects carry no pixels
    ora X16_P5
    bne @w_ok
    rts
@w_ok
    lda X16_P6
    ora X16_P7
    bne @h_ok
    rts
@h_ok

    lda X16_P0                  ; newcomer corners: x1 = x + w - 1,
    sta dn_x0                   ;                   y1 = y + h - 1
    clc
    adc X16_P4
    sta dn_x1
    lda X16_P1
    sta dn_x0+1
    adc X16_P5
    sta dn_x1+1
    lda dn_x1
    bne @xw_ok
    dec dn_x1+1
@xw_ok
    dec dn_x1

    lda X16_P2
    sta dn_y0
    clc
    adc X16_P6
    sta dn_y1
    lda X16_P3
    sta dn_y0+1
    adc X16_P7
    sta dn_y1+1
    lda dn_y1
    bne @yw_ok
    dec dn_y1+1
@yw_ok
    dec dn_y1

@scan
    ldx #0
@next
    cpx dr_n
    bcs @scanned
    jsr dr_touches              ; carry set: newcomer meets rect X
    bcc @miss
    jsr dr_union                ; grow the newcomer over rect X...
    jsr dr_remove               ; ...retire the slot...
    bra @scan                   ; ...and rescan: it may now reach others
@miss
    inx
    bra @next

@scanned
    lda dr_n
    cmp #DR_MAX
    bcc @append
    ldx #0                      ; full: fold the oldest into the
    jsr dr_union                ; newcomer and try again -- the list
    jsr dr_remove               ; shrank, so this terminates
    bra @scan

@append
    ldx dr_n
    lda dn_x0
    sta dr_x0l,x
    lda dn_x0+1
    sta dr_x0h,x
    lda dn_y0
    sta dr_y0l,x
    lda dn_y0+1
    sta dr_y0h,x
    lda dn_x1
    sta dr_x1l,x
    lda dn_x1+1
    sta dr_x1h,x
    lda dn_y1
    sta dr_y1l,x
    lda dn_y1+1
    sta dr_y1h,x
    inc dr_n
@done
    rts

; ---------------------------------------------------------------------
; dr_touches -- carry set if the newcomer overlaps or touches (1px
; apart counts) rect X. Preserves X.
;
; Separation on any axis disproves contact:
;   new.x0 > r.x1 + 1  or  r.x0 > new.x1 + 1   (same for y)
; Tests run as "r.x1 + 1 >= new.x0", unsigned 16-bit.
; ---------------------------------------------------------------------
dr_touches
    lda dr_x1l,x                ; r.x1 + 1 >= new.x0 ?
    clc
    adc #1
    sta X16_T0
    lda dr_x1h,x
    adc #0
    cmp dn_x0+1
    bne @x_a
    lda X16_T0
    cmp dn_x0
@x_a
    bcc @apart

    lda dn_x1                   ; new.x1 + 1 >= r.x0 ?
    clc
    adc #1
    sta X16_T0
    lda dn_x1+1
    adc #0
    cmp dr_x0h,x
    bne @x_b
    lda X16_T0
    cmp dr_x0l,x
@x_b
    bcc @apart

    lda dr_y1l,x                ; r.y1 + 1 >= new.y0 ?
    clc
    adc #1
    sta X16_T0
    lda dr_y1h,x
    adc #0
    cmp dn_y0+1
    bne @y_a
    lda X16_T0
    cmp dn_y0
@y_a
    bcc @apart

    lda dn_y1                   ; new.y1 + 1 >= r.y0 ?
    clc
    adc #1
    sta X16_T0
    lda dn_y1+1
    adc #0
    cmp dr_y0h,x
    bne @y_b
    lda X16_T0
    cmp dr_y0l,x
@y_b
    bcc @apart
    sec
    rts
@apart
    clc
    rts

; ---------------------------------------------------------------------
; dr_union -- grow the newcomer to cover rect X. Preserves X.
; ---------------------------------------------------------------------
dr_union
    lda dr_x0h,x                ; new.x0 = min(new.x0, r.x0)
    cmp dn_x0+1
    bne @x0_h
    lda dr_x0l,x
    cmp dn_x0
@x0_h
    bcs @x0_keep
    lda dr_x0l,x
    sta dn_x0
    lda dr_x0h,x
    sta dn_x0+1
@x0_keep

    lda dr_y0h,x                ; new.y0 = min(new.y0, r.y0)
    cmp dn_y0+1
    bne @y0_h
    lda dr_y0l,x
    cmp dn_y0
@y0_h
    bcs @y0_keep
    lda dr_y0l,x
    sta dn_y0
    lda dr_y0h,x
    sta dn_y0+1
@y0_keep

    lda dn_x1+1                 ; new.x1 = max(new.x1, r.x1)
    cmp dr_x1h,x
    bne @x1_h
    lda dn_x1
    cmp dr_x1l,x
@x1_h
    bcs @x1_keep
    lda dr_x1l,x
    sta dn_x1
    lda dr_x1h,x
    sta dn_x1+1
@x1_keep

    lda dn_y1+1                 ; new.y1 = max(new.y1, r.y1)
    cmp dr_y1h,x
    bne @y1_h
    lda dn_y1
    cmp dr_y1l,x
@y1_h
    bcs @y1_keep
    lda dr_y1l,x
    sta dn_y1
    lda dr_y1h,x
    sta dn_y1+1
@y1_keep
    rts

; ---------------------------------------------------------------------
; dr_remove -- retire slot X: the last rect moves into it. Preserves X.
; ---------------------------------------------------------------------
dr_remove
    dec dr_n
    cpx dr_n
    beq @last                   ; removing the tail: nothing to move
    ldy dr_n
    lda dr_x0l,y
    sta dr_x0l,x
    lda dr_x0h,y
    sta dr_x0h,x
    lda dr_y0l,y
    sta dr_y0l,x
    lda dr_y0h,y
    sta dr_y0h,x
    lda dr_x1l,y
    sta dr_x1l,x
    lda dr_x1h,y
    sta dr_x1h,x
    lda dr_y1l,y
    sta dr_y1l,x
    lda dr_y1h,y
    sta dr_y1h,x
@last
    rts

; ---------------------------------------------------------------------
dr_n    .byte 0
dn_x0   .word 0
dn_y0   .word 0
dn_x1   .word 0
dn_y1   .word 0

dr_x0l  .res DR_MAX, 0
dr_x0h  .res DR_MAX, 0
dr_y0l  .res DR_MAX, 0
dr_y0h  .res DR_MAX, 0
dr_x1l  .res DR_MAX, 0
dr_x1h  .res DR_MAX, 0
dr_y1l  .res DR_MAX, 0
dr_y1h  .res DR_MAX, 0
