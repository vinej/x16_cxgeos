;ACME
; =====================================================================
; x16lib :: gfx/shapes.asm -- circle, disc, flood fill (any bitmap)
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does,
; under X16_USE_SHAPES).
;
; The shapes are ENGINE-AGNOSTIC and live here ONCE, not per engine:
; they draw through three entry symbols and read the canvas bounds
; through two, all overridable BEFORE this file is sourced. Left alone
; they bind to the 2bpp module (bitmap2). Any engine with the same call
; shapes can sit behind them:
;   - bitmap2 (2bpp): the default, no work.
;   - bitmap (8bpp): predefine SHP_PSET / SHP_HLINE to small shims that
;     move the colour from A into X16_P3 (where gfx_pset wants it), then
;     jmp gfx_pset / gfx_hline; SHP_READ = gfx_read; SHP_W/H = 320/240.
;   - CXGEOS points them at its graphics port and gets every mode at once.
;
;   SHP_PSET   pset:  P0/P1 = x, P2/P3 = y, A = colour (must clip)
;   SHP_READ   read:  P0/P1 = x, P2/P3 = y -> A = the pixel
;   SHP_HLINE  hline: P0/P1 = x, P2/P3 = y, P4/P5 = len, A = colour
;   SHP_W/H    the ADDRESS of a little-endian word: canvas w / h
;
; The P block is reloaded before every call, so the bound routines may
; clobber it freely; X16_T0..T7 are never touched here.
;
;   shape_circle  in: P0/P1 = cx, P2/P3 = cy, P4 = r (0-255), A = colour
;                 An outline, by the midpoint walk, plotted with
;                 SHP_PSET -- so it clips wherever pset clips.
;   shape_disc    same arguments, filled with spans. SHP_HLINE does not
;                 clip (the module policy), so keep a disc on screen.
;   shape_ellipse in: P0/P1 = cx, P2/P3 = cy, P4 = rx, P5 = ry (each
;                 0-255), A = colour. An axis-aligned outline by the
;                 midpoint walk, plotted with SHP_PSET -- so it clips
;                 wherever pset clips.
;   shape_fellipse same arguments, filled with spans. Like shape_disc
;                 it draws with SHP_HLINE, so keep it on screen.
;   shape_flood   in: P0/P1 = x, P2/P3 = y, A = colour. Scanline seed
;                 fill of the region containing (x,y). Bounds-checked
;                 against SHP_W/SHP_H, so it never reads off canvas.
;                 Carry set if the seed stack overflowed -- a very
;                 tortured region may come back incomplete.
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; shape_circle
; ---------------------------------------------------------------------
shape_circle
	sta shapes_col
	jsr shapes_take_cxy               ; cx/cy out of the P block, x=r, y=0
shapes_cloop
	lda shapes_y                      ; while y <= x
	cmp shapes_x
	beq shapes_cplot                  ; the diagonal point still plots
	bcs shapes_cdone
shapes_cplot
	lda shapes_x                      ; the (x,y) octant pair...
	sta shapes_a
	lda shapes_y
	sta shapes_b
	jsr shapes_pair4
	lda shapes_y                      ; ...and the (y,x) pair
	sta shapes_a
	lda shapes_x
	sta shapes_b
	jsr shapes_pair4
	jsr shapes_step                   ; the midpoint error walk
	bra shapes_cloop
shapes_cdone
	rts

; ---------------------------------------------------------------------
; shape_disc
; ---------------------------------------------------------------------
shape_disc
	sta shapes_col
	jsr shapes_take_cxy
shapes_dloop
	lda shapes_y
	cmp shapes_x
	beq shapes_dspan
	bcs shapes_ddone
shapes_dspan
	lda shapes_x                      ; spans at cy +/- y, half-width x...
	sta shapes_a
	lda shapes_y
	sta shapes_b
	jsr shapes_span2
	lda shapes_y                      ; ...and at cy +/- x, half-width y
	sta shapes_a
	lda shapes_x
	sta shapes_b
	jsr shapes_span2
	jsr shapes_step
	bra shapes_dloop
shapes_ddone
	rts

