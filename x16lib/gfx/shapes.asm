; ca65
; =====================================================================
; x16lib :: gfx/shapesshp_asm -- circle, disc, flood fill (any bitmap)
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_codeshp_asm does,
; under X16_USE_SHAPES).
;
; The shapes are ENGINE-AGNOSTIC: they draw through three entry symbols
; and read the canvas bounds through two, all overridable BEFORE this
; file is sourced. Left alone, they bind to the 2bpp module -- which is
; how bitmap2 gains the circle/disc/flood that bitmap (8bpp) has native
; -- but any engine with the same three call shapes can sit behind them
; (CXGEOS points them at its graphics port and gets every mode at once):
;
;   SHP_PSET   pset:  P0/P1 = x, P2/P3 = y, A = colour (must clip)
;   SHP_READ   read:  P0/P1 = x, P2/P3 = y -> A = the pixel
;   SHP_HLINE  hline: P0/P1 = x, P2/P3 = y, P4/P5 = len, A = colour
;   SHP_W/H    the ADDRESS of a little-endian word: canvas w / h
;
; The P block is reloaded before every call, so the bound routines may
; clobber it freely; X16_T0.shp_T7 are never touched here.
;
;   shape_circle  in: P0/P1 = cx, P2/P3 = cy, P4 = r (0-255), A = colour
;                 An outline, by the midpoint walk, plotted with
;                 SHP_PSET -- so it clips wherever pset clips.
;   shape_disc    same arguments, filled with spans. SHP_HLINE does not
;                 clip (the module policy), so keep a disc on screen.
;   shape_flood   in: P0/P1 = x, P2/P3 = y, A = colour. Scanline seed
;                 fill of the region containing (x,y). Bounds-checked
;                 against SHP_W/SHP_H, so it never reads off canvas.
;                 Carry set if the seed stack overflowed -- a very
;                 tortured region may come back incomplete.
; =====================================================================


; ---------------------------------------------------------------------
; shape_circle
; ---------------------------------------------------------------------
shape_circle
	sta shp_col
	jsr shp_take_cxy               ; cx/cy out of the P block, x=r, y=0
shp_cloop
	lda shp_y                      ; while y <= x
	cmp shp_x
	beq shp_cplot                  ; the diagonal point still plots
	bcs shp_cdone
shp_cplot
	lda shp_x                      ; the (x,y) octant pair...
	sta shp_a
	lda shp_y
	sta shp_b
	jsr shp_pair4
	lda shp_y                      ; ..shp_and the (y,x) pair
	sta shp_a
	lda shp_x
	sta shp_b
	jsr shp_pair4
	jsr shp_step                   ; the midpoint error walk
	bra shp_cloop
shp_cdone
	rts

; ---------------------------------------------------------------------
; shape_disc
; ---------------------------------------------------------------------
shape_disc
	sta shp_col
	jsr shp_take_cxy
shp_dloop
	lda shp_y
	cmp shp_x
	beq shp_dspan
	bcs shp_ddone
shp_dspan
	lda shp_x                      ; spans at cy +/- y, half-width x...
	sta shp_a
	lda shp_y
	sta shp_b
	jsr shp_span2
	lda shp_y                      ; ..shp_and at cy +/- x, half-width y
	sta shp_a
	lda shp_x
	sta shp_b
	jsr shp_span2
	jsr shp_step
	bra shp_dloop
shp_ddone
	rts

; --- shared circle/disc machinery -------------------------------------
shp_take_cxy                       ; P -> locals; x = r, y = 0, err = 1 - r
	lda X16_P0
	sta shp_cx
	lda X16_P1
	sta shp_cx+1
	lda X16_P2
	sta shp_cy
	lda X16_P3
	sta shp_cy+1
	lda X16_P4
	sta shp_x
	lda #0
	sta shp_y
	sec                         ; err = 1 - r, signed 16-bit
	lda #1
	sbc shp_x
	sta shp_err
	lda #0
	sbc #0
	sta shp_err+1
	rts

shp_step                           ; y++; err < 0 ? err += 2y+1
	inc shp_y                      ;      else x--, err += 2(y-x)+1
	bit shp_err+1
	bmi shp_grow
	dec shp_x
	sec                         ; t = y - x, sign-extended
	lda shp_y
	sbc shp_x
	sta shp_t
	lda #0
	sbc #0
	sta shp_t+1
	bra shp_apply
shp_grow
	lda shp_y                      ; t = y (positive)
	sta shp_t
	lda #0
	sta shp_t+1
shp_apply
	asl shp_t                      ; err += 2t + 1
	rol shp_t+1
	inc shp_t
	bne :+
	inc shp_t+1
:	clc
	lda shp_err
	adc shp_t
	sta shp_err
	lda shp_err+1
	adc shp_t+1
	sta shp_err+1
	rts

shp_pair4                          ; pset the 4 sign combos of (cx±a, cy±b)
	lda #0
	sta shp_sx
	sta shp_sy
