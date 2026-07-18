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
; gfx_pset clips. The line/rect primitives do NOT: they assume
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
; bitmap_addr8 -- the 17-bit framebuffer address of (gb8_x, gb8_y) -> the
; port named by bitmap_ld0/bitmap_ld1, with INC_1. y*320 = (y<<8) + (y<<6).
; ---------------------------------------------------------------------
bitmap_addr8
	lda gb8_y                   ; y << 6 into a word
	sta gb8_t
	lda #0
	sta gb8_t+1
	ldx #6
bitmap_a8sh
	asl gb8_t
	rol gb8_t+1
	dex
	bne bitmap_a8sh
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

bitmap_ld0
	lda #VERA_CTRL_ADDRSEL
	trb VERA_CTRL
	bra bitmap_ldgo
bitmap_ld1
	lda #VERA_CTRL_ADDRSEL
	tsb VERA_CTRL
bitmap_ldgo
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
bitmap_gpcp
	lda (X16_T0),y
	sta gp8_pat,y
	dey
	bpl bitmap_gpcp
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
bitmap_gprow
	jsr bitmap_addr8
	jsr bitmap_ld0
	lda gb8_y                   ; the pattern row: y & 7
	and #7
	tay
	lda gp8_pat,y
	ldy gp8_rot                 ; pre-rotate to the column phase
	beq bitmap_gpgo
bitmap_gppre
	asl
	adc #0                      ; circular left: bit 7 wraps to bit 0
	dey
	bne bitmap_gppre
bitmap_gpgo
	sta gp8_cur
	lda gp8_w                   ; the width countdown, 16-bit
	sta gb8_t
	lda gp8_w+1
	sta gb8_t+1
bitmap_gppx
	lda gp8_cur                 ; bit 7 = this pixel
	bmi bitmap_gpfg
	lda gp8_bg
	bra bitmap_gpout
bitmap_gpfg
	lda gp8_fg
bitmap_gpout
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
	bne bitmap_gppx
	inc gb8_y                   ; the next row
	dec gp8_h
	bne bitmap_gprow
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
bitmap_gbrow
	jsr bitmap_addr8
	jsr bitmap_ld0
	lda gb8_op
	beq bitmap_gbcopy
	jsr bitmap_ld1                    ; the RMW ops read through port 1
	ldy #0
bitmap_gbop
	lda gb8_op
	cmp #2
	beq bitmap_gband
	bcs bitmap_gbxor
	lda (X16_PTR3),y            ; OR
	ora VERA_DATA1
	bra bitmap_gbw
bitmap_gband
	lda (X16_PTR3),y
	and VERA_DATA1
	bra bitmap_gbw
bitmap_gbxor
	lda (X16_PTR3),y
	eor VERA_DATA1
bitmap_gbw
	sta VERA_DATA0
	iny
	cpy X16_P4
	bne bitmap_gbop
	bra bitmap_gbnext
bitmap_gbcopy
	ldy #0
bitmap_gbcp
	lda (X16_PTR3),y
	sta VERA_DATA0
	iny
	cpy X16_P4
	bne bitmap_gbcp
bitmap_gbnext
	clc                         ; the next source row
	lda X16_PTR3
	adc X16_P4
	sta X16_PTR3
	bcc :+
	inc X16_PTR3+1
:	inc gb8_y
	dec gb8_h
	bne bitmap_gbrow
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
bitmap_gmrow
	jsr bitmap_addr8
	jsr bitmap_ld0
	ldy #0
bitmap_gmpx
	lda (X16_PTR3),y
	beq bitmap_gmskip
	sta VERA_DATA0
	bra bitmap_gmn
bitmap_gmskip
	lda VERA_DATA0              ; advance without writing
bitmap_gmn
	iny
	cpy X16_P4
	bne bitmap_gmpx
	clc
	lda X16_PTR3
	adc X16_P4
	sta X16_PTR3
	bcc :+
	inc X16_PTR3+1
:	inc gb8_y
	dec gb8_h
	bne bitmap_gmrow
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
; The gfx_char / gfx_text glyph drawing below is optional. Define
; X16_BITMAP_MIN to leave it out: init/clear/read/pset/lines/rect/
; frame/pattern/blit only. CXGEOS's 8bpp overlay image uses it to fit
; its fixed region; a full build is unchanged.
;
; Circle, disc and flood are NOT here -- they live in gfx/shapes.asm,
; which draws through any engine's pset/hline/read and so serves this
; module and gfx2 alike (source it and bind SHP_* to gfx_* to draw them
; at 8bpp). One copy, not one per engine.
.ifndef X16_BITMAP_MIN

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
; Module variables. Kept out of zero page: these are only touched by
; the routine that owns them, never across a call boundary.
; ---------------------------------------------------------------------
.endif

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
