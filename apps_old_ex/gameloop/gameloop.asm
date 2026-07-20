; ca65
; =====================================================================
; CXGEOS :: apps/gameloop/gameloop.asm -- a game owns the IRQ; a dialog
; borrows it
; =====================================================================
; The pattern a game wants: it installs its OWN raster-line handler for
; smooth, frame-locked motion and reads input directly, never starting
; CXGEOS's event sampler. To ask the user something -- a pause menu, an
; options panel -- it borrows the events for the length of one modal
; dialog and then takes the raster line back:
;
;     game loop, game_irq animating, GETIN for input
;     cx_ev_init      ; CXGEOS takes the line + samples (game_irq saved)
;     cx_panel        ; a modal panel the kernel's IRQ drives
;     cx_ev_stop      ; the line returns to game_irq; the game resumes
;
; The "game" here is a colour cycle on the 8bpp field: game_irq writes one
; VERA palette entry per frame, at the top of the frame. Watch it -- the
; field pulses while you play, FREEZES the instant the options panel opens
; (game_irq no longer holds the line), and RESUMES the moment you close it
; (cx_ev_stop handed the line back). SPACE opens options, ESC quits.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

KEY_ESC   = $1B
KEY_SPACE = $20
WG_CHECK  = 1

gtick     = $60                 ; the frame game_irq is on (also the colour)

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    ldx #0                      ; a line so a headless boot log shows we ran
@pr
    lda s_up,x
    beq @prd
    jsr CHROUT
    inx
    bra @pr
@prd

    lda #1                      ; CX_MODE_BMP8: the game's 256-colour field
    jsr cx_gfx_mode
    lda #6                      ; fill with palette entry 6 -- the entry
    jsr cx_gfx_clear            ; game_irq cycles, so the whole field pulses
    lda #1                      ; white ink for the labels (mode 1 honours it)
    jsr cx_ink

    lda #<s_t1                  ; a couple of lines of on-screen help
    ldx #>s_t1
    ldy #10
    jsr drawtext
    lda #<s_t2
    ldx #>s_t2
    ldy #30
    jsr drawtext

    ; --- take the raster line. This handler is the game's, and runs every
    ; frame whether CXGEOS's events do or not. cx_ev_raster installs it at
    ; scanline 0 through the kernel's own IRQ, and chains the KERNAL IRQ so
    ; GETIN keeps working -- so cx_ev_init below can save and restore it.
    stz gtick
    lda #<game_irq
    ldx #>game_irq
    jsr cx_ev_raster

gloop
    jsr GETIN                   ; KERNAL: A = a key, or 0. The keyboard is
    cmp #KEY_SPACE              ; filled by the chained KERNAL IRQ; no CXGEOS
    beq open_config            ; events are running during play
    cmp #KEY_ESC
    beq do_exit
    bra gloop

; --- borrow CXGEOS's events for one modal panel, then take the line back.
; This is the whole feature: the game paused (its IRQ off), a dialog the
; kernel's IRQ serves, the game resumed exactly where it froze.
open_config
    jsr cx_ev_init              ; CXGEOS takes the line + samples input;
                                ; game_irq is saved and the cycle freezes
    lda #1
    jsr cx_mouse_show           ; the pointer, so the buttons can be clicked
    lda #<panel
    ldx #>panel
    jsr cx_panel                ; modal: draws, runs its own loop, returns A
    jsr cx_mouse_hide
    jsr cx_ev_stop              ; the raster line returns to game_irq -- the
    jmp gloop                   ; colour cycles again from where it stopped

do_exit
    jmp cx_exit                 ; the loader takes the raster line down for us

; drawtext -- A/X = string, Y = y; x is fixed at 8 (mode-1 pixels). The
; string is held on the stack while x/y overwrite P0-P3.
drawtext
    pha                         ; string low
    phx                         ; string high
    lda #8
    sta X16_P0
    stz X16_P1
    sty X16_P2
    stz X16_P3
    plx                         ; string high -> X
    pla                         ; string low  -> A
    jsr cx_font_draw
    rts

; --- game_irq: the game's per-frame handler, on scanline 0. One VERA
; write, cheap and frame-locked -- cycle palette entry 6 (the field's
; colour). x16lib's irq_handler saved the VERA address port around us,
; so touching it here does not disturb the foreground.
game_irq
    inc gtick
    lda #$0C                    ; VRAM $1FA0C: palette entry 6 (n*2 + $1FA00)
    sta VERA_ADDR_L
    lda #$FA
    sta VERA_ADDR_M
    lda #(VERA_ADDR_H_BANK | (VERA_INC_1 << 4))
    sta VERA_ADDR_H
    lda gtick                   ; low byte: green | blue
    sta VERA_DATA0
    lda gtick
    lsr
    lsr
    lsr
    lsr
    sta VERA_DATA0              ; high byte: the red nibble (0000 RRRR)
    rts

; --- the options panel: a title, two checkboxes, OK / Cancel (320x240) --
panel
    .word 40, 44, 240          ; box x, y, w (pixels)
    .byte 120                  ; box h (within the mode-1 save-under strip)
    .addr s_ptitle
    .addr panel_w
    .byte 2
    .addr s_ok, s_cancel
panel_w
    .byte 2
    .byte WG_CHECK, 0
    .word 58, 74, 180
    .byte 14, 1, 0
    .addr s_snd
    .byte 0, 0, 0
    .byte WG_CHECK, 0
    .word 58, 98, 180
    .byte 14, 0, 0
    .addr s_mus
    .byte 0, 0, 0

s_ptitle .byte "Options", 0
s_snd    .byte "sound effects", 0
s_mus    .byte "music", 0
s_ok     .byte "OK", 0
s_cancel .byte "Cancel", 0

s_t1     .byte "SPACE: options", 0
s_t2     .byte "ESC: quit", 0
s_up     .byte "GAMELOOP UP", $0D, 0