; --- shared circle/disc/ellipse machinery -------------------------------
shapes_take_cxy
	lda X16_P0
	sta shapes_cx
	lda X16_P1
	sta shapes_cx+1
	lda X16_P2
	sta shapes_cy
	lda X16_P3
	sta shapes_cy+1
	lda X16_P4
	sta shapes_x
	lda #0
	sta shapes_y
	sec                         ; err = 1 - r, signed 16-bit
	lda #1
	sbc shapes_x
	sta shapes_err
	lda #0
	sbc #0
	sta shapes_err+1
	rts

shapes_step
	inc shapes_y                      ;      else x--, err += 2(y-x)+1
	bit shapes_err+1
	bmi shapes_grow
	dec shapes_x
	sec                         ; t = y - x, sign-extended
	lda shapes_y
	sbc shapes_x
	sta shapes_t
	lda #0
	sbc #0
	sta shapes_t+1
	bra shapes_apply
shapes_grow
	lda shapes_y                      ; t = y (positive)
	sta shapes_t
	lda #0
	sta shapes_t+1
shapes_apply
	asl shapes_t                      ; err += 2t + 1
	rol shapes_t+1
	inc shapes_t
	bne :+
	inc shapes_t+1
:	clc
	lda shapes_err
	adc shapes_t
	sta shapes_err
	lda shapes_err+1
	adc shapes_t+1
	sta shapes_err+1
	rts

shapes_pair4
	lda #0
	sta shapes_sx
	sta shapes_sy
shapes_p4go
	jsr shapes_emit1
	lda shapes_sx                     ; walk ++, -+, +-, -- via two flags
	eor #1
	sta shapes_sx
	bne shapes_p4go
	lda shapes_sy
	eor #1
	sta shapes_sy
	bne shapes_p4go
	rts

shapes_emit1
	lda shapes_sx
	bne shapes_e1xm
	clc                         ; x = cx + a
	lda shapes_cx
	adc shapes_a
	sta X16_P0
	lda shapes_cx+1
	adc #0
	sta X16_P1
	bra shapes_e1y
shapes_e1xm
	sec                         ; x = cx - a
	lda shapes_cx
	sbc shapes_a
	sta X16_P0
	lda shapes_cx+1
	sbc #0
	sta X16_P1
shapes_e1y
	lda shapes_sy
	bne shapes_e1ym
	clc
	lda shapes_cy
	adc shapes_b
	sta X16_P2
	lda shapes_cy+1
	adc #0
	sta X16_P3
	bra shapes_e1go
shapes_e1ym
	sec
	lda shapes_cy
	sbc shapes_b
	sta X16_P2
	lda shapes_cy+1
	sbc #0
	sta X16_P3
shapes_e1go
	lda shapes_col
	jmp SHP_PSET

shapes_span2
	lda #0
	sta shapes_sy
	jsr shapes_espan
	lda #1
	sta shapes_sy
	; fall through
shapes_espan
	sec                         ; x = cx - a
	lda shapes_cx
	sbc shapes_a
	sta X16_P0
	lda shapes_cx+1
	sbc #0
	sta X16_P1
	lda shapes_sy
	bne shapes_esym
	clc
	lda shapes_cy
	adc shapes_b
	sta X16_P2
	lda shapes_cy+1
	adc #0
	sta X16_P3
	bra shapes_esgo
shapes_esym
	sec
	lda shapes_cy
	sbc shapes_b
	sta X16_P2
	lda shapes_cy+1
	sbc #0
	sta X16_P3
shapes_esgo
	lda shapes_a                      ; len = 2a + 1
	sta X16_P4
	lda #0
	sta X16_P5
	asl X16_P4
	rol X16_P5
	inc X16_P4
	bne :+
	inc X16_P5
:	lda shapes_col
	jmp SHP_HLINE

; ---------------------------------------------------------------------
; shape_ellipse / shape_fellipse
; ---------------------------------------------------------------------
; One walk serves both: the error-form midpoint ellipse (Zingl),
; quadrant II from (-rx, 0) up to (0, ry), mirrored 4 ways by the
; circle's own shapes_pair4 / shapes_span2. The decision terms reach 2*rx*ry^2
; (about 33M at 255/255), so the arithmetic is 32-bit; the one setup
; product rx * 2ry^2 is a repeated subtract, a few thousand cycles at
; the very worst -- noise against the drawing itself.
;   dx = ry^2 - rx*2ry^2, dy = rx^2, err = dx + dy
;   each step: e2 = 2*err;
;     e2 >= dx ?  x++, err += dx += 2ry^2
;     e2 <= dy ?  y++, err += dy += 2rx^2
;   while x <= 0; then a centre column finishes the flat tips (small
;   rx). A row's widest span always lands before its narrower echoes,
;   so the fill's overdraw is harmless, same as the disc's.
; ---------------------------------------------------------------------
shape_ellipse
	sta shapes_col
	stz shapes_efl
	bra shapes_etake
