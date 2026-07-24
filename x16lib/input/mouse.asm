;ACME
; =====================================================================
; x16lib :: input/mouse.asm -- full KERNAL mouse wrappers
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; This gate complements the compact mouse helpers in X16_USE_INPUT. It
; exposes the full stable KERNAL mouse surface with distinct mse_* names
; so it can be enabled alongside X16_USE_INPUT or a section bundle.
;
; MOUSE_CONFIG:
;       A = $00 hide mouse
;           n   show mouse and select cursor sprite n
;           $FF show mouse without changing cursor sprite
;       X = width in 8-pixel units
;       Y = height in 8-pixel units
;       X=0 and Y=0 leaves the current bounds unchanged
;
; MOUSE_GET:
;       X = zero-page destination for xlo,xhi,ylo,yhi
;       A = buttons, X = signed wheel delta
; =====================================================================

; (zone: file scope in ca65)

MSE_BUTTON_LEFT   = %00000001
MSE_BUTTON_RIGHT  = %00000010
MSE_BUTTON_MIDDLE = %00000100
MSE_BUTTON_4      = %00010000
MSE_BUTTON_5      = %00100000

; ---------------------------------------------------------------------
; mse_config -- raw MOUSE_CONFIG wrapper
;   in: A = show/cursor selector, X = width/8, Y = height/8
; ---------------------------------------------------------------------
mse_config
    jmp MOUSE_CONFIG

; ---------------------------------------------------------------------
; mse_scan -- scan mouse once
; ---------------------------------------------------------------------
mse_scan
    jmp MOUSE_SCAN

; ---------------------------------------------------------------------
; mse_get_to -- raw MOUSE_GET wrapper
;   in:  X = zero-page destination for xlo,xhi,ylo,yhi
;   out: A = buttons, X = signed wheel delta
; ---------------------------------------------------------------------
mse_get_to
    jmp MOUSE_GET

; ---------------------------------------------------------------------
; mse_get -- read mouse to X16_P0..X16_P3
;   out: X16_P0/P1 = x, X16_P2/P3 = y, A = buttons, X = wheel delta
; ---------------------------------------------------------------------
mse_get
    ldx #X16_P0
    jmp MOUSE_GET

; ---------------------------------------------------------------------
; mse_show -- show and select cursor sprite A, keeping current bounds
; ---------------------------------------------------------------------
mse_show
    ldx #0
    ldy #0
    jmp MOUSE_CONFIG

; ---------------------------------------------------------------------
; mse_show_keep -- show mouse without changing cursor sprite or bounds
; ---------------------------------------------------------------------
mse_show_keep
    lda #$ff
    ldx #0
    ldy #0
    jmp MOUSE_CONFIG

; ---------------------------------------------------------------------
; mse_hide -- hide mouse, keeping current bounds
; ---------------------------------------------------------------------
mse_hide
    lda #0
    ldx #0
    ldy #0
    jmp MOUSE_CONFIG

; (end zone)
