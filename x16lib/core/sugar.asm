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
; instead of a dozen lda/sta lines. This is the same idea as the CXRF
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
;       X16_USE_BITMAP2H     = 1
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
; video/vdc  (VERA display composer)
; =====================================================================
; -> A = DC_VIDEO
.ifdef X16_USE_VERA_DC
.macro xm_vdc_get_video
    jsr vdc_get_video
.endmacro
.endif
.ifdef X16_USE_VERA_DC
.macro xm_vdc_set_video p_video
    lda #(p_video)
    jsr vdc_set_video
.endmacro
.endif
.ifdef X16_USE_VERA_DC
.macro xm_vdc_set_output p_mode
    lda #(p_mode)
    jsr vdc_set_output
.endmacro
.endif
.ifdef X16_USE_VERA_DC
.macro xm_vdc_set_layers p_mask
    lda #(p_mask)
    jsr vdc_set_layers
.endmacro
.endif
.ifdef X16_USE_VERA_DC
.macro xm_vdc_layer_on p_mask
    lda #(p_mask)
    jsr vdc_layer_on
.endmacro
.endif
.ifdef X16_USE_VERA_DC
.macro xm_vdc_layer_off p_mask
    lda #(p_mask)
    jsr vdc_layer_off
.endmacro
.endif
; -> A = HSCALE, X = VSCALE
.ifdef X16_USE_VERA_DC
.macro xm_vdc_get_scale
    jsr vdc_get_scale
.endmacro
.endif
.ifdef X16_USE_VERA_DC
.macro xm_vdc_set_scale p_hscale, p_vscale
    lda #(p_hscale)
    ldx #(p_vscale)
    jsr vdc_set_scale
.endmacro
.endif
; -> A = border palette index
.ifdef X16_USE_VERA_DC
.macro xm_vdc_get_border
    jsr vdc_get_border
.endmacro
.endif
.ifdef X16_USE_VERA_DC
.macro xm_vdc_set_border p_color
    lda #(p_color)
    jsr vdc_set_border
.endmacro
.endif
; -> A = HSTART, X = HSTOP, Y = VSTART, r0L = VSTOP
.ifdef X16_USE_VERA_DC
.macro xm_vdc_get_active_raw
    jsr vdc_get_active_raw
.endmacro
.endif
.ifdef X16_USE_VERA_DC
.macro xm_vdc_set_active_raw p_hstart, p_hstop, p_vstart, p_vstop
    lda #(p_hstart)
    ldx #(p_hstop)
    ldy #(p_vstart)
    pha
    lda #(p_vstop)
    sta r0L
    pla
    jsr vdc_set_active_raw
.endmacro
.endif
.ifdef X16_USE_VERA_DC
.macro xm_vdc_set_active p_hstart, p_hstop, p_vstart, p_vstop
    lda #<(p_hstart)
    sta X16_P0
    lda #>(p_hstart)
    sta X16_P1
    lda #<(p_hstop)
    sta X16_P2
    lda #>(p_hstop)
    sta X16_P3
    lda #<(p_vstart)
    sta X16_P4
    lda #>(p_vstart)
    sta X16_P5
    lda #<(p_vstop)
    sta X16_P6
    lda #>(p_vstop)
    sta X16_P7
    jsr vdc_set_active
.endmacro
.endif
.ifdef X16_USE_VERA_DC
.macro xm_vdc_fullscreen
    jsr vdc_fullscreen
.endmacro
.endif
; -> carry set if valid, A = major, X = minor, Y = build
.ifdef X16_USE_VERA_DC
.macro xm_vdc_get_version
    jsr vdc_get_version
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
; gfx/bitmap8l  (320x240 @ 8bpp)
; =====================================================================
.ifdef X16_USE_BITMAP8L
.macro xm_gfx8l_init
    jsr gfx8l_init
.endmacro
.endif
.ifdef X16_USE_BITMAP8L
.macro xm_gfx8l_clear p_col
    lda #(p_col)
    jsr gfx8l_clear
.endmacro
.endif
.ifdef X16_USE_BITMAP8L
.macro xm_gfx8l_pset p_x, p_y, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    lda #(p_col)
    sta X16_P3
    jsr gfx8l_pset
.endmacro
.endif
; -> A = colour
.ifdef X16_USE_BITMAP8L
.macro xm_gfx8l_read p_x, p_y
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    jsr gfx8l_read
.endmacro
.endif
.ifdef X16_USE_BITMAP8L
.macro xm_gfx8l_hline p_x, p_y, p_len, p_col
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
    jsr gfx8l_hline
.endmacro
.endif
.ifdef X16_USE_BITMAP8L
.macro xm_gfx8l_vline p_x, p_y, p_len, p_col
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
    jsr gfx8l_vline
.endmacro
.endif
.ifdef X16_USE_BITMAP8L
.macro xm_gfx8l_rect p_x, p_y, p_w, p_h, p_col
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
    jsr gfx8l_rect
.endmacro
.endif
.ifdef X16_USE_BITMAP8L
.macro xm_gfx8l_frame p_x, p_y, p_w, p_h, p_col
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
    jsr gfx8l_frame
.endmacro
.endif
; A/X = the address of an 8x8 1bpp pattern
.ifdef X16_USE_BITMAP8L
.macro xm_gfx8l_pattern_set p_pat
    lda #<(p_pat)
    ldx #>(p_pat)
    jsr gfx8l_pattern_set
.endmacro
.endif
.ifdef X16_USE_BITMAP8L
.macro xm_gfx8l_pattern_rect p_x, p_y, p_w, p_h
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
    jsr gfx8l_pattern_rect
.endmacro
.endif
.ifdef X16_USE_BITMAP8L
.macro xm_gfx8l_line p_x0, p_y0, p_x1, p_y1, p_col
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
    jsr gfx8l_line
.endmacro
.endif
.ifdef X16_USE_BITMAP8L
.macro xm_gfx8l_char p_code, p_x, p_y, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    lda #(p_col)
    sta X16_P3
    lda #(p_code)
    jsr gfx8l_char
.endmacro
.endif
; str = a NUL-terminated string
.ifdef X16_USE_BITMAP8L
.macro xm_gfx8l_text p_str, p_x, p_y, p_col
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
    jsr gfx8l_text
.endmacro
.endif

; =====================================================================
; gfx/bitmap8h  (640x480 @ 8bpp; VERA_2 SDRAM layer)
; =====================================================================
.ifdef X16_USE_BITMAP8H
.macro xm_gfx8h_has
    jsr gfx8h_has
.endmacro
.macro xm_gfx8h_init
    jsr gfx8h_init
.endmacro
.macro xm_gfx8h_off
    jsr gfx8h_off
.endmacro
.macro xm_gfx8h_passthru_on
    jsr gfx8h_passthru_on
.endmacro
.macro xm_gfx8h_passthru_off
    jsr gfx8h_passthru_off
.endmacro
.macro xm_gfx8h_pal_set p_index, p_lo, p_hi
    ldx #(p_index)
    lda #(p_lo)
    ldy #(p_hi)
    jsr gfx8h_pal_set
.endmacro
.macro xm_gfx8h_pal_load p_src, p_first, p_count
    lda #<(p_src)
    sta X16_PTR0
    lda #>(p_src)
    sta X16_PTR0+1
    lda #(p_first)
    ldx #(p_count)
    jsr gfx8h_pal_load
.endmacro
.macro xm_gfx8h_clear p_col
    lda #(p_col)
    jsr gfx8h_clear
.endmacro
.macro xm_gfx8h_pset p_x, p_y, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    lda #(p_col)
    jsr gfx8h_pset
.endmacro
.macro xm_gfx8h_read p_x, p_y
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    jsr gfx8h_read
.endmacro
.macro xm_gfx8h_hline p_x, p_y, p_len, p_col
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
    jsr gfx8h_hline
.endmacro
.macro xm_gfx8h_vline p_x, p_y, p_len, p_col
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
    jsr gfx8h_vline
.endmacro
.macro xm_gfx8h_rect p_x, p_y, p_w, p_h, p_col
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
    jsr gfx8h_rect
.endmacro
.macro xm_gfx8h_frame p_x, p_y, p_w, p_h, p_col
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
    jsr gfx8h_frame
.endmacro
.macro xm_gfx8h_line p_x0, p_y0, p_x1, p_y1, p_col
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
    jsr gfx8h_line