shape_fellipse
	sta shapes_col
	lda #1
	sta shapes_efl
shapes_etake
	lda X16_P0                  ; centre out of the P block
	sta shapes_cx
	lda X16_P1
	sta shapes_cx+1
	lda X16_P2
	sta shapes_cy
	lda X16_P3
	sta shapes_cy+1
	lda X16_P4
	sta shapes_ew
	lda X16_P5
	sta shapes_eh

	lda shapes_eh                     ; shapes_sq = ry^2
	jsr shapes_sq16
	lda shapes_sq                     ; dx = ry^2 (the rx*2ry^2 comes off below)
	sta shapes_edx
	lda shapes_sq+1
	sta shapes_edx+1
	stz shapes_edx+2
	stz shapes_edx+3
	lda shapes_sq                     ; shapes_e2b = 2ry^2
	sta shapes_e2b
	lda shapes_sq+1
	sta shapes_e2b+1
	stz shapes_e2b+2
	stz shapes_e2b+3
	asl shapes_e2b
	rol shapes_e2b+1
	rol shapes_e2b+2
	ldx shapes_ew                     ; dx -= rx * 2ry^2, one 2ry^2 at a time
	beq shapes_exset
shapes_emul
	sec
	lda shapes_edx
	sbc shapes_e2b
	sta shapes_edx
	lda shapes_edx+1
	sbc shapes_e2b+1
	sta shapes_edx+1
	lda shapes_edx+2
	sbc shapes_e2b+2
	sta shapes_edx+2
	lda shapes_edx+3
	sbc shapes_e2b+3
	sta shapes_edx+3
	dex
	bne shapes_emul
shapes_exset
	lda shapes_ew                     ; shapes_sq = rx^2
	jsr shapes_sq16
	lda shapes_sq                     ; dy = rx^2
	sta shapes_edy
	lda shapes_sq+1
	sta shapes_edy+1
	stz shapes_edy+2
	stz shapes_edy+3
	lda shapes_sq                     ; shapes_e2a = 2rx^2
	sta shapes_e2a
	lda shapes_sq+1
	sta shapes_e2a+1
	stz shapes_e2a+2
	stz shapes_e2a+3
	asl shapes_e2a
	rol shapes_e2a+1
	rol shapes_e2a+2
	clc                         ; err = dx + dy
	lda shapes_edx
	adc shapes_edy
	sta shapes_eerr
	lda shapes_edx+1
	adc shapes_edy+1
	sta shapes_eerr+1
	lda shapes_edx+2
	adc shapes_edy+2
	sta shapes_eerr+2
	lda shapes_edx+3
	adc shapes_edy+3
	sta shapes_eerr+3
	sec                         ; x = -rx (16-bit signed), y = 0
	lda #0
	sbc shapes_ew
	sta shapes_ex
	lda #0
	sbc #0
	sta shapes_ex+1
	stz shapes_ey

shapes_eloop
	sec                         ; this step's quadrant point: (|x|, y)
	lda #0
	sbc shapes_ex
	sta shapes_a
	lda shapes_ey
	sta shapes_b
	jsr shapes_eplot
	lda shapes_eerr                   ; e2 = 2*err
	sta shapes_ee2
	lda shapes_eerr+1
	sta shapes_ee2+1
	lda shapes_eerr+2
	sta shapes_ee2+2
	lda shapes_eerr+3
	sta shapes_ee2+3
	asl shapes_ee2
	rol shapes_ee2+1
	rol shapes_ee2+2
	rol shapes_ee2+3
	sec                         ; e2 >= dx?  sign of e2 - dx decides
	lda shapes_ee2
	sbc shapes_edx
	lda shapes_ee2+1
	sbc shapes_edx+1
	lda shapes_ee2+2
	sbc shapes_edx+2
	lda shapes_ee2+3
	sbc shapes_edx+3
	bmi shapes_noxstep
	inc shapes_ex                     ; x++
	bne shapes_exdx
	inc shapes_ex+1
