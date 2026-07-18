;ACME
; =====================================================================
; x16lib :: gfx/bitmap.asm -- 320x240x256 bitmap drawing
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
; Requires X16_USE_VERA (uses vera_fill).
;
; The framebuffer is 8bpp at VRAM $00000, one byte per pixel, rows of
; 320. A pixel is at y*320 + x.
;
; gfx_pset clips. The line/rect/circle primitives do NOT: they assume
; their arguments are on screen. Clipping every span would cost more
; than it saves for a caller that already knows its geometry.
;
; Nothing here changes the screen mode. Call gfx_init once to switch the
; display to bitmap mode; the drawing routines only touch VRAM, so they
; also work on an off-screen buffer.
; =====================================================================

; (zone: file scope in ca65)

GFX_WIDTH  = 320
GFX_HEIGHT = 240

; ---------------------------------------------------------------------
; gfx_init  -- 320x240@256c bitmap on layer 0, 40x30 text on layer 1
; gfx_clear -- in: A = colour
; ---------------------------------------------------------------------
gfx_init
    lda #$80
    jmp screen_set_mode

; 320*240 = 76800 bytes does not fit vera_fill's 16-bit count (passing
; it naively truncates to $2C00 and clears only the top 35 rows), so
; clear in two halves; port 0 keeps auto-incrementing between calls.
gfx_clear
    pha
    vera_addr 0, VRAM_BITMAP, VERA_INC_1
    pla
    pha
    ldx #<(GFX_WIDTH * GFX_HEIGHT / 2)
    ldy #>(GFX_WIDTH * GFX_HEIGHT / 2)
    jsr vera_fill
    pla
    ldx #<(GFX_WIDTH * GFX_HEIGHT / 2)
    ldy #>(GFX_WIDTH * GFX_HEIGHT / 2)
    jmp vera_fill

; ---------------------------------------------------------------------
; gfx_setptr -- point data port 0 at pixel (x,y)
;   in:  A = increment index (VERA_INC_*)
;        X16_P0/P1 = x, X16_P2 = y
;
; y*320 = (y<<8) + (y<<6), so no multiply is needed. Result is 17-bit.
; Stepping by VERA_INC_320 then walks straight down a column.
; ---------------------------------------------------------------------
gfx_setptr
    asl
    asl
    asl
    asl
    sta X16_T5                  ; increment field, pre-shifted

    lda X16_P2                  ; y << 6
    stz X16_T3
    asl
    rol X16_T3
    asl
    rol X16_T3
    asl
    rol X16_T3
    asl
    rol X16_T3
    asl
    rol X16_T3
    asl
    rol X16_T3
    sta X16_T4                  ; T4/T3 = y*64

    clc                         ; + y<<8, whose low byte is zero
    lda X16_T4
    sta X16_T0
    lda X16_P2
    adc X16_T3
    sta X16_T1
    lda #0
    adc #0
    sta X16_T2                  ; T2:T1:T0 = y*320

    clc                         ; + x
    lda X16_T0
    adc X16_P0
    sta X16_T0
    lda X16_T1
    adc X16_P1
    sta X16_T1
    lda X16_T2
    adc #0
    sta X16_T2

    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL
    lda X16_T0
    sta VERA_ADDR_L
    lda X16_T1
    sta VERA_ADDR_M
    lda X16_T2
    and #VERA_ADDR_H_BANK
    ora X16_T5
    sta VERA_ADDR_H
    rts

; ---------------------------------------------------------------------
; gfx_pset -- set one pixel, clipped
;   in:  X16_P0/P1 = x, X16_P2 = y, X16_P3 = colour
; ---------------------------------------------------------------------
gfx_pset
    lda X16_P2
    cmp #GFX_HEIGHT
    bcs @off                    ; y >= 240

    lda X16_P1                  ; x high byte
    beq @on                     ; x < 256, always on screen
    cmp #1
    bne @off                    ; x >= 512
    lda X16_P0
    cmp #<GFX_WIDTH             ; 320 = $140, so x low must be < $40
    bcs @off
@on
    lda #VERA_INC_0
    jsr gfx_setptr
    lda X16_P3
    sta VERA_DATA0
@off
    rts

; ---------------------------------------------------------------------
; gfx_hline -- in: X16_P0/P1 = x, X16_P2 = y, X16_P3 = colour,
;                  X16_P4/P5 = length
; ---------------------------------------------------------------------
gfx_hline
    lda #VERA_INC_1
    jsr gfx_setptr
    lda X16_P3
    ldx X16_P4
    ldy X16_P5
    jmp vera_fill

; ---------------------------------------------------------------------
; gfx_vline -- in: X16_P0/P1 = x, X16_P2 = y, X16_P3 = colour,
;                  X16_P4 = length (1-255)
;
; VERA_INC_320 is one of the hardware's odd increments, so a vertical
; line is the same tight loop as a horizontal one.
; ---------------------------------------------------------------------
gfx_vline
    lda #VERA_INC_320
    jsr gfx_setptr
    lda X16_P3
    ldx X16_P4
    ldy #0
    jmp vera_fill

; ---------------------------------------------------------------------
; gfx_rect -- filled rectangle
;   in:  X16_P0/P1 = x, X16_P2 = y, X16_P3 = colour,
;        X16_P4/P5 = width, X16_P6 = height
; ---------------------------------------------------------------------
gfx_rect
@row
    lda X16_P6
    beq @done
    jsr gfx_hline               ; leaves P0..P5 alone
    inc X16_P2
    dec X16_P6
    bra @row
