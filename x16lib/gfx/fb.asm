;ACME
; =====================================================================
; x16lib :: gfx/fb.asm -- KERNAL framebuffer wrappers
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; These are thin wrappers over the stable Commander X16 KERNAL
; framebuffer jump table. The default ROM driver is 320x240 at 8bpp, but
; the KERNAL GRAPH layer can install a different FB driver.
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; fb_init -- initialize the active framebuffer driver
; ---------------------------------------------------------------------
fb_init
    jmp FB_INIT

; ---------------------------------------------------------------------
; fb_get_info -- get framebuffer geometry
;   out: r0 = width, r1 = height, A = color depth
; ---------------------------------------------------------------------
fb_get_info
    jmp FB_GET_INFO

; ---------------------------------------------------------------------
; fb_set_palette -- set one or more VERA palette entries
;   in: r0 = palette data pointer, A = start index, X = count (0 = 256)
; ---------------------------------------------------------------------
fb_set_palette
    jmp FB_SET_PALETTE

; ---------------------------------------------------------------------
; fb_cursor_position -- position the framebuffer cursor
;   in: r0 = x, r1 = y
; ---------------------------------------------------------------------
fb_cursor_position
    jmp FB_CURSOR_POSITION

; ---------------------------------------------------------------------
; fb_cursor_next_line -- move framebuffer cursor to the next scanline
; ---------------------------------------------------------------------
fb_cursor_next_line
    jmp FB_CURSOR_NEXT_LINE

; ---------------------------------------------------------------------
; fb_get_pixel -- read pixel at current framebuffer cursor
;   out: A = color
; ---------------------------------------------------------------------
fb_get_pixel
    jmp FB_GET_PIXEL

; ---------------------------------------------------------------------
; fb_get_pixels -- read pixels from cursor into memory
;   in: r0 = destination pointer, r1 = count
; ---------------------------------------------------------------------
fb_get_pixels
    jmp FB_GET_PIXELS

; ---------------------------------------------------------------------
; fb_set_pixel -- write pixel at current framebuffer cursor
;   in: A = color
; ---------------------------------------------------------------------
fb_set_pixel
    jmp FB_SET_PIXEL

; ---------------------------------------------------------------------
; fb_set_pixels -- write pixels from memory to cursor
;   in: r0 = source pointer, r1 = count
; ---------------------------------------------------------------------
fb_set_pixels
    jmp FB_SET_PIXELS

; ---------------------------------------------------------------------
; fb_set_8_pixels -- draw an 8-bit pattern at cursor
;   in: A = pattern, X = foreground color
; ---------------------------------------------------------------------
fb_set_8_pixels
    jmp FB_SET_8_PIXELS

; ---------------------------------------------------------------------
; fb_set_8_pixels_opaque -- draw an 8-bit masked pattern at cursor
;   in: A = mask, r0L = pattern, X = foreground, Y = background
; ---------------------------------------------------------------------
fb_set_8_pixels_opaque
    jmp FB_SET_8_PIXELS_OPAQUE

; ---------------------------------------------------------------------
; fb_fill_pixels -- fill from cursor
;   in: r0 = pixel count, r1 = step size, A = color
; ---------------------------------------------------------------------
fb_fill_pixels
    jmp FB_FILL_PIXELS

; ---------------------------------------------------------------------
; fb_filter_pixels -- filter pixels from cursor
;   in: r0 = pixel count, r1 = filter routine pointer
;        filter: A = old color, returns A = new color
; ---------------------------------------------------------------------
fb_filter_pixels
    jmp FB_FILTER_PIXELS

; ---------------------------------------------------------------------
; fb_move_pixels -- move a horizontal pixel span
;   in: r0 = source x, r1 = source y, r2 = target x,
;       r3 = target y, r4 = pixel count
; ---------------------------------------------------------------------
fb_move_pixels
    jmp FB_MOVE_PIXELS

; (end zone)
