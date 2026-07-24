; ca65
; =====================================================================
; CXRF :: apps/gameloop/gameloop.asm -- a game owns the IRQ; a dialog
; borrows it
; =====================================================================
; The pattern a game wants: it installs its OWN raster-line handler for
; smooth, frame-locked motion and reads input directly, never starting
; CXRF's event sampler. To ask the user something -- a pause menu, an
; options panel -- it borrows the events for the length of one modal
; dialog and then takes the raster line back:
;
;     game loop, game_irq animating, GETIN for input
;     cx_ev_init      ; CXRF takes the line + samples (game_irq saved)
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
.include "asmsdk/ca65/cxrf.inc"

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

    cxm_gfx_mode CX_MODE_BMPLOW, 0       ; the game's 256-colour field
    cxm_gfx_clear 6                 ; fill with palette entry 6 -- the entry
                                ; game_irq cycles, so the whole field pulses
    cxm_ink 1                   ; white ink for the labels (mode 1 honours it)

    cxm_say s_t1, 8, 10         ; a couple of lines of on-screen help (x=8,
    cxm_say s_t2, 8, 30         ; mode-1 pixels)

    ; --- take the raster line. This handler is the game's, and runs every
    ; frame whether CXRF's events do or not. cx_ev_raster installs it at
    ; scanline 0 through the kernel's own IRQ, and chains the KERNAL IRQ so
    ; GETIN keeps working -- so cx_ev_init below can save and restore it.
    stz gtick
    cxm_ev_raster game_irq

gloop
    jsr GETIN                   ; KERNAL: A = a key, or 0. The keyboard is
    cmp #CX_K_SPACE            ; filled by the chained KERNAL IRQ; no CXRF
    beq open_config            ; events are running during play
    cmp #CX_K_ESC
    beq do_exit
    bra gloop

; --- borrow CXRF's events for one modal panel, then take the line back.
; This is the whole feature: the game paused (its IRQ off), a dialog the
; kernel's IRQ serves, the game resumed exactly where it froze.
open_config
    cxm_ev_init                 ; CXRF takes the line + samples input;
                                ; game_irq is saved and the cycle freezes
    cxm_mouse_show 1            ; the pointer, so the buttons can be clicked
    cxm_panel panel             ; modal: draws, runs its own loop, returns A
    cxm_mouse_hide
    cxm_ev_stop                 ; the raster line returns to game_irq -- the
    jmp gloop                   ; colour cycles again from where it stopped

do_exit
    cxm_exit                    ; the loader takes the raster line down for us

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
    cxm_panel_hdr 40, 44, 240, 120, s_ptitle, panel_w, 2   ; box + title + 2 buttons
    cxm_item s_ok
    cxm_item s_cancel
panel_w
    cxm_wcount panel_w, panel_w_end
    cxm_wg_check 58, 74, 180, 14, 1, s_snd     ; sound effects, on
    cxm_wg_check 58, 98, 180, 14, 0, s_mus     ; music, off
panel_w_end:

s_ptitle .byte "Options", 0
s_snd    .byte "sound effects", 0
s_mus    .byte "music", 0
s_ok     .byte "OK", 0
s_cancel .byte "Cancel", 0

s_t1     .byte "SPACE: options", 0
s_t2     .byte "ESC: quit", 0
s_up     .byte "GAMELOOP UP", $0D, 0
