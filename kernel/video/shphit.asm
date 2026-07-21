; ca65
; =====================================================================
; CXGEOS :: kernel/video/shphit.asm -- WG_HIT tests for the extra shapes
; =====================================================================
; The rectangle/circle/ellipse hit tests live in the widget bank (bank 16,
; kernel/ui/widget.asm). The v0.8.0 shapes that joined the port -- the
; regular POLYGON and the ARC/PIE wedge -- need trig to test a point, so
; their point-in-shape predicates ride bank 19 beside sin8/cos8/atan2 and
; the shape code, reached from wg_hit_refine through the cxb_call
; trampoline wg_hit_far. (This file is .included into shapes.asm's
; bank-19 segment, and into the flat test runner's link.)
;
; Both new hit shapes are CIRCLE-based: radius = WG_W>>1, centre = the box
; centre, exactly as WH_CIRCLE is "an ellipse with a square box" -- author
; them with a SQUARE box (the arc/pie and polygon draws are circle-based
; too, so a square box makes the region match the drawing). The record
; carries two extra bytes in the pad the toolkit never uses on a hit
; region (a hit region is never a list, so WG_TOP is free):
;
;   WH_POLYGON: WH_SIDES = 3..24 sides, WH_ROT = rotation (byte angle)
;   WH_PIE    : WH_A0    = start angle, WH_A1 = end angle
;
; Byte angles follow sin8/cos8: 0 = east, 64 = south, 128 = west, 192 =
; north (screen-y-down), the same convention shape_arc/shape_pie draw in.
;
; shp_hit -- carry set if the event point (X16_P2/P3 = x, X16_P4/P5 = y)
; lies inside CX_M_PTR's WG_HIT shape (WG_VAL >= WH_POLYGON). It reads the
; record and the point itself; A/X/Y are scratch, carry is the answer.
; Each routine owns its exits (a clc/rts or sec/rts near the branch) so no
; conditional branch has to reach out of its 127-byte range.
; =====================================================================

; record field offsets (mirror widget.asm)
SH_WG_X   = 2
SH_WG_Y   = 4
SH_WG_W   = 6
SH_WG_H   = 8
SH_WG_VAL = 9
SH_WH_P0  = 13                  ; WH_SIDES / WH_A0
SH_WH_P1  = 14                  ; WH_ROT   / WH_A1
SH_WH_PIE = 4                   ; WG_VAL for the pie wedge (else polygon)

shp_hit
    ; ---- radius, centre, and the signed deltas dx/dy ----
    ldy #SH_WG_W+1             ; r = WG_W>>1 (a byte; round regions <= 510 px)
    lda (CX_M_PTR),y
    lsr
    ldy #SH_WG_W
    lda (CX_M_PTR),y
    ror
    sta sh_r
    clc                        ; cx = WG_X + r
    ldy #SH_WG_X
    lda (CX_M_PTR),y
    adc sh_r
    sta sh_cx
    ldy #SH_WG_X+1
    lda (CX_M_PTR),y
    adc #0
    sta sh_cx+1
    sec                        ; dx = px - cx
    lda X16_P2
    sbc sh_cx
    sta sh_dx
    lda X16_P3
    sbc sh_cx+1
    sta sh_dx+1

    ldy #SH_WG_H              ; ry = WG_H>>1 (byte); cy = WG_Y + ry
    lda (CX_M_PTR),y
    lsr
    sta sh_ry
    clc
    ldy #SH_WG_Y
    lda (CX_M_PTR),y
    adc sh_ry
    sta sh_cy
    ldy #SH_WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta sh_cy+1
    sec                        ; dy = py - cy
    lda X16_P4
    sbc sh_cy
    sta sh_dy
    lda X16_P5
    sbc sh_cy+1
    sta sh_dy+1

    ; ---- |dx|, |dy| (bytes) and their signs (bit7) ----
    lda sh_dx+1
    sta sh_sx
    bpl @adxpos
    sec                        ; |dx| = -dx (low byte; |dx| <= r <= 255)
    lda #0
    sbc sh_dx
    sta sh_adx
    bra @ady
@adxpos
    lda sh_dx
    sta sh_adx
@ady
    lda sh_dy+1
    sta sh_sy
    bpl @adypos
    sec
    lda #0
    sbc sh_dy
    sta sh_ady
    bra @rtest
@adypos
    lda sh_dy
    sta sh_ady

    ; ---- inside the inscribed circle?  dx*dx + dy*dy <= r*r ----
@rtest
    lda sh_adx
    ldx sh_adx
    jsr shp_umul               ; sh_prod = |dx|^2
    lda sh_prod
    sta sh_acc
    lda sh_prod+1
    sta sh_acc+1
    stz sh_acc2
    lda sh_ady
    ldx sh_ady
    jsr shp_umul               ; sh_prod = |dy|^2
    clc
    lda sh_acc
    adc sh_prod
    sta sh_acc
    lda sh_acc+1
    adc sh_prod+1
    sta sh_acc+1
    lda sh_acc2
    adc #0
    sta sh_acc2                ; sh_acc(24b) = dx^2 + dy^2
    lda sh_r
    ldx sh_r
    jsr shp_umul               ; sh_prod = r^2 (16b)
    lda sh_acc2
    bne @rout                  ; >= 65536 > r^2 -> outside
    lda sh_acc+1
    cmp sh_prod+1
    bcc @rin
    bne @rout
    lda sh_acc
    cmp sh_prod
    bcc @rin
    beq @rin
@rout
    clc
    rts
@rin

    ; ---- angle theta = atan2(dx, dy), deltas scaled to signed bytes ----
    lda sh_r                   ; scale = (r >= 128) ? 1 : 0  (|delta| <= r)
    cmp #128
    lda #0
    rol
    sta sh_scale
    lda sh_adx
    ldx sh_scale
    beq @bx_ns
    lsr
@bx_ns
    ldx sh_sx
    bpl @bx_pos
    eor #$FF
    inc
@bx_pos
    sta sh_bx
    lda sh_ady
    ldx sh_scale
    beq @by_ns
    lsr
@by_ns
    ldx sh_sy
    bpl @by_pos
    eor #$FF
    inc
@by_pos
    sta sh_by
    lda sh_bx
    ldx sh_by
    jsr atan2                  ; A = theta (0..255)
    sta sh_theta

    ; ---- branch on the shape ----
    ldy #SH_WG_VAL
    lda (CX_M_PTR),y
    cmp #SH_WH_PIE
    beq shp_pie
    jmp shp_polygon

; =====================================================================
; the pie wedge: inside the circle (already proven) AND theta in [a0, a1)
; =====================================================================
shp_pie
    ldy #SH_WH_P0
    lda (CX_M_PTR),y
    sta sh_a0
    ldy #SH_WH_P1
    lda (CX_M_PTR),y
    sec
    sbc sh_a0                  ; span = (a1 - a0) & 255
    beq @in                    ; span 0 -> the whole disc (angle always in)
    sta sh_span
    lda sh_theta               ; d = (theta - a0) & 255
    sec
    sbc sh_a0
    cmp sh_span                ; inside iff d < span
    bcc @in
    clc
    rts
@in
    sec
    rts

; =====================================================================
; the regular convex polygon: a single half-plane test against the edge
; whose outward normal is nearest the point's direction (for a regular
; n-gon that edge is the only binding constraint).
;   k    = floor(rel * n / 256),  rel = (theta - rot) & 255
;   beta = rot + (2k+1)*128/n     (the edge-normal byte angle)
;   apo  = r * cos8(round(128/n)) (r * apothem/circumradius)
;   inside iff dx*cos8(beta) + dy*sin8(beta) <= apo
; =====================================================================
shp_polygon
    ldy #SH_WH_P0
    lda (CX_M_PTR),y           ; n = sides, clamped to 3..24
    cmp #3
    bcs @nlo
    lda #3
