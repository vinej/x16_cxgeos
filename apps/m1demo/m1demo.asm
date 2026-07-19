; ca65
; =====================================================================
; CXGEOS :: apps/m1demo/m1demo.asm -- the toolkit in mode 1 (8bpp)
; =====================================================================
; The toolkit in the 320x240 256-colour bitmap: switch to mode 1, then
; raise a modal alert. The same dialog engine that draws on the desktop
; and in the text TUI draws here too -- framed box, message, buttons --
; sized to the 320x240 screen from the port's mode-1 metrics, saved
; under to a VRAM strip. The default palette gives 0/1/3 = black/white/
; cyan, so the theme roles show. Holds on the modal wait for a capture.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    ldx #0
@pr
    lda s_up,x
    beq @prd
    jsr $FFD2
    inx
    bra @pr
@prd

    jsr cx_ev_init
    lda #<handlers
    ldx #>handlers
    jsr cx_ev_handlers

    lda #1                      ; CX_MODE_BMP8
    jsr cx_gfx_mode
    lda #6                      ; a blue field (default palette)
    jsr cx_gfx_clear

    lda #<alert
    ldx #>alert
    jsr cx_dlg_alert            ; modal: draws the box and waits

@hold
    bra @hold

handlers
    .addr h_rts, h_rts, h_rts, h_rts, h_rts
    .addr h_rts, h_rts, h_rts, h_rts, h_rts
h_rts
    rts

alert
    .byte 2
    .addr s_msg
    .addr s_no, s_yes
s_msg .byte "Overwrite the image?", 0
s_no  .byte "no", 0
s_yes .byte "yes", 0
s_up  .byte "M1DEMO UP", $0D, 0
