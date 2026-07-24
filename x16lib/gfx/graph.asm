;ACME
; =====================================================================
; x16lib :: gfx/graph.asm -- KERNAL GRAPH wrappers
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; These are thin wrappers over the stable Commander X16 KERNAL GRAPH API.
; GRAPH is the ROM's higher-level drawing layer on top of the active
; framebuffer driver.
; =====================================================================

; (zone: file scope in ca65)

; --- character style bits used by graph_get_char_size ----------------
GRAPH_STYLE_UNDERLINE = %00000001
GRAPH_STYLE_BOLD      = %00000010
GRAPH_STYLE_ITALIC    = %00000100

; ---------------------------------------------------------------------
; graph_init -- initialize GRAPH and active framebuffer driver
;   in: r0 = FB_* driver vector pointer, or 0 for default 320x240@8bpp
; ---------------------------------------------------------------------
graph_init
    jmp GRAPH_INIT

; ---------------------------------------------------------------------
; graph_clear -- clear current GRAPH window to background color
; ---------------------------------------------------------------------
graph_clear
    jmp GRAPH_CLEAR

; ---------------------------------------------------------------------
; graph_set_window -- set clipping/window rectangle
;   in: r0 = x, r1 = y, r2 = width, r3 = height
;       0/0/0/0 resets to full screen
; ---------------------------------------------------------------------
graph_set_window
    jmp GRAPH_SET_WINDOW

; ---------------------------------------------------------------------
; graph_set_colors -- set drawing colors
;   in: A = primary/stroke, X = secondary/fill, Y = background
; ---------------------------------------------------------------------
graph_set_colors
    jmp GRAPH_SET_COLORS

; ---------------------------------------------------------------------
; graph_draw_line -- draw line
;   in: r0 = x1, r1 = y1, r2 = x2, r3 = y2
; ---------------------------------------------------------------------
graph_draw_line
    jmp GRAPH_DRAW_LINE

; ---------------------------------------------------------------------
; graph_draw_rect -- draw rectangle
;   in: r0 = x, r1 = y, r2 = width, r3 = height, r4 = corner radius
;       C clear = outline, C set = fill
; ---------------------------------------------------------------------
graph_draw_rect
    jmp GRAPH_DRAW_RECT

; ---------------------------------------------------------------------
; graph_move_rect -- move rectangle
;   in: r0 = sx, r1 = sy, r2 = tx, r3 = ty, r4 = width, r5 = height
; ---------------------------------------------------------------------
graph_move_rect
    jmp GRAPH_MOVE_RECT

; ---------------------------------------------------------------------
; graph_draw_oval -- draw oval
;   in: r0 = x, r1 = y, r2 = width, r3 = height
;       C clear = outline, C set = fill
; ---------------------------------------------------------------------
graph_draw_oval
    jmp GRAPH_DRAW_OVAL

; ---------------------------------------------------------------------
; graph_draw_image -- draw image bytes
;   in: r0 = x, r1 = y, r2 = image pointer, r3 = width, r4 = height
; ---------------------------------------------------------------------
graph_draw_image
    jmp GRAPH_DRAW_IMAGE

; ---------------------------------------------------------------------
; graph_set_font -- set current GRAPH font
;   in: r0 = font pointer, or 0 for system font
; ---------------------------------------------------------------------
graph_set_font
    jmp GRAPH_SET_FONT

; ---------------------------------------------------------------------
; graph_get_char_size -- get character metrics
;   in:  A = character, X = GRAPH_STYLE_* bits
;   out: printable: C clear, A = baseline, X = width, Y = height
;        control:   C set, X = new style
; ---------------------------------------------------------------------
graph_get_char_size
    jmp GRAPH_GET_CHAR_SIZE

; ---------------------------------------------------------------------
; graph_put_char -- draw a character and update position
;   in:  A = character, r0 = x, r1 = y
;   out: r0/r1 = updated position, carry set if outside bounds
; ---------------------------------------------------------------------
graph_put_char
    jmp GRAPH_PUT_CHAR

; (end zone)