@nlo
    cmp #25
    bcc @nok
    lda #24
@nok
    sta sh_n
    ldy #SH_WH_P1
    lda (CX_M_PTR),y
    sta sh_rot

    lda sh_theta               ; rel = (theta - rot) & 255
    sec
    sbc sh_rot
    ldx sh_n
    jsr shp_umul               ; sh_prod = rel * n
    lda sh_prod+1              ; k = high byte = floor(rel*n/256)
    asl                        ; 2k
    ora #1                     ; 2k+1  (odd, <= 47)
    ldx #128
    jsr shp_umul               ; sh_prod = (2k+1)*128  (<= 6016)
    ldx sh_n
    jsr shp_div16_8            ; A = (2k+1)*128 / n  (noff, < 256)
    clc
    adc sh_rot
    sta sh_beta                ; beta = (rot + noff) & 255

    lda sh_n                   ; halfoff = round(128/n) = (128 + n/2)/n
    lsr
    clc
    adc #128
    sta sh_prod
    stz sh_prod+1
    ldx sh_n
    jsr shp_div16_8            ; A = halfoff (< 64, so cos8 is positive)
    jsr cos8
    ldx sh_r
    jsr shp_umul               ; sh_prod = r * cos8(halfoff) = apo (>= 0)
    lda sh_prod
    sta sh_apo
    lda sh_prod+1
    sta sh_apo+1

    ; proj = dx*cos8(beta) + dy*sin8(beta)   (signed 16-bit)
    lda sh_adx
    sta sh_amag
    lda sh_sx
    sta sh_dsign
    lda sh_beta
    jsr cos8
    jsr shp_term               ; sh_prod = dx * cos8(beta)
    lda sh_prod
    sta sh_proj
    lda sh_prod+1
    sta sh_proj+1
    lda sh_ady
    sta sh_amag
    lda sh_sy
    sta sh_dsign
    lda sh_beta
    jsr sin8
    jsr shp_term               ; sh_prod = dy * sin8(beta)
    clc
    lda sh_proj
    adc sh_prod
    sta sh_proj
    lda sh_proj+1
    adc sh_prod+1
    sta sh_proj+1

    lda sh_proj+1              ; inside iff proj <= apo (signed; apo >= 0)
    bmi @in                    ; proj < 0 -> inside
    cmp sh_apo+1
    bcc @in
    bne @out
    lda sh_proj
    cmp sh_apo
    bcc @in
    beq @in