.endmacro
.macro xm_gfx8h_pattern_set p_pat, p_bg, p_fg
    lda #(p_bg)
    sta X16_P4
    lda #(p_fg)
    sta X16_P5
    lda #<(p_pat)
    ldx #>(p_pat)
    jsr gfx8h_pattern_set
.endmacro
.macro xm_gfx8h_pattern_rect p_x, p_y, p_w, p_h
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
    jsr gfx8h_pattern_rect
.endmacro
.macro xm_gfx8h_copy p_src, p_dst, p_len
    lda #<(p_src)
    sta X16_P0
    lda #>((p_src) >> 8)
    sta X16_P1
    lda #>((p_src) >> 16)
    sta X16_P2
    lda #<(p_dst)
    sta X16_P3
    lda #>((p_dst) >> 8)
    sta X16_P4
    lda #>((p_dst) >> 16)
    sta X16_P5
    lda #<(p_len)
    ldx #>((p_len) >> 8)
    ldy #>((p_len) >> 16)
    jsr gfx8h_copy
.endmacro
.endif

; =====================================================================
; gfx/bitmap2h  (640x480 @ 2bpp; colour in A)
; =====================================================================
.ifdef X16_USE_BITMAP2H
.macro xm_gfx2h_init
    jsr gfx2h_init
.endmacro
.endif
.ifdef X16_USE_BITMAP2H
.macro xm_gfx2h_clear p_col
    lda #(p_col)
    jsr gfx2h_clear
.endmacro
.endif
.ifdef X16_USE_BITMAP2H
.macro xm_gfx2h_pset p_x, p_y, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    lda #(p_col)
    jsr gfx2h_pset
.endmacro
.endif
; -> A = colour, carry set if (x,y) is off screen
.ifdef X16_USE_BITMAP2H
.macro xm_gfx2h_read p_x, p_y
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    jsr gfx2h_read
.endmacro
.endif
.ifdef X16_USE_BITMAP2H
.macro xm_gfx2h_hline p_x, p_y, p_len, p_col
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
    jsr gfx2h_hline
.endmacro
.endif
.ifdef X16_USE_BITMAP2H
.macro xm_gfx2h_vline p_x, p_y, p_len, p_col
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
    jsr gfx2h_vline
.endmacro
.endif
.ifdef X16_USE_BITMAP2H
.macro xm_gfx2h_rect p_x, p_y, p_w, p_h, p_col
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
    jsr gfx2h_rect
.endmacro
.endif
.ifdef X16_USE_BITMAP2H
.macro xm_gfx2h_frame p_x, p_y, p_w, p_h, p_col
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
    jsr gfx2h_frame
.endmacro
.endif
.ifdef X16_USE_BITMAP2H
.macro xm_gfx2h_line p_x0, p_y0, p_x1, p_y1, p_col
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
    jsr gfx2h_line
.endmacro
.endif
; A/X = the address of an 8x8 1bpp pattern
.ifdef X16_USE_BITMAP2H
.macro xm_gfx2h_pattern_set p_pat
    lda #<(p_pat)
    ldx #>(p_pat)
    jsr gfx2h_pattern_set
.endmacro
.endif
.ifdef X16_USE_BITMAP2H
.macro xm_gfx2h_pattern_rect p_x, p_y, p_w, p_h
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
    jsr gfx2h_pattern_rect
.endmacro
.endif

; =====================================================================
; gfx/bitmap2l  (320x240 @ 2bpp; colour in A)
; =====================================================================
.ifdef X16_USE_BITMAP2L
.macro xm_gfx2l_init
    jsr gfx2l_init
.endmacro
.endif
.ifdef X16_USE_BITMAP2L
.macro xm_gfx2l_clear p_col
    lda #(p_col)
    jsr gfx2l_clear
.endmacro
.endif
.ifdef X16_USE_BITMAP2L
.macro xm_gfx2l_pset p_x, p_y, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    lda #(p_col)
    jsr gfx2l_pset
.endmacro
.endif
; -> A = colour, carry set if (x,y) is off screen
.ifdef X16_USE_BITMAP2L
.macro xm_gfx2l_read p_x, p_y
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    jsr gfx2l_read
.endmacro
.endif
.ifdef X16_USE_BITMAP2L
.macro xm_gfx2l_hline p_x, p_y, p_len, p_col
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
    jsr gfx2l_hline
.endmacro
.endif
.ifdef X16_USE_BITMAP2L
.macro xm_gfx2l_vline p_x, p_y, p_len, p_col
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
    jsr gfx2l_vline
.endmacro
.endif
.ifdef X16_USE_BITMAP2L
.macro xm_gfx2l_rect p_x, p_y, p_w, p_h, p_col
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
    jsr gfx2l_rect
.endmacro
.endif
.ifdef X16_USE_BITMAP2L
.macro xm_gfx2l_frame p_x, p_y, p_w, p_h, p_col
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
    jsr gfx2l_frame
.endmacro
.endif
.ifdef X16_USE_BITMAP2L
.macro xm_gfx2l_line p_x0, p_y0, p_x1, p_y1, p_col
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
    jsr gfx2l_line
.endmacro
.endif
; A/X = the address of an 8x8 1bpp pattern
.ifdef X16_USE_BITMAP2L
.macro xm_gfx2l_pattern_set p_pat
    lda #<(p_pat)
    ldx #>(p_pat)
    jsr gfx2l_pattern_set
.endmacro
.endif
.ifdef X16_USE_BITMAP2L
.macro xm_gfx2l_pattern_rect p_x, p_y, p_w, p_h
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
    jsr gfx2l_pattern_rect
.endmacro
.endif

; =====================================================================
; gfx/bitmap4l  (320x240 @ 4bpp)
; =====================================================================
.ifdef X16_USE_BITMAP4L
.macro xm_gfx4l_init
    jsr gfx4l_init
.endmacro
.macro xm_gfx4l_clear p_col
    lda #(p_col)
    jsr gfx4l_clear
.endmacro
.macro xm_gfx4l_pset p_x, p_y, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    lda #(p_col)
    sta X16_P3
    jsr gfx4l_pset
.endmacro
.macro xm_gfx4l_read p_x, p_y
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    jsr gfx4l_read
.endmacro
.macro xm_gfx4l_hline p_x, p_y, p_len, p_col
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
    jsr gfx4l_hline
.endmacro
.macro xm_gfx4l_vline p_x, p_y, p_len, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    lda #(p_col)
    sta X16_P3
    lda #(p_len)
    sta X16_P4
    jsr gfx4l_vline
.endmacro
.macro xm_gfx4l_rect p_x, p_y, p_w, p_h, p_col
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
    jsr gfx4l_rect
.endmacro
.macro xm_gfx4l_frame p_x, p_y, p_w, p_h, p_col
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
    jsr gfx4l_frame
.endmacro
.macro xm_gfx4l_line p_x0, p_y0, p_x1, p_y1, p_col
    lda #<(p_x0)
    sta X16_P0
    lda #>(p_x0)
    sta X16_P1
    lda #(p_y0)
    sta X16_P2
    lda #<(p_x1)
    sta X16_P3
    lda #>(p_x1)
    sta X16_P4
    lda #(p_y1)
    sta X16_P5
    lda #(p_col)
    sta X16_P6
    jsr gfx4l_line
.endmacro
.macro xm_gfx4l_pattern_set p_pat, p_bg, p_fg
    lda #(p_bg)
    sta X16_P4
    lda #(p_fg)
    sta X16_P5
    lda #<(p_pat)
    ldx #>(p_pat)
    jsr gfx4l_pattern_set
.endmacro
.macro xm_gfx4l_pattern_rect p_x, p_y, p_w, p_h
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
    jsr gfx4l_pattern_rect
.endmacro
.macro xm_gfx4l_char p_code, p_x, p_y, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #(p_y)
    sta X16_P2
    lda #(p_col)
    sta X16_P3
    lda #(p_code)
    jsr gfx4l_char
.endmacro
.macro xm_gfx4l_text p_str, p_x, p_y, p_col
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
    jsr gfx4l_text
.endmacro
.endif

; =====================================================================
; gfx/bitmap4h  (640x480 @ 4bpp; VERA_2 SDRAM layer)
; =====================================================================
.ifdef X16_USE_BITMAP4H
.macro xm_gfx4h_has
    jsr gfx4h_has
