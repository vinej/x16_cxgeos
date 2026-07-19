; ca65
; =====================================================================
; CXGEOS :: apps/dtext/dtext.asm -- an alert dialog in the text TUI
; =====================================================================
; The dialog toolkit through the port: switch to mode 3, raise a modal
; alert. The same dialog engine that draws a 400x96 pixel box on the
; desktop draws a centred CELL box here -- frame, message, buttons --
; sized and placed from the port's per-mode metrics. It holds on the
; modal wait, so a screenshot can see it.
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
    jsr CHROUT
    inx
    bra @pr
@prd

    jsr cx_ev_init
    lda #<handlers
    ldx #>handlers
    jsr cx_ev_handlers

    lda #3                      ; CX_MODE_TEXT
    jsr cx_gfx_mode
    lda #6
    jsr cx_gfx_clear

    lda #1                     ; the arrow, so it can be clicked
    jsr cx_mouse_show
    lda #<alert
    ldx #>alert
    jsr cx_dlg_alert           ; modal: draws the box, waits for a button
                               ; (click or RETURN), returns the choice
    jmp cx_exit                ; ...then back to the desktop

handlers
    .addr h_rts, h_rts, h_rts, h_rts, h_rts
    .addr h_rts, h_rts, h_rts, h_rts, h_rts
h_rts
    rts

alert
    .byte 2
    .addr s_msg
    .addr s_no, s_yes
s_msg .byte "Delete the selected file?", 0
s_no  .byte "no", 0
s_yes .byte "yes", 0
s_up  .byte "DTEXT UP", $0D, 0