shapes_exdx
	clc                         ; err += dx += 2ry^2
	lda shapes_edx
	adc shapes_e2b
	sta shapes_edx
	lda shapes_edx+1
	adc shapes_e2b+1
	sta shapes_edx+1
	lda shapes_edx+2
	adc shapes_e2b+2
	sta shapes_edx+2
	lda shapes_edx+3
	adc shapes_e2b+3
	sta shapes_edx+3
	clc
	lda shapes_eerr
	adc shapes_edx
	sta shapes_eerr
	lda shapes_eerr+1
	adc shapes_edx+1
	sta shapes_eerr+1
	lda shapes_eerr+2
	adc shapes_edx+2
	sta shapes_eerr+2
	lda shapes_eerr+3
	adc shapes_edx+3
	sta shapes_eerr+3
shapes_noxstep
	sec                         ; e2 <= dy?  sign of dy - e2 decides
	lda shapes_edy
	sbc shapes_ee2
	lda shapes_edy+1
	sbc shapes_ee2+1
	lda shapes_edy+2
	sbc shapes_ee2+2
	lda shapes_edy+3
	sbc shapes_ee2+3
	bmi shapes_noystep
	inc shapes_ey                     ; y++
	clc                         ; err += dy += 2rx^2
	lda shapes_edy
	adc shapes_e2a
	sta shapes_edy
	lda shapes_edy+1
	adc shapes_e2a+1
	sta shapes_edy+1
	lda shapes_edy+2
	adc shapes_e2a+2
	sta shapes_edy+2
	lda shapes_edy+3
	adc shapes_e2a+3
	sta shapes_edy+3
	clc
	lda shapes_eerr
	adc shapes_edy
	sta shapes_eerr
	lda shapes_eerr+1
	adc shapes_edy+1
	sta shapes_eerr+1
	lda shapes_eerr+2
	adc shapes_edy+2
	sta shapes_eerr+2
	lda shapes_eerr+3
	adc shapes_edy+3
	sta shapes_eerr+3
shapes_noystep
	lda shapes_ex+1                   ; while x <= 0
	bmi shapes_econt
	ora shapes_ex
	bne shapes_etip
shapes_econt
	jmp shapes_eloop
shapes_etip
	lda shapes_ey                     ; flat tip: the centre column on to ry
	cmp shapes_eh
	bcs shapes_edone
	inc shapes_ey
	stz shapes_a
	lda shapes_ey
	sta shapes_b
	jsr shapes_eplot
	bra shapes_etip
shapes_edone
	rts

shapes_eplot
	lda shapes_efl
	beq shapes_eout
	jmp shapes_span2
shapes_eout
	jmp shapes_pair4

shapes_sq16
	sta shapes_sm
	stz shapes_sq
	stz shapes_sq+1
	tax
	beq shapes_sqdone
shapes_sqlp
	clc
	lda shapes_sq
	adc shapes_sm
	sta shapes_sq
	bcc shapes_sqnc
	inc shapes_sq+1
shapes_sqnc
	dex
	bne shapes_sqlp
shapes_sqdone
	rts

; ---------------------------------------------------------------------
; shape_flood
; ---------------------------------------------------------------------
; Pop a seed, widen it into a span of the target colour, fill the span,
; then scan the rows above and below for runs of target and push one
; seed per run. The stack holds seeds as x.w y.w; when it is full a
; seed is dropped and the overflow is remembered in the carry.
; ---------------------------------------------------------------------
FLOOD_MAX = 96                  ; seeds; 4 bytes each

shape_flood
	sta shapes_col
	lda #0
	sta shapes_ovf
	sta shapes_sp
	jsr shapes_rd_p                   ; the target = the seed's own colour
	sta shapes_tgt
	cmp shapes_col                    ; filling with itself never ends: done
	bne shapes_fseed
	clc                         ; (no overflow could have happened yet)
	rts
