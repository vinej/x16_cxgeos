; ca65
; =====================================================================
; CXRF :: kernel/video/engine1.asm -- mode 1: 320x240 @ 8bpp (256c)
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

X16_BITMAP_MIN = 1              ; no 8x8 glyph blitter: text is the CXF
                               ; proportional font, rendered by ov1_ctext

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
    jmp ov1_text                ; text: the CXF proportional font
    jmp ov1_measure             ; measure: the CXF advance widths
    jmp ov1_rsave               ; rsave/rrest: 8bpp framebuffer rows <->
    jmp ov1_rrest               ; a VRAM strip (fx_copy), the toolkit's
                                ; save-under in mode 1
    .byte 1                     ; cxov_ink -- the text ink, a palette
                                ; index; each entry resets it to white
    ; UI metrics in pixels: the menu's are the mode-0 values (the 8x8
    ; font fits a 12px bar, a 10px row), but the dialog box is sized to
    ; the 320x240 screen -- 280 wide, not 400
    .byte 12, 10,  8, 16,  2,  4,  8,  4,  1
    .word 280
    .byte 80, 72, 16, 80, 12, 30               ; dgh dgbw dgbh dgbsp dgpad dgfldy

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
ov1_no                          ; an entry this engine does not offer yet
    sec                         ; (the 8bpp save-under)
    rts

; the text entry: A/X = string, P0/P1 = x, P2/P3 = y. Draws the system
; CXF proportional font -- the desktop's font -- into the 8bpp
; framebuffer, so mode 1 reads like mode 0 rather than the blocky charset.
ov1_text
    jsr ov1_ctext
    clc
    rts

; measure -- the CXF's proportional widths (font_measure is mode-neutral;
; it just sums advances, and restores the caller's bank)
ov1_measure
    jmp font_measure

; ov1_ctext -- A/X = string, P0/P1 = pen x, P2 = y. Renders the parsed
; system font (f_*, set at boot) glyph by glyph into VRAM $00000 (8bpp,
; 320 bytes a row). Transparent: only set pixels take the ink, so text
; lands over whatever paper is there. The pen advances in P0/P1. The
; glyph bitmaps live in the font's bank, so RAM_BANK is saved and put
; back for the toolkit caller.
ov1_ctext
    sta X16_TPTR0               ; the string, in a zp pointer
    stx X16_TPTR0+1
    lda RAM_BANK
    sta ov1_obank
    stz ov1_ci
@nextchar
    ldy ov1_ci
    lda (X16_TPTR0),y           ; low RAM: readable under any bank
    bne @have
    lda ov1_obank               ; end: the caller's bank back
    sta RAM_BANK
    rts
@have
    sta ov1_ch
    sec
    sbc f_first
    bcs @gefirst
    jmp @advance                ; below the font's first codepoint
@gefirst
    cmp f_count
    bcc @infont
    jmp @advance                ; above the last: no glyph, just space
@infont
    tax                         ; i = ch - first; ptr = f_bmp + i*f_height
    lda f_bmp
    sta X16_TPTR3
    lda f_bmp+1
    sta X16_TPTR3+1
    cpx #0
    beq @gpok
@gpadd
    clc
    lda X16_TPTR3
    adc f_height
    sta X16_TPTR3
    bcc @gpnc
    inc X16_TPTR3+1
@gpnc
    dex
    bne @gpadd