.endmacro
.macro xm_gfx4h_init
    jsr gfx4h_init
.endmacro
.macro xm_gfx4h_off
    jsr gfx4h_off
.endmacro
.macro xm_gfx4h_passthru_on
    jsr gfx4h_passthru_on
.endmacro
.macro xm_gfx4h_passthru_off
    jsr gfx4h_passthru_off
.endmacro
.macro xm_gfx4h_pal_set p_index, p_lo, p_hi
    ldx #(p_index)
    lda #(p_lo)
    ldy #(p_hi)
    jsr gfx4h_pal_set
.endmacro
.macro xm_gfx4h_pal_load p_src, p_first, p_count
    lda #<(p_src)
    sta X16_PTR0
    lda #>(p_src)
    sta X16_PTR0+1
    lda #(p_first)
    ldx #(p_count)
    jsr gfx4h_pal_load
.endmacro
.macro xm_gfx4h_clear p_col
    lda #(p_col)
    jsr gfx4h_clear
.endmacro
.macro xm_gfx4h_pset p_x, p_y, p_col
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    lda #(p_col)
    jsr gfx4h_pset
.endmacro
.macro xm_gfx4h_read p_x, p_y
    lda #<(p_x)
    sta X16_P0
    lda #>(p_x)
    sta X16_P1
    lda #<(p_y)
    sta X16_P2
    lda #>(p_y)
    sta X16_P3
    jsr gfx4h_read
.endmacro
.macro xm_gfx4h_hline p_x, p_y, p_len, p_col
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
    jsr gfx4h_hline
.endmacro
.macro xm_gfx4h_vline p_x, p_y, p_len, p_col
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
    jsr gfx4h_vline
.endmacro
.macro xm_gfx4h_rect p_x, p_y, p_w, p_h, p_col
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
    jsr gfx4h_rect
.endmacro
.macro xm_gfx4h_frame p_x, p_y, p_w, p_h, p_col
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
    jsr gfx4h_frame
.endmacro
.macro xm_gfx4h_line p_x0, p_y0, p_x1, p_y1, p_col
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
    jsr gfx4h_line
.endmacro
.macro xm_gfx4h_pattern_set p_pat, p_bg, p_fg
    lda #(p_bg)
    sta X16_P4
    lda #(p_fg)
    sta X16_P5
    lda #<(p_pat)
    ldx #>(p_pat)
    jsr gfx4h_pattern_set
.endmacro
.macro xm_gfx4h_pattern_rect p_x, p_y, p_w, p_h
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
    jsr gfx4h_pattern_rect
.endmacro
.macro xm_gfx4h_copy p_src, p_dst, p_len
    lda #<(p_src)
    sta X16_P0
    lda #>((p_src) >> 8)
    sta X16_P1
    lda #>((p_src) >> 16)
    sta X16_P2
    lda #<(p_dst)
    sta X16_P3
    lda #>((p_dst) >> 8)
    sta X16_P4
    lda #>((p_dst) >> 16)
    sta X16_P5
    lda #<(p_len)
    ldx #>((p_len) >> 8)
    ldy #>((p_len) >> 16)
    jsr gfx4h_copy
.endmacro
.endif

; =====================================================================
; gfx/graph  (KERNAL GRAPH API)
; =====================================================================
.ifdef X16_USE_GRAPH
.macro xm_graph_init_default
    stz r0L
    stz r0H
    jsr graph_init
.endmacro
.endif
.ifdef X16_USE_GRAPH
.macro xm_graph_init p_driver
    lda #<(p_driver)
    sta r0L
    lda #>(p_driver)
    sta r0H
    jsr graph_init
.endmacro
.endif
.ifdef X16_USE_GRAPH
.macro xm_graph_clear
    jsr graph_clear
.endmacro
.endif
.ifdef X16_USE_GRAPH
.macro xm_graph_set_window p_x, p_y, p_w, p_h
    lda #<(p_x)
    sta r0L
    lda #>(p_x)
    sta r0H
    lda #<(p_y)
    sta r1L
    lda #>(p_y)
    sta r1H
    lda #<(p_w)
    sta r2L
    lda #>(p_w)
    sta r2H
    lda #<(p_h)
    sta r3L
    lda #>(p_h)
    sta r3H
    jsr graph_set_window
.endmacro
.endif
.ifdef X16_USE_GRAPH
.macro xm_graph_set_colors p_stroke, p_fill, p_background
    lda #(p_stroke)
    ldx #(p_fill)
    ldy #(p_background)
    jsr graph_set_colors
.endmacro
.endif
.ifdef X16_USE_GRAPH
.macro xm_graph_draw_line p_x1, p_y1, p_x2, p_y2
    lda #<(p_x1)
    sta r0L
    lda #>(p_x1)
    sta r0H
    lda #<(p_y1)
    sta r1L
    lda #>(p_y1)
    sta r1H
    lda #<(p_x2)
    sta r2L
    lda #>(p_x2)
    sta r2H
    lda #<(p_y2)
    sta r3L
    lda #>(p_y2)
    sta r3H
    jsr graph_draw_line
.endmacro
.endif
.ifdef X16_USE_GRAPH
.macro xm_graph_draw_rect_outline p_x, p_y, p_w, p_h, p_radius
    lda #<(p_x)
    sta r0L
    lda #>(p_x)
    sta r0H
    lda #<(p_y)
    sta r1L
    lda #>(p_y)
    sta r1H
    lda #<(p_w)
    sta r2L
    lda #>(p_w)
    sta r2H
    lda #<(p_h)
    sta r3L
    lda #>(p_h)
    sta r3H
    lda #<(p_radius)
    sta r4L
    lda #>(p_radius)
    sta r4H
    clc
    jsr graph_draw_rect
.endmacro
.endif
.ifdef X16_USE_GRAPH
.macro xm_graph_draw_rect_fill p_x, p_y, p_w, p_h, p_radius
    lda #<(p_x)
    sta r0L
    lda #>(p_x)
    sta r0H
    lda #<(p_y)
    sta r1L
    lda #>(p_y)
    sta r1H
    lda #<(p_w)
    sta r2L
    lda #>(p_w)
    sta r2H
    lda #<(p_h)
    sta r3L
    lda #>(p_h)
    sta r3H
    lda #<(p_radius)
    sta r4L
    lda #>(p_radius)
    sta r4H
    sec
    jsr graph_draw_rect
.endmacro
.endif
.ifdef X16_USE_GRAPH
.macro xm_graph_move_rect p_sx, p_sy, p_tx, p_ty, p_w, p_h
    lda #<(p_sx)
    sta r0L
    lda #>(p_sx)
    sta r0H
    lda #<(p_sy)
    sta r1L
    lda #>(p_sy)
    sta r1H
    lda #<(p_tx)
    sta r2L
    lda #>(p_tx)
    sta r2H
    lda #<(p_ty)
    sta r3L
    lda #>(p_ty)
    sta r3H
    lda #<(p_w)
    sta r4L
    lda #>(p_w)
    sta r4H
    lda #<(p_h)
    sta r5L
    lda #>(p_h)
    sta r5H
    jsr graph_move_rect
.endmacro
.endif
.ifdef X16_USE_GRAPH
.macro xm_graph_draw_oval_outline p_x, p_y, p_w, p_h
    lda #<(p_x)
    sta r0L
    lda #>(p_x)
    sta r0H
    lda #<(p_y)
    sta r1L
    lda #>(p_y)
    sta r1H
    lda #<(p_w)
    sta r2L
    lda #>(p_w)
    sta r2H
    lda #<(p_h)
    sta r3L
    lda #>(p_h)
    sta r3H
    clc
    jsr graph_draw_oval
.endmacro
.endif
.ifdef X16_USE_GRAPH
.macro xm_graph_draw_oval_fill p_x, p_y, p_w, p_h
    lda #<(p_x)
    sta r0L
    lda #>(p_x)
    sta r0H
    lda #<(p_y)
    sta r1L
    lda #>(p_y)
    sta r1H
    lda #<(p_w)
    sta r2L
    lda #>(p_w)
    sta r2H
    lda #<(p_h)
    sta r3L
    lda #>(p_h)
    sta r3H
    sec
    jsr graph_draw_oval