@done
    rts

; ---------------------------------------------------------------------
; gfx_frame -- rectangle outline
;   same arguments as gfx_rect
; ---------------------------------------------------------------------
gfx_frame
    ; Take a private copy of everything: gfx_vline reuses P4 as its
    ; length, which is where the caller's width lives.
    lda X16_P0
    sta gb_x
    lda X16_P1
    sta gb_x+1
    lda X16_P2
    sta gb_y
    lda X16_P3
    sta gb_c
    lda X16_P4
    sta gb_w
    lda X16_P5
    sta gb_w+1
    lda X16_P6
    sta gb_h

    jsr bitmap_restore_span           ; top edge
    jsr gfx_hline

    jsr bitmap_restore_span           ; bottom edge, y + h - 1
    clc
    lda gb_y
    adc gb_h
    sec
    sbc #1
    sta X16_P2
    jsr gfx_hline

    jsr bitmap_restore_col            ; left edge
    jsr gfx_vline

    jsr bitmap_restore_col            ; right edge, x + w - 1
    clc
    lda gb_x
    adc gb_w
    sta X16_P0
    lda gb_x+1
    adc gb_w+1
    sta X16_P1
    lda X16_P0
    bne @no_borrow
    dec X16_P1
@no_borrow
    dec X16_P0
    jsr gfx_vline

    rts

; x, y, colour, width -- arguments for gfx_hline
bitmap_restore_span
    lda gb_x
    sta X16_P0
    lda gb_x+1
    sta X16_P1
    lda gb_y
    sta X16_P2
    lda gb_c
    sta X16_P3
    lda gb_w
    sta X16_P4
    lda gb_w+1
    sta X16_P5
    rts

; x, y, colour, height -- arguments for gfx_vline
bitmap_restore_col
    lda gb_x
    sta X16_P0
    lda gb_x+1
    sta X16_P1
    lda gb_y
    sta X16_P2
    lda gb_c
    sta X16_P3
    lda gb_h
    sta X16_P4
    rts

; ---------------------------------------------------------------------
; gfx_read -- read one pixel
;   in:  X16_P0/P1 = x, X16_P2 = y
;   out: A = the colour
; ---------------------------------------------------------------------
gfx_read
	lda #0                      ; VERA_INC_0: a lone read
	jsr gfx_setptr
	lda VERA_DATA0
	rts

; ---------------------------------------------------------------------
; the 2bpp module's stencil-and-blit family, at 8bpp. One byte is one
; pixel here, which makes every one of these simpler than its 2bpp
; sibling: no sub-byte phases, and a masked blit is a colour key.
;
; b8_addr8 -- the 17-bit framebuffer address of (gb8_x, gb8_y) -> the
; port named by b8_ld0/b8_ld1, with INC_1. y*320 = (y<<8) + (y<<6).
; ---------------------------------------------------------------------
b8_addr8
	lda gb8_y                   ; y << 6 into a word
	sta gb8_t
	lda #0
	sta gb8_t+1
	ldx #6
b8_a8sh
	asl gb8_t
	rol gb8_t+1
	dex
	bne b8_a8sh
	clc                         ; + y << 8
	lda gb8_t+1
	adc gb8_y
	sta gb8_t+1
	lda #0
	adc #0
	sta gb8_t+2                 ; bit 16
	clc                         ; + x
	lda gb8_t
	adc gb8_x
	sta gb8_t
	lda gb8_t+1
	adc gb8_x+1
	sta gb8_t+1
	lda gb8_t+2
	adc #0
	sta gb8_t+2
	rts

b8_ld0                            ; port 0 <- the address, INC_1
	lda #VERA_CTRL_ADDRSEL
	trb VERA_CTRL
	bra b8_ldgo
b8_ld1                            ; port 1 <- the address, INC_1
	lda #VERA_CTRL_ADDRSEL
	tsb VERA_CTRL
b8_ldgo
	lda gb8_t
	sta VERA_ADDR_L
	lda gb8_t+1
	sta VERA_ADDR_M
	lda gb8_t+2
	ora #(VERA_INC_1 << 4)
	sta VERA_ADDR_H
	rts

; ---------------------------------------------------------------------
; gfx_pattern_set -- cache an 8x8 1bpp pattern for gfx_pattern_rect
;   in:  A = pattern low, X = pattern high (8 row bytes, top first;
;            bit 7 is the leftmost pixel)
;        X16_P4 = background colour, X16_P5 = foreground colour
;
; The full-colour pair is the one deliberate departure from the 2bpp
; signature, whose Y packs two 2-bit colours; 8bpp colours need bytes.
; ---------------------------------------------------------------------
gfx_pattern_set
	sta X16_T0
	stx X16_T0+1
	ldy #7
b8_gpcp
	lda (X16_T0),y
	sta gp8_pat,y
	dey
	bpl b8_gpcp
	lda X16_P4
	sta gp8_bg
	lda X16_P5
	sta gp8_fg
	rts