@gpok
    jsr ov1_vbase               ; ov1_va = y*320 + x (the glyph's top-left)
    ldx f_bank
    stx RAM_BANK                ; the bitmaps live with the font
    lda f_height
    sta ov1_rows
    ldy #0                      ; row within the glyph
@row
    lda ov1_va                  ; point VERA port 0 at the row, inc 1
    sta VERA_ADDR_L
    lda ov1_va+1
    sta VERA_ADDR_M
    lda ov1_va+2
    ora #(VERA_INC_1 << 4)
    sta VERA_ADDR_H
    lda (X16_TPTR3),y           ; the 1bpp row, MSB = leftmost
    sta ov1_bits
    ldx #8
@bit
    asl ov1_bits
    bcc @off
    lda cxov_ink
    sta VERA_DATA0              ; a set pixel takes the ink
    bra @bnext
@off
    lda VERA_DATA0              ; transparent: just step the address on
@bnext
    dex
    bne @bit
    clc                         ; next row is 320 bytes down
    lda ov1_va
    adc #<320
    sta ov1_va
    lda ov1_va+1
    adc #>320
    sta ov1_va+1
    lda ov1_va+2
    adc #0
    sta ov1_va+2
    iny
    dec ov1_rows
    bne @row
@advance
    lda ov1_ch                  ; the pen moves by the glyph's advance
    jsr f_advance
    clc
    adc X16_P0
    sta X16_P0
    bcc @anc
    inc X16_P1
@anc
    inc ov1_ci
    jmp @nextchar

; ov1_vbase -- ov1_va (17-bit VRAM) = P2(y)*320 + P0/P1(x)
ov1_vbase
    lda X16_P2                  ; y*64
    stz ov1_va+1
    asl
    rol ov1_va+1
    asl
    rol ov1_va+1
    asl
    rol ov1_va+1
    asl
    rol ov1_va+1
    asl
    rol ov1_va+1
    asl
    rol ov1_va+1
    sta ov1_va
    lda ov1_va+1                ; + y*256 (add y into the middle byte)
    clc
    adc X16_P2
    sta ov1_va+1
    lda #0
    adc #0
    sta ov1_va+2
    clc                         ; + x
    lda ov1_va
    adc X16_P0
    sta ov1_va
    lda ov1_va+1
    adc X16_P1
    sta ov1_va+1
    lda ov1_va+2
    adc #0
    sta ov1_va+2
    rts

ov1_ci    .byte 0
ov1_ch    .byte 0
ov1_rows  .byte 0
ov1_bits  .byte 0
ov1_obank .byte 0
ov1_va    .res 3, 0

; ov1_rsave / ov1_rrest -- the toolkit's save-under in mode 1. P0/P1 =
; first row, P2 = row count. The 8bpp framebuffer is at VRAM $00000,
; 320 bytes a row; fx_copy moves the covered rows to a strip in the free
; VRAM above the picture ($13100, past the mouse sprite) and back --
; VRAM-to-VRAM, no bank consumed. Row and count are small (a dropdown or
; a dialog), so row*320 and count*320 stay within 16 bits.
M1_STRIP = $13100
ov1_rsave
    ldx #1                      ; framebuffer -> strip
    bra ov1_su
ov1_rrest
    ldx #0                      ; strip -> framebuffer
ov1_su
    stx ov1_sdir
    lda X16_P0                  ; the framebuffer offset = first_row * 320
    jsr ov1_mul320
    lda ov1_r
    sta ov1_off
    lda ov1_r+1
    sta ov1_off+1
    lda X16_P2                  ; the byte count = count * 320
    jsr ov1_mul320
    lda ov1_r
    sta X16_P6
    lda ov1_r+1
    sta X16_P7
    lda ov1_sdir
    beq @rest
    lda ov1_off                 ; save: fb[off] -> strip
    sta X16_P0
    lda ov1_off+1
    sta X16_P1
    stz X16_P2
    lda #<M1_STRIP
    sta X16_P3
    lda #>M1_STRIP
    sta X16_P4
    lda #^M1_STRIP
    sta X16_P5
    jmp fx_copy
@rest
    lda #<M1_STRIP              ; restore: strip -> fb[off]
    sta X16_P0
    lda #>M1_STRIP
    sta X16_P1
    lda #^M1_STRIP
    sta X16_P2
    lda ov1_off
    sta X16_P3
    lda ov1_off+1
    sta X16_P4
    stz X16_P5
    jmp fx_copy

ov1_mul320                      ; A = k -> ov1_r (word) = k * 320
    sta ov1_t                   ; k*320 = k*256 + k*64
    stz ov1_r+1
    asl
    rol ov1_r+1
    asl
    rol ov1_r+1
    asl
    rol ov1_r+1
    asl
    rol ov1_r+1
    asl
    rol ov1_r+1
    asl
    rol ov1_r+1                 ; ov1_r+1:A = k*64
    sta ov1_r
    lda ov1_t                   ; + k*256 (k into the high byte)
    clc
    adc ov1_r+1
    sta ov1_r+1
    rts
ov1_sdir .byte 0
ov1_t    .byte 0
ov1_r    .word 0
ov1_off  .word 0

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