.endmacro
.endif
.ifdef X16_USE_GRAPH
.macro xm_graph_draw_image p_x, p_y, p_image, p_w, p_h
    lda #<(p_x)
    sta r0L
    lda #>(p_x)
    sta r0H
    lda #<(p_y)
    sta r1L
    lda #>(p_y)
    sta r1H
    lda #<(p_image)
    sta r2L
    lda #>(p_image)
    sta r2H
    lda #<(p_w)
    sta r3L
    lda #>(p_w)
    sta r3H
    lda #<(p_h)
    sta r4L
    lda #>(p_h)
    sta r4H
    jsr graph_draw_image
.endmacro
.endif
.ifdef X16_USE_GRAPH
.macro xm_graph_set_font_default
    stz r0L
    stz r0H
    jsr graph_set_font
.endmacro
.endif
.ifdef X16_USE_GRAPH
.macro xm_graph_set_font p_font
    lda #<(p_font)
    sta r0L
    lda #>(p_font)
    sta r0H
    jsr graph_set_font
.endmacro
.endif
; -> printable: C clear, A baseline, X width, Y height; control: C set
.ifdef X16_USE_GRAPH
.macro xm_graph_get_char_size p_char, p_style
    lda #(p_char)
    ldx #(p_style)
    jsr graph_get_char_size
.endmacro
.endif
; -> r0/r1 updated, carry set if outside bounds
.ifdef X16_USE_GRAPH
.macro xm_graph_put_char p_char, p_x, p_y
    lda #<(p_x)
    sta r0L
    lda #>(p_x)
    sta r0H
    lda #<(p_y)
    sta r1L
    lda #>(p_y)
    sta r1H
    lda #(p_char)
    jsr graph_put_char
.endmacro
.endif

; =====================================================================
; gfx/console  (KERNAL console API)
; =====================================================================
.ifdef X16_USE_CONSOLE
.macro xm_con_init_fullscreen
    stz r0L
    stz r0H
    stz r1L
    stz r1H
    stz r2L
    stz r2H
    stz r3L
    stz r3H
    jsr con_init
.endmacro
.endif
.ifdef X16_USE_CONSOLE
.macro xm_con_init p_x, p_y, p_w, p_h
    lda #<(p_x)
    sta r0L
    lda #>(p_x)
    sta r0H
    lda #<(p_y)
    sta r1L
    lda #>(p_y)
    sta r1H
    lda #<(p_w)
    sta r2L
    lda #>(p_w)
    sta r2H
    lda #<(p_h)
    sta r3L
    lda #>(p_h)
    sta r3H
    jsr con_init
.endmacro
.endif
.ifdef X16_USE_CONSOLE
.macro xm_con_set_paging_message p_msg
    lda #<(p_msg)
    sta r0L
    lda #>(p_msg)
    sta r0H
    jsr con_set_paging_message
.endmacro
.endif
.ifdef X16_USE_CONSOLE
.macro xm_con_disable_paging
    jsr con_disable_paging
.endmacro
.endif
.ifdef X16_USE_CONSOLE
.macro xm_con_put_char_wrap p_char
    lda #(p_char)
    clc
    jsr con_put_char
.endmacro
.endif
.ifdef X16_USE_CONSOLE
.macro xm_con_put_char_word p_char
    lda #(p_char)
    sec
    jsr con_put_char
.endmacro
.endif
.ifdef X16_USE_CONSOLE
.macro xm_con_get_char
    jsr con_get_char
.endmacro
.endif
.ifdef X16_USE_CONSOLE
.macro xm_con_put_image p_image, p_w, p_h
    lda #<(p_image)
    sta r0L
    lda #>(p_image)
    sta r0H
    lda #<(p_w)
    sta r1L
    lda #>(p_w)
    sta r1H
    lda #<(p_h)
    sta r2L
    lda #>(p_h)
    sta r2H
    jsr con_put_image
.endmacro
.endif

; =====================================================================
; gfx/fb  (KERNAL framebuffer API)
; =====================================================================
.ifdef X16_USE_FB
.macro xm_fb_init
    jsr fb_init
.endmacro
.endif
.ifdef X16_USE_FB
.macro xm_fb_get_info
    jsr fb_get_info
.endmacro
.endif
.ifdef X16_USE_FB
.macro xm_fb_set_palette p_data, p_start, p_count
    lda #<(p_data)
    sta r0L
    lda #>(p_data)
    sta r0H
    lda #(p_start)
    ldx #(p_count)
    jsr fb_set_palette
.endmacro
.endif
.ifdef X16_USE_FB
.macro xm_fb_cursor_position p_x, p_y
    lda #<(p_x)
    sta r0L
    lda #>(p_x)
    sta r0H
    lda #<(p_y)
    sta r1L
    lda #>(p_y)
    sta r1H
    jsr fb_cursor_position
.endmacro
.endif
.ifdef X16_USE_FB
.macro xm_fb_cursor_next_line
    jsr fb_cursor_next_line
.endmacro
.endif
; -> A = color
.ifdef X16_USE_FB
.macro xm_fb_get_pixel p_x, p_y
    xm_fb_cursor_position p_x, p_y
    jsr fb_get_pixel
.endmacro
.endif
.ifdef X16_USE_FB
.macro xm_fb_set_pixel p_x, p_y, p_color
    xm_fb_cursor_position p_x, p_y
    lda #(p_color)
    jsr fb_set_pixel
.endmacro
.endif
.ifdef X16_USE_FB
.macro xm_fb_get_pixels p_dest, p_count
    lda #<(p_dest)
    sta r0L
    lda #>(p_dest)
    sta r0H
    lda #<(p_count)
    sta r1L
    lda #>(p_count)
    sta r1H
    jsr fb_get_pixels
.endmacro
.endif
.ifdef X16_USE_FB
.macro xm_fb_set_pixels p_src, p_count
    lda #<(p_src)
    sta r0L
    lda #>(p_src)
    sta r0H
    lda #<(p_count)
    sta r1L
    lda #>(p_count)
    sta r1H
    jsr fb_set_pixels
.endmacro
.endif
.ifdef X16_USE_FB
.macro xm_fb_set_8_pixels p_pattern, p_color
    lda #(p_pattern)
    ldx #(p_color)
    jsr fb_set_8_pixels
.endmacro
.endif
.ifdef X16_USE_FB
.macro xm_fb_set_8_pixels_opaque p_mask, p_pattern, p_fg, p_bg
    lda #<(p_pattern)
    sta r0L
    lda #(p_mask)
    ldx #(p_fg)
    ldy #(p_bg)
    jsr fb_set_8_pixels_opaque
.endmacro
.endif
.ifdef X16_USE_FB
.macro xm_fb_fill_pixels p_count, p_step, p_color
    lda #<(p_count)
    sta r0L
    lda #>(p_count)
    sta r0H
    lda #<(p_step)
    sta r1L
    lda #>(p_step)
    sta r1H
    lda #(p_color)
    jsr fb_fill_pixels
.endmacro
.endif
.ifdef X16_USE_FB
.macro xm_fb_filter_pixels p_count, p_filter
    lda #<(p_count)
    sta r0L
    lda #>(p_count)
    sta r0H
    lda #<(p_filter)
    sta r1L
    lda #>(p_filter)
    sta r1H
    jsr fb_filter_pixels
.endmacro
.endif
.ifdef X16_USE_FB
.macro xm_fb_move_pixels p_sx, p_sy, p_tx, p_ty, p_count
    lda #<(p_sx)
    sta r0L
    lda #>(p_sx)
    sta r0H
    lda #<(p_sy)
    sta r1L
    lda #>(p_sy)
    sta r1H
    lda #<(p_tx)
    sta r2L
    lda #>(p_tx)
    sta r2H
    lda #<(p_ty)
    sta r3L
    lda #>(p_ty)
    sta r3H
    lda #<(p_count)
    sta r4L
    lda #>(p_count)
    sta r4H
    jsr fb_move_pixels
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
; gfx/verafx_utils  (low-level VERA FX primitives)
; =====================================================================
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_off
    jsr fxu_off