shapes_fseed
	lda X16_P0                  ; push the seed
	sta shapes_qx
	lda X16_P1
	sta shapes_qx+1
	lda X16_P2
	sta shapes_qy
	lda X16_P3
	sta shapes_qy+1
	jsr shapes_push
shapes_floop
	lda shapes_sp                     ; stack empty: finished
	bne shapes_fbody
	jmp shapes_fexit
shapes_fbody
	jsr shapes_pop                    ; seed -> shapes_qx/shapes_qy
	jsr shapes_rd_q                   ; still target? (may have been filled)
	cmp shapes_tgt
	bne shapes_floop

	lda shapes_qx                     ; widen left: xl = leftmost target
	sta shapes_xl
	lda shapes_qx+1
	sta shapes_xl+1
shapes_wleft
	lda shapes_xl
	ora shapes_xl+1
	beq shapes_wldone                 ; at column 0
	sec                         ; probe xl-1
	lda shapes_xl
	sbc #1
	sta shapes_qx
	lda shapes_xl+1
	sbc #0
	sta shapes_qx+1
	jsr shapes_rd_q
	cmp shapes_tgt
	bne shapes_wldone
	lda shapes_qx
	sta shapes_xl
	lda shapes_qx+1
	sta shapes_xl+1
	bra shapes_wleft
shapes_wldone
	lda shapes_qy                     ; widen right: xr = rightmost target
	sta shapes_qy                     ; (qy already holds the row)
	lda shapes_xl
	sta shapes_xr
	lda shapes_xl+1
	sta shapes_xr+1
shapes_wright
	clc                         ; probe xr+1, stop at SHP_W-1
	lda shapes_xr
	adc #1
	sta shapes_qx
	lda shapes_xr+1
	adc #0
	sta shapes_qx+1
	lda shapes_qx                     ; qx == W? off the right edge
	cmp SHP_W
	bne shapes_wrprobe
	lda shapes_qx+1
	cmp SHP_W+1
	beq shapes_wrdone
shapes_wrprobe
	jsr shapes_rd_q
	cmp shapes_tgt
	bne shapes_wrdone
	lda shapes_qx
	sta shapes_xr
	lda shapes_qx+1
	sta shapes_xr+1
	bra shapes_wright
shapes_wrdone
	lda shapes_xl                     ; fill the span: hline(xl, y, xr-xl+1)
	sta X16_P0
	lda shapes_xl+1
	sta X16_P1
	lda shapes_qy
	sta X16_P2
	lda shapes_qy+1
	sta X16_P3
	sec
	lda shapes_xr
	sbc shapes_xl
	sta X16_P4
	lda shapes_xr+1
	sbc shapes_xl+1
	sta X16_P5
	inc X16_P4
	bne :+
	inc X16_P5
:	lda shapes_col
	jsr SHP_HLINE

	lda shapes_qy                     ; shapes_scanrow clobbers shapes_qy, so keep the filled
	sta shapes_row                    ; row here for BOTH neighbour scans
	lda shapes_qy+1
	sta shapes_row+1

	lda shapes_row                    ; the row above...
	sta shapes_ry
	lda shapes_row+1
	sta shapes_ry+1
	lda shapes_ry
	ora shapes_ry+1
	beq shapes_below                  ; row 0 has nothing above
	sec
	lda shapes_ry
	sbc #1
	sta shapes_ry
	lda shapes_ry+1
	sbc #0
	sta shapes_ry+1
	jsr shapes_scanrow
shapes_below
	clc                         ; ...and the row below
	lda shapes_row
	adc #1
	sta shapes_ry
	lda shapes_row+1
	adc #0
	sta shapes_ry+1
	lda shapes_ry                     ; ry == H? off the bottom
	cmp SHP_H
	bne shapes_bscan
	lda shapes_ry+1
	cmp SHP_H+1
	beq shapes_fnext
shapes_bscan
	jsr shapes_scanrow
shapes_fnext
	jmp shapes_floop
shapes_fexit
	lsr shapes_ovf                    ; overflow -> carry
	rts

; scan shapes_xl...xr on row shapes_ry for runs of target; push one seed per run
shapes_scanrow
	lda #0
	sta shapes_run
	lda shapes_xl
	sta shapes_tx
	lda shapes_xl+1
	sta shapes_tx+1