; ---------------------------------------------------------------------
; gfx_pattern_rect -- fill a rectangle with the cached pattern
;   in:  X16_P0/P1 = x, X16_P2 = y, X16_P4/P5 = width, X16_P6 = height
;
; Tiles from the screen origin, like the 2bpp module: the pattern cell
; under a pixel depends only on the pixel, not the rectangle.
; ---------------------------------------------------------------------
gfx_pattern_rect
	lda X16_P0
	sta gb8_x
	lda X16_P1
	sta gb8_x+1
	lda X16_P2
	sta gb8_y
	lda X16_P4
	sta gp8_w
	lda X16_P5
	sta gp8_w+1
	lda X16_P6
	sta gp8_h
	lda X16_P0                  ; the column phase: x & 7, fixed for
	and #7                      ; every row
	sta gp8_rot
b8_gprow
	jsr b8_addr8
	jsr b8_ld0
	lda gb8_y                   ; the pattern row: y & 7
	and #7
	tay
	lda gp8_pat,y
	ldy gp8_rot                 ; pre-rotate to the column phase
	beq b8_gpgo
b8_gppre
	asl
	adc #0                      ; circular left: bit 7 wraps to bit 0
	dey
	bne b8_gppre
b8_gpgo
	sta gp8_cur
	lda gp8_w                   ; the width countdown, 16-bit
	sta gb8_t
	lda gp8_w+1
	sta gb8_t+1
b8_gppx
	lda gp8_cur                 ; bit 7 = this pixel
	bmi b8_gpfg
	lda gp8_bg
	bra b8_gpout
b8_gpfg
	lda gp8_fg
b8_gpout
	sta VERA_DATA0
	lda gp8_cur                 ; rotate to the next column
	asl
	adc #0
	sta gp8_cur
	lda gb8_t                   ; width--
	bne :+
	dec gb8_t+1
:	dec gb8_t
	lda gb8_t
	ora gb8_t+1
	bne b8_gppx
	inc gb8_y                   ; the next row
	dec gp8_h
	bne b8_gprow
	rts

; ---------------------------------------------------------------------
; gfx_blit -- rows of pixel bytes from RAM to the framebuffer
;   in:  A = raster op: 0 copy, 1 OR, 2 AND, 3 XOR
;        X16_P0/P1 = x, X16_P2 = y, X16_P4 = width in PIXELS (1-255),
;        X16_P5 = height in rows, X16_P6/P7 = source (row-major)
;
; The source pointer is X16_PTR3 -- P6/P7 double as real zero page, the
; 2bpp module's own trick. No clipping.
; ---------------------------------------------------------------------
gfx_blit
	sta gb8_op
	lda X16_P0
	sta gb8_x
	lda X16_P1
	sta gb8_x+1
	lda X16_P2
	sta gb8_y
	lda X16_P5
	sta gb8_h
b8_gbrow
	jsr b8_addr8
	jsr b8_ld0
	lda gb8_op
	beq b8_gbcopy
	jsr b8_ld1                    ; the RMW ops read through port 1
	ldy #0
b8_gbop
	lda gb8_op
	cmp #2
	beq b8_gband
	bcs b8_gbxor
	lda (X16_PTR3),y            ; OR
	ora VERA_DATA1
	bra b8_gbw
b8_gband
	lda (X16_PTR3),y
	and VERA_DATA1
	bra b8_gbw
b8_gbxor
	lda (X16_PTR3),y
	eor VERA_DATA1
b8_gbw
	sta VERA_DATA0
	iny
	cpy X16_P4
	bne b8_gbop
	bra b8_gbnext
b8_gbcopy
	ldy #0
b8_gbcp
	lda (X16_PTR3),y
	sta VERA_DATA0
	iny
	cpy X16_P4
	bne b8_gbcp
b8_gbnext
	clc                         ; the next source row
	lda X16_PTR3
	adc X16_P4
	sta X16_PTR3
	bcc :+
	inc X16_PTR3+1
:	inc gb8_y
	dec gb8_h
	bne b8_gbrow
	rts

; ---------------------------------------------------------------------
; gfx_blitm -- a masked blit: byte $00 is transparent
;   in:  X16_P0/P1 = x, X16_P2 = y, X16_P4 = width in PIXELS (1-255),
;        X16_P5 = height, X16_P6/P7 = source (row-major)
;
; At 8bpp the mask IS the data: colour 0 means "leave the screen
; alone" (a read still advances the port, which is the whole trick).
; The 2bpp module needs interleaved mask bytes; one byte per pixel
; does not.
; ---------------------------------------------------------------------
gfx_blitm
	lda X16_P0
	sta gb8_x
	lda X16_P1
	sta gb8_x+1
	lda X16_P2
	sta gb8_y
	lda X16_P5
	sta gb8_h
b8_gmrow
	jsr b8_addr8
	jsr b8_ld0
	ldy #0
b8_gmpx
	lda (X16_PTR3),y
	beq b8_gmskip
	sta VERA_DATA0
	bra b8_gmn
b8_gmskip
	lda VERA_DATA0              ; advance without writing
b8_gmn
	iny
	cpy X16_P4
	bne b8_gmpx
	clc
	lda X16_PTR3
	adc X16_P4
	sta X16_PTR3
	bcc :+
	inc X16_PTR3+1
:	inc gb8_y
	dec gb8_h
	bne b8_gmrow
	rts

gp8_pat .res 8, 0
gp8_bg  .byte 0
gp8_fg  .byte 0
gp8_w   .word 0
gp8_h   .byte 0
gp8_rot .byte 0
gp8_cur .byte 0
gb8_x   .word 0
gb8_y   .byte 0
gb8_h   .byte 0
gb8_op  .byte 0
gb8_t   .res 3, 0