shp_p4go
	jsr shp_emit1
	lda shp_sx                     ; walk ++, -+, +-, -- via two flags
	eor #1
	sta shp_sx
	bne shp_p4go
	lda shp_sy
	eor #1
	sta shp_sy
	bne shp_p4go
	rts

shp_emit1                          ; one pset at (cx sx? -a : +a, cy sy? -b : +b)
	lda shp_sx
	bne shp_e1xm
	clc                         ; x = cx + a
	lda shp_cx
	adc shp_a
	sta X16_P0
	lda shp_cx+1
	adc #0
	sta X16_P1
	bra shp_e1y
shp_e1xm
	sec                         ; x = cx - a
	lda shp_cx
	sbc shp_a
	sta X16_P0
	lda shp_cx+1
	sbc #0
	sta X16_P1
shp_e1y
	lda shp_sy
	bne shp_e1ym
	clc
	lda shp_cy
	adc shp_b
	sta X16_P2
	lda shp_cy+1
	adc #0
	sta X16_P3
	bra shp_e1go
shp_e1ym
	sec
	lda shp_cy
	sbc shp_b
	sta X16_P2
	lda shp_cy+1
	sbc #0
	sta X16_P3
shp_e1go
	lda shp_col
	jmp SHP_PSET

shp_span2                          ; hline half-width a at cy+b and cy-b
	lda #0
	sta shp_sy
	jsr shp_espan
	lda #1
	sta shp_sy
	; fall through
shp_espan
	sec                         ; x = cx - a
	lda shp_cx
	sbc shp_a
	sta X16_P0
	lda shp_cx+1
	sbc #0
	sta X16_P1
	lda shp_sy
	bne shp_esym
	clc
	lda shp_cy
	adc shp_b
	sta X16_P2
	lda shp_cy+1
	adc #0
	sta X16_P3
	bra shp_esgo
shp_esym
	sec
	lda shp_cy
	sbc shp_b
	sta X16_P2
	lda shp_cy+1
	sbc #0
	sta X16_P3
shp_esgo
	lda shp_a                      ; len = 2a + 1
	sta X16_P4
	lda #0
	sta X16_P5
	asl X16_P4
	rol X16_P5
	inc X16_P4
	bne :+
	inc X16_P5
:	lda shp_col
	jmp SHP_HLINE

; ---------------------------------------------------------------------
; shape_flood
; ---------------------------------------------------------------------
; Pop a seed, widen it into a span of the target colour, fill the span,
; then scan the rows above and below for runs of target and push one
; seed per run. The stack holds seeds as xshp_w yshp_w; when it is full a
; seed is dropped and the overflow is remembered in the carry.
; ---------------------------------------------------------------------
FLOOD_MAX = 96                  ; seeds; 4 bytes each

shape_flood
	sta shp_col
	lda #0
	sta shp_ovf
	sta shp_sp
	jsr shp_rd_p                   ; the target = the seed's own colour
	sta shp_tgt
	cmp shp_col                    ; filling with itself never ends: done
	bne shp_fseed
	clc                         ; (no overflow could have happened yet)
	rts
shp_fseed
	lda X16_P0                  ; push the seed
	sta shp_qx
	lda X16_P1
	sta shp_qx+1
	lda X16_P2
	sta shp_qy
	lda X16_P3
	sta shp_qy+1
	jsr shp_push
shp_floop
	lda shp_sp                     ; stack empty: finished
	bne shp_fbody
	jmp shp_fexit
shp_fbody
	jsr shp_pop                    ; seed -> shp_qx/shp_qy
	jsr shp_rd_q                   ; still target? (may have been filled)
	cmp shp_tgt
	bne shp_floop

	lda shp_qx                     ; widen left: xl = leftmost target
	sta shp_xl
	lda shp_qx+1
	sta shp_xl+1
shp_wleft
	lda shp_xl
	ora shp_xl+1
	beq shp_wldone                 ; at column 0
	sec                         ; probe xl-1
	lda shp_xl
	sbc #1
	sta shp_qx
	lda shp_xl+1
	sbc #0
	sta shp_qx+1
	jsr shp_rd_q
	cmp shp_tgt
	bne shp_wldone
	lda shp_qx
	sta shp_xl
	lda shp_qx+1
	sta shp_xl+1
	bra shp_wleft
shp_wldone
	lda shp_qy                     ; widen right: xr = rightmost target
	sta shp_qy                     ; (qy already holds the row)
	lda shp_xl
	sta shp_xr
	lda shp_xl+1
	sta shp_xr+1
shp_wright
	clc                         ; probe xr+1, stop at SHP_W-1
	lda shp_xr
	adc #1
	sta shp_qx
	lda shp_xr+1
	adc #0
	sta shp_qx+1
	lda shp_qx                     ; qx == W? off the right edge
	cmp SHP_W
	bne shp_wrprobe
	lda shp_qx+1
	cmp SHP_W+1
	beq shp_wrdone