.endmacro
.endif
; -> A = FX_CTRL
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_get_ctrl
    jsr fxu_get_ctrl
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_set_ctrl p_ctrl
    lda #(p_ctrl)
    jsr fxu_set_ctrl
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_ctrl_on p_mask
    lda #(p_mask)
    jsr fxu_ctrl_on
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_ctrl_off p_mask
    lda #(p_mask)
    jsr fxu_ctrl_off
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_addr1_mode p_mode
    lda #(p_mode)
    jsr fxu_addr1_mode
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_cache_write_on
    jsr fxu_cache_write_on
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_cache_write_off
    jsr fxu_cache_write_off
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_cache_fill_on
    jsr fxu_cache_fill_on
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_cache_fill_off
    jsr fxu_cache_fill_off
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_cache_cycle_on
    jsr fxu_cache_cycle_on
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_cache_cycle_off
    jsr fxu_cache_cycle_off
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_transparent_on
    jsr fxu_transparent_on
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_transparent_off
    jsr fxu_transparent_off
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_4bit_on
    jsr fxu_4bit_on
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_4bit_off
    jsr fxu_4bit_off
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_hop_on
    jsr fxu_hop_on
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_hop_off
    jsr fxu_hop_off
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_set_mult p_mult
    lda #(p_mult)
    jsr fxu_set_mult
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_set_cache p_b0, p_b1, p_b2, p_b3
    lda #(p_b0)
    sta X16_P0
    lda #(p_b1)
    sta X16_P1
    lda #(p_b2)
    sta X16_P2
    lda #(p_b3)
    sta X16_P3
    jsr fxu_set_cache
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_reset_accum
    jsr fxu_reset_accum
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_accumulate
    jsr fxu_accumulate
.endmacro
.endif
; -> A = DATA0 read
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_cache_fill0
    jsr fxu_cache_fill0
.endmacro
.endif
; -> A = DATA1 read
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_cache_fill1
    jsr fxu_cache_fill1
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_cache_write0 p_mask
    lda #(p_mask)
    jsr fxu_cache_write0
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_cache_write1 p_mask
    lda #(p_mask)
    jsr fxu_cache_write1
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_set_incr p_xinc, p_yinc
    lda #<(p_xinc)
    sta X16_P0
    lda #>(p_xinc)
    sta X16_P1
    lda #<(p_yinc)
    sta X16_P2
    lda #>(p_yinc)
    sta X16_P3
    jsr fxu_set_incr
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_set_pos p_xpos, p_ypos
    lda #<(p_xpos)
    sta X16_P0
    lda #>(p_xpos)
    sta X16_P1
    lda #<(p_ypos)
    sta X16_P2
    lda #>(p_ypos)
    sta X16_P3
    jsr fxu_set_pos
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_set_subpos p_xsub, p_ysub
    lda #(p_xsub)
    ldx #(p_ysub)
    jsr fxu_set_subpos
.endmacro
.endif
; -> A = poly fill low, X = high
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_get_poly_fill
    jsr fxu_get_poly_fill
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_set_tilebase p_value
    lda #(p_value)
    jsr fxu_set_tilebase
.endmacro
.endif
.ifdef X16_USE_VERAFX_UTILS
.macro xm_fxu_set_mapbase p_value
    lda #(p_value)
    jsr fxu_set_mapbase
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
; audio/rom  (full BANK_AUDIO API)
; =====================================================================
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_audio_init
    jsr ar_audio_init
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_playstring_voice p_voice
    lda #(p_voice)
    jsr ar_playstring_voice
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_fmplaystring p_str, p_len
    lda #(p_len)
    ldx #<(p_str)
    ldy #>(p_str)
    jsr ar_fmplaystring
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_fmchordstring p_str, p_len
    lda #(p_len)
    ldx #<(p_str)
    ldy #>(p_str)
    jsr ar_fmchordstring
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psgplaystring p_str, p_len
    lda #(p_len)
    ldx #<(p_str)
    ldy #>(p_str)
    jsr ar_psgplaystring
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psgchordstring p_str, p_len
    lda #(p_len)
    ldx #<(p_str)
    ldy #>(p_str)
    jsr ar_psgchordstring
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_fmfreq p_channel, p_hz
    lda #(p_channel)
    ldx #<(p_hz)
    ldy #>(p_hz)
    clc
    jsr ar_fmfreq
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_fmfreq_no_retrigger p_channel, p_hz
    lda #(p_channel)
    ldx #<(p_hz)
    ldy #>(p_hz)
    sec
    jsr ar_fmfreq
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_fmnote p_channel, p_note, p_kf
    lda #(p_channel)
    ldx #(p_note)
    ldy #(p_kf)
    clc
    jsr ar_fmnote
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_fmnote_no_retrigger p_channel, p_note, p_kf
    lda #(p_channel)
    ldx #(p_note)
    ldy #(p_kf)
    sec
    jsr ar_fmnote
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_fmvib p_speed, p_depth
    lda #(p_speed)
    ldx #(p_depth)
    jsr ar_fmvib
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psgfreq p_voice, p_hz
    lda #(p_voice)
    ldx #<(p_hz)
    ldy #>(p_hz)
    jsr ar_psgfreq
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psgnote p_voice, p_note, p_kf
    lda #(p_voice)
    ldx #(p_note)
    ldy #(p_kf)
    jsr ar_psgnote
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psgwav p_voice, p_wave
    lda #(p_voice)
    ldx #(p_wave)
    jsr ar_psgwav
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_bas2fm p_note
    ldx #(p_note)
    jsr ar_note_bas2fm
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_bas2midi p_note
    ldx #(p_note)
    jsr ar_note_bas2midi
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_bas2psg p_note, p_kf
    ldx #(p_note)
    ldy #(p_kf)
    jsr ar_note_bas2psg
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_fm2bas p_kc
    ldx #(p_kc)
    jsr ar_note_fm2bas
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_fm2midi p_kc
    ldx #(p_kc)
    jsr ar_note_fm2midi
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_fm2psg p_kc, p_kf
    ldx #(p_kc)
    ldy #(p_kf)
    jsr ar_note_fm2psg
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_freq2bas p_hz
    ldx #<(p_hz)
    ldy #>(p_hz)
    jsr ar_note_freq2bas
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_freq2fm p_hz
    ldx #<(p_hz)
    ldy #>(p_hz)
    jsr ar_note_freq2fm
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_freq2midi p_hz
    ldx #<(p_hz)
    ldy #>(p_hz)
    jsr ar_note_freq2midi
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_freq2psg p_hz
    ldx #<(p_hz)
    ldy #>(p_hz)
    jsr ar_note_freq2psg
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_midi2bas p_note
    lda #(p_note)
    jsr ar_note_midi2bas
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_midi2fm p_note
    ldx #(p_note)
    jsr ar_note_midi2fm
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_midi2psg p_note, p_kf
    ldx #(p_note)
    ldy #(p_kf)
    jsr ar_note_midi2psg
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_psg2bas p_freq
    ldx #<(p_freq)
    ldy #>(p_freq)
    jsr ar_note_psg2bas
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_psg2fm p_freq
    ldx #<(p_freq)
    ldy #>(p_freq)
    jsr ar_note_psg2fm
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_note_psg2midi p_freq
    ldx #<(p_freq)
    ldy #>(p_freq)
    jsr ar_note_psg2midi
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psg_init
    jsr ar_psg_init
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psg_playfreq p_voice, p_freq
    lda #(p_voice)
    ldx #<(p_freq)
    ldy #>(p_freq)
    jsr ar_psg_playfreq
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psg_read_raw p_reg
    ldx #(p_reg)
    clc
    jsr ar_psg_read
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psg_read_cooked p_reg
    ldx #(p_reg)
    sec
    jsr ar_psg_read
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psg_setatten p_voice, p_atten
    lda #(p_voice)
    ldx #(p_atten)
    jsr ar_psg_setatten
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psg_setfreq p_voice, p_freq
    lda #(p_voice)
    ldx #<(p_freq)
    ldy #>(p_freq)
    jsr ar_psg_setfreq
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psg_setpan p_voice, p_pan
    lda #(p_voice)
    ldx #(p_pan)
    jsr ar_psg_setpan
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psg_setvol p_voice, p_vol
    lda #(p_voice)
    ldx #(p_vol)
    jsr ar_psg_setvol
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psg_write p_reg, p_value
    lda #(p_value)
    ldx #(p_reg)
    jsr ar_psg_write
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psg_write_fast p_reg, p_value
    lda #(p_value)
    ldx #(p_reg)
    jsr ar_psg_write_fast
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psg_getatten p_voice
    lda #(p_voice)
    jsr ar_psg_getatten
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_psg_getpan p_voice
    lda #(p_voice)
    jsr ar_psg_getpan
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_init
    jsr ar_ym_init
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_loaddefpatches
    jsr ar_ym_loaddefpatches
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_loadpatch_rom p_channel, p_patch
    lda #(p_channel)
    ldx #(p_patch)
    sec
    jsr ar_ym_loadpatch
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_loadpatchlfn p_channel, p_lfn
    lda #(p_channel)
    ldx #(p_lfn)
    jsr ar_ym_loadpatchlfn
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_playdrum p_channel, p_note
    lda #(p_channel)
    ldx #(p_note)
    jsr ar_ym_playdrum
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_playnote p_channel, p_kc, p_kf
    lda #(p_channel)
    ldx #(p_kc)
    ldy #(p_kf)
    clc
    jsr ar_ym_playnote
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_setatten p_channel, p_atten
    lda #(p_channel)
    ldx #(p_atten)
    jsr ar_ym_setatten
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_setdrum p_channel, p_note
    lda #(p_channel)
    ldx #(p_note)
    jsr ar_ym_setdrum
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_setnote p_channel, p_kc, p_kf
    lda #(p_channel)
    ldx #(p_kc)
    ldy #(p_kf)
    jsr ar_ym_setnote
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_setpan p_channel, p_pan
    lda #(p_channel)
    ldx #(p_pan)
    jsr ar_ym_setpan
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_read_raw p_reg
    ldx #(p_reg)
    clc
    jsr ar_ym_read
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_read_cooked p_reg
    ldx #(p_reg)
    sec
    jsr ar_ym_read
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_release p_channel
    lda #(p_channel)
    jsr ar_ym_release
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_trigger p_channel
    lda #(p_channel)
    clc
    jsr ar_ym_trigger
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_trigger_no_retrigger p_channel
    lda #(p_channel)
    sec
    jsr ar_ym_trigger
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_write p_reg, p_value
    lda #(p_value)
    ldx #(p_reg)
    jsr ar_ym_write
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_getatten p_channel
    lda #(p_channel)
    jsr ar_ym_getatten
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_getpan p_channel
    lda #(p_channel)
    jsr ar_ym_getpan