; ---------------------------------------------------------------------
; gfx_line -- Bresenham, any direction
;   in:  X16_P0/P1 = x0, X16_P2 = y0
;        X16_P3/P4 = x1, X16_P5 = y1
;        X16_P6    = colour
;
; Works entirely from its own variables, because gfx_pset wants the
; colour in X16_P3 -- which is where x1 lives on entry.
; ---------------------------------------------------------------------
gfx_line
    lda X16_P0
    sta gl_x0
    lda X16_P1
    sta gl_x0+1
    lda X16_P2
    sta gl_y0
    lda X16_P3
    sta gl_x1
    lda X16_P4
    sta gl_x1+1
    lda X16_P5
    sta gl_y1
    lda X16_P6
    sta gl_color

    ; dx = |x1 - x0|, sx = sign
    sec
    lda gl_x1
    sbc gl_x0
    sta gl_dx
    lda gl_x1+1
    sbc gl_x0+1
    sta gl_dx+1
    bpl @dx_pos
    sec
    lda #0
    sbc gl_dx
    sta gl_dx
    lda #0
    sbc gl_dx+1
    sta gl_dx+1
    lda #$FF
    sta gl_sx
    sta gl_sx+1                 ; -1, sign extended
    bra @dx_done
@dx_pos
    lda #$01
    sta gl_sx
    stz gl_sx+1
@dx_done

    ; dy = -|y1 - y0|, sy = sign
    sec
    lda gl_y1
    sbc gl_y0
    bpl @dy_pos
    eor #$FF
    clc
    adc #1                      ; absolute value
    sta gl_tmp
    lda #$FF
    sta gl_sy
    bra @dy_done
@dy_pos
    sta gl_tmp
    lda #$01
    sta gl_sy
@dy_done
    sec
    lda #0
    sbc gl_tmp
    sta gl_dy
    lda #0
    sbc #0
    sta gl_dy+1                 ; gl_dy = -|dy|, 16-bit signed

    clc                         ; err = dx + dy
    lda gl_dx
    adc gl_dy
    sta gl_err
    lda gl_dx+1
    adc gl_dy+1
    sta gl_err+1

@loop
    jsr bitmap_plot

    lda gl_x0                   ; reached the end point?
    cmp gl_x1
    bne @step
    lda gl_x0+1
    cmp gl_x1+1
    bne @step
    lda gl_y0
    cmp gl_y1
    bne @step
    rts

@step
    lda gl_err                  ; e2 = err * 2
    asl
    sta gl_e2
    lda gl_err+1
    rol
    sta gl_e2+1

    ; if e2 >= dy  ->  err += dy, x0 += sx
    sec
    lda gl_e2
    sbc gl_dy
    lda gl_e2+1
    sbc gl_dy+1
    bvc @nv1
    eor #$80                    ; signed compare: fold overflow into sign
@nv1
    bmi @skip_x
    clc
    lda gl_err
    adc gl_dy
    sta gl_err
    lda gl_err+1
    adc gl_dy+1
    sta gl_err+1
    clc
    lda gl_x0
    adc gl_sx
    sta gl_x0
    lda gl_x0+1
    adc gl_sx+1
    sta gl_x0+1
@skip_x

    ; if e2 <= dx  ->  err += dx, y0 += sy
    sec
    lda gl_dx
    sbc gl_e2
    lda gl_dx+1
    sbc gl_e2+1
    bvc @nv2
    eor #$80
@nv2
    bmi @skip_y
    clc
    lda gl_err
    adc gl_dx
    sta gl_err
    lda gl_err+1
    adc gl_dx+1
    sta gl_err+1
    clc
    lda gl_y0
    adc gl_sy
    sta gl_y0
@skip_y
    jmp @loop

; plot (gl_x0, gl_y0) in gl_color
bitmap_plot
    lda gl_x0
    sta X16_P0
    lda gl_x0+1
    sta X16_P1
    lda gl_y0
    sta X16_P2
    lda gl_color
    sta X16_P3
    jmp gfx_pset

; --- X16_BITMAP_MIN: core-only build ---------------------------------
; Define X16_BITMAP_MIN to stop here: init/clear/read/pset/lines/rect/
; frame/pattern/blit only. CXGEOS's 8bpp overlay image uses it to fit
; its fixed region; a full build is unchanged.
.ifndef X16_BITMAP_MIN

; ---------------------------------------------------------------------
; gfx_circle -- midpoint circle outline
;   in:  X16_P0/P1 = centre x, X16_P2 = centre y, X16_P3 = colour,
;        X16_P4 = radius (0-120)
;
; Plots through gfx_pset, so the circle clips at every screen edge for
; free. Preserves X16_P0..P4.
; ---------------------------------------------------------------------
gfx_circle
    jsr bitmap_c_setup
    lda gc_r
    bne @go
    lda gc_cx                   ; radius 0: a single point
    sta X16_P0
    lda gc_cx+1
    sta X16_P1
    lda gc_cy
    sta X16_P2
    jsr gfx_pset
    jmp bitmap_c_restore
@go
    ; x = r, y = 0, err = 1 - r
    lda gc_r
    sta gc_x
    stz gc_y
    sec
    lda #1
    sbc gc_r
    sta gc_err
    lda #0
    sbc #0
    sta gc_err+1

