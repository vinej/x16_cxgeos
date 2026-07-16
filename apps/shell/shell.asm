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
.include "sdk/include_ca65/cxgeos.inc"

EV_KEY  = 5                     ; ABI event numbering
EV_MENU = 7

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
    jsr cx_gfx_init
    lda #0
    jsr cx_gfx_clear

    lda #<s_title
    ldx #>s_title
    ldy #<32
    jsr say
    lda #<s_hint1
    ldx #>s_hint1
    ldy #<56
    jsr say
    lda #<s_hint2
    ldx #>s_hint2
    ldy #<72
    jsr say

    jsr cx_ev_init              ; events first: the menu bar lives on
    lda #<bar                   ; the region stack ev_init resets
    ldx #>bar
    jsr cx_menu_set
    lda #1                      ; the arrow (sprite 1); the loader hid it
    jsr cx_mouse_show

    lda #<handlers
    ldx #>handlers
    jsr cx_ev_handlers
    jmp cx_ev_mainloop

; ---------------------------------------------------------------------
; say -- A/X = string, Y = the row (all rows here fit a byte). Column
; 24: a stub shell needs exactly one margin.
; ---------------------------------------------------------------------
say
    sty X16_P2
    stz X16_P3
    ldy #24
    sty X16_P0
    stz X16_P1
    jmp cx_font_draw

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
    rts
@sys
    lda X16_P1                  ; About is its only item
    bne @none
    lda #<about_dlg             ; a real dialog: the call blocks until
    ldx #>about_dlg             ; the button, and every pixel it covered
    jmp cx_dlg_alert            ; comes back on its own
@theme
    lda X16_P1                  ; 0 = daylight, 1 = midnight
    beq @day
    lda #<theme_night
    ldx #>theme_night
    jmp cx_theme_set
@day
    lda #<theme_day
    ldx #>theme_day
    jmp cx_theme_set
@h1
    lda #<s_f1
    ldx #>s_f1
    ldy #s_f1_len
    jsr cx_app_load             ; returns only on failure
    bra sorry
@h2
    lda #<s_f2
    ldx #>s_f2
    ldy #s_f2_len
    jsr cx_app_load
    bra sorry
@h3
    lda #<s_f3
    ldx #>s_f3
    ldy #s_f3_len
    jsr cx_app_load
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
    rts
@one
    lda #<s_f1
    ldx #>s_f1
    ldy #s_f1_len
    jsr cx_app_load
    bra sorry
@two
    lda #<s_f2
    ldx #>s_f2
    ldy #s_f2_len
    jsr cx_app_load
    bra sorry
@three
    lda #<s_f3
    ldx #>s_f3
    ldy #s_f3_len
    jsr cx_app_load

sorry                           ; a load that came back is a load that
    lda #<s_missing             ; failed
    ldx #>s_missing
    ldy #<120
    jmp say

handlers                        ; NULL MOVE DOWN UP DBL KEY TIMER MENU WIDGET
    .addr 0, 0, 0, 0, 0
    .addr on_key
    .addr 0
    .addr on_menu
    .addr 0                     ; WIDGET: the shell has none

; ---------------------------------------------------------------------
; the menu tree (docs/formats.md)
; ---------------------------------------------------------------------
bar
    .byte 3
    .addr s_m0, m0_items
    .addr s_m1, m1_items
    .addr s_m2, m2_items
m0_items
    .byte 1
    .addr s_i_about
m1_items
    .byte 3
    .addr s_i_h1
    .addr s_i_h2
    .addr s_i_h3
m2_items
    .byte 2
    .addr s_i_day
    .addr s_i_night

about_dlg
    .byte 1
    .addr s_about
    .addr s_i_ok

; a theme is the four palette RGBs (GB, R nibbles) and the role indices
theme_day                       ; the default: black ink on white paper
    .byte $FF, $0F,  $AA, $0A,  $55, $05,  $00, $00
    .byte 0, 1, 3, 0
theme_night                     ; pale ink on a deep blue-black
    .byte $01, $00,  $23, $01,  $56, $03,  $BC, $0A
    .byte 0, 1, 3, 0

s_m0      .byte "CXGEOS", 0
s_m1      .byte "Demos", 0
s_m2      .byte "Themes", 0
s_i_about .byte "about this machine", 0
s_i_h1    .byte "hello, from assembly", 0
s_i_h2    .byte "hello, from C", 0
s_i_h3    .byte "the widget gallery", 0
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