.endmacro
.endif
.ifdef X16_USE_AUDIO_ROM
.macro xm_ar_ym_get_chip_type
    jsr ar_ym_get_chip_type
.endmacro
.endif

; =====================================================================
; audio/zsm  (compact ZSM stream player)
; =====================================================================
.ifdef X16_USE_ZSM
.macro xm_zsm_init p_header
    lda #<(p_header)
    sta r0L
    lda #>(p_header)
    sta r0H
    jsr zsm_init
.endmacro
.endif
.ifdef X16_USE_ZSM
.macro xm_zsm_init_stream p_stream, p_loop
    lda #<(p_stream)
    sta r0L
    lda #>(p_stream)
    sta r0H
    lda #<(p_loop)
    sta r1L
    lda #>(p_loop)
    sta r1H
    jsr zsm_init_stream
.endmacro
.endif
.ifdef X16_USE_ZSM
.macro xm_zsm_play
    jsr zsm_play
.endmacro
.endif
.ifdef X16_USE_ZSM
.macro xm_zsm_stop
    jsr zsm_stop
.endmacro
.endif
.ifdef X16_USE_ZSM
.macro xm_zsm_rewind
    jsr zsm_rewind
.endmacro
.endif
; -> A = low byte, X = high byte
.ifdef X16_USE_ZSM
.macro xm_zsm_get_tickrate
    jsr zsm_get_tickrate
.endmacro
.endif
; -> A = ZSM_FLAG_* bits, carry set if active
.ifdef X16_USE_ZSM
.macro xm_zsm_status
    jsr zsm_status
.endmacro
.endif
; -> A = ZSM_FLAG_* bits, carry set if active
.ifdef X16_USE_ZSM
.macro xm_zsm_tick
    jsr zsm_tick
.endmacro
.endif
; -> carry set if a supported PCM table is present
.ifdef X16_USE_ZSM_PCM
.macro xm_zsm_pcm_present
    jsr zsm_pcm_present
.endmacro
.endif
.ifdef X16_USE_ZSM_PCM
.macro xm_zsm_pcm_trigger p_instrument
    lda #(p_instrument)
    jsr zsm_pcm_trigger
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
; input/mouse
; =====================================================================
.ifdef X16_USE_MOUSE
.macro xm_mse_config p_cursor, p_width8, p_height8
    lda #(p_cursor)
    ldx #(p_width8)
    ldy #(p_height8)
    jsr mse_config
.endmacro
.endif
.ifdef X16_USE_MOUSE
.macro xm_mse_scan
    jsr mse_scan
.endmacro
.endif
; -> P0/1 = x, P2/3 = y, A = buttons, X = wheel delta
.ifdef X16_USE_MOUSE
.macro xm_mse_get
    jsr mse_get
.endmacro
.endif
; -> sugar_zp/sugar_zp+1 = x, sugar_zp+2/sugar_zp+3 = y, A = buttons, X = wheel delta
.ifdef X16_USE_MOUSE
.macro xm_mse_get_to p_zp
    ldx #(p_zp)
    jsr mse_get_to
.endmacro
.endif
.ifdef X16_USE_MOUSE
.macro xm_mse_show p_cursor
    lda #(p_cursor)
    jsr mse_show
.endmacro
.endif
.ifdef X16_USE_MOUSE
.macro xm_mse_show_keep
    jsr mse_show_keep
.endmacro
.endif
.ifdef X16_USE_MOUSE
.macro xm_mse_hide
    jsr mse_hide
.endmacro
.endif

; =====================================================================
; input/keyboard
; =====================================================================
.ifdef X16_USE_KEYBOARD
.macro xm_kbd_scan
    jsr kbd_scan
.endmacro
.endif
; -> A = next PETSCII key, X = queued key count, Z set when empty
.ifdef X16_USE_KEYBOARD
.macro xm_kbd_peek
    jsr kbd_peek
.endmacro
.endif
.ifdef X16_USE_KEYBOARD
.macro xm_kbd_put p_key
    lda #(p_key)
    jsr kbd_put
.endmacro
.endif
; -> A = KBD_MOD_* bitfield
.ifdef X16_USE_KEYBOARD
.macro xm_kbd_get_modifiers
    jsr kbd_get_modifiers
.endmacro
.endif
; -> A = layout index, X/Y = current NUL-terminated layout string
.ifdef X16_USE_KEYBOARD
.macro xm_kbd_get_keymap
    jsr kbd_get_keymap
.endmacro
.endif
; -> carry clear on success, carry set on unknown layout
.ifdef X16_USE_KEYBOARD
.macro xm_kbd_set_keymap p_name
    ldx #<(p_name)
    ldy #>(p_name)
    jsr kbd_set_keymap
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
; storage/iec
; =====================================================================
.ifdef X16_USE_IEC
.macro xm_iec_listen p_device
    lda #(p_device)
    jsr iec_listen
.endmacro
.endif
.ifdef X16_USE_IEC
.macro xm_iec_talk p_device
    lda #(p_device)
    jsr iec_talk
.endmacro
.endif
.ifdef X16_USE_IEC
.macro xm_iec_second p_command
    lda #(p_command)
    jsr iec_second
.endmacro
.endif
.ifdef X16_USE_IEC
.macro xm_iec_tksa p_command
    lda #(p_command)
    jsr iec_tksa
.endmacro
.endif
.ifdef X16_USE_IEC
.macro xm_iec_ciout p_byte
    lda #(p_byte)
    jsr iec_ciout
.endmacro
.endif
.ifdef X16_USE_IEC
.macro xm_iec_acptr
    jsr iec_acptr
.endmacro
.endif
.ifdef X16_USE_IEC
.macro xm_iec_unlisten
    jsr iec_unlisten
.endmacro
.endif
.ifdef X16_USE_IEC
.macro xm_iec_untalk
    jsr iec_untalk
.endmacro
.endif
.ifdef X16_USE_IEC
.macro xm_iec_set_timeout p_control
    lda #(p_control)
    jsr iec_set_timeout