shp_wrprobe
	jsr shp_rd_q
	cmp shp_tgt
	bne shp_wrdone
	lda shp_qx
	sta shp_xr
	lda shp_qx+1
	sta shp_xr+1
	bra shp_wright
shp_wrdone
	lda shp_xl                     ; fill the span: hline(xl, y, xr-xl+1)
	sta X16_P0
	lda shp_xl+1
	sta X16_P1
	lda shp_qy
	sta X16_P2
	lda shp_qy+1
	sta X16_P3
	sec
	lda shp_xr
	sbc shp_xl
	sta X16_P4
	lda shp_xr+1
	sbc shp_xl+1
	sta X16_P5
	inc X16_P4
	bne :+
	inc X16_P5
:	lda shp_col
	jsr SHP_HLINE

	lda shp_qy                     ; the row above...
	sta shp_ry
	lda shp_qy+1
	sta shp_ry+1
	lda shp_ry
	ora shp_ry+1
	beq shp_below                  ; row 0 has nothing above
	sec
	lda shp_ry
	sbc #1
	sta shp_ry
	lda shp_ry+1
	sbc #0
	sta shp_ry+1
	jsr shp_scanrow
shp_below
	clc                         ; ..shp_and the row below
	lda shp_qy
	adc #1
	sta shp_ry
	lda shp_qy+1
	adc #0
	sta shp_ry+1
	lda shp_ry                     ; ry == H? off the bottom
	cmp SHP_H
	bne shp_bscan
	lda shp_ry+1
	cmp SHP_H+1
	beq shp_fnext
shp_bscan
	jsr shp_scanrow
shp_fnext
	jmp shp_floop
shp_fexit
	lsr shp_ovf                    ; overflow -> carry
	rts

; scan shp_xl..shp_xr on row shp_ry for runs of target; push one seed per run
shp_scanrow
	lda #0
	sta shp_run
	lda shp_xl
	sta shp_tx
	lda shp_xl+1
	sta shp_tx+1
shp_srloop
	lda shp_tx                     ; read (tx, ry)
	sta shp_qx
	lda shp_tx+1
	sta shp_qx+1
	lda shp_ry
	sta shp_qy
	lda shp_ry+1
	sta shp_qy+1
	jsr shp_rd_q
	cmp shp_tgt
	bne shp_srmiss
	lda shp_run                    ; entering a run: one seed
	bne shp_srnext
	lda #1
	sta shp_run
	jsr shp_push
	bra shp_srnext
shp_srmiss
	lda #0
	sta shp_run
shp_srnext
	lda shp_tx                     ; tx == xr? done
	cmp shp_xr
	bne shp_srinc
	lda shp_tx+1
	cmp shp_xr+1
	beq shp_srdone
shp_srinc
	inc shp_tx
	bne shp_srloop
	inc shp_tx+1
	bra shp_srloop
shp_srdone
	rts

shp_rd_p                           ; read at the CALLER's P block (entry)
	jmp SHP_READ
shp_rd_q                           ; read at (shp_qx, shp_qy)
	lda shp_qx
	sta X16_P0
	lda shp_qx+1
	sta X16_P1
	lda shp_qy
	sta X16_P2
	lda shp_qy+1
	sta X16_P3
	jmp SHP_READ

shp_push                           ; (shp_qx,shp_qy) onto the stack, or drop + ovf
	lda shp_sp
	cmp #FLOOD_MAX
	bcc :+
	lda #2                      ; remembered; lsr at exit -> carry
	sta shp_ovf
	rts
:	asl                         ; sp * 4
	asl
	tax
	lda shp_qx
	sta shp_stk,x
	lda shp_qx+1
	sta shp_stk+1,x
	lda shp_qy
	sta shp_stk+2,x
	lda shp_qy+1
	sta shp_stk+3,x
	inc shp_sp
	rts

shp_pop                            ; the top seed -> (shp_qx,shp_qy)
	dec shp_sp
	lda shp_sp
	asl
	asl
	tax
	lda shp_stk,x
	sta shp_qx
	lda shp_stk+1,x
	sta shp_qx+1
	lda shp_stk+2,x
	sta shp_qy
	lda shp_stk+3,x
	sta shp_qy+1
	rts

; --- the state ---------------------------------------------------------
shp_col .byte 0
shp_cx  .word 0
shp_cy  .word 0
shp_x   .byte 0
shp_y   .byte 0
shp_a   .byte 0
shp_b   .byte 0
shp_sx  .byte 0
shp_sy  .byte 0
shp_err .word 0
shp_t   .word 0

shp_tgt .byte 0
shp_ovf .byte 0
shp_sp  .byte 0
shp_qx  .word 0
shp_qy  .word 0
shp_xl  .word 0
shp_xr  .word 0
shp_ry  .word 0
shp_tx  .word 0
shp_run .byte 0
shp_stk .res FLOOD_MAX * 4, 0

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