@loop
    lda gc_x                    ; the 8 octant points
    ldy gc_y
    jsr bitmap_c_plot4
    lda gc_y
    ldy gc_x
    jsr bitmap_c_plot4

    inc gc_y
    lda gc_err+1                ; err < 0 ?
    bmi @err_neg
    dec gc_x                    ; no: also step x inward,
    sec                         ; err += 2*(y - x) + 1
    lda gc_y
    sbc gc_x
    sta X16_T0
    lda #0
    sbc #0
    sta X16_T1
    asl X16_T0
    rol X16_T1
    inc X16_T0
    bne @add_err
    inc X16_T1
@add_err
    clc
    lda gc_err
    adc X16_T0
    sta gc_err
    lda gc_err+1
    adc X16_T1
    sta gc_err+1
    bra @cont
@err_neg
    lda gc_y                    ; err += 2*y + 1
    stz X16_T1
    asl
    rol X16_T1
    inc a
    bne @add2
    inc X16_T1
@add2
    clc
    adc gc_err
    sta gc_err
    lda gc_err+1
    adc X16_T1
    sta gc_err+1
@cont
    lda gc_y
    cmp gc_x
    bcc @loop
    beq @loop_last
    jmp bitmap_c_restore
@loop_last
    lda gc_x                    ; the final x == y diagonal points
    ldy gc_y
    jsr bitmap_c_plot4
    jmp bitmap_c_restore

; ---------------------------------------------------------------------
; gfx_disc -- filled circle
;   same arguments as gfx_circle. Draws horizontal spans clamped to
;   the screen, so it clips too. Preserves X16_P0..P4.
; ---------------------------------------------------------------------
gfx_disc
    jsr bitmap_c_setup
    lda gc_r
    sta gc_x
    stz gc_y
    sec
    lda #1
    sbc gc_r
    sta gc_err
    lda #0
    sbc #0
    sta gc_err+1

@dloop
    lda gc_x                    ; spans at cy+/-y, half-width x
    ldy gc_y
    jsr bitmap_c_span2
    lda gc_y                    ; spans at cy+/-x, half-width y
    ldy gc_x
    jsr bitmap_c_span2

    inc gc_y
    lda gc_err+1
    bmi @derr_neg
    dec gc_x
    sec
    lda gc_y
    sbc gc_x
    sta X16_T0
    lda #0
    sbc #0
    sta X16_T1
    asl X16_T0
    rol X16_T1
    inc X16_T0
    bne @dadd
    inc X16_T1
@dadd
    clc
    lda gc_err
    adc X16_T0
    sta gc_err
    lda gc_err+1
    adc X16_T1
    sta gc_err+1
    bra @dcont
@derr_neg
    lda gc_y
    stz X16_T1
    asl
    rol X16_T1
    inc a
    bne @dadd2
    inc X16_T1
@dadd2
    clc
    adc gc_err
    sta gc_err
    lda gc_err+1
    adc X16_T1
    sta gc_err+1
@dcont
    lda gc_y
    cmp gc_x
    bcc @dloop
    beq @dloop_last
    jmp bitmap_c_restore
@dloop_last
    lda gc_x
    ldy gc_y
    jsr bitmap_c_span2
    jmp bitmap_c_restore

; --- circle plumbing --------------------------------------------------

bitmap_c_setup
    lda X16_P0
    sta gc_cx
    sta gc_sav
    lda X16_P1
    sta gc_cx+1
    sta gc_sav+1
    lda X16_P2
    sta gc_cy
    sta gc_sav+2
    lda X16_P4
    sta gc_r
    sta gc_sav+3
    rts

bitmap_c_restore
    lda gc_sav
    sta X16_P0
    lda gc_sav+1
    sta X16_P1
    lda gc_sav+2
    sta X16_P2
    lda gc_sav+3
    sta X16_P4
    rts

; plot (cx +/- A, cy +/- Y): the four reflections of one octant point
bitmap_c_plot4
    sta gc_ox
    sty gc_oy
    jsr bitmap_c_ypl
    bcs @p4_low
    jsr bitmap_c_xpl
    jsr gfx_pset
    jsr bitmap_c_xmi
    jsr gfx_pset
@p4_low
    jsr bitmap_c_ymi
    bcs @p4_done
    jsr bitmap_c_xpl
    jsr gfx_pset
    jsr bitmap_c_xmi
    jsr gfx_pset
@p4_done
    rts

; two clamped horizontal spans: rows cy +/- Y, half-width A
bitmap_c_span2
    sta gc_ox
    sty gc_oy
    jsr bitmap_c_ypl
    bcs @s2_lower
    jsr bitmap_c_hspan
@s2_lower
    lda gc_oy
    beq @s2_done                ; same row twice: skip the mirror
    jsr bitmap_c_ymi
    bcs @s2_done
    jsr bitmap_c_hspan
@s2_done
    rts

; X16_P2 already holds the row: draw cx-gc_ox .. cx+gc_ox clamped
bitmap_c_hspan
    sec                         ; left = cx - ox, clamped to 0
    lda gc_cx
    sbc gc_ox
    sta X16_T0
    lda gc_cx+1
    sbc #0
    sta X16_T1
    bpl @left_ok
    stz X16_T0
    stz X16_T1
