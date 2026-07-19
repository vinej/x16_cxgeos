;ACME
; =====================================================================
; x16lib :: input/input.asm -- joystick, mouse, keyboard
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; Thin wrappers over the KERNAL. Nothing here touches VERA directly
; except mouse_show, which the KERNAL handles for us.
; =====================================================================

; (zone: file scope in ca65)

; --- joystick button bits (ACTIVE LOW: a clear bit means pressed) -----
; byte 0
JOY_B      = %10000000
JOY_Y      = %01000000
JOY_SELECT = %00100000
JOY_START  = %00010000
JOY_UP     = %00001000
JOY_DOWN   = %00000100
JOY_LEFT   = %00000010
JOY_RIGHT  = %00000001
; byte 1
JOY_A      = %10000000
JOY_X      = %01000000
JOY_L      = %00100000
JOY_R      = %00010000

JOY_PRESENT = $00
JOY_ABSENT  = $FF

; ---------------------------------------------------------------------
; joy_scan -- sample every joystick. Call once per frame before joy_get.
;             The KERNAL's IRQ already does this; only needed if you
;             have taken the interrupt over.
; ---------------------------------------------------------------------
joy_scan
    jmp JOYSTICK_SCAN

; ---------------------------------------------------------------------
; joy_get
;   in:  A = joystick (0 = keyboard, 1-4 = gamepads)
;   out: A = buttons byte 0 (B Y SELECT START UP DOWN LEFT RIGHT)
;        X = buttons byte 1 (A X L R and four set filler bits)
;        Y = $00 present, $FF absent
;
; Bits are ACTIVE LOW. A pressed button reads 0, so test with a mask and
; branch on zero:  and #JOY_LEFT : beq moving_left
; ---------------------------------------------------------------------
joy_get
    jmp JOYSTICK_GET

; ---------------------------------------------------------------------
; mouse_show -- in: A = $00 hide, $FF show without changing the cursor,
;                      n  show and select cursor sprite n
;               The screen size is left unchanged (MOUSE_CONFIG is
;               called with X = Y = 0). Call MOUSE_CONFIG yourself to
;               resize the mouse field.
; mouse_hide
; ---------------------------------------------------------------------
mouse_show
    ldx #0
    ldy #0
    jmp MOUSE_CONFIG

mouse_hide
    lda #0
    ldx #0
    ldy #0
    jmp MOUSE_CONFIG

; ---------------------------------------------------------------------
; mouse_get -- read position and buttons
;   out: X16_P0/P1 = x, X16_P2/P3 = y, A = buttons
;        (bit 0 left, bit 1 right, bit 2 middle)
;
; The KERNAL writes the four position bytes to zero page starting at the
; address in X, which is why the results land in the parameter block.
; ---------------------------------------------------------------------
mouse_get
    ldx #X16_P0
    jmp MOUSE_GET

; ---------------------------------------------------------------------
; key_get -- out: A = PETSCII code, or 0 if nothing is waiting
;            Non-blocking.
; ---------------------------------------------------------------------
key_get
    jmp GETIN

; key_wait (blocking) and key_peek (lookahead) are convenience calls an
; event-driven program never uses -- it drains with key_get -- so they are
; behind X16_USE_INPUT_KEYWAIT (X16_USE_INPUT still pulls them, for compat).
.ifdef X16_USE_INPUT_KEYWAIT
; ---------------------------------------------------------------------
; key_wait -- block until a key is pressed.  out: A = PETSCII code
; ---------------------------------------------------------------------
key_wait
@loop
    jsr GETIN
    beq @loop
    rts

; ---------------------------------------------------------------------
; key_peek -- out: A = next key without consuming it
;                  X = number of keys queued
;                  Z set (and X = 0) when the buffer is empty
; ---------------------------------------------------------------------
key_peek
    jmp KBDBUF_PEEK
.endif

; (end zone)
