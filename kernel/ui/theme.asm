; ca65
; =====================================================================
; CXRF :: kernel/ui/theme.asm -- the live theme
; =====================================================================
; Twelve resident bytes every UI drawer reads, plus a bank-2 setter.
; Resident, deliberately: the menu and dialog engines execute in bank 2
; and could not read a theme stored in bank 1 -- one window.
;
; A theme is the four palette RGBs plus which index plays which role
; (docs/formats.md). Text ink is NOT a role: the glyph cache is built
; as colour-3 coverage, so text is always index 3 and themes recolour
; it through the palette entry. Setting a theme repaints nothing --
; palette entries change on screen instantly; role changes show on the
; next redraw, which is the app's business.
; =====================================================================

; the live theme, defaults matching gfx2_init's own palette
cx_theme
th_pal    .byte $FF, $0F        ; 0: white -- the paper
          .byte $AA, $0A        ; 1: light gray -- the highlight
          .byte $55, $05        ; 2: dark gray
          .byte $00, $00        ; 3: black -- ink and frames
th_paper  .byte 0
th_hi     .byte 1
th_frame  .byte 3
          .byte 0               ; reserved

; the slot's resident stub
cx_do_theme_set
    jsr cxb_call
    .byte 2
    .addr $A000 + 4*3

.segment "B2CODE"

; ---------------------------------------------------------------------
; th_set -- A/X = a 12-byte theme record in the app's memory. Copied
; into the resident block, and the palette programmed while the beam
; watches: the colours change NOW, everywhere, which is the whole show.
; ---------------------------------------------------------------------
th_set
    sta CX_M_PTR
    stx CX_M_PTR+1
    ldy #11
@copy
    lda (CX_M_PTR),y
    sta cx_theme,y
    dey
    bpl @copy

    vera_addrsel 0
    lda #<VRAM_PALETTE
    sta VERA_ADDR_L
    lda #>VRAM_PALETTE
    sta VERA_ADDR_M
    lda #^VRAM_PALETTE          ; bit 16 low, increment in the HIGH
    ora #(VERA_INC_1 << 4)      ; nibble -- raw VERA_INC_1 sets none, so
    sta VERA_ADDR_H             ; all eight writes would hit $1FA00
    ldy #0
@pal
    lda th_pal,y
    sta VERA_DATA0
    iny
    cpy #8
    bne @pal
    rts

.segment "CODE"
