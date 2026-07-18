; ca65
; =====================================================================
; CXGEOS :: kernel/video/engine1.asm -- mode 1: 320x240 @ 8bpp (256c)
; =====================================================================
; The second engine image behind the graphics port: the fixed vector,
; thin argument adapters, and x16lib's 8bpp bitmap module, compiled to
; RUN at the overlay but STORED in bank 4 (OV1CODE). cx_gfx_mode(1)
; copies it in and runs its init.
;
; The adapters exist because the ABI and the module disagree about
; registers: the ABI says colour in A and 16-bit y; bitmap.asm wants
; colour in P3 and a byte y (240 rows fit one). y's high byte is
; ignored -- at 320x240 it is zero for every on-screen point.
;
; The full thirteen entries are real since the library's two-way parity
; pass: pattern/blit are the 8bpp natives (bg/fg as full bytes in P4/P5,
; blit widths in pixels, blitm's $00 a colour key). Text stays the
; toolkit's, and the toolkit is mode-0-only by contract.
;
; bitmap.asm's extras (circle, disc, flood, charset text) are gated out
; (X16_BITMAP_MIN): unreachable through today's 13 entries, and they
; would not fit the port region. The slots that expose them one day can
; grow the region then.
; =====================================================================

.ifndef CX_NO_OVERLAY

.segment "OV1CODE"

ov1_vector                      ; the port's entry vector, slot order
    jmp ov1_init
    jmp gfx_clear               ; A = colour: the module's own shape
    jmp ov1_pset
    jmp gfx_read                ; the module's own read (no clip here)
    jmp ov1_hline
    jmp ov1_vline
    jmp ov1_rect
    jmp ov1_frame
    jmp ov1_line
    jmp gfx_pattern_set         ; pattern: mode 1 takes bg/fg in P4/P5
    jmp gfx_pattern_rect        ; (full 0-255; Y's packed pair only
    jmp gfx_blit                ; holds 2-bit colours). blit width is in
    jmp gfx_blitm               ; PIXELS; blitm's $00 is transparent
    jmp ov1_text                ; text: 8x8 charset glyphs from $1F000
    jmp ov1_measure             ; measure: 8 pixels per glyph
    .byte 1                     ; cxov_ink -- the text ink, a palette
                                ; index; each entry resets it to white

.assert ov1_vector = CX_OVL, error, "OV1CODE must start at CX_OVL -- kernel.cfg and ovl.inc disagree"

; --- init: program VERA for 320x240 bitmap, 8bpp, layer 0 -------------
; The module's own gfx_init goes through the KERNAL screen editor; the
; port programs VERA directly, exactly as gfx2_init does for mode 0.
;
; The CHARSET first: mode 1's text draws 8x8 glyphs from VRAM $1F000 in
; SCREEN-CODE order, but what sits there depends on history -- ISO after
; boot (ASCII-indexed: mode-1 text would render garbage), PETSCII only
; if mode 3 ran. So entry normalizes it exactly the way mode 3 does --
; CINT then the CHR$(14) switch, the proven pair -- and THEN programs
; VERA for the bitmap (undoing the text display CINT set up). A custom
; charset is a per-entry upload: cx_vram_write 2KB to $1F000 AFTER
; cx_mode, same contract as mode 3. Safe here for the same reason as
; mode 3: this engine runs in the overlay (low RAM, always mapped), so
; the bank-unsafe KERNAL screen calls cannot corrupt banked code.
ov1_init
    php
    sei
    jsr screen_reset            ; CINT: the ROM charset lands at $1F000
    lda #$0E                    ; CHR$(14): the PETSCII upper/lower set
    jsr screen_chrout           ; (screen-code order, like mode 3)
    plp

    vera_dcsel 0
    lda #$40                    ; 2:1 scale -> 320x240
    sta VERA_DC_HSCALE
    sta VERA_DC_VSCALE
    stz VERA_DC_BORDER

    lda #(VERA_LAYER_BITMAP | VERA_LAYER_BPP_8)
    sta VERA_L0_CONFIG
    stz VERA_L0_TILEBASE        ; bitmap base $00000, 320 wide
    stz VERA_L0_HSCROLL_L
    stz VERA_L0_HSCROLL_H       ; bits 3:0 = bitmap palette offset
    stz VERA_L0_VSCROLL_L
    stz VERA_L0_VSCROLL_H

    lda #VERA_VIDEO_LAYER1_EN   ; layer 1 off, layer 0 on
    trb VERA_DC_VIDEO
    lda #VERA_VIDEO_LAYER0_EN
    tsb VERA_DC_VIDEO
    rts

; --- the adapters -----------------------------------------------------
; the text entry: A/X = string, P0/P1 = x, P2/P3 = y. gfx_text draws 8x8
; charset glyphs (ASCII in, screen codes out) and wants the colour in P3
; -- which the port uses as y's high byte, dead at 240 rows -- so the
; ink (cxov_ink, cx_ink's byte in this image) overwrites it.
ov1_text
    sta ov1_ts                  ; the string survives the ink load
    stx ov1_ts+1
    lda cxov_ink
    sta X16_P3
    lda ov1_ts
    ldx ov1_ts+1
    jsr gfx_text                ; advances P0/P1 8 per glyph: the pen
    clc                         ; comes back for free
    rts
ov1_ts .word 0

; measure -- A/X = string -> P0/P1 = width in pixels (8 per glyph)
ov1_measure
    sta X16_TPTR0
    stx X16_TPTR0+1
    ldy #0
@len
    lda (X16_TPTR0),y
    beq @done
    iny
    bne @len
@done
    tya                         ; width = length * 8, 16-bit
    stz X16_P1
    asl
    rol X16_P1
    asl
    rol X16_P1
    asl
    rol X16_P1
    sta X16_P0
    clc
    rts

ov1_pset                        ; colour A -> P3 (y's dead high byte)
    sta X16_P3
    jmp gfx_pset
ov1_hline
    sta X16_P3
    jmp gfx_hline
ov1_vline
    sta X16_P3
    jmp gfx_vline
ov1_rect
    sta X16_P3
    jmp gfx_rect
ov1_frame
    sta X16_P3
    jmp gfx_frame

ov1_line                        ; ABI x1 P4/P5, y1 P6, colour A -> the
    pha                         ; module's x1 P3/P4, y1 P5, colour P6.
    lda X16_P4                  ; Each source is read before it is
    sta X16_P3                  ; overwritten, in this order and only
    lda X16_P5                  ; this order.
    sta X16_P4
    lda X16_P6
    sta X16_P5
    pla
    sta X16_P6
    jmp gfx_line

; gfx_init's `jmp screen_set_mode` resolves to the real KERNAL console
; now that X16_USE_SCREEN is on (mode 3 needs it too); the port never
; calls gfx_init anyway -- ov1_init programs VERA directly.
.include "gfx/bitmap.asm"

.segment "CODE"

.endif
