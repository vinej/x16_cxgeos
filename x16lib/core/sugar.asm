;ACME
; =====================================================================
; x16lib :: core/sugar.asm -- optional friendly call macros (the "xm_" SDK)
; =====================================================================
; A thin, READ-ONLY convenience layer over the whole library: one macro
; per public routine, named xm_<routine>, that loads the argument block
; and calls it. So a program reads
;
;       +xm_shape_frrect 40, 40, 200, 110, 28, FILL
;       +xm_pal_set 1, $0F00
;       +xm_sprite_pos 0, 100, 50
;
; instead of a dozen lda/sta lines. This is the same idea as the CXGEOS
; asmsdk cxm_* layer, adapted to this repo's conventions and generated
; the same way as everything else here (written for ACME; the six ports
; are produced by tools/acme2*sugar_py -- it is NOT in their SKIP set).
;
; PURELY ADDITIVE and OPT-IN. Nothing sources this for you; add it
; yourself, once. Each module's macros are wrapped in that module's
; X16_USE_* gate, so SET YOUR GATES FIRST, then source this (before your
; own code, since the macros must be defined before you invoke them):
;
;       .include "x16.asm"
;       X16_USE_SHAPES_RRECT = 1     ; <- your gates first
;       X16_USE_BITMAP2      = 1
;       .include "core/sugar.asm"     ; <- then the (optional) macros
;       ... your program ...
;       .include "x16_code.asm"
;
; The gating matters: a macro that referenced a routine from a module you
; did not enable would be a dangling symbol under the stricter assemblers
; (KickAssembler), so xm_pal_set only exists when X16_USE_PALETTE is set,
; and so on. Set a gate to get its macros; the sub-gates (SHAPES_RRECT,
; PCM_STREAM, ...) each gate their own.
;
; A program that does not source this file, or does not invoke a macro,
; is byte-for-byte unchanged. Each macro expands to exactly the
; hand-written argument setup + jsr, so it costs nothing at run time, and
; you still pay only for the modules whose gates you enable -- a macro is
; only "real" when you invoke it and only then needs its routine linked.
;
; Conventions (mirroring the routine headers):
;   * A macro takes the routine's arguments in their natural order.
;     16-bit things (coordinates, sizes, addresses) are passed whole and
;     split here; bytes (colours, radii, angles, voice/sprite numbers)
;     pass through as-is.
;   * Angles are the sin8/cos8 byte convention: 0 = east, 64 = south.
;   * Arguments are loaded as IMMEDIATES (lda #arg), so pass constants or
;     assemble-time expressions. To call with a value held in a variable,
;     set the argument block by hand and jsr the routine directly -- the
;     macro is a convenience for the common constant case, not a wrapper
;     you can feed run-time values through.
;   * A "-> " note above a macro says what the routine returns (registers
;     / the P block / a carry flag); the macro does not capture it.
;   * Pure no-argument arithmetic (i16_add, f_neg, d_sqrt, ...) has no
;     macro -- a wrapper would add nothing, so call it directly. The
;     init/on/off/wait style calls are wrapped for a uniform call style.
;
; The routines these wrap live behind the X16_USE_* gates documented in
; x16_code.asm; enabling a macro's module is on you.
; =====================================================================

; =====================================================================
; video/vera
; =====================================================================
; point port 0 (compose the H byte -- bank | DECR | incr<<4 -- yourself)
.ifdef X16_USE_VERA
.macro xm_vera_set_addr0 p_l, p_m, p_h
    lda #(p_l)
    ldx #(p_m)
    ldy #(p_h)
    jsr vera_set_addr0
.endmacro
.endif
; point port 1
.ifdef X16_USE_VERA
.macro xm_vera_set_addr1 p_l, p_m, p_h
    lda #(p_l)
    ldx #(p_m)
    ldy #(p_h)
    jsr vera_set_addr1
.endmacro
.endif
; fill `count` bytes with `val` from the current port address
.ifdef X16_USE_VERA
.macro xm_vera_fill p_val, p_count
    lda #(p_val)
    ldx #<(p_count)
    ldy #>(p_count)
    jsr vera_fill
.endmacro
.endif
; copy `count` bytes port0 -> port1 (both pre-pointed)
.ifdef X16_USE_VERA
.macro xm_vera_copy p_count
    ldx #<(p_count)
    ldy #>(p_count)
    jsr vera_copy
.endmacro
.endif

; =====================================================================
; video/screen
; =====================================================================
; -> carry set if the mode is unsupported
.ifdef X16_USE_SCREEN
.macro xm_screen_set_mode p_mode
    lda #(p_mode)
    jsr screen_set_mode
.endmacro
.endif
.ifdef X16_USE_SCREEN
.macro xm_screen_reset
    jsr screen_reset
.endmacro
.endif
.ifdef X16_USE_SCREEN
.macro xm_screen_cls
    jsr screen_cls
.endmacro
.endif
.ifdef X16_USE_SCREEN
.macro xm_screen_chrout p_ch
    lda #(p_ch)
    jsr screen_chrout
.endmacro
.endif
.ifdef X16_USE_SCREEN
.macro xm_screen_color p_fg, p_bg
    lda #(p_fg)
    ldx #(p_bg)
    jsr screen_color
.endmacro
.endif
.ifdef X16_USE_SCREEN
.macro xm_screen_border p_col
    lda #(p_col)
    jsr screen_border
.endmacro
.endif
.ifdef X16_USE_SCREEN
.macro xm_screen_locate p_row, p_col
    ldx #(p_row)
    ldy #(p_col)
    jsr screen_locate
.endmacro
.endif
.ifdef X16_USE_SCREEN
.macro xm_screen_charset p_cs
    lda #(p_cs)
    jsr screen_charset
.endmacro
.endif
; print a NUL-terminated string
.ifdef X16_USE_SCREEN
.macro xm_screen_puts p_addr
    lda #<(p_addr)
    ldx #>(p_addr)
    jsr screen_puts
.endmacro
.endif

; =====================================================================
; video/palette
; =====================================================================
; set one entry; rgb is a 12-bit $0RGB value
.ifdef X16_USE_PALETTE
.macro xm_pal_set p_index, p_rgb
    ldx #(p_index)
    lda #<(p_rgb)
    ldy #>(p_rgb)
    jsr pal_set
.endmacro
.endif
; bulk-load `count` entries from RAM (2 bytes each, low first)
.ifdef X16_USE_PALETTE
.macro xm_pal_load p_src, p_first, p_count
    lda #<(p_src)
    sta X16_PTR0
    lda #>(p_src)
    sta X16_PTR0+1
    lda #(p_first)
    ldx #(p_count)
    jsr pal_load
.endmacro
.endif

; =====================================================================
; video/tile  (layer config + tilemap cells)
; =====================================================================
.ifdef X16_USE_TILE
.macro xm_layer_on p_layer
    lda #(p_layer)
    jsr layer_on
.endmacro
.endif
.ifdef X16_USE_TILE
.macro xm_layer_off p_layer
    lda #(p_layer)
    jsr layer_off
.endmacro
.endif
.ifdef X16_USE_TILE
.macro xm_layer_set_config p_layer, p_cfg
    ldx #(p_layer)
    lda #(p_cfg)
    jsr layer_set_config
.endmacro
.endif
.ifdef X16_USE_TILE
.macro xm_layer_set_mapbase p_layer, p_base
    ldx #(p_layer)
    lda #(p_base)
    jsr layer_set_mapbase
.endmacro
.endif
.ifdef X16_USE_TILE
.macro xm_layer_scroll_x p_layer, p_val
    ldx #(p_layer)
    lda #<(p_val)
    sta X16_P0
    lda #>(p_val)
    sta X16_P1
    jsr layer_scroll_x
.endmacro
.endif
.ifdef X16_USE_TILE
.macro xm_layer_scroll_y p_layer, p_val
    ldx #(p_layer)
    lda #<(p_val)
    sta X16_P0
    lda #>(p_val)
    sta X16_P1
    jsr layer_scroll_y
.endmacro
.endif
.ifdef X16_USE_TILE
.macro xm_tile_setptr p_col, p_row
    ldx #(p_col)
    ldy #(p_row)
    jsr tile_setptr
.endmacro
.endif
.ifdef X16_USE_TILE
.macro xm_tile_put p_col, p_row, p_code, p_attr
    ldx #(p_col)
    ldy #(p_row)
    lda #(p_code)
    sta X16_P0
    lda #(p_attr)
    sta X16_P1
    jsr tile_put
.endmacro
.endif
; -> A = screen code, X = attribute
.ifdef X16_USE_TILE
.macro xm_tile_get p_col, p_row
    ldx #(p_col)
    ldy #(p_row)
    jsr tile_get
.endmacro
.endif

; =====================================================================
; sprite/sprite
; =====================================================================
.ifdef X16_USE_SPRITE
.macro xm_sprites_on
    jsr sprites_on
.endmacro
.endif
.ifdef X16_USE_SPRITE
.macro xm_sprites_off
    jsr sprites_off
.endmacro
.endif
.ifdef X16_USE_SPRITE
.macro xm_sprite_init_all
    jsr sprite_init_all
.endmacro
.endif
.ifdef X16_USE_SPRITE
.macro xm_sprite_pos p_sprite, p_x, p_y
    ldx #(p_sprite)
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    jsr sprite_pos
.endmacro
.endif
; -> P0/1 = x, P2/3 = y
.ifdef X16_USE_SPRITE
.macro xm_sprite_get_pos p_sprite
    ldx #(p_sprite)
    jsr sprite_get_pos
.endmacro
.endif
; vaddr = 32-byte-aligned 17-bit VRAM address; mode = SPRITE_MODE_4BPP/8BPP
.ifdef X16_USE_SPRITE
.macro xm_sprite_image p_sprite, p_vaddr, p_mode
    ldx #(p_sprite)
    lda #<(p_vaddr)
    sta X16_P0
    lda #>(p_vaddr)
    sta X16_P1
    lda #<((p_vaddr) >> 16)
    sta X16_P2
    lda #(p_mode)
    jsr sprite_image
.endmacro
.endif
.ifdef X16_USE_SPRITE
.macro xm_sprite_flags p_sprite, p_flags
    ldx #(p_sprite)
    lda #(p_flags)
    jsr sprite_flags
.endmacro
.endif
.ifdef X16_USE_SPRITE
.macro xm_sprite_z p_sprite, p_z
    ldx #(p_sprite)
    lda #(p_z)
    jsr sprite_z
.endmacro
.endif
; width/height are SPRITE_SIZE_8/16/32/64 codes
.ifdef X16_USE_SPRITE
.macro xm_sprite_size p_sprite, p_wcode, p_hcode, p_paloff
    ldx #(p_sprite)
    lda #(p_paloff)
    sta X16_P0
    ldy #(p_hcode)
    lda #(p_wcode)
    jsr sprite_size
.endmacro
.endif

; =====================================================================
; gfx/bitmap  (320x240 @ 8bpp)
; =====================================================================
.ifdef X16_USE_BITMAP
.macro xm_gfx_init
    jsr gfx_init
.endmacro
.endif
.ifdef X16_USE_BITMAP
.macro xm_gfx_clear p_col
    lda #(p_col)
    jsr gfx_clear
.endmacro
.endif
.ifdef X16_USE_BITMAP
.macro xm_gfx_pset p_x, p_y, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    lda #(p_col)
    sta X16_P3
    jsr gfx_pset
.endmacro
.endif
; -> A = colour
.ifdef X16_USE_BITMAP
.macro xm_gfx_read p_x, p_y
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    jsr gfx_read
.endmacro
.endif
.ifdef X16_USE_BITMAP
.macro xm_gfx_hline p_x, p_y, p_len, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    lda #(p_col)
    sta X16_P3
    lda #<(p_len)
    sta X16_P4
    lda #>(p_len)
    sta X16_P5
    jsr gfx_hline
.endmacro
.endif
.ifdef X16_USE_BITMAP
.macro xm_gfx_vline p_x, p_y, p_len, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    lda #(p_col)
    sta X16_P3
    lda #<(p_len)
    sta X16_P4
    lda #>(p_len)
    sta X16_P5
    jsr gfx_vline
.endmacro
.endif
.ifdef X16_USE_BITMAP
.macro xm_gfx_rect p_x, p_y, p_w, p_h, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    lda #(p_col)
    sta X16_P3
    lda #<(p_w)
    sta X16_P4
    lda #>(p_w)
    sta X16_P5
    lda #(p_h)
    sta X16_P6
    jsr gfx_rect
.endmacro
.endif
.ifdef X16_USE_BITMAP
.macro xm_gfx_frame p_x, p_y, p_w, p_h, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    lda #(p_col)
    sta X16_P3
    lda #<(p_w)
    sta X16_P4
    lda #>(p_w)
    sta X16_P5
    lda #(p_h)
    sta X16_P6
    jsr gfx_frame
.endmacro
.endif
; A/X = the address of an 8x8 1bpp pattern
.ifdef X16_USE_BITMAP
.macro xm_gfx_pattern_set p_pat
    lda #<(p_pat)
    ldx #>(p_pat)
    jsr gfx_pattern_set
.endmacro
.endif
.ifdef X16_USE_BITMAP
.macro xm_gfx_pattern_rect p_x, p_y, p_w, p_h
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    lda #<(p_w)
    sta X16_P4
    lda #>(p_w)
    sta X16_P5
    lda #(p_h)
    sta X16_P6
    jsr gfx_pattern_rect
.endmacro
.endif
.ifdef X16_USE_BITMAP
.macro xm_gfx_line p_x0, p_y0, p_x1, p_y1, p_col
    lda #<(p_x0)
    sta X16_P0
    lda #>(p_x0)
    sta X16_P1
    lda #(p_y0)
    sta X16_P2
    lda #(p_col)
    sta X16_P3
    lda #<(p_x1)
    sta X16_P4
    lda #>(p_x1)
    sta X16_P5
    lda #(p_y1)
    sta X16_P6
    jsr gfx_line
.endmacro
.endif
.ifdef X16_USE_BITMAP
.macro xm_gfx_char p_code, p_x, p_y, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    lda #(p_col)
    sta X16_P3
    lda #(p_code)
    jsr gfx_char
.endmacro
.endif
; str = a NUL-terminated string
.ifdef X16_USE_BITMAP
.macro xm_gfx_text p_str, p_x, p_y, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    lda #(p_col)
    sta X16_P3
    lda #<(p_str)
    ldx #>(p_str)
    jsr gfx_text
.endmacro
.endif

; =====================================================================
; gfx/bitmap2  (640x480 @ 2bpp; colour in A)
; =====================================================================
.ifdef X16_USE_BITMAP2
.macro xm_gfx2_init
    jsr gfx2_init
.endmacro
.endif
.ifdef X16_USE_BITMAP2
.macro xm_gfx2_clear p_col
    lda #(p_col)
    jsr gfx2_clear
.endmacro
.endif
.ifdef X16_USE_BITMAP2
.macro xm_gfx2_pset p_x, p_y, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    lda #(p_col)
    jsr gfx2_pset
.endmacro
.endif
; -> A = colour, carry set if (x,y) is off screen
.ifdef X16_USE_BITMAP2
.macro xm_gfx2_read p_x, p_y
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    jsr gfx2_read
.endmacro
.endif
.ifdef X16_USE_BITMAP2
.macro xm_gfx2_hline p_x, p_y, p_len, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    lda #<(p_len)
    sta X16_P4
    lda #>(p_len)
    sta X16_P5
    lda #(p_col)
    jsr gfx2_hline
.endmacro
.endif
.ifdef X16_USE_BITMAP2
.macro xm_gfx2_vline p_x, p_y, p_len, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    lda #<(p_len)
    sta X16_P4
    lda #>(p_len)
    sta X16_P5
    lda #(p_col)
    jsr gfx2_vline
.endmacro
.endif
.ifdef X16_USE_BITMAP2
.macro xm_gfx2_rect p_x, p_y, p_w, p_h, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    lda #<(p_w)
    sta X16_P4
    lda #>(p_w)
    sta X16_P5
    lda #<(p_h)
    sta X16_P6
    lda #>(p_h)
    sta X16_P7
    lda #(p_col)
    jsr gfx2_rect
.endmacro
.endif
.ifdef X16_USE_BITMAP2
.macro xm_gfx2_frame p_x, p_y, p_w, p_h, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    lda #<(p_w)
    sta X16_P4
    lda #>(p_w)
    sta X16_P5
    lda #<(p_h)
    sta X16_P6
    lda #>(p_h)
    sta X16_P7
    lda #(p_col)
    jsr gfx2_frame
.endmacro
.endif
.ifdef X16_USE_BITMAP2
.macro xm_gfx2_line p_x0, p_y0, p_x1, p_y1, p_col
    lda #<(p_x0)
    sta X16_P0
    lda #>(p_x0)
    sta X16_P1
    lda #<(p_y0)
    sta X16_P2
    lda #>(p_y0)
    sta X16_P3
    lda #<(p_x1)
    sta X16_P4
    lda #>(p_x1)
    sta X16_P5
    lda #<(p_y1)
    sta X16_P6
    lda #>(p_y1)
    sta X16_P7
    lda #(p_col)
    jsr gfx2_line
.endmacro
.endif
; A/X = the address of an 8x8 1bpp pattern
.ifdef X16_USE_BITMAP2
.macro xm_gfx2_pattern_set p_pat
    lda #<(p_pat)
    ldx #>(p_pat)
    jsr gfx2_pattern_set
.endmacro
.endif
.ifdef X16_USE_BITMAP2
.macro xm_gfx2_pattern_rect p_x, p_y, p_w, p_h
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    lda #<(p_w)
    sta X16_P4
    lda #>(p_w)
    sta X16_P5
    lda #<(p_h)
    sta X16_P6
    lda #>(p_h)
    sta X16_P7
    jsr gfx2_pattern_rect
.endmacro
.endif

; =====================================================================
; gfx/shapes  (engine-agnostic; bind SHP_* to pick the engine)
; =====================================================================
.ifdef X16_USE_SHAPES
.macro xm_shape_circle p_cx, p_cy, p_r, p_col
    lda #<(p_cx)
    sta X16_P0
    lda #>(p_cx)
    sta X16_P1
    lda #<(p_cy)
    sta X16_P2
    lda #>(p_cy)
    sta X16_P3
    lda #(p_r)
    sta X16_P4
    lda #(p_col)
    jsr shape_circle
.endmacro
.endif
.ifdef X16_USE_SHAPES
.macro xm_shape_disc p_cx, p_cy, p_r, p_col
    lda #<(p_cx)
    sta X16_P0
    lda #>(p_cx)
    sta X16_P1
    lda #<(p_cy)
    sta X16_P2
    lda #>(p_cy)
    sta X16_P3
    lda #(p_r)
    sta X16_P4
    lda #(p_col)
    jsr shape_disc
.endmacro
.endif
.ifdef X16_USE_SHAPES
.macro xm_shape_ellipse p_cx, p_cy, p_rx, p_ry, p_col
    lda #<(p_cx)
    sta X16_P0
    lda #>(p_cx)
    sta X16_P1
    lda #<(p_cy)
    sta X16_P2
    lda #>(p_cy)
    sta X16_P3
    lda #(p_rx)
    sta X16_P4
    lda #(p_ry)
    sta X16_P5
    lda #(p_col)
    jsr shape_ellipse
.endmacro
.endif
.ifdef X16_USE_SHAPES
.macro xm_shape_fellipse p_cx, p_cy, p_rx, p_ry, p_col
    lda #<(p_cx)
    sta X16_P0
    lda #>(p_cx)
    sta X16_P1
    lda #<(p_cy)
    sta X16_P2
    lda #>(p_cy)
    sta X16_P3
    lda #(p_rx)
    sta X16_P4
    lda #(p_ry)
    sta X16_P5
    lda #(p_col)
    jsr shape_fellipse
.endmacro
.endif
.ifdef X16_USE_SHAPES_RRECT
.macro xm_shape_rrect p_x, p_y, p_w, p_h, p_r, p_col
    lda #<(p_x)
    sta rr_x
    lda #>(p_x)
    sta rr_x+1
    lda #<(p_y)
    sta rr_y
    lda #>(p_y)
    sta rr_y+1
    lda #<(p_w)
    sta rr_w
    lda #>(p_w)
    sta rr_w+1
    lda #<(p_h)
    sta rr_h
    lda #>(p_h)
    sta rr_h+1
    lda #(p_r)
    sta rr_r
    lda #(p_col)
    jsr shape_rrect
.endmacro
.endif
.ifdef X16_USE_SHAPES_RRECT
.macro xm_shape_frrect p_x, p_y, p_w, p_h, p_r, p_col
    lda #<(p_x)
    sta rr_x
    lda #>(p_x)
    sta rr_x+1
    lda #<(p_y)
    sta rr_y
    lda #>(p_y)
    sta rr_y+1
    lda #<(p_w)
    sta rr_w
    lda #>(p_w)
    sta rr_w+1
    lda #<(p_h)
    sta rr_h
    lda #>(p_h)
    sta rr_h+1
    lda #(p_r)
    sta rr_r
    lda #(p_col)
    jsr shape_frrect
.endmacro
.endif
.ifdef X16_USE_SHAPES_POLY
.macro xm_shape_polygon p_cx, p_cy, p_r, p_sides, p_rot, p_col
    lda #<(p_cx)
    sta X16_P0
    lda #>(p_cx)
    sta X16_P1
    lda #<(p_cy)
    sta X16_P2
    lda #>(p_cy)
    sta X16_P3
    lda #(p_r)
    sta X16_P4
    lda #(p_sides)
    sta X16_P5
    lda #(p_rot)
    sta X16_P6
    lda #(p_col)
    jsr shape_polygon
.endmacro
.endif
.ifdef X16_USE_SHAPES_POLY
.macro xm_shape_fpolygon p_cx, p_cy, p_r, p_sides, p_rot, p_col
    lda #<(p_cx)
    sta X16_P0
    lda #>(p_cx)
    sta X16_P1
    lda #<(p_cy)
    sta X16_P2
    lda #>(p_cy)
    sta X16_P3
    lda #(p_r)
    sta X16_P4
    lda #(p_sides)
    sta X16_P5
    lda #(p_rot)
    sta X16_P6
    lda #(p_col)
    jsr shape_fpolygon
.endmacro
.endif
.ifdef X16_USE_SHAPES_ARC
.macro xm_shape_arc p_cx, p_cy, p_r, p_a0, p_a1, p_col
    lda #<(p_cx)
    sta X16_P0
    lda #>(p_cx)
    sta X16_P1
    lda #<(p_cy)
    sta X16_P2
    lda #>(p_cy)
    sta X16_P3
    lda #(p_r)
    sta X16_P4
    lda #(p_a0)
    sta X16_P5
    lda #(p_a1)
    sta X16_P6
    lda #(p_col)
    jsr shape_arc
.endmacro
.endif
.ifdef X16_USE_SHAPES_PIE
.macro xm_shape_pie p_cx, p_cy, p_r, p_a0, p_a1, p_col
    lda #<(p_cx)
    sta X16_P0
    lda #>(p_cx)
    sta X16_P1
    lda #<(p_cy)
    sta X16_P2
    lda #>(p_cy)
    sta X16_P3
    lda #(p_r)
    sta X16_P4
    lda #(p_a0)
    sta X16_P5
    lda #(p_a1)
    sta X16_P6
    lda #(p_col)
    jsr shape_pie
.endmacro
.endif
.ifdef X16_USE_SHAPES_BEZIER
.macro xm_shape_bezier p_x0, p_y0, p_x1, p_y1, p_x2, p_y2, p_x3, p_y3, p_col
    lda #<(p_x0)
    sta bez_x0
    lda #>(p_x0)
    sta bez_x0+1
    lda #<(p_y0)
    sta bez_y0
    lda #>(p_y0)
    sta bez_y0+1
    lda #<(p_x1)
    sta bez_x1
    lda #>(p_x1)
    sta bez_x1+1
    lda #<(p_y1)
    sta bez_y1
    lda #>(p_y1)
    sta bez_y1+1
    lda #<(p_x2)
    sta bez_x2
    lda #>(p_x2)
    sta bez_x2+1
    lda #<(p_y2)
    sta bez_y2
    lda #>(p_y2)
    sta bez_y2+1
    lda #<(p_x3)
    sta bez_x3
    lda #>(p_x3)
    sta bez_x3+1
    lda #<(p_y3)
    sta bez_y3
    lda #>(p_y3)
    sta bez_y3+1
    lda #(p_col)
    jsr shape_bezier
.endmacro
.endif
; -> carry set if the seed stack overflowed
.ifdef X16_USE_SHAPES
.macro xm_shape_flood p_x, p_y, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    lda #(p_col)
    jsr shape_flood
.endmacro
.endif

; =====================================================================
; gfx/verafx  (VERA FX; check vera_has_fx first)
; =====================================================================
.ifdef X16_USE_VERAFX
.macro xm_fx_off
    jsr fx_off
.endmacro
.endif
; -> P4..P7 = signed 16x16 product
.ifdef X16_USE_VERAFX
.macro xm_fx_mult p_a, p_b
    lda #<(p_a)
    sta X16_P0
    lda #>(p_a)
    sta X16_P1
    lda #<(p_b)
    sta X16_P2
    lda #>(p_b)
    sta X16_P3
    jsr fx_mult
.endmacro
.endif
; fill `count` bytes with `val` from the current port address
.ifdef X16_USE_VERAFX
.macro xm_fx_fill p_val, p_count
    lda #(p_val)
    ldx #<(p_count)
    ldy #>(p_count)
    jsr fx_fill
.endmacro
.endif
.ifdef X16_USE_VERAFX
.macro xm_fx_clear p_addrlo, p_addrmid, p_addrhi, p_count
    lda #(p_addrlo)
    sta X16_P0
    lda #(p_addrmid)
    sta X16_P1
    lda #(p_addrhi)
    sta X16_P2
    lda #<(p_count)
    sta X16_P3
    lda #>(p_count)
    sta X16_P4
    jsr fx_clear
.endmacro
.endif
.ifdef X16_USE_VERAFX
.macro xm_fx_transp_on
    jsr fx_transp_on
.endmacro
.endif
.ifdef X16_USE_VERAFX
.macro xm_fx_transp_off
    jsr fx_transp_off
.endmacro
.endif
.ifdef X16_USE_VERAFX
.macro xm_fx_line p_x0, p_y0, p_x1, p_y1, p_col
    lda #<(p_x0)
    sta X16_P0
    lda #>(p_x0)
    sta X16_P1
    lda #(p_y0)
    sta X16_P2
    lda #(p_col)
    sta X16_P3
    lda #<(p_x1)
    sta X16_P4
    lda #>(p_x1)
    sta X16_P5
    lda #(p_y1)
    sta X16_P6
    jsr fx_line
.endmacro
.endif

; =====================================================================
; system/irq
; =====================================================================
.ifdef X16_USE_IRQ
.macro xm_irq_install
    jsr irq_install
.endmacro
.endif
.ifdef X16_USE_IRQ
.macro xm_irq_remove
    jsr irq_remove
.endmacro
.endif
.ifdef X16_USE_IRQ
.macro xm_vsync_wait
    jsr vsync_wait
.endmacro
.endif
.ifdef X16_USE_IRQ
.macro xm_irq_line_install p_handler
    lda #<(p_handler)
    ldx #>(p_handler)
    jsr irq_line_install
.endmacro
.endif
; handler = 0 for polling (read with sprite_collisions)
.ifdef X16_USE_IRQ
.macro xm_irq_sprcol_install p_handler
    lda #<(p_handler)
    ldx #>(p_handler)
    jsr irq_sprcol_install
.endmacro
.endif
.ifdef X16_USE_IRQ
.macro xm_irq_sprcol_remove
    jsr irq_sprcol_remove
.endmacro
.endif

; =====================================================================
; audio/psg
; =====================================================================
.ifdef X16_USE_PSG
.macro xm_psg_init
    jsr psg_init
.endmacro
.endif
.ifdef X16_USE_PSG
.macro xm_psg_set_freq p_voice, p_freq
    ldx #(p_voice)
    lda #<(p_freq)
    sta X16_P0
    lda #>(p_freq)
    sta X16_P1
    jsr psg_set_freq
.endmacro
.endif
.ifdef X16_USE_PSG
.macro xm_psg_set_vol p_voice, p_vol, p_pan
    ldx #(p_voice)
    lda #(p_vol)
    ldy #(p_pan)
    jsr psg_set_vol
.endmacro
.endif
.ifdef X16_USE_PSG
.macro xm_psg_set_wave p_voice, p_wave, p_width
    ldx #(p_voice)
    lda #(p_wave)
    ldy #(p_width)
    jsr psg_set_wave
.endmacro
.endif
.ifdef X16_USE_PSG
.macro xm_psg_note_off p_voice
    ldx #(p_voice)
    jsr psg_note_off
.endmacro
.endif
.ifdef X16_USE_PSG
.macro xm_psg_env_start p_voice
    lda #(p_voice)
    jsr psg_env_start
.endmacro
.endif
.ifdef X16_USE_PSG
.macro xm_psg_env_release p_voice
    lda #(p_voice)
    jsr psg_env_release
.endmacro
.endif
.ifdef X16_USE_PSG
.macro xm_psg_env_stop p_voice
    lda #(p_voice)
    jsr psg_env_stop
.endmacro
.endif
.ifdef X16_USE_PSG
.macro xm_psg_env_tick
    jsr psg_env_tick
.endmacro
.endif

; =====================================================================
; audio/ym  (YM2151 FM)
; =====================================================================
.ifdef X16_USE_YM
.macro xm_ym_init
    jsr ym_init
.endmacro
.endif
.ifdef X16_USE_YM
.macro xm_ym_write p_reg, p_val
    lda #(p_val)
    ldx #(p_reg)
    jsr ym_write
.endmacro
.endif
.ifdef X16_USE_YM
.macro xm_ym_poke p_reg, p_val
    lda #(p_val)
    ldx #(p_reg)
    jsr ym_poke
.endmacro
.endif
; load a built-in ROM patch (0-162) into a channel
.ifdef X16_USE_YM
.macro xm_ym_patch_rom p_channel, p_index
    lda #(p_channel)
    ldx #(p_index)
    sec
    jsr ym_patch
.endmacro
.endif
.ifdef X16_USE_YM
.macro xm_ym_note p_channel, p_kc, p_kf
    lda #(p_channel)
    ldx #(p_kc)
    ldy #(p_kf)
    jsr ym_note
.endmacro
.endif
; note = (octave<<4)|1..12; note 0 releases
.ifdef X16_USE_YM
.macro xm_ym_note_bas p_channel, p_note
    lda #(p_channel)
    ldx #(p_note)
    jsr ym_note_bas
.endmacro
.endif
.ifdef X16_USE_YM
.macro xm_ym_release_note p_channel
    lda #(p_channel)
    jsr ym_release_note
.endmacro
.endif
.ifdef X16_USE_YM
.macro xm_ym_vol p_channel, p_atten
    lda #(p_channel)
    ldx #(p_atten)
    jsr ym_vol
.endmacro
.endif
.ifdef X16_USE_YM
.macro xm_ym_pan p_channel, p_pan
    lda #(p_channel)
    ldx #(p_pan)
    jsr ym_pan
.endmacro
.endif
.ifdef X16_USE_YM
.macro xm_ym_drum p_channel, p_note
    lda #(p_channel)
    ldx #(p_note)
    jsr ym_drum
.endmacro
.endif

; =====================================================================
; audio/pcm
; =====================================================================
.ifdef X16_USE_PCM
.macro xm_pcm_ctrl p_byte
    lda #(p_byte)
    jsr pcm_ctrl
.endmacro
.endif
.ifdef X16_USE_PCM
.macro xm_pcm_rate p_rate
    lda #(p_rate)
    jsr pcm_rate
.endmacro
.endif
.ifdef X16_USE_PCM
.macro xm_pcm_reset
    jsr pcm_reset
.endmacro
.endif
.ifdef X16_USE_PCM
.macro xm_pcm_put p_sample
    lda #(p_sample)
    jsr pcm_put
.endmacro
.endif
.ifdef X16_USE_PCM
.macro xm_pcm_write p_src, p_count
    lda #<(p_src)
    sta X16_P0
    lda #>(p_src)
    sta X16_P1
    lda #<(p_count)
    sta X16_P2
    lda #>(p_count)
    sta X16_P3
    jsr pcm_write
.endmacro
.endif
.ifdef X16_USE_PCM_STREAM
.macro xm_pcm_stream_start p_src, p_count, p_loop
    lda #<(p_src)
    sta X16_P0
    lda #>(p_src)
    sta X16_P1
    lda #<(p_count)
    sta X16_P2
    lda #>(p_count)
    sta X16_P3
    lda #(p_loop)
    sta X16_P4
    jsr pcm_stream_start
.endmacro
.endif
.ifdef X16_USE_PCM_STREAM
.macro xm_pcm_stream_stop
    jsr pcm_stream_stop
.endmacro
.endif

; =====================================================================
; audio/adpcm
; =====================================================================
.ifdef X16_USE_ADPCM
.macro xm_adpcm_init
    jsr adpcm_init
.endmacro
.endif
.ifdef X16_USE_ADPCM
.macro xm_adpcm_nibble p_code
    lda #(p_code)
    jsr adpcm_nibble
.endmacro
.endif
.ifdef X16_USE_ADPCM
.macro xm_adpcm_block p_src, p_dst, p_count
    lda #<(p_src)
    sta X16_P0
    lda #>(p_src)
    sta X16_P1
    lda #<(p_dst)
    sta X16_P2
    lda #>(p_dst)
    sta X16_P3
    lda #<(p_count)
    sta X16_P4
    lda #>(p_count)
    sta X16_P5
    jsr adpcm_block
.endmacro
.endif

; =====================================================================
; input/input
; =====================================================================
.ifdef X16_USE_INPUT
.macro xm_joy_scan
    jsr joy_scan
.endmacro
.endif
; -> A/X/Y = button bytes
.ifdef X16_USE_INPUT
.macro xm_joy_get p_pad
    lda #(p_pad)
    jsr joy_get
.endmacro
.endif
.ifdef X16_USE_INPUT
.macro xm_mouse_show p_cursor
    lda #(p_cursor)
    jsr mouse_show
.endmacro
.endif
.ifdef X16_USE_INPUT
.macro xm_mouse_hide
    jsr mouse_hide
.endmacro
.endif
; -> P0/1 = x, P2/3 = y, A = buttons
.ifdef X16_USE_INPUT
.macro xm_mouse_get
    jsr mouse_get
.endmacro
.endif
; -> A = PETSCII, 0 if none waiting
.ifdef X16_USE_INPUT
.macro xm_key_get
    jsr key_get
.endmacro
.endif
; -> A = PETSCII (blocks)
.ifdef X16_USE_INPUT
.macro xm_key_wait
    jsr key_wait
.endmacro
.endif
; -> A = next key without consuming it
.ifdef X16_USE_INPUT
.macro xm_key_peek
    jsr key_peek
.endmacro
.endif

; =====================================================================
; storage/bank  (banked RAM)
; =====================================================================
.ifdef X16_USE_BANK
.macro xm_bank_set p_bank
    lda #(p_bank)
    jsr bank_set
.endmacro
.endif
; -> A = byte
.ifdef X16_USE_BANK
.macro xm_bank_peek p_bank, p_offset
    lda #<(p_offset)
    sta X16_P0
    lda #>(p_offset)
    sta X16_P1
    lda #(p_bank)
    jsr bank_peek
.endmacro
.endif
.ifdef X16_USE_BANK
.macro xm_bank_poke p_bank, p_offset, p_byte
    lda #<(p_offset)
    sta X16_P0
    lda #>(p_offset)
    sta X16_P1
    lda #(p_byte)
    ldx #(p_bank)
    jsr bank_poke
.endmacro
.endif
.ifdef X16_USE_BANK
.macro xm_mem_to_bank p_src, p_bank, p_offset, p_count
    lda #<(p_src)
    sta X16_P0
    lda #>(p_src)
    sta X16_P1
    lda #(p_bank)
    sta X16_P2
    lda #<(p_offset)
    sta X16_P3
    lda #>(p_offset)
    sta X16_P4
    lda #<(p_count)
    sta X16_P5
    lda #>(p_count)
    sta X16_P6
    jsr mem_to_bank
.endmacro
.endif

; =====================================================================
; storage/bankalloc
; =====================================================================
.ifdef X16_USE_BANKALLOC
.macro xm_bank_alloc_init p_first, p_last
    lda #(p_first)
    ldx #(p_last)
    jsr bank_alloc_init
.endmacro
.endif
; -> carry clear, A = the bank number
.ifdef X16_USE_BANKALLOC
.macro xm_bank_alloc
    jsr bank_alloc
.endmacro
.endif
.ifdef X16_USE_BANKALLOC
.macro xm_bank_free p_bank
    lda #(p_bank)
    jsr bank_free
.endmacro
.endif
.ifdef X16_USE_BANKALLOC
.macro xm_bank_reserve p_bank
    lda #(p_bank)
    jsr bank_reserve
.endmacro
.endif

; =====================================================================
; storage/mem  (KERNAL block ops; stream to/from VERA_DATA0 too)
; =====================================================================
.ifdef X16_USE_MEM
.macro xm_mem_fill p_dst, p_count, p_val
    lda #<(p_dst)
    sta X16_P0
    lda #>(p_dst)
    sta X16_P1
    lda #<(p_count)
    sta X16_P2
    lda #>(p_count)
    sta X16_P3
    lda #(p_val)
    jsr mem_fill
.endmacro
.endif
.ifdef X16_USE_MEM
.macro xm_mem_copy p_src, p_dst, p_count
    lda #<(p_src)
    sta X16_P0
    lda #>(p_src)
    sta X16_P1
    lda #<(p_dst)
    sta X16_P2
    lda #>(p_dst)
    sta X16_P3
    lda #<(p_count)
    sta X16_P4
    lda #>(p_count)
    sta X16_P5
    jsr mem_copy
.endmacro
.endif
; -> A = CRC low, X = CRC high
.ifdef X16_USE_MEM
.macro xm_mem_crc p_addr, p_count
    lda #<(p_addr)
    sta X16_P0
    lda #>(p_addr)
    sta X16_P1
    lda #<(p_count)
    sta X16_P2
    lda #>(p_count)
    sta X16_P3
    jsr mem_crc
.endmacro
.endif
; -> A/X = one past the last output byte
.ifdef X16_USE_MEM
.macro xm_mem_decompress p_src, p_dst
    lda #<(p_src)
    sta X16_P0
    lda #>(p_src)
    sta X16_P1
    lda #<(p_dst)
    sta X16_P2
    lda #>(p_dst)
    sta X16_P3
    jsr mem_decompress
.endmacro
.endif

; =====================================================================
; storage/load
; =====================================================================
.ifdef X16_USE_LOAD
.macro xm_fs_setname p_name, p_len
    lda #<(p_name)
    sta X16_P0
    lda #>(p_name)
    sta X16_P1
    lda #(p_len)
    jsr fs_setname
.endmacro
.endif
; -> carry set = error, A = KERNAL error code
.ifdef X16_USE_LOAD
.macro xm_fs_load p_name, p_len, p_device, p_sa, p_dst
    lda #<(p_name)
    sta X16_P0
    lda #>(p_name)
    sta X16_P1
    lda #(p_len)
    sta X16_P2
    lda #(p_device)
    sta X16_P3
    lda #(p_sa)
    sta X16_P4
    lda #<(p_dst)
    sta X16_P5
    lda #>(p_dst)
    sta X16_P6
    jsr fs_load
.endmacro
.endif
.ifdef X16_USE_LOAD
.macro xm_fs_vload p_name, p_len, p_device, p_vbank, p_vaddr
    lda #<(p_name)
    sta X16_P0
    lda #>(p_name)
    sta X16_P1
    lda #(p_len)
    sta X16_P2
    lda #(p_device)
    sta X16_P3
    lda #(p_vbank)
    sta X16_P4
    lda #<(p_vaddr)
    sta X16_P5
    lda #>(p_vaddr)
    sta X16_P6
    jsr fs_vload
.endmacro
.endif

; =====================================================================
; storage/dos
; =====================================================================
; -> A = status code
.ifdef X16_USE_DOS
.macro xm_dos_cmd p_cmd, p_len
    lda #<(p_cmd)
    ldx #>(p_cmd)
    ldy #(p_len)
    jsr dos_cmd
.endmacro
.endif
.ifdef X16_USE_DOS
.macro xm_dos_status
    jsr dos_status
.endmacro
.endif
.ifdef X16_USE_DOS
.macro xm_dos_delete p_name, p_len
    lda #<(p_name)
    ldx #>(p_name)
    ldy #(p_len)
    jsr dos_delete
.endmacro
.endif

; =====================================================================
; storage/bmx
; =====================================================================
.ifdef X16_USE_BMX
.macro xm_bmx_load p_name, p_len, p_device, p_vbank, p_vaddr
    lda #<(p_name)
    sta X16_P0
    lda #>(p_name)
    sta X16_P1
    lda #(p_len)
    sta X16_P2
    lda #(p_device)
    sta X16_P3
    lda #(p_vbank)
    sta X16_P4
    lda #<(p_vaddr)
    sta X16_P5
    lda #>(p_vaddr)
    sta X16_P6
    jsr bmx_load
.endmacro
.endif

; =====================================================================
; util/math
; =====================================================================
.ifdef X16_USE_MATH
.macro xm_rnd_seed p_seed
    lda #<(p_seed)
    ldx #>(p_seed)
    jsr rnd_seed
.endmacro
.endif
; -> A = -127..127
.ifdef X16_USE_MATH
.macro xm_sin8 p_angle
    lda #(p_angle)
    jsr sin8
.endmacro
.endif
.ifdef X16_USE_MATH
.macro xm_cos8 p_angle
    lda #(p_angle)
    jsr cos8
.endmacro
.endif
; -> A = 1..255
.ifdef X16_USE_MATH
.macro xm_sin8u p_angle
    lda #(p_angle)
    jsr sin8u
.endmacro
.endif
.ifdef X16_USE_MATH
.macro xm_cos8u p_angle
    lda #(p_angle)
    jsr cos8u
.endmacro
.endif
; -> A = angle 0-255
.ifdef X16_USE_MATH
.macro xm_atan2 p_dx, p_dy
    lda #(p_dx)
    ldx #(p_dy)
    jsr atan2
.endmacro
.endif
; -> A = interpolated value
.ifdef X16_USE_MATH
.macro xm_lerp8 p_a, p_b, p_t
    lda #(p_a)
    sta X16_P0
    lda #(p_b)
    sta X16_P1
    lda #(p_t)
    jsr lerp8
.endmacro
.endif

; =====================================================================
; util/collide
; =====================================================================
; -> carry set if the two boxes overlap (8-bit coordinates and sizes)
.ifdef X16_USE_COLLIDE
.macro xm_collide8 p_ax, p_ay, p_aw, p_ah, p_bx, p_by, p_bw, p_bh
    lda #(p_ax)
    sta X16_P0
    lda #(p_ay)
    sta X16_P1
    lda #(p_aw)
    sta X16_P2
    lda #(p_ah)
    sta X16_P3
    lda #(p_bx)
    sta X16_P4
    lda #(p_by)
    sta X16_P5
    lda #(p_bw)
    sta X16_P6
    lda #(p_bh)
    sta X16_P7
    jsr collide8
.endmacro
.endif
; -> carry set if the two boxes overlap (16-bit; writes cl_* directly)
.ifdef X16_USE_COLLIDE
.macro xm_collide16 p_ax, p_ay, p_aw, p_ah, p_bx, p_by, p_bw, p_bh
    lda #<(p_ax)
    sta cl_ax
    lda #>(p_ax)
    sta cl_ax+1
    lda #<(p_ay)
    sta cl_ay
    lda #>(p_ay)
    sta cl_ay+1
    lda #<(p_aw)
    sta cl_aw
    lda #>(p_aw)
    sta cl_aw+1
    lda #<(p_ah)
    sta cl_ah
    lda #>(p_ah)
    sta cl_ah+1
    lda #<(p_bx)
    sta cl_bx
    lda #>(p_bx)
    sta cl_bx+1
    lda #<(p_by)
    sta cl_by
    lda #>(p_by)
    sta cl_by+1
    lda #<(p_bw)
    sta cl_bw
    lda #>(p_bw)
    sta cl_bw+1
    lda #<(p_bh)
    sta cl_bh
    lda #>(p_bh)
    sta cl_bh+1
    jsr collide16
.endmacro
.endif

; =====================================================================
; util/bits
; =====================================================================
.ifdef X16_USE_BITS
.macro xm_catnib p_hi, p_lo
    lda #(p_hi)
    ldx #(p_lo)
    jsr catnib
.endmacro
.endif
.ifdef X16_USE_BITS
.macro xm_hinib p_byte
    lda #(p_byte)
    jsr hinib
.endmacro
.endif
.ifdef X16_USE_BITS
.macro xm_lonib p_byte
    lda #(p_byte)
    jsr lonib
.endmacro
.endif
.ifdef X16_USE_BITS
.macro xm_bit_set p_addr, p_mask
    lda #<(p_addr)
    sta X16_PTR0
    lda #>(p_addr)
    sta X16_PTR0+1
    lda #(p_mask)
    jsr bit_set
.endmacro
.endif
.ifdef X16_USE_BITS
.macro xm_bit_clr p_addr, p_mask
    lda #<(p_addr)
    sta X16_PTR0
    lda #>(p_addr)
    sta X16_PTR0+1
    lda #(p_mask)
    jsr bit_clr
.endmacro
.endif
; -> Z clear if any masked bit was set
.ifdef X16_USE_BITS
.macro xm_bit_test p_addr, p_mask
    lda #<(p_addr)
    sta X16_PTR0
    lda #>(p_addr)
    sta X16_PTR0+1
    lda #(p_mask)
    jsr bit_test
.endmacro
.endif

; =====================================================================
; util/number
; =====================================================================
; -> A/X = buffer, Y = length
.ifdef X16_USE_NUMBER
.macro xm_u16_to_dec p_value
    lda #<(p_value)
    sta X16_P0
    lda #>(p_value)
    sta X16_P1
    jsr u16_to_dec
.endmacro
.endif
; -> A/X = buffer, Y = 4
.ifdef X16_USE_NUMBER
.macro xm_u16_to_hex p_value
    lda #<(p_value)
    sta X16_P0
    lda #>(p_value)
    sta X16_P1
    jsr u16_to_hex
.endmacro
.endif
; -> P4/5 = value, carry set on a bad digit
.ifdef X16_USE_NUMBER
.macro xm_dec_to_u16 p_str, p_len
    lda #<(p_str)
    sta X16_P0
    lda #>(p_str)
    sta X16_P1
    lda #(p_len)
    sta X16_P2
    jsr dec_to_u16
.endmacro
.endif

; =====================================================================
; util/fixed
; =====================================================================
; -> P4..P7 = product
.ifdef X16_USE_FIXED
.macro xm_umul16 p_a, p_b
    lda #<(p_a)
    sta X16_P0
    lda #>(p_a)
    sta X16_P1
    lda #<(p_b)
    sta X16_P2
    lda #>(p_b)
    sta X16_P3
    jsr umul16
.endmacro
.endif
; signed 8.8; -> P0/1 = result
.ifdef X16_USE_FIXED
.macro xm_mul88 p_a, p_b
    lda #<(p_a)
    sta X16_P0
    lda #>(p_a)
    sta X16_P1
    lda #<(p_b)
    sta X16_P2
    lda #>(p_b)
    sta X16_P3
    jsr mul88
.endmacro
.endif

; =====================================================================
; util/int16  (load i16_a / i16_b with +i16_const; ops are argument-free)
; =====================================================================
.ifdef X16_USE_INT16
.macro xm_i16_from_u8 p_byte
    lda #(p_byte)
    jsr i16_from_u8
.endmacro
.endif
.ifdef X16_USE_INT16
.macro xm_i16_from_s8 p_byte
    lda #(p_byte)
    jsr i16_from_s8
.endmacro
.endif

; =====================================================================
; util/int32  (load i32_a / i32_b with +i32_const)
; =====================================================================
.ifdef X16_USE_INT32
.macro xm_i32_from_u16 p_value
    lda #<(p_value)
    ldx #>(p_value)
    jsr i32_from_u16
.endmacro
.endif
.ifdef X16_USE_INT32
.macro xm_i32_from_s16 p_value
    lda #<(p_value)
    ldx #>(p_value)
    jsr i32_from_s16
.endmacro
.endif

; =====================================================================
; util/float  (FAC is the accumulator; addr = a 5-byte float in memory)
; =====================================================================
.ifdef X16_USE_FLOAT
.macro xm_f_from_u8 p_byte
    lda #(p_byte)
    jsr f_from_u8
.endmacro
.endif
.ifdef X16_USE_FLOAT
.macro xm_f_from_s16 p_value
    lda #<(p_value)
    ldx #>(p_value)
    jsr f_from_s16
.endmacro
.endif
.ifdef X16_USE_FLOAT
.macro xm_f_load p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr f_load
.endmacro
.endif
.ifdef X16_USE_FLOAT
.macro xm_f_store p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr f_store
.endmacro
.endif
.ifdef X16_USE_FLOAT
.macro xm_f_add p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr f_add
.endmacro
.endif
.ifdef X16_USE_FLOAT
.macro xm_f_sub p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr f_sub
.endmacro
.endif
.ifdef X16_USE_FLOAT
.macro xm_f_mul p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr f_mul
.endmacro
.endif
.ifdef X16_USE_FLOAT
.macro xm_f_div p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr f_div
.endmacro
.endif
.ifdef X16_USE_FLOAT
.macro xm_f_cmp p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr f_cmp
.endmacro
.endif
; FAC = mem - FAC
.ifdef X16_USE_FLOAT
.macro xm_f_rsub p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr f_rsub
.endmacro
.endif
; FAC = mem / FAC
.ifdef X16_USE_FLOAT
.macro xm_f_rdiv p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr f_rdiv
.endmacro
.endif
; FAC = FAC ^ mem
.ifdef X16_USE_FLOAT
.macro xm_f_pow p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr f_pow
.endmacro
.endif
; FAC = the value parsed from a string of `len` chars
.ifdef X16_USE_FLOAT
.macro xm_f_from_str p_str, p_len
    lda #<(p_str)
    ldy #>(p_str)
    ldx #(p_len)
    jsr f_from_str
.endmacro
.endif

; =====================================================================
; util/double  (d_ac is the accumulator; addr = an 8-byte double in memory)
; =====================================================================
.ifdef X16_USE_DOUBLE
.macro xm_d_load p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr d_load
.endmacro
.endif
.ifdef X16_USE_DOUBLE
.macro xm_d_store p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr d_store
.endmacro
.endif
.ifdef X16_USE_DOUBLE
.macro xm_d_add p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr d_add
.endmacro
.endif
.ifdef X16_USE_DOUBLE
.macro xm_d_sub p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr d_sub
.endmacro
.endif
.ifdef X16_USE_DOUBLE
.macro xm_d_mul p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr d_mul
.endmacro
.endif
.ifdef X16_USE_DOUBLE
.macro xm_d_div p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr d_div
.endmacro
.endif
.ifdef X16_USE_DOUBLE
.macro xm_d_cmp p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr d_cmp
.endmacro
.endif
; d_ac = d_ac ^ mem  (base ^ exponent)
.ifdef X16_USE_DOUBLE
.macro xm_d_pow p_addr
    lda #<(p_addr)
    ldy #>(p_addr)
    jsr d_pow
.endmacro
.endif
; d_ac = the value parsed from a string of `len` chars
.ifdef X16_USE_DOUBLE
.macro xm_d_from_str p_str, p_len
    lda #<(p_str)
    ldy #>(p_str)
    ldx #(p_len)
    jsr d_from_str
.endmacro
.endif
.ifdef X16_USE_DOUBLE
.macro xm_d_from_s16 p_value
    lda #<(p_value)
    ldx #>(p_value)
    jsr d_from_s16
.endmacro
.endif

; =====================================================================
; util/clip
; =====================================================================
.ifdef X16_USE_CLIP
.macro xm_clip_set p_xmin, p_ymin, p_xmax, p_ymax
    lda #<(p_xmin)
    sta X16_P0
    lda #>(p_xmin)
    sta X16_P1
    lda #<(p_ymin)
    sta X16_P2
    lda #>(p_ymin)
    sta X16_P3
    lda #<(p_xmax)
    sta X16_P4
    lda #>(p_xmax)
    sta X16_P5
    lda #<(p_ymax)
    sta X16_P6
    lda #>(p_ymax)
    sta X16_P7
    jsr clip_set
.endmacro
.endif

; =====================================================================
; util/buffers  (ring buffer + byte stack)
; =====================================================================
.ifdef X16_USE_BUFFERS
.macro xm_rb_init
    jsr rb_init
.endmacro
.endif
; -> carry set if the buffer was full
.ifdef X16_USE_BUFFERS
.macro xm_rb_put p_byte
    lda #(p_byte)
    jsr rb_put
.endmacro
.endif
; -> A = byte, carry set if empty
.ifdef X16_USE_BUFFERS
.macro xm_rb_get
    jsr rb_get
.endmacro
.endif
.ifdef X16_USE_BUFFERS
.macro xm_rb_count
    jsr rb_count
.endmacro
.endif
.ifdef X16_USE_BUFFERS
.macro xm_stk_init
    jsr stk_init
.endmacro
.endif
; -> carry set if the stack was full
.ifdef X16_USE_BUFFERS
.macro xm_stk_push p_byte
    lda #(p_byte)
    jsr stk_push
.endmacro
.endif
; -> A = byte, carry set if empty
.ifdef X16_USE_BUFFERS
.macro xm_stk_pop
    jsr stk_pop
.endmacro
.endif
.ifdef X16_USE_BUFFERS
.macro xm_stk_depth
    jsr stk_depth
.endmacro
.endif

; =====================================================================
; util/zx0 and util/tscrunch
; =====================================================================
; -> A/X = one past the last output byte
.ifdef X16_USE_ZX0
.macro xm_zx0_decompress p_src, p_dst
    lda #<(p_src)
    sta X16_P0
    lda #>(p_src)
    sta X16_P1
    lda #<(p_dst)
    sta X16_P2
    lda #>(p_dst)
    sta X16_P3
    jsr zx0_decompress
.endmacro
.endif
.ifdef X16_USE_TSC
.macro xm_tsc_decompress p_src, p_dst
    lda #<(p_src)
    sta X16_P0
    lda #>(p_src)
    sta X16_P1
    lda #<(p_dst)
    sta X16_P2
    lda #>(p_dst)
    sta X16_P3
    jsr tsc_decompress
.endmacro
.endif

; =====================================================================
; comms/serial
; =====================================================================
; -> A = count (0-2), carry clear if any found, ser_u0/ser_u1 = bases
.ifdef X16_USE_SERIAL
.macro xm_ser_detect
    jsr ser_detect
.endmacro
.endif
.ifdef X16_USE_SERIAL
.macro xm_ser_init p_base, p_divisor
    lda #<(p_divisor)
    sta X16_P0
    lda #>(p_divisor)
    sta X16_P1
    lda #<(p_base)
    ldx #>(p_base)
    jsr ser_init
.endmacro
.endif
; -> carry set if a received byte is waiting
.ifdef X16_USE_SERIAL
.macro xm_ser_avail
    jsr ser_avail
.endmacro
.endif
; -> carry clear + A = byte, or carry set if the RX FIFO was empty
.ifdef X16_USE_SERIAL
.macro xm_ser_get
    jsr ser_get
.endmacro
.endif
; -> A = byte (blocks until one arrives)
.ifdef X16_USE_SERIAL
.macro xm_ser_get_wait
    jsr ser_get_wait
.endmacro
.endif
.ifdef X16_USE_SERIAL
.macro xm_ser_put p_byte
    lda #(p_byte)
    jsr ser_put
.endmacro
.endif
.ifdef X16_USE_SERIAL
.macro xm_ser_puts p_addr
    lda #<(p_addr)
    ldx #>(p_addr)
    jsr ser_puts
.endmacro
.endif
.ifdef X16_USE_SERIAL
.macro xm_ser_write p_addr, p_len
    ldy #(p_len)
    lda #<(p_addr)
    ldx #>(p_addr)
    jsr ser_write
.endmacro
.endif
; -> X16_P4/P5 = bytes stored
.ifdef X16_USE_SERIAL
.macro xm_ser_read_until p_match, p_buffer, p_max
    lda #<(p_buffer)
    sta X16_P0
    lda #>(p_buffer)
    sta X16_P1
    lda #<(p_max)
    sta X16_P2
    lda #>(p_max)
    sta X16_P3
    lda #<(p_match)
    ldx #>(p_match)
    jsr ser_read_until
.endmacro
.endif
.ifdef X16_USE_SERIAL
.macro xm_ser_discard_until p_match
    lda #<(p_match)
    ldx #>(p_match)
    jsr ser_discard_until
.endmacro
.endif

; =====================================================================
; comms/zimodem
; =====================================================================
.ifdef X16_USE_SERIAL_ZIMODEM
.macro xm_zi_init p_base, p_divisor
    lda #<(p_divisor)
    sta X16_P0
    lda #>(p_divisor)
    sta X16_P1
    lda #<(p_base)
    ldx #>(p_base)
    jsr zi_init
.endmacro
.endif
.ifdef X16_USE_SERIAL_ZIMODEM
.macro xm_zi_cmd p_addr
    lda #<(p_addr)
    ldx #>(p_addr)
    jsr zi_cmd
.endmacro
.endif
.ifdef X16_USE_SERIAL_ZIMODEM
.macro xm_zi_wait_ok
    jsr zi_wait_ok
.endmacro
.endif
.ifdef X16_USE_SERIAL_ZIMODEM
.macro xm_zi_reset
    jsr zi_reset
.endmacro
.endif
.ifdef X16_USE_SERIAL_ZIMODEM
.macro xm_zi_get_ip p_buffer
    lda #<(p_buffer)
    ldx #>(p_buffer)
    jsr zi_get_ip
.endmacro
.endif
; -> carry clear if the transfer started, carry set if not found
.ifdef X16_USE_SERIAL_ZIMODEM
.macro xm_zi_hex_open p_filename
    lda #<(p_filename)
    ldx #>(p_filename)
    jsr zi_hex_open
.endmacro
.endif
; -> A = bytes decoded into the buffer, 0 when the file is done
.ifdef X16_USE_SERIAL_ZIMODEM
.macro xm_zi_hex_chunk p_buffer
    lda #<(p_buffer)
    ldx #>(p_buffer)
    jsr zi_hex_chunk
.endmacro
.endif
.ifdef X16_USE_SERIAL_ZIMODEM
.macro xm_zi_hex_close
    jsr zi_hex_close
.endmacro
.endif
; -> A = bytes written (sugar_digits / 2)
.ifdef X16_USE_SERIAL_ZIMODEM
.macro xm_zi_hexdecode p_src, p_digits, p_dest
    lda #<(p_dest)
    sta X16_P0
    lda #>(p_dest)
    sta X16_P1
    ldy #(p_digits)
    lda #<(p_src)
    ldx #>(p_src)
    jsr zi_hexdecode
.endmacro
.endif

; =====================================================================
; string/string
; =====================================================================
; -> Y = length
.ifdef X16_USE_STRING
.macro xm_str_length p_str
    lda #<(p_str)
    ldx #>(p_str)
    jsr str_length
.endmacro
.endif
; -> Y = length copied
.ifdef X16_USE_STRING
.macro xm_str_copy p_src, p_dst
    lda #<(p_dst)
    sta X16_P0
    lda #>(p_dst)
    sta X16_P1
    lda #<(p_src)
    ldx #>(p_src)
    jsr str_copy
.endmacro
.endif
.ifdef X16_USE_STRING
.macro xm_str_ncopy p_src, p_dst, p_max
    lda #<(p_dst)
    sta X16_P0
    lda #>(p_dst)
    sta X16_P1
    ldy #(p_max)
    lda #<(p_src)
    ldx #>(p_src)
    jsr str_ncopy
.endmacro
.endif
; -> A = resulting length
.ifdef X16_USE_STRING
.macro xm_str_append p_tgt, p_suffix
    lda #<(p_suffix)
    sta X16_P0
    lda #>(p_suffix)
    sta X16_P1
    lda #<(p_tgt)
    ldx #>(p_tgt)
    jsr str_append
.endmacro
.endif
.ifdef X16_USE_STRING
.macro xm_str_nappend p_tgt, p_suffix, p_max
    lda #<(p_suffix)
    sta X16_P0
    lda #>(p_suffix)
    sta X16_P1
    ldy #(p_max)
    lda #<(p_tgt)
    ldx #>(p_tgt)
    jsr str_nappend
.endmacro
.endif
; -> A = -1 / 0 / 1
.ifdef X16_USE_STRING
.macro xm_str_compare p_s1, p_s2
    lda #<(p_s2)
    sta X16_P0
    lda #>(p_s2)
    sta X16_P1
    lda #<(p_s1)
    ldx #>(p_s1)
    jsr str_compare
.endmacro
.endif
; -> A = hash
.ifdef X16_USE_STRING
.macro xm_str_hash p_str
    lda #<(p_str)
    ldx #>(p_str)
    jsr str_hash
.endmacro
.endif

; =====================================================================
; string/case
; =====================================================================
.ifdef X16_USE_STRING_CASE
.macro xm_str_lower p_str
    lda #<(p_str)
    ldx #>(p_str)
    jsr str_lower
.endmacro
.endif
.ifdef X16_USE_STRING_CASE
.macro xm_str_lower_iso p_str
    lda #<(p_str)
    ldx #>(p_str)
    jsr str_lower_iso
.endmacro
.endif
.ifdef X16_USE_STRING_CASE
.macro xm_str_upper p_str
    lda #<(p_str)
    ldx #>(p_str)
    jsr str_upper
.endmacro
.endif
.ifdef X16_USE_STRING_CASE
.macro xm_str_upper_iso p_str
    lda #<(p_str)
    ldx #>(p_str)
    jsr str_upper_iso
.endmacro
.endif
; -> A = -1 / 0 / 1
.ifdef X16_USE_STRING_CASE
.macro xm_str_compare_nocase p_s1, p_s2
    lda #<(p_s2)
    sta X16_P0
    lda #>(p_s2)
    sta X16_P1
    lda #<(p_s1)
    ldx #>(p_s1)
    jsr str_compare_nocase
.endmacro
.endif
.ifdef X16_USE_STRING_CASE
.macro xm_str_compare_nocase_iso p_s1, p_s2
    lda #<(p_s2)
    sta X16_P0
    lda #>(p_s2)
    sta X16_P1
    lda #<(p_s1)
    ldx #>(p_s1)
    jsr str_compare_nocase_iso
.endmacro
.endif

; =====================================================================
; string/find
; =====================================================================
; -> carry set + A = index if found
.ifdef X16_USE_STRING_FIND
.macro xm_str_find p_str, p_ch
    ldy #(p_ch)
    lda #<(p_str)
    ldx #>(p_str)
    jsr str_find
.endmacro
.endif
.ifdef X16_USE_STRING_FIND
.macro xm_str_rfind p_str, p_ch
    ldy #(p_ch)
    lda #<(p_str)
    ldx #>(p_str)
    jsr str_rfind
.endmacro
.endif
.ifdef X16_USE_STRING_FIND
.macro xm_str_find_eol p_str
    lda #<(p_str)
    ldx #>(p_str)
    jsr str_find_eol
.endmacro
.endif
; -> carry set if the character occurs
.ifdef X16_USE_STRING_FIND
.macro xm_str_contains p_str, p_ch
    ldy #(p_ch)
    lda #<(p_str)
    ldx #>(p_str)
    jsr str_contains
.endmacro
.endif
; -> carry set (A = 1) if it matches
.ifdef X16_USE_STRING_FIND
.macro xm_str_pattern_match p_str, p_pattern
    lda #<(p_pattern)
    sta X16_P0
    lda #>(p_pattern)
    sta X16_P1
    lda #<(p_str)
    ldx #>(p_str)
    jsr str_pattern_match
.endmacro
.endif

; =====================================================================
; string/slice
; =====================================================================
.ifdef X16_USE_STRING_SLICE
.macro xm_str_left p_src, p_dst, p_len
    lda #<(p_dst)
    sta X16_P0
    lda #>(p_dst)
    sta X16_P1
    ldy #(p_len)
    lda #<(p_src)
    ldx #>(p_src)
    jsr str_left
.endmacro
.endif
.ifdef X16_USE_STRING_SLICE
.macro xm_str_right p_src, p_dst, p_len
    lda #<(p_dst)
    sta X16_P0
    lda #>(p_dst)
    sta X16_P1
    ldy #(p_len)
    lda #<(p_src)
    ldx #>(p_src)
    jsr str_right
.endmacro
.endif
.ifdef X16_USE_STRING_SLICE
.macro xm_str_slice p_src, p_dst, p_start, p_len
    lda #<(p_dst)
    sta X16_P0
    lda #>(p_dst)
    sta X16_P1
    lda #(p_start)
    sta X16_P2
    ldy #(p_len)
    lda #<(p_src)
    ldx #>(p_src)
    jsr str_slice
.endmacro
.endif
; -> Y = new length
.ifdef X16_USE_STRING_SLICE
.macro xm_str_ltrim p_str
    lda #<(p_str)
    ldx #>(p_str)
    jsr str_ltrim
.endmacro
.endif
.ifdef X16_USE_STRING_SLICE
.macro xm_str_rtrim p_str
    lda #<(p_str)
    ldx #>(p_str)
    jsr str_rtrim
.endmacro
.endif
.ifdef X16_USE_STRING_SLICE
.macro xm_str_trim p_str
    lda #<(p_str)
    ldx #>(p_str)
    jsr str_trim
.endmacro
.endif
