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
; they bind to the 2bpp high-res module (bitmap2h). Any engine with the same call
; shapes can sit behind them:
;   - bitmap2h (2bpp): the default, no work.
;   - bitmap8l (8bpp): predefine SHP_PSET / SHP_HLINE to small shims that
;     move the colour from A into X16_P3 (where gfx8l_pset wants it), then
;     jmp gfx8l_pset / gfx8l_hline; SHP_READ = gfx8l_read; SHP_W/H = 320/240.
;   - CXRF points them at its graphics port and gets every mode at once.
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
; shape_circle / shape_disc -- one walk for both, like the ellipse:
; shapes_efl routes each plot through shapes_eplot to the octant points (outline)
; or the spans (fill).
; ---------------------------------------------------------------------
; CXRF: X16_SKIP_BASE lets this file be !source'd a 2nd time for the extra
; shapes only (base + defaults in bank 17, extras in bank 19). Upstream-safe.
.ifndef X16_SKIP_BASE
shape_circle
	sta shapes_col
	stz shapes_efl                    ; outline: the octant point pairs
	bra shapes_cgo
shape_disc
	sta shapes_col
	lda #1                      ; filled: spans at cy +/- b instead
	sta shapes_efl
shapes_cgo
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
	jsr shapes_eplot
	lda shapes_y                      ; ...and the (y,x) pair
	sta shapes_a
	lda shapes_x
	sta shapes_b
	jsr shapes_eplot
	jsr shapes_step                   ; the midpoint error walk
	bra shapes_cloop
shapes_cdone
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
	jsr shapes_subx                   ; x = cx - a
shapes_e1y
	jsr shapes_sety
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
	jsr shapes_subx                   ; x = cx - a
	jsr shapes_sety
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

shapes_subx
	sec
	lda shapes_cx
	sbc shapes_a
	sta X16_P0
	lda shapes_cx+1
	sbc #0
	sta X16_P1
	rts

shapes_sety
	lda shapes_sy
	bne shapes_sym
	clc
	lda shapes_cy
	adc shapes_b
	sta X16_P2
	lda shapes_cy+1
	adc #0
	sta X16_P3
	rts