.endmacro
.endif
.ifdef X16_USE_IEC
.macro xm_iec_readst
    jsr iec_readst
.endmacro
.endif
; -> X/Y = bytes read, carry set when unsupported/error
.ifdef X16_USE_IEC
.macro xm_iec_macptr p_dest, p_count
    lda #(p_count)
    ldx #<(p_dest)
    ldy #>(p_dest)
    jsr iec_macptr
.endmacro
.endif
; -> X/Y = bytes written, carry set when unsupported/error
.ifdef X16_USE_IEC
.macro xm_iec_mciout p_src, p_count
    lda #(p_count)
    ldx #<(p_src)
    ldy #>(p_src)
    jsr iec_mciout
.endmacro
.endif
.ifdef X16_USE_IEC
.macro xm_iec_open_channel p_device, p_secondary
    lda #(p_device)
    ldy #(p_secondary)
    jsr iec_open_channel
.endmacro
.endif
.ifdef X16_USE_IEC
.macro xm_iec_data_channel p_device, p_secondary
    lda #(p_device)
    ldy #(p_secondary)
    jsr iec_data_channel
.endmacro
.endif
.ifdef X16_USE_IEC
.macro xm_iec_talk_channel p_device, p_secondary
    lda #(p_device)
    ldy #(p_secondary)
    jsr iec_talk_channel
.endmacro
.endif
.ifdef X16_USE_IEC
.macro xm_iec_close_channel p_device, p_secondary
    lda #(p_device)
    ldy #(p_secondary)
    jsr iec_close_channel
.endmacro
.endif

; =====================================================================
; storage/fileio
; =====================================================================
.ifdef X16_USE_FILEIO
.macro xm_fio_set_lfs p_logical, p_device, p_secondary
    lda #(p_logical)
    ldx #(p_device)
    ldy #(p_secondary)
    jsr fio_set_lfs
.endmacro
.endif
.ifdef X16_USE_FILEIO
.macro xm_fio_set_name p_name, p_len
    lda #(p_len)
    ldx #<(p_name)
    ldy #>(p_name)
    jsr fio_set_name
.endmacro
.endif
; -> carry set = KERNAL open error
.ifdef X16_USE_FILEIO
.macro xm_fio_open_named p_name, p_len, p_logical, p_device, p_secondary
    lda #<(p_name)
    sta X16_P0
    lda #>(p_name)
    sta X16_P1
    lda #(p_len)
    sta X16_P2
    lda #(p_logical)
    sta X16_P3
    lda #(p_device)
    sta X16_P4
    lda #(p_secondary)
    sta X16_P5
    jsr fio_open_named
.endmacro
.endif
; -> carry set = OPEN or CHKIN error
.ifdef X16_USE_FILEIO
.macro xm_fio_open_read p_name, p_len, p_logical, p_device, p_secondary
    lda #<(p_name)
    sta X16_P0
    lda #>(p_name)
    sta X16_P1
    lda #(p_len)
    sta X16_P2
    lda #(p_logical)
    sta X16_P3
    lda #(p_device)
    sta X16_P4
    lda #(p_secondary)
    sta X16_P5
    jsr fio_open_read
.endmacro
.endif
; -> carry set = OPEN or CHKOUT error
.ifdef X16_USE_FILEIO
.macro xm_fio_open_write p_name, p_len, p_logical, p_device, p_secondary
    lda #<(p_name)
    sta X16_P0
    lda #>(p_name)
    sta X16_P1
    lda #(p_len)
    sta X16_P2
    lda #(p_logical)
    sta X16_P3
    lda #(p_device)
    sta X16_P4
    lda #(p_secondary)
    sta X16_P5
    jsr fio_open_write
.endmacro
.endif
.ifdef X16_USE_FILEIO
.macro xm_fio_close p_logical
    lda #(p_logical)
    jsr fio_close
.endmacro
.endif
.ifdef X16_USE_FILEIO
.macro xm_fio_close_named p_logical
    lda #(p_logical)
    sta X16_P3
    jsr fio_close_named
.endmacro
.endif
.ifdef X16_USE_FILEIO
.macro xm_fio_chkin p_logical
    ldx #(p_logical)
    jsr fio_chkin
.endmacro
.endif
.ifdef X16_USE_FILEIO
.macro xm_fio_chkout p_logical
    ldx #(p_logical)
    jsr fio_chkout
.endmacro
.endif
.ifdef X16_USE_FILEIO
.macro xm_fio_clrchn
    jsr fio_clrchn
.endmacro
.endif
.ifdef X16_USE_FILEIO
.macro xm_fio_chrin
    jsr fio_chrin
.endmacro
.endif
.ifdef X16_USE_FILEIO
.macro xm_fio_chrout p_byte
    lda #(p_byte)
    jsr fio_chrout
.endmacro
.endif
.ifdef X16_USE_FILEIO
.macro xm_fio_readst
    jsr fio_readst
.endmacro
.endif
.ifdef X16_USE_FILEIO
.macro xm_fio_getin
    jsr fio_getin
.endmacro
.endif
.ifdef X16_USE_FILEIO
.macro xm_fio_close_all
    jsr fio_close_all
.endmacro
.endif
.ifdef X16_USE_FILEIO
.macro xm_fio_close_device p_device
    lda #(p_device)
    jsr fio_close_device
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
.ifdef X16_USE_BMX
.macro xm_bmx_load_hires p_name, p_len, p_device
    lda #<(p_name)
    sta X16_P0
    lda #>(p_name)
    sta X16_P1
    lda #(p_len)
    sta X16_P2
    lda #(p_device)
    sta X16_P3
    jsr bmx_load_hires
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
; -> A/X = buffer, Y = length
.ifdef X16_USE_NUMBER
.macro xm_u8_to_dec p_value
    lda #(p_value)
    jsr u8_to_dec
.endmacro
.endif
; -> A/X = buffer, Y = 2
.ifdef X16_USE_NUMBER
.macro xm_u8_to_hex p_value
    lda #(p_value)
    jsr u8_to_hex
.endmacro
.endif
; -> A/X = buffer, Y = 8
.ifdef X16_USE_NUMBER
.macro xm_u8_to_bin p_value
    lda #(p_value)
    jsr u8_to_bin
.endmacro
.endif
; -> A/X = buffer, Y = 16
.ifdef X16_USE_NUMBER
.macro xm_u16_to_bin p_value
    lda #<(p_value)
    sta X16_P0
    lda #>(p_value)
    sta X16_P1
    jsr u16_to_bin
.endmacro
.endif
; -> A/X = buffer, Y = length
.ifdef X16_USE_NUMBER
.macro xm_s8_to_dec p_value
    lda #(p_value)
    jsr s8_to_dec
.endmacro
.endif
; -> A/X = buffer, Y = length
.ifdef X16_USE_NUMBER
.macro xm_s16_to_dec p_value
    lda #<(p_value)
    sta X16_P0
    lda #>(p_value)
    sta X16_P1
    jsr s16_to_dec
.endmacro
.endif

; =====================================================================
; util/sort  (base pointer + element count; sorts in place)
; =====================================================================
.ifdef X16_USE_SORT
.macro xm_sort_u8 p_ptr, p_count
    lda #<(p_ptr)
    sta X16_P0
    lda #>(p_ptr)
    sta X16_P1
    lda #<(p_count)
    sta X16_P2
    lda #>(p_count)
    sta X16_P3
    jsr sort_u8
.endmacro
.endif
.ifdef X16_USE_SORT
.macro xm_sort_s8 p_ptr, p_count
    lda #<(p_ptr)
    sta X16_P0
    lda #>(p_ptr)
    sta X16_P1
    lda #<(p_count)
    sta X16_P2
    lda #>(p_count)
    sta X16_P3
    jsr sort_s8
.endmacro
.endif
.ifdef X16_USE_SORT
.macro xm_sort_u16 p_ptr, p_count
    lda #<(p_ptr)
    sta X16_P0
    lda #>(p_ptr)
    sta X16_P1
    lda #<(p_count)
    sta X16_P2
    lda #>(p_count)
    sta X16_P3
    jsr sort_u16
.endmacro
.endif
.ifdef X16_USE_SORT
.macro xm_sort_s16 p_ptr, p_count
    lda #<(p_ptr)
    sta X16_P0
    lda #>(p_ptr)
    sta X16_P1
    lda #<(p_count)
    sta X16_P2
    lda #>(p_count)
    sta X16_P3
    jsr sort_s16