shapes_srloop
	lda shapes_tx                     ; read (tx, ry)
	sta shapes_qx
	lda shapes_tx+1
	sta shapes_qx+1
	lda shapes_ry
	sta shapes_qy
	lda shapes_ry+1
	sta shapes_qy+1
	jsr shapes_rd_q
	cmp shapes_tgt
	bne shapes_srmiss
	lda shapes_run                    ; entering a run: one seed
	bne shapes_srnext
	lda #1
	sta shapes_run
	jsr shapes_push
	bra shapes_srnext
shapes_srmiss
	lda #0
	sta shapes_run
shapes_srnext
	lda shapes_tx                     ; tx == xr? done
	cmp shapes_xr
	bne shapes_srinc
	lda shapes_tx+1
	cmp shapes_xr+1
	beq shapes_srdone
shapes_srinc
	inc shapes_tx
	bne shapes_srloop
	inc shapes_tx+1
	bra shapes_srloop
shapes_srdone
	rts

shapes_rd_p
	jmp SHP_READ
shapes_rd_q
	lda shapes_qx
	sta X16_P0
	lda shapes_qx+1
	sta X16_P1
	lda shapes_qy
	sta X16_P2
	lda shapes_qy+1
	sta X16_P3
	jmp SHP_READ

shapes_push
	lda shapes_sp
	cmp #FLOOD_MAX
	bcc :+
	lda #2                      ; remembered; lsr at exit -> carry
	sta shapes_ovf
	rts
:	asl                         ; sp * 4
	asl
	tax
	lda shapes_qx
	sta shapes_stk,x
	lda shapes_qx+1
	sta shapes_stk+1,x
	lda shapes_qy
	sta shapes_stk+2,x
	lda shapes_qy+1
	sta shapes_stk+3,x
	inc shapes_sp
	rts

shapes_pop
	dec shapes_sp
	lda shapes_sp
	asl
	asl
	tax
	lda shapes_stk,x
	sta shapes_qx
	lda shapes_stk+1,x
	sta shapes_qx+1
	lda shapes_stk+2,x
	sta shapes_qy
	lda shapes_stk+3,x
	sta shapes_qy+1
	rts

; --- the state ---------------------------------------------------------
shapes_col
    .byte 0
shapes_cx
    .word 0
shapes_cy
    .word 0
shapes_x
    .byte 0
shapes_y
    .byte 0
shapes_a
    .byte 0
shapes_b
    .byte 0
shapes_sx
    .byte 0
shapes_sy
    .byte 0
shapes_err
    .word 0
shapes_t
    .word 0

shapes_efl
    .byte 0
shapes_ew
    .byte 0
shapes_eh
    .byte 0
shapes_ex
    .word 0
shapes_ey
    .byte 0
shapes_sm
    .byte 0
shapes_sq
    .word 0
shapes_edx
    .res 4, 0
shapes_edy
    .res 4, 0
shapes_eerr
    .res 4, 0
shapes_ee2
    .res 4, 0
shapes_e2a
    .res 4, 0
shapes_e2b
    .res 4, 0

shapes_tgt
    .byte 0
shapes_ovf
    .byte 0
shapes_sp
    .byte 0
shapes_qx
    .word 0
shapes_qy
    .word 0
shapes_xl
    .word 0
shapes_xr
    .word 0
shapes_ry
    .word 0
shapes_row
    .word 0
shapes_tx
    .word 0
shapes_run
    .byte 0
shapes_stk
    .res FLOOD_MAX * 4, 0

; --- the default binding: the 2bpp module ------------------------------
; (evaluated here, at the END, so an overrider defines its symbols
; before sourcing the file and these !ifdefs stay quiet)
; The default-bound words are emitted UNCONDITIONALLY -- data inside an
; !ifndef would appear in pass 1 and vanish in pass 2 (the symbol exists
; by then), shifting every later address into a phase error.
shp_wdef .word 640
shp_hdef .word 480

.ifndef SHP_PSET
SHP_PSET  = gfx2_pset
.endif
.ifndef SHP_READ
SHP_READ  = gfx2_read
.endif
.ifndef SHP_HLINE
SHP_HLINE = gfx2_hline
.endif
.ifndef SHP_W
SHP_W     = shp_wdef
.endif
.ifndef SHP_H
SHP_H     = shp_hdef
.endif

; (end zone)