@left_ok
    clc                         ; right = cx + ox, clamped to 319
    lda gc_cx
    adc gc_ox
    sta X16_T2
    lda gc_cx+1
    adc #0
    sta X16_T3
    ; right >= 320 ?
    lda X16_T3
    cmp #>320
    bcc @right_ok
    bne @clamp_r
    lda X16_T2
    cmp #<320
    bcc @right_ok
@clamp_r
    lda #<319
    sta X16_T2
    lda #>319
    sta X16_T3
@right_ok
    ; entirely off screen?
    sec
    lda X16_T2
    sbc X16_T0
    sta X16_T4
    lda X16_T3
    sbc X16_T1
    sta X16_T5
    bmi @off
    inc X16_T4                  ; length = right - left + 1
    bne @len_ok
    inc X16_T5
@len_ok
    lda X16_T0
    sta X16_P0
    lda X16_T1
    sta X16_P1
    lda X16_T4
    sta X16_P4
    lda X16_T5
    sta X16_P5
    jmp gfx_hline
@off
    rts

; X16_P2 = cy + gc_oy; carry set if the row is off screen (>255).
; Rows 240-255 are left to gfx_pset/vera_fill? No -- reject them here.
bitmap_c_ypl
    clc
    lda gc_cy
    adc gc_oy
    bcs @ypl_bad                ; past 255
    cmp #GFX_HEIGHT
    bcs @ypl_bad                ; 240..255
    sta X16_P2
    clc
    rts
@ypl_bad
    sec
    rts

; X16_P2 = cy - gc_oy; carry set if above the screen.
bitmap_c_ymi
    sec
    lda gc_cy
    sbc gc_oy
    bcc @ymi_bad
    sta X16_P2
    clc
    rts
@ymi_bad
    sec
    rts

bitmap_c_xpl
    clc
    lda gc_cx
    adc gc_ox
    sta X16_P0
    lda gc_cx+1
    adc #0
    sta X16_P1
    rts

bitmap_c_xmi
    sec
    lda gc_cx
    sbc gc_ox
    sta X16_P0
    lda gc_cx+1
    sbc #0
    sta X16_P1
    rts

gc_cx  .word 0
gc_cy  .byte 0
gc_r   .byte 0
gc_x   .byte 0
gc_y   .byte 0
gc_ox  .byte 0
gc_oy  .byte 0
gc_err .word 0
gc_sav .res 4, 0

; ---------------------------------------------------------------------
; gfx_char -- draw one glyph from the VRAM charset into the bitmap
;   in:  A = screen code (0-255)
;        X16_P0/P1 = x, X16_P2 = y, X16_P3 = colour
;
; Reads the 8-byte 1bpp glyph from the charset the KERNAL keeps at
; VRAM $1F000; set bits become colour pixels through gfx_pset (so text
; clips), clear bits stay transparent. Preserves X16_P0..P3.
;
; gfx_text -- a NUL-terminated string, 8 pixels per character
;   in:  A = string low, X = string high; X16_P0..P3 as above.
;   ASCII letters are converted to screen codes ('A'-'Z' work as
;   expected); X16_P0/P1 are left one past the final character.
; ---------------------------------------------------------------------
gfx_char
    ; glyph address = VRAM_CHARSET + code * 8  (17-bit)
    sta gt_code
    stz gt_hi
    asl
    rol gt_hi
    asl
    rol gt_hi
    asl
    rol gt_hi                   ; gt_hi:A = code * 8
    pha
    vera_addrsel 1
    pla
    sta VERA_ADDR_L
    lda gt_hi
    clc
    adc #<(VRAM_CHARSET >> 8)
    sta VERA_ADDR_M
    lda #(VERA_ADDR_H_BANK | (VERA_INC_1 << 4))   ; $1F000 is in bank 1
    sta VERA_ADDR_H
    ldx #0
@fetch
    lda VERA_DATA1
    sta gt_glyph,x
    inx
    cpx #8
    bne @fetch
    vera_addrsel 0

    lda X16_P0                  ; park the caller's position
    sta gt_bx
    lda X16_P1
    sta gt_bx+1
    lda X16_P2
    sta gt_by

    stz gt_row
@rows
    ldx gt_row
    lda gt_glyph,x
    sta gt_bits
    beq @next_row               ; a blank row: nothing to plot
    stz gt_col
@cols
    asl gt_bits                 ; leftmost pixel first
    bcc @next_col
    clc
    lda gt_bx
    adc gt_col
    sta X16_P0
    lda gt_bx+1
    adc #0
    sta X16_P1
    clc
    lda gt_by
    adc gt_row
    bcs @next_col               ; wrapped past 255: off screen
    sta X16_P2
    jsr gfx_pset
@next_col
    inc gt_col
    lda gt_col
    cmp #8
    bne @cols
@next_row
    inc gt_row
    lda gt_row
    cmp #8
    bne @rows

    lda gt_bx                   ; restore the caller's block
    sta X16_P0
    lda gt_bx+1
    sta X16_P1
    lda gt_by
    sta X16_P2
    rts

gfx_text
    sta bitmap_gt_lda+1               ; the string pointer lives in the lda's
    stx bitmap_gt_lda+2               ; own operand (no zero page needed)
gtx_tloop
bitmap_gt_lda
    lda $FFFF                   ; operand patched above and stepped below
    beq gtx_tdone
    ; ASCII -> screen code: bit 6 set means letters/at-sign block
    bit #%01000000
    beq gtx_code_ok
    and #$1F