shapes_sym
	sec
	lda shapes_cy
	sbc shapes_b
	sta X16_P2
	lda shapes_cy+1
	sbc #0
	sta X16_P3
	rts

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
	lda shapes_eerr                   ; e2 = 2*err, copied with the shift
	asl
	sta shapes_ee2
	lda shapes_eerr+1
	rol
	sta shapes_ee2+1
	lda shapes_eerr+2
	rol
	sta shapes_ee2+2
	lda shapes_eerr+3
	rol
	sta shapes_ee2+3
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
	jsr SHP_READ                ; the target = the seed's own colour
	                            ; (read at the CALLER's P block)
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
	lda shapes_xl                     ; widen right: xr = rightmost target
	sta shapes_xr                     ; (qy already holds the row)
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

shapes_rd_q
	ldx #3
shapes_rq_l
	lda shapes_qx,x
	sta X16_P0,x
	dex
	bpl shapes_rq_l
	jmp SHP_READ

shapes_push
	lda shapes_sp
	cmp #FLOOD_MAX
	bcc :+
	lda #1                      ; remembered; lsr at exit -> carry
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

; ---------------------------------------------------------------------
; shape_polygon / shape_fpolygon -- regular convex polygons (X16_USE_SHAPES_POLY)
; ---------------------------------------------------------------------
; A regular N-gon: N vertices evenly spaced on a circle of radius r about
; (cx, cy), the first at byte-angle `rotation` (0 = east, 64 = south, the
; sin8/cos8 convention). shape_polygon draws the outline through SHP_PSET
; (so it clips like shape_circle); shape_fpolygon fills it with SHP_HLINE
; spans (so it does NOT clip -- keep it on screen, like shape_disc).
;
;   in: P0/P1 = cx, P2/P3 = cy, P4 = radius (0-255),
;       P5 = sides (3..POLY_MAX; fewer draws nothing, more is clamped),
;       P6 = rotation (byte angle), A = colour
;
; Vertices come from sin8/cos8 (hence the X16_USE_MATH dependency) scaled
; by r and rounded. The fill is a per-scanline convex span fill: for each
; row it finds the two edge crossings and draws between them, half-open at
; the bottom row so tiled polygons do not double-paint a shared edge. It
; is a one-shot primitive (cost ~ sides * height), not a per-frame filler.
;
; House style, as everywhere in this file: all labels are zone-locals with
; unique names (ACME's @cheap locals do not reset at a zone-local routine
; label, so two routines could not each own an @loop), and the work is cut
; into small routines so no branch reaches past its 127-byte range.
; ---------------------------------------------------------------------
.endif

.ifdef X16_USE_SHAPES_POLY

POLY_MAX = 24                   ; vertices; the buffers below are 2 bytes each

shape_polygon
	sta poly_col
	stz poly_efl                ; outline
	jmp shapes_poly_begin
shape_fpolygon
	sta poly_col
	lda #1                      ; filled
	sta poly_efl
	; fall through
shapes_poly_begin
	lda X16_P5                  ; clamp the side count to 3..POLY_MAX
	cmp #3
	bcc shapes_pg_bret                ; fewer than 3: not a polygon
	cmp #(POLY_MAX + 1)
	bcc shapes_pg_bnok
	lda #POLY_MAX
shapes_pg_bnok
	sta poly_n
	lda X16_P0
	sta poly_cx
	lda X16_P1
	sta poly_cx+1
	lda X16_P2
	sta poly_cy
	lda X16_P3
	sta poly_cy+1
	lda X16_P4
	sta poly_r
	stz poly_acc                ; angle accumulator = rotation << 8
	lda X16_P6
	sta poly_acc+1
	jsr shapes_poly_verts
	lda poly_efl
	bne shapes_pg_bfill
	jmp shapes_poly_outline
shapes_pg_bfill
	jmp shapes_poly_fill
shapes_pg_bret
	rts

; compute the N vertices into poly_vx[]/poly_vy[]
shapes_poly_verts
	jsr shapes_poly_step              ; poly_step = 65536 / n
	stz poly_i
shapes_pg_vloop
	lda poly_i
	cmp poly_n
	beq shapes_pg_vend
	lda poly_acc+1              ; this vertex's byte angle
	pha
	jsr cos8                    ; A = cos * 127 (signed)
	jsr shapes_poly_scale             ; poly_off = round(r * A / 128), signed
	lda poly_i
	asl
	tax                         ; 2*i
	clc
	lda poly_cx
	adc poly_off
	sta poly_vx,x
	lda poly_cx+1
	adc poly_off+1
	sta poly_vx+1,x
	pla                         ; the angle again
	jsr sin8                    ; A = sin * 127 (signed)
	jsr shapes_poly_scale
	lda poly_i
	asl
	tax
	clc
	lda poly_cy
	adc poly_off
	sta poly_vy,x
	lda poly_cy+1
	adc poly_off+1
	sta poly_vy+1,x
	clc                         ; acc += step
	lda poly_acc
	adc poly_step
	sta poly_acc
	lda poly_acc+1
	adc poly_step+1
	sta poly_acc+1
	inc poly_i
	bra shapes_pg_vloop
shapes_pg_vend
	rts

; poly_off = round(poly_r * |A| / 128) with A's sign, A a signed byte
shapes_poly_scale
	stz poly_sgn
	pha
	and #$80
	beq shapes_pg_spos
	inc poly_sgn
	pla
	eor #$FF
	clc
	adc #1
	bra shapes_pg_smul
shapes_pg_spos
	pla
shapes_pg_smul
	jsr shapes_poly_mul8              ; poly_p16 = poly_r * |A|
	clc
	lda poly_p16                ; + 0.5 LSB, so >>7 rounds
	adc #64
	sta poly_p16
	lda poly_p16+1
	adc #0
	sta poly_p16+1
	lda poly_p16                ; >>7 (product < 32768, so one byte out)
	asl
	lda poly_p16+1
	rol
	sta poly_off
	stz poly_off+1
	lda poly_sgn
	beq shapes_pg_sdone
	sec                         ; negate
	lda #0
	sbc poly_off
	sta poly_off
	lda #0
	sbc poly_off+1
	sta poly_off+1
shapes_pg_sdone
	rts

; poly_p16 = poly_r * A  (8x8 -> 16, unsigned)
shapes_poly_mul8
	sta poly_t
	lda #0
	ldx #8
shapes_pg_mloop
	lsr poly_t
	bcc shapes_pg_mskip
	clc
	adc poly_r
shapes_pg_mskip
	ror
	ror poly_p16
	dex
	bne shapes_pg_mloop
	sta poly_p16+1
	rts

; poly_step = floor(65536 / poly_n), by restoring division of $010000
shapes_poly_step
	stz poly_dvd
	stz poly_dvd+1
	lda #1
	sta poly_dvd+2
	stz poly_rem
	stz poly_step
	stz poly_step+1
	ldx #24
shapes_pg_dloop
	asl poly_dvd
	rol poly_dvd+1
	rol poly_dvd+2
	rol poly_rem                ; carry = the remainder's 9th bit
	bcs shapes_pg_dsub                ; overflowed 8 bits: certainly >= n
	lda poly_rem
	cmp poly_n
	bcc shapes_pg_dnoq
shapes_pg_dsub
	lda poly_rem                ; carry is set on both paths here
	sbc poly_n
	sta poly_rem
	sec                         ; quotient bit = 1
	bra shapes_pg_dbit
shapes_pg_dnoq
	clc                         ; quotient bit = 0
shapes_pg_dbit
	rol poly_step
	rol poly_step+1
	dex
	bne shapes_pg_dloop
	rts

; --- outline ---------------------------------------------------------
shapes_poly_outline
	stz poly_i
shapes_pg_oloop
	lda poly_i                  ; endpoint 0 = vertex i
	asl
	tax
	lda poly_vx,x
	sta poly_lx0
	lda poly_vx+1,x
	sta poly_lx0+1
	lda poly_vy,x
	sta poly_ly0
	lda poly_vy+1,x
	sta poly_ly0+1
	lda poly_i                  ; endpoint 1 = vertex (i+1) mod n
	clc
	adc #1
	cmp poly_n
	bne shapes_pg_ojok
	lda #0
shapes_pg_ojok
	asl
	tax
	lda poly_vx,x
	sta poly_lx1
	lda poly_vx+1,x
	sta poly_lx1+1
	lda poly_vy,x
	sta poly_ly1
	lda poly_vy+1,x
	sta poly_ly1+1
	jsr shapes_poly_line
	inc poly_i
	lda poly_i
	cmp poly_n
	bne shapes_pg_oloop
	rts

; 16-bit Bresenham from (lx0,ly0) to (lx1,ly1), plotting through SHP_PSET
; (the gfx2h_line algorithm, engine-agnostic and clipping via the binding)
shapes_poly_line
	sec                         ; dx = |x1 - x0|, sx = direction
	lda poly_lx1
	sbc poly_lx0
	sta poly_ldx
	lda poly_lx1+1
	sbc poly_lx0+1
	sta poly_ldx+1
	bpl shapes_pg_ldxp
	sec
	lda #0
	sbc poly_ldx
	sta poly_ldx
	lda #0
	sbc poly_ldx+1
	sta poly_ldx+1
	lda #$FF
	sta poly_lsx
	sta poly_lsx+1
	bra shapes_pg_ldxd
shapes_pg_ldxp
	lda #1
	sta poly_lsx
	stz poly_lsx+1
shapes_pg_ldxd
	sec                         ; dy = -|y1 - y0|, sy = direction
	lda poly_ly1
	sbc poly_ly0
	sta poly_lt
	lda poly_ly1+1
	sbc poly_ly0+1
	sta poly_lt+1
	bpl shapes_pg_ldyp
	sec
	lda #0
	sbc poly_lt
	sta poly_lt
	lda #0
	sbc poly_lt+1
	sta poly_lt+1
	lda #$FF
	sta poly_lsy
	sta poly_lsy+1
	bra shapes_pg_ldyd
shapes_pg_ldyp
	lda #1
	sta poly_lsy
	stz poly_lsy+1
shapes_pg_ldyd
	sec                         ; ldy = -|dy|
	lda #0
	sbc poly_lt
	sta poly_ldy
	lda #0
	sbc poly_lt+1
	sta poly_ldy+1
	clc                         ; err = dx + dy
	lda poly_ldx
	adc poly_ldy
	sta poly_lerr
	lda poly_ldx+1
	adc poly_ldy+1
	sta poly_lerr+1
shapes_pg_lloop
	lda poly_lx0
	sta X16_P0
	lda poly_lx0+1
	sta X16_P1
	lda poly_ly0
	sta X16_P2
	lda poly_ly0+1
	sta X16_P3
	lda poly_col
	jsr SHP_PSET
	lda poly_lx0                ; reached the endpoint?
	cmp poly_lx1
	bne shapes_pg_lstep
	lda poly_lx0+1
	cmp poly_lx1+1
	bne shapes_pg_lstep
	lda poly_ly0
	cmp poly_ly1
	bne shapes_pg_lstep
	lda poly_ly0+1
	cmp poly_ly1+1
	bne shapes_pg_lstep
	rts
shapes_pg_lstep
	lda poly_lerr               ; e2 = 2 * err
	asl
	sta poly_le2
	lda poly_lerr+1
	rol
	sta poly_le2+1
	sec                         ; e2 >= dy ?  err += dy, x0 += sx
	lda poly_le2
	sbc poly_ldy
	lda poly_le2+1
	sbc poly_ldy+1
	bvc shapes_pg_lnv1
	eor #$80
shapes_pg_lnv1
	bmi shapes_pg_lskx
	clc
	lda poly_lerr
	adc poly_ldy
	sta poly_lerr
	lda poly_lerr+1
	adc poly_ldy+1
	sta poly_lerr+1
	clc
	lda poly_lx0
	adc poly_lsx
	sta poly_lx0
	lda poly_lx0+1
	adc poly_lsx+1
	sta poly_lx0+1
shapes_pg_lskx
	sec                         ; e2 <= dx ?  err += dx, y0 += sy
	lda poly_ldx
	sbc poly_le2
	lda poly_ldx+1
	sbc poly_le2+1
	bvc shapes_pg_lnv2
	eor #$80
shapes_pg_lnv2
	bmi shapes_pg_lsky
	clc
	lda poly_lerr
	adc poly_ldx
	sta poly_lerr
	lda poly_lerr+1
	adc poly_ldx+1
	sta poly_lerr+1
	clc
	lda poly_ly0
	adc poly_lsy
	sta poly_ly0
	lda poly_ly0+1
	adc poly_lsy+1
	sta poly_ly0+1
shapes_pg_lsky
	jmp shapes_pg_lloop

; --- fill ------------------------------------------------------------
; one scanline at a time; shapes_poly_scanline gathers the row's span and draws
; it, shapes_poly_edge does the per-edge crossing. Kept apart so every branch
; stays in range and each routine owns its own zone-local labels.
shapes_poly_fill
	jsr shapes_poly_ybounds           ; poly_ymin / poly_ymax over all vertices
	lda poly_ymin
	sta poly_y
	lda poly_ymin+1
	sta poly_y+1
shapes_pg_floop
	lda poly_ymax               ; y > ymax ? done
	cmp poly_y
	lda poly_ymax+1
	sbc poly_y+1
	bvc shapes_pg_fl1
	eor #$80
shapes_pg_fl1
	bmi shapes_pg_fret                ; ymax < y
	jsr shapes_poly_scanline
	inc poly_y
	bne shapes_pg_floop
	inc poly_y+1
	bra shapes_pg_floop
shapes_pg_fret
	rts

; fill row poly_y: find the span (xl..xr) across the edges, draw it
shapes_poly_scanline
	stz poly_found
	lda #$FF                    ; xl = +32767, xr = -32768
	sta poly_xl
	lda #$7F
	sta poly_xl+1
	stz poly_xr
	lda #$80
	sta poly_xr+1
	stz poly_i
shapes_pg_slloop
	lda poly_i
	cmp poly_n
	beq shapes_pg_sldraw
	jsr shapes_poly_edge
	inc poly_i
	bra shapes_pg_slloop
shapes_pg_sldraw
	lda poly_found
	beq shapes_pg_slret
	lda poly_xl                 ; span (xl .. xr) on row y
	sta X16_P0
	lda poly_xl+1
	sta X16_P1
	lda poly_y
	sta X16_P2
	lda poly_y+1
	sta X16_P3
	sec                         ; len = xr - xl + 1
	lda poly_xr
	sbc poly_xl
	sta X16_P4
	lda poly_xr+1
	sbc poly_xl+1
	sta X16_P5
	inc X16_P4
	bne shapes_pg_sllen
	inc X16_P5
shapes_pg_sllen
	lda poly_col
	jmp SHP_HLINE
shapes_pg_slret
	rts

; edge poly_i crossing row poly_y: if it spans the row, fold its x into
; poly_xl (min) / poly_xr (max) and set poly_found
shapes_poly_edge
	lda poly_i                  ; vertex a = i
	asl
	tax
	lda poly_i                  ; vertex b = (i+1) mod n
	clc
	adc #1
	cmp poly_n
	bne shapes_pg_ejok
	lda #0
shapes_pg_ejok
	asl
	tay
	lda poly_vx,x
	sta poly_xa
	lda poly_vx+1,x
	sta poly_xa+1
	lda poly_vy,x
	sta poly_ya
	lda poly_vy+1,x
	sta poly_ya+1
	lda poly_vx,y
	sta poly_xb
	lda poly_vx+1,y
	sta poly_xb+1
	lda poly_vy,y
	sta poly_yb
	lda poly_vy+1,y
	sta poly_yb+1
	lda poly_ya                 ; top = the smaller-y endpoint
	cmp poly_yb
	lda poly_ya+1
	sbc poly_yb+1
	bvc shapes_pg_escab
	eor #$80
shapes_pg_escab
	bmi shapes_pg_eatop               ; ya < yb
	lda poly_xb                 ; b on top
	sta poly_xtop
	lda poly_xb+1
	sta poly_xtop+1
	lda poly_yb
	sta poly_ytop
	lda poly_yb+1
	sta poly_ytop+1
	lda poly_xa
	sta poly_xbot
	lda poly_xa+1
	sta poly_xbot+1
	lda poly_ya
	sta poly_ybot
	lda poly_ya+1
	sta poly_ybot+1
	bra shapes_pg_eedge
shapes_pg_eatop
	lda poly_xa                 ; a on top
	sta poly_xtop
	lda poly_xa+1
	sta poly_xtop+1
	lda poly_ya
	sta poly_ytop
	lda poly_ya+1
	sta poly_ytop+1
	lda poly_xb
	sta poly_xbot
	lda poly_xb+1
	sta poly_xbot+1
	lda poly_yb
	sta poly_ybot
	lda poly_yb+1
	sta poly_ybot+1
shapes_pg_eedge
	lda poly_y                  ; y < ytop ? out (also skips horizontals)
	cmp poly_ytop
	lda poly_y+1
	sbc poly_ytop+1
	bvc shapes_pg_esct
	eor #$80
shapes_pg_esct
	bmi shapes_pg_eout
	lda poly_y                  ; y >= ybot ? out (half-open bottom)
	cmp poly_ybot
	lda poly_y+1
	sbc poly_ybot+1
	bvc shapes_pg_escb
	eor #$80
shapes_pg_escb
	bpl shapes_pg_eout
	bra shapes_pg_ein
shapes_pg_eout
	rts
shapes_pg_ein
	sec                         ; md3 = dy = ybot - ytop  (> 0)
	lda poly_ybot
	sbc poly_ytop
	sta poly_md3
	lda poly_ybot+1
	sbc poly_ytop+1
	sta poly_md3+1
	sec                         ; md2 = t = y - ytop
	lda poly_y
	sbc poly_ytop
	sta poly_md2
	lda poly_y+1
	sbc poly_ytop+1
	sta poly_md2+1
	sec                         ; md1 = dx = xbot - xtop (signed)
	lda poly_xbot
	sbc poly_xtop
	sta poly_md1
	lda poly_xbot+1
	sbc poly_xtop+1
	sta poly_md1+1
	stz poly_dxs
	lda poly_md1+1
	bpl shapes_pg_edxpos
	inc poly_dxs                ; dx < 0: take |dx|, remember the sign
	sec
	lda #0
	sbc poly_md1
	sta poly_md1
	lda #0
	sbc poly_md1+1
	sta poly_md1+1
shapes_pg_edxpos
	jsr shapes_poly_umuldiv           ; poly_mdq = |dx| * t / dy
	lda poly_dxs
	bne shapes_pg_exneg
	clc                         ; x = xtop + mdq
	lda poly_xtop
	adc poly_mdq
	sta poly_x
	lda poly_xtop+1
	adc poly_mdq+1
	sta poly_x+1
	bra shapes_pg_egotx
shapes_pg_exneg
	sec                         ; x = xtop - mdq
	lda poly_xtop
	sbc poly_mdq
	sta poly_x
	lda poly_xtop+1
	sbc poly_mdq+1
	sta poly_x+1
shapes_pg_egotx
	lda #1
	sta poly_found
	lda poly_x                  ; xl = min(xl, x)
	cmp poly_xl
	lda poly_x+1
	sbc poly_xl+1
	bvc shapes_pg_escl
	eor #$80
shapes_pg_escl
	bpl shapes_pg_enoxl               ; x >= xl
	lda poly_x
	sta poly_xl
	lda poly_x+1
	sta poly_xl+1
shapes_pg_enoxl
	lda poly_xr                 ; xr = max(xr, x)
	cmp poly_x
	lda poly_xr+1
	sbc poly_x+1
	bvc shapes_pg_escr
	eor #$80
shapes_pg_escr
	bpl shapes_pg_enoxr               ; xr >= x
	lda poly_x
	sta poly_xr
	lda poly_x+1
	sta poly_xr+1
shapes_pg_enoxr
	rts

; poly_ymin / poly_ymax = the y extent of the vertices
shapes_poly_ybounds
	lda poly_vy
	sta poly_ymin
	sta poly_ymax
	lda poly_vy+1
	sta poly_ymin+1
	sta poly_ymax+1
	lda #1
	sta poly_i
shapes_pg_ybloop
	lda poly_i
	cmp poly_n
	beq shapes_pg_ybend
	asl
	tax
	lda poly_vy,x               ; vy[i] < ymin ?
	cmp poly_ymin
	lda poly_vy+1,x
	sbc poly_ymin+1
	bvc shapes_pg_ybc1
	eor #$80
shapes_pg_ybc1
	bpl shapes_pg_ybnmin
	lda poly_vy,x
	sta poly_ymin
	lda poly_vy+1,x
	sta poly_ymin+1
shapes_pg_ybnmin
	lda poly_ymax               ; vy[i] > ymax ?
	cmp poly_vy,x
	lda poly_ymax+1
	sbc poly_vy+1,x
	bvc shapes_pg_ybc2
	eor #$80
shapes_pg_ybc2
	bpl shapes_pg_ybnmax
	lda poly_vy,x
	sta poly_ymax
	lda poly_vy+1,x
	sta poly_ymax+1
shapes_pg_ybnmax
	inc poly_i
	bra shapes_pg_ybloop
shapes_pg_ybend
	rts

; poly_mdq = poly_md1 * poly_md2 / poly_md3, all unsigned (16x16->32, /16)
shapes_poly_umuldiv
	stz poly_prod+2
	stz poly_prod+3
	ldx #16
shapes_pg_uml
	lsr poly_md2+1
	ror poly_md2
	bcc shapes_pg_unoadd
	lda poly_prod+2
	clc
	adc poly_md1
	sta poly_prod+2
	lda poly_prod+3
	adc poly_md1+1
	bra shapes_pg_urot
shapes_pg_unoadd
	lda poly_prod+3
shapes_pg_urot
	ror
	sta poly_prod+3
	ror poly_prod+2
	ror poly_prod+1
	ror poly_prod
	dex
	bne shapes_pg_uml
	stz poly_rem
	stz poly_rem+1
	ldx #32
shapes_pg_udv
	asl poly_prod
	rol poly_prod+1
	rol poly_prod+2
	rol poly_prod+3
	rol poly_rem
	rol poly_rem+1
	sec
	lda poly_rem
	sbc poly_md3
	tay
	lda poly_rem+1
	sbc poly_md3+1
	bcc shapes_pg_udvno
	sta poly_rem+1
	sty poly_rem
	inc poly_prod
shapes_pg_udvno
	dex
	bne shapes_pg_udv
	lda poly_prod
	sta poly_mdq
	lda poly_prod+1
	sta poly_mdq+1
	rts

; --- polygon state ---------------------------------------------------
poly_col   .byte 0
poly_efl   .byte 0
poly_cx    .word 0
poly_cy    .word 0
poly_r     .byte 0
poly_n     .byte 0
poly_i     .byte 0
poly_acc   .word 0
poly_step  .word 0
poly_off   .word 0
poly_sgn   .byte 0
poly_p16   .word 0
poly_t     .byte 0
poly_dvd   .res 3, 0
poly_rem   .word 0
poly_vx    .res POLY_MAX * 2, 0
poly_vy    .res POLY_MAX * 2, 0

poly_lx0   .word 0
poly_ly0   .word 0
poly_lx1   .word 0
poly_ly1   .word 0
poly_ldx   .word 0
poly_ldy   .word 0
poly_lerr  .word 0
poly_le2   .word 0
poly_lsx   .word 0
poly_lsy   .word 0
poly_lt    .word 0

poly_ymin  .word 0
poly_ymax  .word 0
poly_y     .word 0
poly_found .byte 0
poly_xa    .word 0
poly_ya    .word 0
poly_xb    .word 0
poly_yb    .word 0
poly_xtop  .word 0
poly_ytop  .word 0
poly_xbot  .word 0
poly_ybot  .word 0
poly_x     .word 0
poly_xl    .word 0
poly_xr    .word 0
poly_dxs   .byte 0
poly_md1   .word 0
poly_md2   .word 0
poly_md3   .word 0
poly_mdq   .word 0
poly_prod  .res 4, 0

.endif

; ---------------------------------------------------------------------
; shp_line -- shared 16-bit Bresenham (X16_USE_SHP_LINE)
; ---------------------------------------------------------------------
; The curve shapes (arc, bezier) sample a handful of points and join
; them; this is the join. It is the same engine-agnostic gfx2h_line walk
; the polygon carries privately (shapes_poly_line), lifted out so arc and
; bezier share ONE copy behind their own gate. A program that wants only
; the polygon still pays nothing for this; one that wants an arc pays for
; it once, not once per curve.
;
;   in: shl_x0/shl_y0 -> shl_x1/shl_y1 (signed words), shl_col = colour
;       draws through SHP_PSET, so it clips wherever pset clips.
; ---------------------------------------------------------------------
.ifdef X16_USE_SHP_LINE

shp_line
	sec                         ; dx = |x1 - x0|, sx = direction
	lda shl_x1
	sbc shl_x0
	sta shl_dx
	lda shl_x1+1
	sbc shl_x0+1
	sta shl_dx+1
	bpl shapes_sl_dxp
	sec
	lda #0
	sbc shl_dx
	sta shl_dx
	lda #0
	sbc shl_dx+1
	sta shl_dx+1
	lda #$FF
	sta shl_sx
	sta shl_sx+1
	bra shapes_sl_dxd
shapes_sl_dxp
	lda #1
	sta shl_sx
	stz shl_sx+1
shapes_sl_dxd
	sec                         ; dy = -|y1 - y0|, sy = direction
	lda shl_y1
	sbc shl_y0
	sta shl_t
	lda shl_y1+1
	sbc shl_y0+1
	sta shl_t+1
	bpl shapes_sl_dyp
	sec
	lda #0
	sbc shl_t
	sta shl_t
	lda #0
	sbc shl_t+1
	sta shl_t+1
	lda #$FF
	sta shl_sy
	sta shl_sy+1
	bra shapes_sl_dyd
shapes_sl_dyp
	lda #1
	sta shl_sy
	stz shl_sy+1
shapes_sl_dyd
	sec                         ; dy stored negative
	lda #0
	sbc shl_t
	sta shl_dy
	lda #0
	sbc shl_t+1
	sta shl_dy+1
	clc                         ; err = dx + dy
	lda shl_dx
	adc shl_dy
	sta shl_err
	lda shl_dx+1
	adc shl_dy+1
	sta shl_err+1
shapes_sl_loop
	lda shl_x0
	sta X16_P0
	lda shl_x0+1
	sta X16_P1
	lda shl_y0
	sta X16_P2
	lda shl_y0+1
	sta X16_P3
	lda shl_col
	jsr SHP_PSET
	lda shl_x0                  ; reached the endpoint?
	cmp shl_x1
	bne shapes_sl_step
	lda shl_x0+1
	cmp shl_x1+1
	bne shapes_sl_step
	lda shl_y0
	cmp shl_y1
	bne shapes_sl_step
	lda shl_y0+1
	cmp shl_y1+1
	bne shapes_sl_step
	rts
shapes_sl_step
	lda shl_err                 ; e2 = 2 * err
	asl
	sta shl_e2
	lda shl_err+1
	rol
	sta shl_e2+1
	sec                         ; e2 >= dy ?  err += dy, x0 += sx
	lda shl_e2
	sbc shl_dy
	lda shl_e2+1
	sbc shl_dy+1
	bvc shapes_sl_nv1
	eor #$80
shapes_sl_nv1
	bmi shapes_sl_skx
	clc
	lda shl_err
	adc shl_dy
	sta shl_err
	lda shl_err+1
	adc shl_dy+1
	sta shl_err+1
	clc
	lda shl_x0
	adc shl_sx
	sta shl_x0
	lda shl_x0+1
	adc shl_sx+1
	sta shl_x0+1
shapes_sl_skx
	sec                         ; e2 <= dx ?  err += dx, y0 += sy
	lda shl_dx
	sbc shl_e2
	lda shl_dx+1
	sbc shl_e2+1
	bvc shapes_sl_nv2
	eor #$80
shapes_sl_nv2
	bmi shapes_sl_sky
	clc
	lda shl_err
	adc shl_dx
	sta shl_err
	lda shl_err+1
	adc shl_dx+1
	sta shl_err+1
	clc
	lda shl_y0
	adc shl_sy
	sta shl_y0
	lda shl_y0+1
	adc shl_sy+1
	sta shl_y0+1
shapes_sl_sky
	jmp shapes_sl_loop

shl_x0  .word 0
shl_y0  .word 0
shl_x1  .word 0
shl_y1  .word 0
shl_col .byte 0
shl_dx  .word 0
shl_dy  .word 0
shl_sx  .word 0
shl_sy  .word 0
shl_err .word 0
shl_e2  .word 0
shl_t   .word 0

.endif

; ---------------------------------------------------------------------
; shape_rrect / shape_frrect -- rounded rectangle (X16_USE_SHAPES_RRECT)
; ---------------------------------------------------------------------
; A rectangle with quarter-circle corners. Self-contained: the corners
; come from a midpoint circle walk (no trig, no MATH dependency), the
; straight runs from SHP_HLINE / SHP_PSET.
;
;   in: rr_x/rr_y = top-left corner (signed words),
;       rr_w/rr_h = width / height (words, >= 1),
;       rr_r      = corner radius (0-255, clamped to min(w,h)/2),
;       A         = colour
;
; shape_rrect draws the outline through SHP_PSET (so it clips like
; shape_circle); shape_frrect fills it with SHP_HLINE spans (so it does
; NOT clip -- keep it on screen, like shape_disc). r = 0 degenerates to
; a plain rectangle.
;
; The fill precomputes rr_ext[d] = the corner's horizontal half-extent at
; vertical offset d (0..r) once, then draws one span per row: full width
; in the straight middle band, inset by rr_ext[d] through the rounded
; top and bottom bands.
; ---------------------------------------------------------------------
.ifdef X16_USE_SHAPES_RRECT

shape_rrect
	sta rr_col
	stz rr_fl
	jmp shapes_rr_begin
shape_frrect
	sta rr_col
	lda #1
	sta rr_fl
shapes_rr_begin
	lda rr_x                    ; corner reference points:
	sta rr_x0                   ;   x0 = x, x1 = x + w - 1
	lda rr_x+1
	sta rr_x0+1
	clc
	lda rr_x
	adc rr_w
	sta rr_x1
	lda rr_x+1
	adc rr_w+1
	sta rr_x1+1
	lda rr_x1                   ; x1 -= 1
	bne :+
	dec rr_x1+1
:	dec rr_x1
	lda rr_y                    ;   y0 = y, y1 = y + h - 1
	sta rr_y0
	lda rr_y+1
	sta rr_y0+1
	clc
	lda rr_y
	adc rr_h
	sta rr_y1
	lda rr_y+1
	adc rr_h+1
	sta rr_y1+1
	lda rr_y1                   ; y1 -= 1
	bne :+
	dec rr_y1+1
:	dec rr_y1

	jsr shapes_rr_clampr              ; rr_r = min(rr_r, min(w,h)/2)
	lda rr_x0                   ; corner centres:
	clc                         ;   cxl = x0 + r, cxr = x1 - r
	adc rr_r
	sta rr_cxl
	lda rr_x0+1
	adc #0
	sta rr_cxl+1
	sec
	lda rr_x1
	sbc rr_r
	sta rr_cxr
	lda rr_x1+1
	sbc #0
	sta rr_cxr+1
	lda rr_y0                   ;   cyt = y0 + r, cyb = y1 - r
	clc
	adc rr_r
	sta rr_cyt
	lda rr_y0+1
	adc #0
	sta rr_cyt+1
	sec
	lda rr_y1
	sbc rr_r
	sta rr_cyb
	lda rr_y1+1
	sbc #0
	sta rr_cyb+1

	lda rr_fl
	beq shapes_rr_out
	jmp shapes_rr_fill
shapes_rr_out
	jmp shapes_rr_outline

; rr_r = min(rr_r, min(rr_w, rr_h) / 2)
shapes_rr_clampr
	lda rr_w                    ; m = min(w, h)  (16-bit unsigned)
	sta rr_m
	lda rr_w+1
	sta rr_m+1
	lda rr_h+1
	cmp rr_m+1
	bcc shapes_rr_cmh
	bne shapes_rr_cmok
	lda rr_h
	cmp rr_m
	bcs shapes_rr_cmok
shapes_rr_cmh
	lda rr_h
	sta rr_m
	lda rr_h+1
	sta rr_m+1
shapes_rr_cmok
	lsr rr_m+1                  ; m /= 2
	ror rr_m
	lda rr_m+1                  ; m >= 256 ? radius already fits any byte
	bne shapes_rr_crok
	lda rr_r                    ; r > m ? clamp to m
	cmp rr_m
	bcc shapes_rr_crok
	lda rr_m
	sta rr_r
shapes_rr_crok
	rts

; --- outline ---------------------------------------------------------
shapes_rr_outline
	jsr shapes_rr_corners             ; the four quarter-circle corners
	; top edge: (cxl, y0) .. (cxr, y0)
	lda rr_cxl
	sta X16_P0
	lda rr_cxl+1
	sta X16_P1
	lda rr_y0
	sta X16_P2
	lda rr_y0+1
	sta X16_P3
	jsr shapes_rr_hspan               ; pset run from P0 to cxr on row P2/P3
	; bottom edge: (cxl, y1) .. (cxr, y1)
	lda rr_cxl
	sta X16_P0
	lda rr_cxl+1
	sta X16_P1
	lda rr_y1
	sta X16_P2
	lda rr_y1+1
	sta X16_P3
	jsr shapes_rr_hspan
	; left edge: column x0, rows cyt..cyb
	lda rr_x0
	sta X16_P0
	lda rr_x0+1
	sta X16_P1
	jsr shapes_rr_vspan
	; right edge: column x1, rows cyt..cyb
	lda rr_x1
	sta X16_P0
	lda rr_x1+1
	sta X16_P1
	jsr shapes_rr_vspan
	rts

; pset a horizontal run from (P0/P1) to x=rr_cxr on the row in P2/P3
shapes_rr_hspan
	sec                         ; empty run when cxr < cxl (r reaches w/2):
	lda rr_cxr                  ; the rounded ends meet, no straight top/bottom
	sbc rr_cxl
	lda rr_cxr+1
	sbc rr_cxl+1
	bvc :+
	eor #$80
:	bmi shapes_rr_hsd
	lda X16_P2                  ; hold the row (pset reloads P0..P3)
	sta rr_ry
	lda X16_P3
	sta rr_ry+1
shapes_rr_hsl
	lda rr_ry
	sta X16_P2
	lda rr_ry+1
	sta X16_P3
	lda rr_col
	jsr SHP_PSET
	lda X16_P0                  ; at cxr ?
	cmp rr_cxr
	bne shapes_rr_hsn
	lda X16_P1
	cmp rr_cxr+1
	beq shapes_rr_hsd
shapes_rr_hsn
	inc X16_P0
	bne shapes_rr_hsl
	inc X16_P1
	bra shapes_rr_hsl
shapes_rr_hsd
	rts

; pset a vertical run on column (P0/P1) from y=rr_cyt to y=rr_cyb
shapes_rr_vspan
	sec                         ; empty run when cyb < cyt (r reaches h/2):
	lda rr_cyb                  ; the rounded ends meet, no straight sides
	sbc rr_cyt
	lda rr_cyb+1
	sbc rr_cyt+1
	bvc :+
	eor #$80
:	bmi shapes_rr_vsd
	lda X16_P0
	sta rr_rx
	lda X16_P1
	sta rr_rx+1
	lda rr_cyt
	sta X16_P2
	lda rr_cyt+1
	sta X16_P3
shapes_rr_vsl
	lda rr_rx
	sta X16_P0
	lda rr_rx+1
	sta X16_P1
	lda rr_col
	jsr SHP_PSET
	lda X16_P2                  ; at cyb ?
	cmp rr_cyb
	bne shapes_rr_vsn
	lda X16_P3
	cmp rr_cyb+1
	beq shapes_rr_vsd
shapes_rr_vsn
	inc X16_P2
	bne shapes_rr_vsl
	inc X16_P3
	bra shapes_rr_vsl
shapes_rr_vsd
	rts

; walk the quarter circle once; each octant point plots at all 4 corners
shapes_rr_corners
	lda rr_r                    ; x = r, y = 0, err = 1 - r
	sta rr_wx
	stz rr_wy
	sec
	lda #1
	sbc rr_r
	sta rr_werr
	lda #0
	sbc #0
	sta rr_werr+1
shapes_rr_cwl
	lda rr_wy                   ; while y <= x
	cmp rr_wx
	beq shapes_rr_cwp
	bcs shapes_rr_cwd
shapes_rr_cwp
	lda rr_wx                   ; plot (a,b) = (x,y) and (y,x) at 4 corners
	sta rr_ca
	lda rr_wy
	sta rr_cb
	jsr shapes_rr_c4
	lda rr_wy
	sta rr_ca
	lda rr_wx
	sta rr_cb
	jsr shapes_rr_c4
	jsr shapes_rr_wstep
	bra shapes_rr_cwl
shapes_rr_cwd
	rts

; plot (a,b) offsets at the four corner centres
shapes_rr_c4
	sec                         ; TL: (cxl - a, cyt - b)
	lda rr_cxl
	sbc rr_ca
	sta X16_P0
	lda rr_cxl+1
	sbc #0
	sta X16_P1
	sec
	lda rr_cyt
	sbc rr_cb
	sta X16_P2
	lda rr_cyt+1
	sbc #0
	sta X16_P3
	lda rr_col
	jsr SHP_PSET
	clc                         ; TR: (cxr + a, cyt - b)
	lda rr_cxr
	adc rr_ca
	sta X16_P0
	lda rr_cxr+1
	adc #0
	sta X16_P1
	sec
	lda rr_cyt
	sbc rr_cb
	sta X16_P2
	lda rr_cyt+1
	sbc #0
	sta X16_P3
	lda rr_col
	jsr SHP_PSET
	sec                         ; BL: (cxl - a, cyb + b)
	lda rr_cxl
	sbc rr_ca
	sta X16_P0
	lda rr_cxl+1
	sbc #0
	sta X16_P1
	clc
	lda rr_cyb
	adc rr_cb
	sta X16_P2
	lda rr_cyb+1
	adc #0
	sta X16_P3
	lda rr_col
	jsr SHP_PSET
	clc                         ; BR: (cxr + a, cyb + b)
	lda rr_cxr
	adc rr_ca
	sta X16_P0
	lda rr_cxr+1
	adc #0
	sta X16_P1
	clc
	lda rr_cyb
	adc rr_cb
	sta X16_P2
	lda rr_cyb+1
	adc #0
	sta X16_P3
	lda rr_col
	jmp SHP_PSET

; midpoint error walk shared by shapes_rr_corners and the fill's table build
shapes_rr_wstep
	inc rr_wy
	bit rr_werr+1
	bmi shapes_rr_wgrow
	dec rr_wx
	sec                         ; t = y - x
	lda rr_wy
	sbc rr_wx
	sta rr_wt
	lda #0
	sbc #0
	sta rr_wt+1
	bra shapes_rr_wap
shapes_rr_wgrow
	lda rr_wy                   ; t = y
	sta rr_wt
	lda #0
	sta rr_wt+1
shapes_rr_wap
	asl rr_wt                   ; err += 2t + 1
	rol rr_wt+1
	inc rr_wt
	bne :+
	inc rr_wt+1
:	clc
	lda rr_werr
	adc rr_wt
	sta rr_werr
	lda rr_werr+1
	adc rr_wt+1
	sta rr_werr+1
	rts

; --- fill ------------------------------------------------------------
shapes_rr_fill
	jsr shapes_rr_build               ; rr_ext[0..r] = corner half-extents
	lda rr_y0                   ; row = y0
	sta rr_ry
	lda rr_y0+1
	sta rr_ry+1
shapes_rr_fl
	lda rr_y1                   ; row > y1 ? done
	cmp rr_ry
	lda rr_y1+1
	sbc rr_ry+1
	bvc :+
	eor #$80
:	bmi shapes_rr_fld
	jsr shapes_rr_row
	inc rr_ry
	bne shapes_rr_fl
	inc rr_ry+1
	bra shapes_rr_fl
shapes_rr_fld
	rts

; draw the one span for row rr_ry: full width in the middle band, inset
; by rr_ext[d] in the rounded top/bottom bands
shapes_rr_row
	lda rr_ry                   ; row < cyt ?  top rounded band, d = cyt-row
	cmp rr_cyt
	lda rr_ry+1
	sbc rr_cyt+1
	bvc :+
	eor #$80
:	bmi shapes_rr_rtop
	lda rr_cyb                  ; row > cyb ?  bottom band, d = row-cyb
	cmp rr_ry
	lda rr_cyb+1
	sbc rr_ry+1
	bvc :+
	eor #$80
:	bmi shapes_rr_rbot
	ldx #0                      ; middle band: d = 0, ext[0] = r -> full width
	beq shapes_rr_inset               ; (always: ldx #0 set Z)
shapes_rr_rtop
	sec                         ; d = cyt - row (1..r)
	lda rr_cyt
	sbc rr_ry
	tax
	bra shapes_rr_inset
shapes_rr_rbot
	sec                         ; d = row - cyb (1..r)
	lda rr_ry
	sbc rr_cyb
	tax
shapes_rr_inset
	lda rr_ext,x                ; ins = rr_ext[d]
	sta rr_ins
	stz rr_ins+1
	sec                         ; P0 = left = cxl - ins
	lda rr_cxl
	sbc rr_ins
	sta X16_P0
	lda rr_cxl+1
	sbc #0
	sta X16_P1
	lda rr_ry                   ; row
	sta X16_P2
	lda rr_ry+1
	sta X16_P3
	clc                         ; right = cxr + ins  -> T0
	lda rr_cxr
	adc rr_ins
	sta X16_T0
	lda rr_cxr+1
	adc rr_ins+1
	sta X16_T0+1
	sec                         ; len = right - left + 1
	lda X16_T0
	sbc X16_P0
	sta X16_P4
	lda X16_T0+1
	sbc X16_P1
	sta X16_P5
	inc X16_P4
	bne :+
	inc X16_P5
:	lda rr_col
	jmp SHP_HLINE

; rr_ext[d] = corner half-extent at vertical offset d, for d = 0..r
shapes_rr_build
	ldx #0                      ; zero rr_ext[0..255]
	lda #0
shapes_rr_bz
	sta rr_ext,x
	inx
	bne shapes_rr_bz
	lda rr_r                    ; ext[0] = r
	sta rr_ext
	lda rr_r                    ; walk the quarter circle
	sta rr_wx
	stz rr_wy
	sec
	lda #1
	sbc rr_r
	sta rr_werr
	lda #0
	sbc #0
	sta rr_werr+1
shapes_rr_bwl
	lda rr_wy                   ; while y <= x
	cmp rr_wx
	beq shapes_rr_bwp
	bcs shapes_rr_bwd
shapes_rr_bwp
	ldx rr_wy                   ; ext[y] = max(ext[y], x)
	lda rr_wx
	cmp rr_ext,x
	bcc :+
	sta rr_ext,x
:	ldx rr_wx                   ; ext[x] = max(ext[x], y)
	lda rr_wy
	cmp rr_ext,x
	bcc :+
	sta rr_ext,x
:	jsr shapes_rr_wstep
	bra shapes_rr_bwl
shapes_rr_bwd
	rts

; --- rounded-rect state ----------------------------------------------
rr_x    .word 0
rr_y    .word 0
rr_w    .word 0
rr_h    .word 0
rr_r    .byte 0
rr_col  .byte 0
rr_fl   .byte 0
rr_x0   .word 0
rr_y0   .word 0
rr_x1   .word 0
rr_y1   .word 0
rr_cxl  .word 0
rr_cxr  .word 0
rr_cyt  .word 0
rr_cyb  .word 0
rr_m    .word 0
rr_ry   .word 0
rr_rx   .word 0
rr_ins  .word 0
rr_ca   .byte 0
rr_cb   .byte 0
rr_wx   .byte 0
rr_wy   .byte 0
rr_werr .word 0
rr_wt   .word 0
rr_ext  .res 256, 0

.endif

; ---------------------------------------------------------------------
; shape_arc -- a portion of a circle outline (X16_USE_SHAPES_ARC)
; ---------------------------------------------------------------------
; The arc runs from byte-angle `start` to `end`, increasing (0 = east,
; 64 = south, 128 = west, 192 = north -- the sin8/cos8, screen-y-down
; convention shared with the polygon). It is sampled every ~4 byte-angle
; units and the samples are joined with shp_line, so the chord error is
; under a third of a pixel even at r = 255 and the arc clips wherever
; SHP_PSET clips. When start == end the whole circle is drawn.
;
;   in: P0/P1 = cx, P2/P3 = cy, P4 = r (0-255),
;       P5 = start angle, P6 = end angle, A = colour
;
; shapes_arc_point / shapes_arc_scale place a sample the same way the polygon places
; a vertex (r * cos8/sin8 / 128, rounded); shape_pie reuses them, which
; is why they live in this gate and PIE depends on ARC.
; ---------------------------------------------------------------------
.ifdef X16_USE_SHAPES_ARC

ARC_STEP = 4                    ; byte-angle units between samples

shape_arc
	sta shl_col                 ; shp_line draws in this colour
	lda X16_P0
	sta arc_cx
	lda X16_P1
	sta arc_cx+1
	lda X16_P2
	sta arc_cy
	lda X16_P3
	sta arc_cy+1
	lda X16_P4
	sta arc_r
	lda X16_P5
	sta arc_a0
	sec                         ; span = (end - start) & 255; 0 -> 256
	lda X16_P6
	sbc arc_a0
	sta arc_span
	stz arc_span+1
	lda arc_span
	bne shapes_ar_have
	inc arc_span+1
shapes_ar_have
	lda arc_a0                  ; first sample -> shl_x0/y0 (prev point)
	jsr shapes_arc_point
	lda arc_px
	sta shl_x0
	lda arc_px+1
	sta shl_x0+1
	lda arc_py
	sta shl_y0
	lda arc_py+1
	sta shl_y0+1
	lda arc_a0
	sta arc_ang
shapes_ar_loop
	lda arc_span+1              ; step = min(ARC_STEP, span)
	bne shapes_ar_full
	lda arc_span
	cmp #ARC_STEP
	bcc shapes_ar_last
shapes_ar_full
	lda #ARC_STEP
	sta arc_step
	bra shapes_ar_adv
shapes_ar_last
	lda arc_span
	sta arc_step
shapes_ar_adv
	clc                         ; ang = (ang + step) mod 256
	lda arc_ang
	adc arc_step
	sta arc_ang
	sec                         ; span -= step
	lda arc_span
	sbc arc_step
	sta arc_span
	lda arc_span+1
	sbc #0
	sta arc_span+1
	lda arc_ang                 ; this sample -> shl_x1/y1
	jsr shapes_arc_point
	lda arc_px
	sta shl_x1
	lda arc_px+1
	sta shl_x1+1
	lda arc_py
	sta shl_y1
	lda arc_py+1
	sta shl_y1+1
	jsr shp_line
	lda shl_x1                  ; cur -> prev for the next segment
	sta shl_x0
	lda shl_x1+1
	sta shl_x0+1
	lda shl_y1
	sta shl_y0
	lda shl_y1+1
	sta shl_y0+1
	lda arc_span                ; span exhausted ? done
	ora arc_span+1
	bne shapes_ar_loop
	rts

; sample at byte-angle A -> (arc_px, arc_py)
shapes_arc_point
	pha
	jsr cos8                    ; A = cos * 127 (signed)
	jsr shapes_arc_scale              ; arc_off = round(r * A / 128)
	clc
	lda arc_cx
	adc arc_off
	sta arc_px
	lda arc_cx+1
	adc arc_off+1
	sta arc_px+1
	pla
	jsr sin8                    ; A = sin * 127 (signed)
	jsr shapes_arc_scale
	clc
	lda arc_cy
	adc arc_off
	sta arc_py
	lda arc_cy+1
	adc arc_off+1
	sta arc_py+1
	rts

; arc_off = round(arc_r * |A| / 128) with A's sign (A a signed byte)
shapes_arc_scale
	stz arc_sgn
	pha
	and #$80
	beq shapes_as_pos
	inc arc_sgn
	pla
	eor #$FF
	clc
	adc #1
	bra shapes_as_mul
shapes_as_pos
	pla
shapes_as_mul
	jsr shapes_arc_mul8               ; arc_p16 = arc_r * |A|
	clc
	lda arc_p16                 ; + 0.5 LSB so >>7 rounds
	adc #64
	sta arc_p16
	lda arc_p16+1
	adc #0
	sta arc_p16+1
	lda arc_p16                 ; >>7 (product < 32768, one byte out)
	asl
	lda arc_p16+1
	rol
	sta arc_off
	stz arc_off+1
	lda arc_sgn
	beq shapes_as_done
	sec                         ; negate
	lda #0
	sbc arc_off
	sta arc_off
	lda #0
	sbc arc_off+1
	sta arc_off+1
shapes_as_done
	rts

; arc_p16 = arc_r * A  (8x8 -> 16, unsigned)
shapes_arc_mul8
	sta arc_t
	lda #0
	ldx #8
shapes_am_loop
	lsr arc_t
	bcc shapes_am_skip
	clc
	adc arc_r
shapes_am_skip
	ror
	ror arc_p16
	dex
	bne shapes_am_loop
	sta arc_p16+1
	rts

; --- arc state (shared with shape_pie) -------------------------------
arc_cx   .word 0
arc_cy   .word 0
arc_r    .byte 0
arc_a0   .byte 0
arc_ang  .byte 0
arc_step .byte 0
arc_span .word 0
arc_px   .word 0
arc_py   .word 0
arc_off  .word 0
arc_sgn  .byte 0
arc_p16  .word 0
arc_t    .byte 0

.endif

; ---------------------------------------------------------------------
; shape_pie -- a filled wedge from the centre to the arc (X16_USE_SHAPES_PIE)
; ---------------------------------------------------------------------
; Same arguments and angle convention as shape_arc; the region swept
; between the two radii and the arc is filled. It is built as a fan of
; thin triangles (centre, sample_i, sample_i+1) so ANY span works,
; including the reflex (> 180-degree) case a single convex scan cannot
; do; start == end fills the whole disc. The triangles share their radial
; edges, so like shape_disc it draws with SHP_HLINE (no clipping) and its
; overdraw on the shared edges is harmless. It reuses ARC's shapes_arc_point.
;
;   in: P0/P1 = cx, P2/P3 = cy, P4 = r (0-255),
;       P5 = start angle, P6 = end angle, A = colour
; ---------------------------------------------------------------------
.ifdef X16_USE_SHAPES_PIE

shape_pie
	sta pie_col
	lda X16_P0
	sta arc_cx
	lda X16_P1
	sta arc_cx+1
	lda X16_P2
	sta arc_cy
	lda X16_P3
	sta arc_cy+1
	lda X16_P4
	sta arc_r
	lda X16_P5
	sta arc_a0
	sec                         ; span = (end - start) & 255; 0 -> 256
	lda X16_P6
	sbc arc_a0
	sta arc_span
	stz arc_span+1
	lda arc_span
	bne shapes_pie_have
	inc arc_span+1
shapes_pie_have
	lda arc_a0                  ; prev = sample(start)
	jsr shapes_arc_point
	lda arc_px
	sta pie_prevx
	lda arc_px+1
	sta pie_prevx+1
	lda arc_py
	sta pie_prevy
	lda arc_py+1
	sta pie_prevy+1
	lda arc_a0
	sta arc_ang
shapes_pie_loop
	lda arc_span+1              ; step = min(ARC_STEP, span)
	bne shapes_pie_full
	lda arc_span
	cmp #ARC_STEP
	bcc shapes_pie_last
shapes_pie_full
	lda #ARC_STEP
	sta arc_step
	bra shapes_pie_adv
shapes_pie_last
	lda arc_span
	sta arc_step
shapes_pie_adv
	clc
	lda arc_ang
	adc arc_step
	sta arc_ang
	sec
	lda arc_span
	sbc arc_step
	sta arc_span
	lda arc_span+1
	sbc #0
	sta arc_span+1
	lda arc_ang                 ; cur = sample(ang)
	jsr shapes_arc_point
	lda arc_cx                  ; triangle A = centre
	sta tf_ax
	lda arc_cx+1
	sta tf_ax+1
	lda arc_cy
	sta tf_ay
	lda arc_cy+1
	sta tf_ay+1
	lda pie_prevx               ; B = prev sample
	sta tf_bx
	lda pie_prevx+1
	sta tf_bx+1
	lda pie_prevy
	sta tf_by
	lda pie_prevy+1
	sta tf_by+1
	lda arc_px                  ; C = cur sample
	sta tf_cx
	lda arc_px+1
	sta tf_cx+1
	lda arc_py
	sta tf_cy
	lda arc_py+1
	sta tf_cy+1
	jsr shapes_tf_fill
	lda arc_px                  ; prev = cur
	sta pie_prevx
	lda arc_px+1
	sta pie_prevx+1
	lda arc_py
	sta pie_prevy
	lda arc_py+1
	sta pie_prevy+1
	lda arc_span                ; span exhausted ? done
	ora arc_span+1
	beq shapes_pie_done
	jmp shapes_pie_loop
shapes_pie_done
	rts

; --- triangle scanline fill (fan primitive) --------------------------
; Fills triangle (tf_ax/ay, tf_bx/by, tf_cx/cy) in pie_col with SHP_HLINE
; spans. Sorts the vertices by y, then walks the long edge and the two
; short edges by scanline with a division-free DDA (err += |dx|; while
; err >= dy: x += sign, err -= dy). A zero-height triangle has no area
; and is skipped. Edge state is two-wide: index 0 = long, 2 = short.
shapes_tf_fill
	jsr shapes_tf_sort                ; ay <= by <= cy
	lda tf_ay                   ; ay == cy ? zero height, nothing to fill
	cmp tf_cy
	bne shapes_tf_go
	lda tf_ay+1
	cmp tf_cy+1
	bne shapes_tf_go
	rts
shapes_tf_go
	lda tf_ax                   ; long edge a -> c  (index 0)
	sta tf_isx
	lda tf_ax+1
	sta tf_isx+1
	lda tf_ay
	sta tf_isy
	lda tf_ay+1
	sta tf_isy+1
	lda tf_cx
	sta tf_iex
	lda tf_cx+1
	sta tf_iex+1
	lda tf_cy
	sta tf_iey
	lda tf_cy+1
	sta tf_iey+1
	ldx #0
	jsr shapes_tf_init
	lda tf_ay                   ; y = ay
	sta tf_y
	lda tf_ay+1
	sta tf_y+1
	sec                         ; phase 1 only if ay < by
	lda tf_ay
	sbc tf_by
	lda tf_ay+1
	sbc tf_by+1
	bvc :+
	eor #$80
:	bpl shapes_tf_p2init              ; ay >= by (flat top): skip to phase 2
	lda tf_ax                   ; short edge a -> b  (index 2)
	sta tf_isx
	lda tf_ax+1
	sta tf_isx+1
	lda tf_ay
	sta tf_isy
	lda tf_ay+1
	sta tf_isy+1
	lda tf_bx
	sta tf_iex
	lda tf_bx+1
	sta tf_iex+1
	lda tf_by
	sta tf_iey
	lda tf_by+1
	sta tf_iey+1
	ldx #2
	jsr shapes_tf_init
shapes_tf_p1loop
	sec                         ; y >= by ? phase 1 done
	lda tf_y
	sbc tf_by
	lda tf_y+1
	sbc tf_by+1
	bvc :+
	eor #$80
:	bmi shapes_tf_p1do
	jmp shapes_tf_p2init
shapes_tf_p1do
	jsr shapes_tf_emitrow
	ldx #0
	jsr shapes_tf_adv
	ldx #2
	jsr shapes_tf_adv
	inc tf_y
	bne :+
	inc tf_y+1
:	jmp shapes_tf_p1loop
shapes_tf_p2init
	lda tf_bx                   ; short edge b -> c  (index 2)
	sta tf_isx
	lda tf_bx+1
	sta tf_isx+1
	lda tf_by
	sta tf_isy
	lda tf_by+1
	sta tf_isy+1
	lda tf_cx
	sta tf_iex
	lda tf_cx+1
	sta tf_iex+1
	lda tf_cy
	sta tf_iey
	lda tf_cy+1
	sta tf_iey+1
	ldx #2
	jsr shapes_tf_init
shapes_tf_p2loop
	jsr shapes_tf_emitrow
	lda tf_y                    ; y == cy ? done (last row)
	cmp tf_cy
	bne shapes_tf_p2do
	lda tf_y+1
	cmp tf_cy+1
	bne shapes_tf_p2do
	rts
shapes_tf_p2do
	ldx #0
	jsr shapes_tf_adv
	ldx #2
	jsr shapes_tf_adv
	inc tf_y
	bne :+
	inc tf_y+1
:	jmp shapes_tf_p2loop

; sort tf_a/tf_b/tf_c by y ascending (each slot is x.w then y.w)
shapes_tf_sort
	jsr shapes_tf_cmp_ab
	bpl :+
	jsr shapes_tf_swap_ab
:	jsr shapes_tf_cmp_bc
	bpl :+
	jsr shapes_tf_swap_bc
:	jsr shapes_tf_cmp_ab
	bpl :+
	jsr shapes_tf_swap_ab
:	rts
shapes_tf_cmp_ab
	sec
	lda tf_by
	sbc tf_ay
	lda tf_by+1
	sbc tf_ay+1
	bvc :+
	eor #$80
:	rts
shapes_tf_cmp_bc
	sec
	lda tf_cy
	sbc tf_by
	lda tf_cy+1
	sbc tf_by+1
	bvc :+
	eor #$80
:	rts
shapes_tf_swap_ab
	ldx #3
shapes_tsab
	lda tf_ax,x
	ldy tf_bx,x
	sta tf_bx,x
	tya
	sta tf_ax,x
	dex
	bpl shapes_tsab
	rts
shapes_tf_swap_bc
	ldx #3
shapes_tsbc
	lda tf_bx,x
	ldy tf_cx,x
	sta tf_cx,x
	tya
	sta tf_bx,x
	dex
	bpl shapes_tsbc
	rts

; init edge X (0 long / 2 short) from (tf_isx,tf_isy) to (tf_iex,tf_iey)
shapes_tf_init
	lda tf_isx
	sta e_curx,x
	lda tf_isx+1
	sta e_curx+1,x
	sec                         ; dy = iey - isy  (>= 0)
	lda tf_iey
	sbc tf_isy
	sta e_dy,x
	lda tf_iey+1
	sbc tf_isy+1
	sta e_dy+1,x
	sec                         ; dx = iex - isx  (signed)
	lda tf_iex
	sbc tf_isx
	sta tf_edx
	lda tf_iex+1
	sbc tf_isx+1
	sta tf_edx+1
	bpl shapes_ti_pos
	sec                         ; adx = -dx, sx = -1
	lda #0
	sbc tf_edx
	sta e_adx,x
	lda #0
	sbc tf_edx+1
	sta e_adx+1,x
	lda #$FF
	sta e_sx,x
	sta e_sx+1,x
	bra shapes_ti_err
shapes_ti_pos
	lda tf_edx                  ; adx = dx, sx = +1
	sta e_adx,x
	lda tf_edx+1
	sta e_adx+1,x
	lda #1
	sta e_sx,x
	stz e_sx+1,x
shapes_ti_err
	stz e_err,x
	stz e_err+1,x
	rts

; advance edge X by one scanline (dy for this edge must be > 0)
shapes_tf_adv
	clc                         ; err += adx
	lda e_err,x
	adc e_adx,x
	sta e_err,x
	lda e_err+1,x
	adc e_adx+1,x
	sta e_err+1,x
shapes_ta_w
	sec                         ; err >= dy ?
	lda e_err,x
	sbc e_dy,x
	tay
	lda e_err+1,x
	sbc e_dy+1,x
	bcc shapes_ta_done                ; err < dy
	sta e_err+1,x               ; err -= dy
	tya
	sta e_err,x
	clc                         ; x += sx
	lda e_curx,x
	adc e_sx,x
	sta e_curx,x
	lda e_curx+1,x
	adc e_sx+1,x
	sta e_curx+1,x
	bra shapes_ta_w
shapes_ta_done
	rts

; HLINE on row tf_y between the long (index 0) and short (index 2) x's
shapes_tf_emitrow
	sec                         ; diff = short_x - long_x
	lda e_curx+2
	sbc e_curx
	sta tf_tmp
	lda e_curx+3
	sbc e_curx+1
	sta tf_tmp+1
	bpl shapes_te_pos                 ; short >= long: left = long, len = diff+1
	lda e_curx+2                ; short < long: left = short, len = -diff+1
	sta X16_P0
	lda e_curx+3
	sta X16_P1
	sec
	lda #0
	sbc tf_tmp
	sta X16_P4
	lda #0
	sbc tf_tmp+1
	sta X16_P5
	bra shapes_te_len
shapes_te_pos
	lda e_curx
	sta X16_P0
	lda e_curx+1
	sta X16_P1
	lda tf_tmp
	sta X16_P4
	lda tf_tmp+1
	sta X16_P5
shapes_te_len
	inc X16_P4                  ; len = |diff| + 1
	bne :+
	inc X16_P5
:	lda tf_y
	sta X16_P2
	lda tf_y+1
	sta X16_P3
	lda pie_col
	jsr SHP_HLINE
	rts

; --- pie / triangle-fill state ---------------------------------------
pie_col   .byte 0
pie_prevx .word 0
pie_prevy .word 0
tf_ax  .word 0
tf_ay  .word 0
tf_bx  .word 0
tf_by  .word 0
tf_cx  .word 0
tf_cy  .word 0
tf_y   .word 0
tf_isx .word 0
tf_isy .word 0
tf_iex .word 0
tf_iey .word 0
tf_edx .word 0
tf_tmp .word 0
e_curx .res 4, 0
e_err  .res 4, 0
e_adx  .res 4, 0
e_dy   .res 4, 0
e_sx   .res 4, 0

.endif

; ---------------------------------------------------------------------
; shape_bezier -- cubic Bezier curve (X16_USE_SHAPES_BEZIER)
; ---------------------------------------------------------------------
; The curve through four control points P0 (on the curve), P1, P2
; (handles), P3 (on the curve), by de Casteljau at a handful of t and
; shp_line between the samples. The sample count adapts to the control
; polygon's size (its Manhattan perimeter / 8, clamped to 4..64), so a
; small curve is cheap and a large one stays smooth. Clips wherever
; SHP_PSET clips.
;
;   in: bez_x0/bez_y0 .. bez_x3/bez_y3 = the four control points
;       (signed words, set by the caller), A = colour
;
; t is an 8-bit fraction (0..255); the endpoints P0 and P3 are emitted
; exactly rather than evaluated, so the curve meets its anchors.
; ---------------------------------------------------------------------
.ifdef X16_USE_SHAPES_BEZIER

shape_bezier
	sta shl_col
	jsr shapes_bz_nseg                ; bez_n = clamp(perimeter/8, 4, 64)
	lda bez_x0                  ; prev = P0 (emitted exactly)
	sta shl_x0
	lda bez_x0+1
	sta shl_x0+1
	lda bez_y0
	sta shl_y0
	lda bez_y0+1
	sta shl_y0+1
	lda #1
	sta bez_i
	stz bez_tb
	stz bez_rem
	stz bez_rem+1
shapes_bz_loop
	lda bez_i                   ; i == n ? last segment goes to P3
	cmp bez_n
	beq shapes_bz_last
	inc bez_rem+1               ; rem += 256; while rem >= n: tb++, rem -= n
shapes_bz_tw
	lda bez_rem+1
	bne shapes_bz_tsub
	lda bez_rem
	cmp bez_n
	bcc shapes_bz_tdone
shapes_bz_tsub
	sec
	lda bez_rem
	sbc bez_n
	sta bez_rem
	lda bez_rem+1
	sbc #0
	sta bez_rem+1
	inc bez_tb
	bra shapes_bz_tw
shapes_bz_tdone
	jsr shapes_bz_eval                ; (bez_rx, bez_ry) = B(tb)
	lda bez_rx
	sta shl_x1
	lda bez_rx+1
	sta shl_x1+1
	lda bez_ry
	sta shl_y1
	lda bez_ry+1
	sta shl_y1+1
	jsr shp_line
	lda shl_x1                  ; cur -> prev
	sta shl_x0
	lda shl_x1+1
	sta shl_x0+1
	lda shl_y1
	sta shl_y0
	lda shl_y1+1
	sta shl_y0+1
	inc bez_i
	jmp shapes_bz_loop
shapes_bz_last
	lda bez_x3                  ; final sample = P3, exact
	sta shl_x1
	lda bez_x3+1
	sta shl_x1+1
	lda bez_y3
	sta shl_y1
	lda bez_y3+1
	sta shl_y1+1
	jmp shp_line

; bez_n = clamp(Manhattan perimeter of the control polygon / 8, 4, 64)
shapes_bz_nseg
	stz bez_per
	stz bez_per+1
	ldx #0                      ; X = 4*k over the three control segments
shapes_bn_loop
	sec                         ; dx = pts[k+1]shapes_x - pts[k]shapes_x
	lda bez_x0+4,x
	sbc bez_x0,x
	sta bez_tmp
	lda bez_x0+5,x
	sbc bez_x0+1,x
	sta bez_tmp+1
	jsr shapes_bz_absacc
	sec                         ; dy = pts[k+1]shapes_y - pts[k]shapes_y
	lda bez_x0+6,x
	sbc bez_x0+2,x
	sta bez_tmp
	lda bez_x0+7,x
	sbc bez_x0+3,x
	sta bez_tmp+1
	jsr shapes_bz_absacc
	inx
	inx
	inx
	inx
	cpx #12
	bne shapes_bn_loop
	ldx #3                      ; per >>= 3
shapes_bn_sh
	lsr bez_per+1
	ror bez_per
	dex
	bne shapes_bn_sh
	lda bez_per+1               ; clamp high -> 64
	bne shapes_bn_hi
	lda bez_per
	cmp #64
	bcs shapes_bn_hi
	cmp #4
	bcs shapes_bn_ok                  ; 4..63
	lda #4
shapes_bn_ok
	sta bez_n
	rts
shapes_bn_hi
	lda #64
	sta bez_n
	rts

; bez_per += |bez_tmp|  (signed word magnitude)
shapes_bz_absacc
	lda bez_tmp+1
	bpl shapes_ba_pos
	sec
	lda #0
	sbc bez_tmp
	sta bez_tmp
	lda #0
	sbc bez_tmp+1
	sta bez_tmp+1
shapes_ba_pos
	clc
	lda bez_per
	adc bez_tmp
	sta bez_per
	lda bez_per+1
	adc bez_tmp+1
	sta bez_per+1
	rts

; (bez_rx, bez_ry) = cubic B(bez_tb) by de Casteljau
shapes_bz_eval
	ldx #0                      ; copy control points into the work arrays
	ldy #0
shapes_be_cp
	lda bez_x0,y
	sta bez_wx,x
	lda bez_x0+1,y
	sta bez_wx+1,x
	lda bez_x0+2,y
	sta bez_wy,x
	lda bez_x0+3,y
	sta bez_wy+1,x
	inx
	inx
	tya
	clc
	adc #4
	tay
	cpx #8
	bne shapes_be_cp
	lda #3
	sta bez_cnt
shapes_be_lvl
	lda bez_cnt                 ; inner loop j = 0 .. cnt-1  (index j*2)
	asl
	sta bez_lim
	stz bez_jx
shapes_be_jx
	ldx bez_jx                  ; wx[j] = lerp(wx[j], wx[j+1], t)
	lda bez_wx,x
	sta bez_p
	lda bez_wx+1,x
	sta bez_p+1
	lda bez_wx+2,x
	sta bez_q
	lda bez_wx+3,x
	sta bez_q+1
	jsr shapes_bz_lerp
	ldx bez_jx
	lda bez_r
	sta bez_wx,x
	lda bez_r+1
	sta bez_wx+1,x
	lda bez_wy,x                ; wy[j] = lerp(wy[j], wy[j+1], t)
	sta bez_p
	lda bez_wy+1,x
	sta bez_p+1
	lda bez_wy+2,x
	sta bez_q
	lda bez_wy+3,x
	sta bez_q+1
	jsr shapes_bz_lerp
	ldx bez_jx
	lda bez_r
	sta bez_wy,x
	lda bez_r+1
	sta bez_wy+1,x
	lda bez_jx
	clc
	adc #2
	sta bez_jx
	cmp bez_lim
	bne shapes_be_jx
	dec bez_cnt
	bne shapes_be_lvl
	lda bez_wx                  ; result = work[0]
	sta bez_rx
	lda bez_wx+1
	sta bez_rx+1
	lda bez_wy
	sta bez_ry
	lda bez_wy+1
	sta bez_ry+1
	rts

; bez_r = bez_p + round((bez_q - bez_p) * bez_tb / 256)   (signed)
shapes_bz_lerp
	sec                         ; d = q - p
	lda bez_q
	sbc bez_p
	sta bez_d
	lda bez_q+1
	sbc bez_p+1
	sta bez_d+1
	stz bez_dsgn
	lda bez_d+1                 ; take |d|, remember the sign
	bpl shapes_bl_pos
	inc bez_dsgn
	sec
	lda #0
	sbc bez_d
	sta bez_d
	lda #0
	sbc bez_d+1
	sta bez_d+1
shapes_bl_pos
	jsr shapes_bz_mul                 ; bez_prod = |d| * t (24-bit)
	clc                         ; + 128 (round), then take bytes 1..2 (>>8)
	lda bez_prod
	adc #128
	lda bez_prod+1
	adc #0
	sta bez_m
	lda bez_prod+2
	adc #0
	sta bez_m+1
	lda bez_dsgn
	beq shapes_bl_add
	sec                         ; re-apply the sign
	lda #0
	sbc bez_m
	sta bez_m
	lda #0
	sbc bez_m+1
	sta bez_m+1
shapes_bl_add
	clc                         ; r = p + m
	lda bez_p
	adc bez_m
	sta bez_r
	lda bez_p+1
	adc bez_m+1
	sta bez_r+1
	rts

; bez_prod (24-bit) = bez_d (16-bit) * bez_tb (8-bit), unsigned
shapes_bz_mul
	stz bez_prod
	stz bez_prod+1
	stz bez_prod+2
	lda bez_tb
	sta bez_mt
	ldx #8
shapes_bm_loop
	asl bez_prod
	rol bez_prod+1
	rol bez_prod+2
	asl bez_mt
	bcc shapes_bm_skip
	clc
	lda bez_prod
	adc bez_d
	sta bez_prod
	lda bez_prod+1
	adc bez_d+1
	sta bez_prod+1
	lda bez_prod+2
	adc #0
	sta bez_prod+2
shapes_bm_skip
	dex
	bne shapes_bm_loop
	rts

; --- bezier state ----------------------------------------------------
bez_x0 .word 0
bez_y0 .word 0
bez_x1 .word 0
bez_y1 .word 0
bez_x2 .word 0
bez_y2 .word 0
bez_x3 .word 0
bez_y3 .word 0
bez_n    .byte 0
bez_i    .byte 0
bez_tb   .byte 0
bez_rem  .word 0
bez_per  .word 0
bez_tmp  .word 0
bez_rx   .word 0
bez_ry   .word 0
bez_wx   .res 8, 0
bez_wy   .res 8, 0
bez_cnt  .byte 0
bez_lim  .byte 0
bez_jx   .byte 0
bez_p    .word 0
bez_q    .word 0
bez_d    .word 0
bez_dsgn .byte 0
bez_prod .res 3, 0
bez_mt   .byte 0
bez_m    .word 0
bez_r    .word 0

.endif

; --- the default binding: the 2bpp module ------------------------------
; (evaluated here, at the END, so an overrider defines its symbols
; before sourcing the file and these !ifdefs stay quiet)
; The default-bound words are emitted UNCONDITIONALLY -- data inside an
; !ifndef would appear in pass 1 and vanish in pass 2 (the symbol exists
; by then), shifting every later address into a phase error.
.ifndef X16_SKIP_BASE
shp_wdef .word 640
shp_hdef .word 480

.ifndef SHP_PSET
SHP_PSET  = gfx2h_pset
.endif
.ifndef SHP_READ
SHP_READ  = gfx2h_read
.endif
.ifndef SHP_HLINE
SHP_HLINE = gfx2h_hline
.endif
.ifndef SHP_W
SHP_W     = shp_wdef
.endif
.ifndef SHP_H
SHP_H     = shp_hdef
.endif
.endif

; (end zone)
