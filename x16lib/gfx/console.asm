;ACME
; =====================================================================
; x16lib :: gfx/console.asm -- KERNAL console API wrappers
; =====================================================================
; Gate: X16_USE_CONSOLE
;
; Thin wrappers around the Commander X16 KERNAL console API. The console
; renders through GRAPH, but this gate is intentionally separate so callers
; can opt into only the ROM entry points they want to use.

; PETSCII control codes accepted by con_put_char for GRAPH font styling.
CON_ATTR_UNDERLINE = $04
CON_ATTR_BOLD      = $06
CON_ATTR_ITALICS   = $0b
CON_ATTR_OUTLINE   = $0c
CON_ATTR_RESET     = $92

; con_set_paging_message
;   in: r0 = pointer to a zero-terminated paging prompt
con_set_paging_message
    jmp CONSOLE_SET_PAGING_MESSAGE

; con_disable_paging
;   disables the pause prompt between console pages
con_disable_paging
    stz r0L
    stz r0H
    jmp CONSOLE_SET_PAGING_MESSAGE

; con_put_image
;   in: r0 = image pointer, r1 = width, r2 = height
;       image data uses the GRAPH_draw_image format
con_put_image
    jmp CONSOLE_PUT_IMAGE

; con_init
;   in: r0 = x, r1 = y, r2 = width, r3 = height
;       use all zeroes for the full GRAPH window
con_init
    jmp CONSOLE_INIT

; con_put_char
;   in: A = character, C clear = character wrap, C set = word wrap
con_put_char
    jmp CONSOLE_PUT_CHAR

; con_get_char
;   out: A = character
con_get_char
    jmp CONSOLE_GET_CHAR