gtx_code_ok
    jsr gfx_char
    clc                         ; advance the pen 8 pixels
    lda X16_P0
    adc #8
    sta X16_P0
    lda X16_P1
    adc #0
    sta X16_P1
    inc bitmap_gt_lda+1
    bne gtx_tloop
    inc bitmap_gt_lda+2
    bra gtx_tloop
gtx_tdone
    rts

gt_code  .byte 0
gt_hi    .byte 0
gt_glyph .res 8, 0
gt_bx    .word 0
gt_by    .byte 0
gt_row   .byte 0
gt_col   .byte 0
gt_bits  .byte 0

; ---------------------------------------------------------------------
; gfx_flood -- scanline flood fill
;   in:  X16_P0/P1 = seed x, X16_P2 = seed y, X16_P3 = fill colour
;   out: carry clear = filled completely; carry set = the span stack
;        overflowed and the fill is INCOMPLETE (pathological shapes:
;        the stack holds 170 pending spans)
;
; Fills the 4-connected region of the seed's colour. Filling with the
; colour already under the seed is a no-op. Spans are painted with
; gfx_hline; both VERA ports get repointed freely.
; ---------------------------------------------------------------------
FF_DEPTH = 170

gfx_flood
    lda X16_P2                  ; a seed off screen fills nothing
    cmp #GFX_HEIGHT
    bcs @bail
    lda X16_P1
    beq @seed_ok
    cmp #1
    bne @bail
    lda X16_P0
    cmp #<GFX_WIDTH
    bcc @seed_ok
@bail
    clc
    rts
@seed_ok
    lda X16_P3
    sta ff_col
    lda X16_P0
    sta ff_x
    lda X16_P1
    sta ff_x+1
    lda X16_P2
    sta ff_y

    jsr bitmap_f_rd                   ; the colour being replaced
    sta ff_tgt
    cmp ff_col
    beq @bail                   ; already the fill colour: no-op

    stz ff_sp
    stz ff_ovf
    lda ff_x
    sta ff_px
    lda ff_x+1
    sta ff_px+1
    lda ff_y
    sta ff_ny
    jsr bitmap_f_push

@main
    lda ff_sp
    bne @have_work
    jmp @finish
@have_work
    jsr bitmap_f_pop                  ; -> ff_x / ff_y
    jsr bitmap_f_rd
    cmp ff_tgt
    bne @main                   ; painted over since it was queued

    ; grow the span left: xl = leftmost target pixel
    lda ff_x
    sta ff_xl
    lda ff_x+1
    sta ff_xl+1
    lda ff_xl
    ora ff_xl+1
    beq @left_done
    sec                         ; walk from xl-1 downwards
    lda ff_xl
    sbc #1
    sta ff_ax
    lda ff_xl+1
    sbc #0
    sta ff_ax+1
    lda ff_y
    sta ff_ay
    lda #VERA_ADDR_H_DECR
    jsr bitmap_f_addr1
@left_scan
    lda VERA_DATA1
    cmp ff_tgt
    bne @left_done
    lda ff_xl
    bne @left_dec
    dec ff_xl+1
@left_dec
    dec ff_xl
    lda ff_xl
    ora ff_xl+1
    bne @left_scan
@left_done

    ; grow the span right: xr = rightmost target pixel
    lda ff_x
    sta ff_xr
    lda ff_x+1
    sta ff_xr+1
    jsr bitmap_f_at_right
    bcs @right_done
    clc                         ; walk from xr+1 upwards
    lda ff_xr
    adc #1
    sta ff_ax
    lda ff_xr+1
    adc #0
    sta ff_ax+1
    lda ff_y
    sta ff_ay
    lda #0
    jsr bitmap_f_addr1
@right_scan
    lda VERA_DATA1
    cmp ff_tgt
    bne @right_done
    inc ff_xr
    bne @right_chk
    inc ff_xr+1
@right_chk
    jsr bitmap_f_at_right
    bcc @right_scan
@right_done

    ; paint it
    lda ff_xl
    sta X16_P0
    lda ff_xl+1
    sta X16_P1
    lda ff_y
    sta X16_P2
    lda ff_col
    sta X16_P3
    sec                         ; length = xr - xl + 1
    lda ff_xr
    sbc ff_xl
    sta X16_P4
    lda ff_xr+1
    sbc ff_xl+1
    sta X16_P5
    inc X16_P4
    bne @len_ok
    inc X16_P5
@len_ok
    jsr gfx_hline

    ; queue fresh spans in the rows above and below
    lda ff_y
    beq @no_up
    dec a
    sta ff_ny
    jsr bitmap_f_scanrow
@no_up
    lda ff_y
    cmp #(GFX_HEIGHT - 1)
    bcs @no_down
    inc a
    sta ff_ny
    jsr bitmap_f_scanrow
@no_down
    jmp @main

@finish
    vera_addrsel 0
    lda ff_ovf                  ; carry = "the fill may be incomplete"
    lsr
    rts

ff_x   .word 0
ff_y   .byte 0
ff_xl  .word 0
ff_xr  .word 0
ff_px  .word 0
ff_ny  .byte 0
ff_ax  .word 0
ff_ay  .byte 0
ff_h   .byte 0
ff_tgt .byte 0
ff_col .byte 0
ff_seg .byte 0
ff_cnt .word 0
ff_sp  .byte 0
ff_ovf .byte 0

