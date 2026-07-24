;ACME
; =====================================================================
; x16lib :: input/keyboard.asm -- X16 keyboard buffer and layout helpers
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; This gate exposes the X16-specific keyboard buffer and keymap jump-table
; calls that are not part of the stable X16_USE_INPUT surface.
;
; KEYMAP contract:
;       sec : jsr kbd_keymap       ; get current layout
;             A = layout index, X/Y = NUL-terminated layout name
;       clc : X/Y = name pointer : jsr kbd_keymap
;             carry clear on success, carry set on unknown layout
; =====================================================================

; (zone: file scope in ca65)

KBD_MOD_SHIFT = %00000001
KBD_MOD_ALT   = %00000010       ; Commodore/Alt
KBD_MOD_CTRL  = %00000100
KBD_MOD_CAPS  = %00010000
KBD_MOD_ALTGR = KBD_MOD_ALT | KBD_MOD_CTRL

; ---------------------------------------------------------------------
; kbd_scan -- scan keyboard once
; ---------------------------------------------------------------------
kbd_scan
    jmp SCNKEY

; ---------------------------------------------------------------------
; kbd_peek -- read next buffered key without consuming it
;   out: A = next PETSCII key, X = queued key count, Z set when empty
; ---------------------------------------------------------------------
kbd_peek
    jmp KBDBUF_PEEK

; ---------------------------------------------------------------------
; kbd_put -- append a PETSCII key to the keyboard buffer
;   in: A = PETSCII key
; ---------------------------------------------------------------------
kbd_put
    jmp KBDBUF_PUT

; ---------------------------------------------------------------------
; kbd_get_modifiers -- read the current modifier bitfield
;   out: A = KBD_MOD_* bits
; ---------------------------------------------------------------------
kbd_get_modifiers
    jmp KBDBUF_GET_MODIFIERS

; ---------------------------------------------------------------------
; kbd_keymap -- get or set the active keyboard layout
;   in:  C clear: X/Y = NUL-terminated layout string
;        C set:   query current layout
;   out: query: A = layout index, X/Y = current layout string
;        set:   carry clear on success, carry set on failure
; ---------------------------------------------------------------------
kbd_keymap
    jmp KEYMAP

; ---------------------------------------------------------------------
; kbd_get_keymap -- friendly current-layout query
;   out: A = layout index, X/Y = current layout string
; ---------------------------------------------------------------------
kbd_get_keymap
    sec
    jmp KEYMAP

; ---------------------------------------------------------------------
; kbd_set_keymap -- friendly layout setter
;   in: X/Y = NUL-terminated layout string
;   out: carry clear on success, carry set on failure
; ---------------------------------------------------------------------
kbd_set_keymap
    clc
    jmp KEYMAP

; (end zone)
