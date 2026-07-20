; ca65
; =====================================================================
; CXGEOS :: apps/shell/shell.asm -- the Phase 4/5 stub shell
; =====================================================================
; The first program the boot chain lands in, and the first one that
; looks like an operating system: a menu bar, a pointer, drop-downs
; with hover highlight -- all of it the kernel's, reached through the
; jump table. Phase 6 replaces this with the resident desktop; the
; lifecycle and the menu plumbing it exercises are permanent.
;
; Still built from sdk/ alone, deliberately: whatever this shell cannot
; do through the table is a hole in the ABI.
; =====================================================================

.include "x16.asm"
.include "asmsdk/ca65/cxgeos.inc"

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    ; The marker goes through CHROUT, which the -echo harness can see
    ; whatever the video mode shows.
    ldx #0
@mk
    lda s_marker,x
    beq @go
    jsr CHROUT
    inx
    bra @mk
@go
    cxm_gfx_init
    cxm_gfx_clear 0

    cxm_say s_title, 24, 32
    cxm_say s_hint1, 24, 56
    cxm_say s_hint2, 24, 72

    cxm_ev_init                 ; events first: the menu bar lives on
    cxm_menu_set bar            ; the region stack ev_init resets
    cxm_mouse_show 1            ; the arrow (sprite 1); the loader hid it

    cxm_ev_handlers handlers
    cxm_ev_mainloop

; ---------------------------------------------------------------------
; the handlers
; ---------------------------------------------------------------------
on_menu
    lda X16_P2                  ; which menu
    beq @sys                    ; 0: CXGEOS
    cmp #2
    beq @theme                  ; 2: Themes
    lda X16_P1                  ; 1: Demos -- which item
    beq @h1
    cmp #1
    beq @h2
    cmp #2
    beq @h3
    cmp #3
    beq @h4
    rts
@sys
    lda X16_P1                  ; About is its only item
    bne @none
    cxm_dlg_alert about_dlg         ; a real dialog: blocks until the button,
    rts                         ; and every pixel it covered comes back
@theme
    lda X16_P1                  ; 0 = daylight, 1 = midnight
    beq @day
    cxm_theme_set theme_night
    rts
@day
    cxm_theme_set theme_day
    rts
@h1
    cxm_app_load s_f1, s_f1_len   ; returns only on failure
    bra sorry
@h2
    cxm_app_load s_f2, s_f2_len
    bra sorry
@h3
    cxm_app_load s_f3, s_f3_len
    bra sorry
@h4
    cxm_app_load s_f4, s_f4_len
    bra sorry
@none
    rts

on_key
    lda X16_P1                  ; the menu bar gets first refusal: DOWN
    jsr cx_menu_key             ; opens it, arrows walk it, RETURN picks
    bcc @app                    ; -- carry set means it was a menu key
    rts
@app
    lda X16_P1                  ; the number keys still launch directly
    cmp #'1'
    beq @one
    cmp #'2'
    beq @two
    cmp #'3'
    beq @three
    cmp #'4'
    beq @four
    rts
@one
    cxm_app_load s_f1, s_f1_len
    bra sorry
@two
    cxm_app_load s_f2, s_f2_len
    bra sorry
@three
    cxm_app_load s_f3, s_f3_len
    bra sorry
@four
    cxm_app_load s_f4, s_f4_len

sorry                           ; a load that came back is a load that failed
    cxm_say s_missing, 24, 120
    rts

handlers                        ; NULL MOVE DOWN UP DBL KEY TIMER MENU WIDGET JOY
    .addr 0, 0, 0, 0, 0
    .addr on_key
    .addr 0
    .addr on_menu
    .addr 0                     ; WIDGET: the shell has none
    .addr 0                     ; JOY: EV_COUNT (10) vectors, always

; ---------------------------------------------------------------------
; the menu tree (docs/formats.md)
; ---------------------------------------------------------------------
bar
    cxm_menu_bar 3
    cxm_menu s_m0, m0_items
    cxm_menu s_m1, m1_items
    cxm_menu s_m2, m2_items
m0_items
    cxm_items 1
    cxm_item s_i_about
m1_items
    cxm_items 4
    cxm_item s_i_h1
    cxm_item s_i_h2
    cxm_item s_i_h3
    cxm_item s_i_h4
m2_items
    cxm_items 2
    cxm_item s_i_day
    cxm_item s_i_night

about_dlg
    cxm_dialog 1, s_about
    cxm_item s_i_ok

; a theme is four palette colours ($0RGB) and the paper/hi/frame roles
theme_day                       ; the default: black ink on white paper
    cxm_theme_rec $0FFF, $0AAA, $0555, $0000, 0, 1, 3
theme_night                     ; pale ink on a deep blue-black
    cxm_theme_rec $0001, $0123, $0356, $0ABC, 0, 1, 3

s_m0      .byte "CXGEOS", 0
s_m1      .byte "Demos", 0
s_m2      .byte "Themes", 0
s_i_about .byte "about this machine", 0
s_i_h1    .byte "hello, from assembly", 0
s_i_h2    .byte "hello, from C", 0
s_i_h3    .byte "the widget gallery", 0
s_i_h4    .byte "the file browser", 0
s_i_day   .byte "daylight", 0
s_i_night .byte "midnight", 0
s_i_ok    .byte "ok", 0

s_marker  .byte "CXGEOS SHELL", $0D, 0
s_title   .byte "CXGEOS 0.1", 0
s_hint1   .byte "the menus up there work with the mouse.", 0
s_hint2   .byte "keys work too: 1 and 2 launch the demos.", 0
s_about   .byte "CXGEOS 0.1 -- a from-scratch, GEOS-inspired OS, on stock ROM.", 0
s_missing .byte "that app is not on this disk.                                        ", 0
s_f1      .byte "HELLO1.CXA"
s_f1_len = * - s_f1
s_f2      .byte "HELLO2.CXA"
s_f2_len = * - s_f2
s_f3      .byte "GALLERY.CXA"
s_f3_len = * - s_f3
s_f4      .byte "FILER.CXA"
s_f4_len = * - s_f4