; carry set when ff_xr is the last column (319)
bitmap_f_at_right
    lda ff_xr+1
    cmp #>(GFX_WIDTH - 1)
    bne @below
    lda ff_xr
    cmp #<(GFX_WIDTH - 1)
    bcs @at
@below
    clc
    rts
@at
    sec
    rts

; scan row ff_ny across columns ff_xl..ff_xr, pushing the start of
; every run of target-coloured pixels
bitmap_f_scanrow
    lda ff_xl
    sta ff_ax
    sta ff_px
    lda ff_xl+1
    sta ff_ax+1
    sta ff_px+1
    lda ff_ny
    sta ff_ay
    lda #0
    jsr bitmap_f_addr1
    sec                         ; count = xr - xl + 1
    lda ff_xr
    sbc ff_xl
    sta ff_cnt
    lda ff_xr+1
    sbc ff_xl+1
    sta ff_cnt+1
    inc ff_cnt
    bne @counted
    inc ff_cnt+1
@counted
    stz ff_seg
@cell
    lda VERA_DATA1
    cmp ff_tgt
    bne @break
    lda ff_seg
    bne @step                   ; already inside a run
    jsr bitmap_f_push                 ; a run begins here: remember its start
    lda #1
    sta ff_seg
    bra @step
@break
    stz ff_seg
@step
    inc ff_px
    bne @count
    inc ff_px+1
@count
    lda ff_cnt
    bne @declo
    dec ff_cnt+1
@declo
    dec ff_cnt
    lda ff_cnt
    ora ff_cnt+1
    bne @cell
    rts

ff_stk .res FF_DEPTH * 3, 0

; push (ff_px, ff_ny); a full stack sets ff_ovf instead
bitmap_f_push
    lda ff_sp
    cmp #FF_DEPTH
    bcc @room
    lda #1
    sta ff_ovf
    rts
@room
    jsr bitmap_f_slot
    ldy #0
    lda ff_px
    sta (X16_T6),y
    iny
    lda ff_px+1
    sta (X16_T6),y
    iny
    lda ff_ny
    sta (X16_T6),y
    inc ff_sp
    rts

; pop -> ff_x, ff_y
bitmap_f_pop
    dec ff_sp
    jsr bitmap_f_slot
    ldy #0
    lda (X16_T6),y
    sta ff_x
    iny
    lda (X16_T6),y
    sta ff_x+1
    iny
    lda (X16_T6),y
    sta ff_y
    rts

; X16_T6/T7 = &ff_stk[ff_sp * 3]
bitmap_f_slot
    lda ff_sp
    sta X16_T6
    stz X16_T7
    asl X16_T6
    rol X16_T7
    clc
    lda X16_T6
    adc ff_sp
    sta X16_T6
    lda X16_T7
    adc #0
    sta X16_T7
    clc
    lda X16_T6
    adc #<ff_stk
    sta X16_T6
    lda X16_T7
    adc #>ff_stk
    sta X16_T7
    rts

; A = the pixel at (ff_x, ff_y)
bitmap_f_rd
    lda ff_x
    sta ff_ax
    lda ff_x+1
    sta ff_ax+1
    lda ff_y
    sta ff_ay
    lda #0
    jsr bitmap_f_addr1
    lda VERA_DATA1
    rts

; point port 1 at (ff_ax, ff_ay), INC_1, with A's DECR flag
bitmap_f_addr1
    ora #(VERA_INC_1 << 4)
    sta ff_h
    lda ff_ay                   ; ay*320 = ay*64 + ay*256
    stz X16_T1
    asl
    rol X16_T1
    asl
    rol X16_T1
    asl
    rol X16_T1
    asl
    rol X16_T1
    asl
    rol X16_T1
    asl
    rol X16_T1
    sta X16_T0
    clc
    lda ff_ay
    adc X16_T1
    sta X16_T1
    lda #0
    adc #0
    sta X16_T2
    clc                         ; + ax
    lda X16_T0
    adc ff_ax
    sta X16_T0
    lda X16_T1
    adc ff_ax+1
    sta X16_T1
    lda X16_T2
    adc #0
    sta X16_T2
    lda #VERA_CTRL_ADDRSEL
    tsb VERA_CTRL
    lda X16_T0
    sta VERA_ADDR_L
    lda X16_T1
    sta VERA_ADDR_M
    lda X16_T2
    and #VERA_ADDR_H_BANK
    ora ff_h
    sta VERA_ADDR_H
    rts

; ---------------------------------------------------------------------
; Module variables. Kept out of zero page: these are only touched by
; the routine that owns them, never across a call boundary.
; ---------------------------------------------------------------------
.endif                          ; X16_BITMAP_MIN -- the core data below
                                ; belongs to rect/frame/line, not the extras

gb_x    .word 0
gb_y    .byte 0
gb_w    .word 0
gb_h    .byte 0
gb_c    .byte 0

gl_x0    .word 0
gl_y0    .byte 0
gl_x1    .word 0
gl_y1    .byte 0
gl_color .byte 0
gl_dx    .word 0
gl_dy    .word 0
gl_err   .word 0
gl_e2    .word 0
gl_sx    .word 0
gl_sy    .byte 0
gl_tmp   .byte 0

; (end zone)