.endmacro
.endif
.ifdef X16_USE_SORT
.macro xm_sort_ptr p_ptr, p_count, p_cmp
    lda #<(p_ptr)
    sta X16_P0
    lda #>(p_ptr)
    sta X16_P1
    lda #<(p_count)
    sta X16_P2
    lda #>(p_count)
    sta X16_P3
    lda #<(p_cmp)
    sta X16_P4
    lda #>(p_cmp)
    sta X16_P5
    jsr sort_ptr
.endmacro
.endif

; =====================================================================
; string/strsort
; =====================================================================
.ifdef X16_USE_STRING_SORT
.macro xm_str_sort p_ptr, p_count
    lda #<(p_ptr)
    sta X16_P0
    lda #>(p_ptr)
    sta X16_P1
    lda #<(p_count)
    sta X16_P2
    lda #>(p_count)
    sta X16_P3
    jsr str_sort
.endmacro
.endif

; =====================================================================
; audio/wavfile
; =====================================================================
; -> carry set on failure; wav_format/channels/rate/bits/data_off/data_len set
.ifdef X16_USE_WAV
.macro xm_wav_parse_header p_buf
    lda #<(p_buf)
    sta X16_P0
    lda #>(p_buf)
    sta X16_P1
    jsr wav_parse_header
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
; system/clock
; =====================================================================
; -> A/X/Y = 24-bit 60 Hz timer, low to high
.ifdef X16_USE_CLOCK
.macro xm_clock_get_timer
    jsr clock_get_timer
.endmacro
.endif
.ifdef X16_USE_CLOCK
.macro xm_clock_set_timer p_ticks
    lda #<(p_ticks)
    ldx #>((p_ticks) >> 8)
    ldy #>((p_ticks) >> 16)
    jsr clock_set_timer
.endmacro
.endif
.ifdef X16_USE_CLOCK
.macro xm_clock_update
    jsr clock_update
.endmacro
.endif
; -> r0..r3 = year/month/day/hour/min/sec/jiffy/weekday
.ifdef X16_USE_CLOCK
.macro xm_clock_get_date_time
    jsr clock_get_date_time
.endmacro
.endif
; sugar_year1900 is the KERNAL byte value: full year minus 1900.
.ifdef X16_USE_CLOCK
.macro xm_clock_set_date_time_raw p_year1900, p_month, p_day, p_hours, p_minutes, p_seconds, p_jiffies, p_weekday
    lda #<(p_year1900)
    sta r0L
    lda #<(p_month)
    sta r0H
    lda #<(p_day)
    sta r1L
    lda #<(p_hours)
    sta r1H
    lda #<(p_minutes)
    sta r2L
    lda #<(p_seconds)
    sta r2H
    lda #<(p_jiffies)
    sta r3L
    lda #<(p_weekday)
    sta r3H
    jsr clock_set_date_time
.endmacro
.endif
; Friendly form: sugar_year is the full year, e.g. 2026; jiffies are set to 0.
.ifdef X16_USE_CLOCK
.macro xm_clock_set_date_time p_year, p_month, p_day, p_hours, p_minutes, p_seconds, p_weekday
    lda #<((p_year) - 1900)
    sta r0L
    lda #<(p_month)
    sta r0H
    lda #<(p_day)
    sta r1L
    lda #<(p_hours)
    sta r1H
    lda #<(p_minutes)
    sta r2L
    lda #<(p_seconds)
    sta r2H
    stz r3L
    lda #<(p_weekday)
    sta r3H
    jsr clock_set_date_time
.endmacro
.endif

; =====================================================================
; comms/i2c
; =====================================================================
; -> A = value, carry set on NAK/error
.ifdef X16_USE_I2C
.macro xm_i2c_read_byte p_device, p_offset
    ldx #(p_device)
    ldy #(p_offset)
    jsr i2c_read_byte
.endmacro
.endif
; -> carry set on NAK/error
.ifdef X16_USE_I2C
.macro xm_i2c_write_byte p_value, p_device, p_offset
    lda #(p_value)
    ldx #(p_device)
    ldy #(p_offset)
    jsr i2c_write_byte
.endmacro
.endif
; -> carry set on NAK/error
.ifdef X16_USE_I2C
.macro xm_i2c_batch_read p_device, p_buffer, p_count
    lda #<(p_buffer)
    sta r0
    lda #>(p_buffer)
    sta r0+1
    lda #<(p_count)
    sta r1
    lda #>(p_count)
    sta r1+1
    ldx #(p_device)
    clc
    jsr i2c_batch_read
.endmacro
.endif
; -> carry set on NAK/error; reads repeatedly into the same address
.ifdef X16_USE_I2C
.macro xm_i2c_batch_read_fixed p_device, p_buffer, p_count
    lda #<(p_buffer)
    sta r0
    lda #>(p_buffer)
    sta r0+1
    lda #<(p_count)
    sta r1
    lda #>(p_count)
    sta r1+1
    ldx #(p_device)
    sec
    jsr i2c_batch_read
.endmacro
.endif
; -> r2 = bytes written, carry set on NAK/error
.ifdef X16_USE_I2C
.macro xm_i2c_batch_write p_device, p_buffer, p_count
    lda #<(p_buffer)
    sta r0
    lda #>(p_buffer)
    sta r0+1
    lda #<(p_count)
    sta r1
    lda #>(p_count)
    sta r1+1
    ldx #(p_device)
    jsr i2c_batch_write
.endmacro
.endif

; =====================================================================
; comms/spi  (VERA SPI controller)
; =====================================================================
; -> A = VERA_SPI_* control/status bits
.ifdef X16_USE_VERA_SPI
.macro xm_spi_get_ctrl
    jsr spi_get_ctrl
.endmacro
.endif
.ifdef X16_USE_VERA_SPI
.macro xm_spi_set_ctrl p_ctrl
    lda #(p_ctrl)
    jsr spi_set_ctrl
.endmacro
.endif
.ifdef X16_USE_VERA_SPI
.macro xm_spi_select
    jsr spi_select
.endmacro
.endif
.ifdef X16_USE_VERA_SPI
.macro xm_spi_deselect
    jsr spi_deselect
.endmacro
.endif
.ifdef X16_USE_VERA_SPI
.macro xm_spi_slow
    jsr spi_slow
.endmacro
.endif
.ifdef X16_USE_VERA_SPI
.macro xm_spi_fast
    jsr spi_fast
.endmacro
.endif
.ifdef X16_USE_VERA_SPI
.macro xm_spi_autotx_on
    jsr spi_autotx_on
.endmacro
.endif
.ifdef X16_USE_VERA_SPI
.macro xm_spi_autotx_off
    jsr spi_autotx_off
.endmacro
.endif
.ifdef X16_USE_VERA_SPI
.macro xm_spi_wait
    jsr spi_wait
.endmacro
.endif
; -> A = received byte
.ifdef X16_USE_VERA_SPI
.macro xm_spi_transfer p_byte
    lda #(p_byte)
    jsr spi_transfer
.endmacro
.endif
; -> A = received byte
.ifdef X16_USE_VERA_SPI
.macro xm_spi_read
    jsr spi_read
.endmacro
.endif
.ifdef X16_USE_VERA_SPI
.macro xm_spi_write p_byte
    lda #(p_byte)
    jsr spi_write
.endmacro
.endif
; -> A = received byte; starts the next Auto-TX transfer
.ifdef X16_USE_VERA_SPI
.macro xm_spi_autotx_read
    jsr spi_autotx_read
.endmacro
.endif
.ifdef X16_USE_VERA_SPI
.macro xm_spi_read_bytes p_buffer, p_count
    lda #<(p_buffer)
    sta r0L
    lda #>(p_buffer)
    sta r0H
    lda #<(p_count)
    sta r1L
    lda #>(p_count)
    sta r1H
    jsr spi_read_bytes
.endmacro
.endif
.ifdef X16_USE_VERA_SPI
.macro xm_spi_write_bytes p_buffer, p_count
    lda #<(p_buffer)
    sta r0L
    lda #>(p_buffer)
    sta r0H
    lda #<(p_count)
    sta r1L
    lda #>(p_count)
    sta r1H
    jsr spi_write_bytes
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