@out
    clc
    rts
@in
    sec
    rts

; =====================================================================
; small integer helpers (bank-local; no reentrancy with the draw code --
; hit tests run in the foreground dispatch, the event IRQ never far-calls)
; =====================================================================

; shp_umul -- A * X -> sh_prod (16-bit unsigned). Max 255*255 = 65025.
shp_umul
    sta sh_mul_m
    stz sh_mul_m+1
    stz sh_prod
    stz sh_prod+1
    ldy #8
@lp
    txa
    lsr
    tax
    bcc @skip
    clc
    lda sh_prod
    adc sh_mul_m
    sta sh_prod
    lda sh_prod+1
    adc sh_mul_m+1
    sta sh_prod+1
@skip
    asl sh_mul_m
    rol sh_mul_m+1
    dey
    bne @lp
    rts

; shp_div16_8 -- sh_prod (16-bit) / X -> A (quotient); quotient assumed < 256.
; sh_prod is consumed. Restoring division, remainder discarded.
shp_div16_8
    stx sh_div_d
    lda #0                     ; remainder
    ldy #16
@lp
    asl sh_prod
    rol sh_prod+1
    rol
    cmp sh_div_d
    bcc @no
    sbc sh_div_d
    inc sh_prod                ; quotient bit -> vacated low bit
@no
    dey
    bne @lp
    lda sh_prod                ; the quotient (low byte; high byte is 0)
    rts

; shp_term -- sh_amag (a delta's magnitude) * (A = signed coef), with the
; delta's sign in sh_dsign(bit7) -> sh_prod = the signed 16-bit product.
shp_term
    sta sh_tmp                 ; coef
    eor sh_dsign               ; product sign = delta-sign XOR coef-sign
    and #$80
    sta sh_psign
    lda sh_tmp                 ; |coef|
    bpl @cpos
    eor #$FF
    inc
@cpos
    tax
    lda sh_amag
    jsr shp_umul               ; sh_prod = |delta| * |coef|
    lda sh_psign
    bpl @done
    sec                        ; negate sh_prod (16-bit)
    lda #0
    sbc sh_prod
    sta sh_prod
    lda #0
    sbc sh_prod+1
    sta sh_prod+1
@done
    rts

; --- scratch (bank-19 RAM; dead between calls) -----------------------
sh_r      .byte 0
sh_ry     .byte 0
sh_cx     .word 0
sh_cy     .word 0
sh_dx     .word 0
sh_dy     .word 0
sh_adx    .byte 0
sh_ady    .byte 0
sh_sx     .byte 0
sh_sy     .byte 0
sh_bx     .byte 0
sh_by     .byte 0
sh_scale  .byte 0
sh_theta  .byte 0
sh_n      .byte 0
sh_rot    .byte 0
sh_beta   .byte 0
sh_a0     .byte 0
sh_span   .byte 0
sh_apo    .word 0
sh_proj   .word 0
sh_acc    .word 0
sh_acc2   .byte 0
sh_prod   .word 0
sh_mul_m  .word 0
sh_div_d  .byte 0
sh_amag   .byte 0
sh_dsign  .byte 0
sh_psign  .byte 0
sh_tmp    .byte 0
