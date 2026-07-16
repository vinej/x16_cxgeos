; ca65
; =====================================================================
; CXGEOS :: kernel/font/font.asm -- the font engine
; =====================================================================
; Proportional text on the 640x480 2bpp screen, at gfx2_blitm's speed.
;
; A CXF (docs/formats.md) stores each glyph as 1bpp rows, 8 pixels wide,
; with a per-glyph advance that is usually narrower. Drawing that
; directly would mean expanding and shifting every glyph on every draw.
; font_cache does it once instead: every glyph becomes 2bpp, pre-shifted
; to all four pixel phases, in exactly the (mask, data) pair layout
; gfx2_blitm consumes -- so drawing a glyph is a blit and nothing else.
;
; The cache lives in banked RAM, not VRAM: blitm reads its source with
; (X16_PTR3),y -- CPU RAM. See docs/memory-map.md.
;
;   one glyph   4 phases x 3 columns x 8 rows x 2 bytes = 192 bytes
;   one bank    42 glyphs (8,064 of 8,192), so none straddles a bank
;   glyph i     bank CX_F_BANK0 + i/42, at $A000 + (i%42)*192
;   phase p     + p*48; column c + c*16; row r + r*2 (mask, then data)
;
; `data` is the ink for colour 3, which is $FF in all four pixels -- so
; data is just the glyph's coverage and mask is its complement. Text is
; drawn in colour 3; a theme recolours palette entry 3 rather than the
; pixels, and a selection inverts its region with an XOR blit, which on
; a 2bpp screen swaps 0<->3 and 1<->2. Neither needs a second cache.
;
;   font_set     in:  A/X = CXF image (low RAM)
;                out: carry set if the magic is wrong
;                Reads the header and builds the cache.
;   font_measure in:  A/X = NUL-terminated string
;                out: X16_P0/P1 = width in pixels
;   font_draw    in:  X16_P0/P1 = x, X16_P2/P3 = y, A/X = string
;                out: X16_P0/P1 = the pen, one past the last glyph
;                No clipping: the caller keeps the string on screen.
;
; Both walk the string with an 8-bit index, so a string is 255 chars.
; =====================================================================

CX_F_BANK0    = 6               ; the cache's first RAM bank
CX_F_PERBANK  = 42              ; glyphs per bank
CX_F_WIN      = $A000           ; the banked window

; CXF header offsets
CXF_HEIGHT    = 4
CXF_ASCENT    = 5
CXF_FIRST     = 6
CXF_COUNT     = 7
CXF_MAXWIDTH  = 8
CXF_SPACING   = 9
CXF_WIDTHS    = 16

; ---------------------------------------------------------------------
; font_set -- adopt a CXF and build its cache.
; ---------------------------------------------------------------------
font_set
    sta CX_F_CXF
    stx CX_F_CXF+1

    ldy #3                      ; magic "CXF1"
@magic
    lda (CX_F_CXF),y
    cmp f_magic,y
    bne @bad
    dey
    bpl @magic

    ldy #CXF_HEIGHT             ; park the header: read once, used often
    lda (CX_F_CXF),y
    sta f_height
    ldy #CXF_ASCENT
    lda (CX_F_CXF),y
    sta f_ascent
    ldy #CXF_FIRST
    lda (CX_F_CXF),y
    sta f_first
    ldy #CXF_COUNT
    lda (CX_F_CXF),y
    sta f_count
    ldy #CXF_SPACING
    lda (CX_F_CXF),y
    sta f_spacing

    ; The bitmaps follow the header and the widths table. Both tables are
    ; reached with (CX_F_CXF),y -- 16 + 94 still fits an 8-bit index --
    ; so only the bitmaps need a pointer of their own.
    clc
    lda CX_F_CXF
    adc #CXF_WIDTHS
    sta f_bmp
    lda CX_F_CXF+1
    adc #0
    sta f_bmp+1
    clc
    lda f_bmp
    adc f_count
    sta f_bmp
    lda f_bmp+1
    adc #0
    sta f_bmp+1

    jsr font_cache
    clc
    rts
@bad
    sec
    rts

f_magic .byte "CXF1"

; ---------------------------------------------------------------------
; font_cache -- expand every glyph to 2bpp, pre-shifted to 4 phases.
;
; Paid once per font: 8 rows x 4 phases x 8 bit-tests per glyph, so a
; 95-glyph font is ~24k tests -- a few frames at boot, and nothing at
; draw time. CX_F_ROWP walks the bitmaps a glyph at a time, which keeps
; a gi*height multiply out of the loop.
; ---------------------------------------------------------------------
font_cache
    lda RAM_BANK                ; the caller's bank comes back at the end
    pha

    lda f_bmp                   ; glyph 0's rows
    sta CX_F_ROWP
    lda f_bmp+1
    sta CX_F_ROWP+1
    stz f_gi

@glyph
    jsr f_slot_addr             ; RAM_BANK + CX_F_SRC = this glyph's slot

    stz f_phase
@phase
    stz f_row
@row
    jsr f_row_cov               ; f_cov = the row's three coverage bytes
    jsr f_store_row
    inc f_row
    lda f_row
    cmp f_height
    bne @row

    ; Rows past f_height are left alone: blitm is told the height, so it
    ; never reads them.
    inc f_phase
    lda f_phase
    cmp #4
    bne @phase

    clc                         ; next glyph's rows
    lda CX_F_ROWP
    adc f_height
    sta CX_F_ROWP
    bcc @nc
    inc CX_F_ROWP+1
@nc
    inc f_gi
    lda f_gi
    cmp f_count
    bne @glyph

    pla
    sta RAM_BANK
    rts

; ---------------------------------------------------------------------
; f_slot_addr -- RAM_BANK + CX_F_SRC for glyph f_gi.
;
; bank = CX_F_BANK0 + gi/42, offset = (gi%42)*192. The divide is a
; subtract loop -- three iterations at most, twice per font build.
; The multiply is (n*3)<<6: n is under 42, so n*3 stays inside a byte
; and the whole thing is an add and six shifts.
; ---------------------------------------------------------------------
f_slot_addr
    lda f_gi
    ldx #CX_F_BANK0
@div
    cmp #CX_F_PERBANK
    bcc @got
    sec
    sbc #CX_F_PERBANK
    inx
    bra @div
@got
    stx RAM_BANK                ; A = gi % 42

    sta CX_F_T0                 ; n*3, at most 123
    asl
    clc
    adc CX_F_T0
    sta CX_F_SRC                ; low half of the 16-bit shift
    stz CX_F_SRC+1
    .repeat 6                   ; << 6  ->  n*192
    asl CX_F_SRC
    rol CX_F_SRC+1
    .endrepeat

    lda CX_F_SRC+1              ; + the window base
    ora #>CX_F_WIN
    sta CX_F_SRC+1
    rts

; ---------------------------------------------------------------------
; f_row_cov -- f_cov[0..2] = row f_row of glyph f_gi, expanded to 2bpp
; and shifted to phase f_phase.
;
; Source pixel c lands at screen pixel k = phase + c, which is bits
; 6-2*(k&3) of cache byte k>>2 -- so a set bit is one table lookup and
; an ORA, and the 24-bit shift the naive version would need never
; happens.
; ---------------------------------------------------------------------
f_row_cov
    stz f_cov
    stz f_cov+1
    stz f_cov+2

    ldy f_row
    lda (CX_F_ROWP),y
    beq @done                   ; a blank row: nothing to light
    sta f_bits

    stz f_c
@bit
    asl f_bits                  ; leftmost pixel first
    bcc @next
    lda f_c
    clc
    adc f_phase
    tay                         ; k = phase + c, 0..10
    lda f_kbits,y
    ldx f_kbyte,y
    ora f_cov,x
    sta f_cov,x
@next
    inc f_c
    lda f_c
    cmp #8
    bne @bit
@done
    rts

; ---------------------------------------------------------------------
; f_store_row -- write f_cov into the slot as (mask, data) pairs.
;
; offset = phase*48 + col*16 + row*2, at most 144+32+30 = 206, so the
; whole index fits in Y and the slot pointer never moves.
; ---------------------------------------------------------------------
f_store_row
    ldx f_phase
    lda f_poff,x
    sta CX_F_T0
    lda f_row
    asl
    clc
    adc CX_F_T0
    tay                         ; column 0's mask

    ldx #0
@col
    lda f_cov,x
    eor #$FF
    sta (CX_F_SRC),y            ; mask: the pixels to keep
    iny
    lda f_cov,x
    sta (CX_F_SRC),y            ; data: colour 3's ink = the coverage
    tya
    clc
    adc #15                     ; the next column, 16 on from the mask
    tay
    inx
    cpx #3
    bne @col
    rts

; ---------------------------------------------------------------------
; f_advance -- A = character; out: A = its advance, or 0 if the font has
; no such glyph. Preserves nothing.
; ---------------------------------------------------------------------
f_advance
    sec
    sbc f_first
    bcc @none                   ; below the font's first codepoint
    cmp f_count
    bcs @none
    clc                         ; widths[i] at CXF + 16 + i
    adc #CXF_WIDTHS
    tay
    lda (CX_F_CXF),y
    clc
    adc f_spacing
    rts
@none
    lda #0
    rts

; ---------------------------------------------------------------------
; font_measure -- the width a string will draw to.
; ---------------------------------------------------------------------
font_measure
    sta CX_F_STR
    stx CX_F_STR+1
    stz X16_P0
    stz X16_P1
    stz f_idx
@loop
    ldy f_idx
    lda (CX_F_STR),y
    beq @done
    jsr f_advance
    clc
    adc X16_P0
    sta X16_P0
    bcc @nc
    inc X16_P1
@nc
    inc f_idx
    bne @loop                   ; 255 characters is the string limit
@done
    rts

; ---------------------------------------------------------------------
; font_draw -- a string at (x, y), colour 3.
; ---------------------------------------------------------------------
font_draw
    sta CX_F_STR
    stx CX_F_STR+1
    lda X16_P0
    sta CX_F_PEN
    lda X16_P1
    sta CX_F_PEN+1
    lda X16_P2
    sta CX_F_Y
    lda X16_P3
    sta CX_F_Y+1

    lda RAM_BANK
    pha
    stz f_idx

@loop
    ldy f_idx
    lda (CX_F_STR),y
    beq @done
    sta f_ch

    sec                         ; is it in the font?
    sbc f_first
    bcc @advance
    cmp f_count
    bcs @advance
    sta f_gi

    jsr f_slot_addr             ; RAM_BANK + CX_F_SRC = the slot
    lda CX_F_PEN                ; + the phase this pen lands on
    and #3
    sta f_phase
    tax
    lda f_poff,x
    clc
    adc CX_F_SRC
    sta CX_F_SRC
    bcc @nc
    inc CX_F_SRC+1
@nc

    lda CX_F_PEN                ; blitm consumes P0..P7, so they are
    sta X16_P0                  ; rebuilt for every glyph
    lda CX_F_PEN+1
    sta X16_P1
    lda CX_F_Y
    sta X16_P2
    lda CX_F_Y+1
    sta X16_P3
    lda f_height
    sta X16_P4
    jsr f_columns               ; only the columns this glyph reaches
    sta X16_P5
    lda CX_F_SRC
    sta X16_P6
    lda CX_F_SRC+1
    sta X16_P7
    jsr gfx2_blitm

@advance
    lda f_ch
    jsr f_advance
    clc
    adc CX_F_PEN
    sta CX_F_PEN
    bcc @pnc
    inc CX_F_PEN+1
@pnc
    inc f_idx
    bne @loop

@done
    pla
    sta RAM_BANK
    lda CX_F_PEN                ; hand the pen back
    sta X16_P0
    lda CX_F_PEN+1
    sta X16_P1
    rts

; ---------------------------------------------------------------------
; f_columns -- how many byte columns glyph f_gi covers at f_phase:
; ceil((phase + width) / 4). A 2-pixel glyph at phase 0 touches one
; column, not three, and the blit is a third of the work.
; ---------------------------------------------------------------------
f_columns
    lda f_gi
    clc
    adc #CXF_WIDTHS
    tay
    lda (CX_F_CXF),y            ; the glyph's ink width
    clc
    adc f_phase
    adc #3
    lsr
    lsr
    beq @one                    ; a zero-width glyph still blits nothing
    rts
@one
    lda #1
    rts

; ---------------------------------------------------------------------
; module variables
; ---------------------------------------------------------------------
f_height  .byte 0
f_ascent  .byte 0
f_first   .byte 0
f_count   .byte 0
f_spacing .byte 0
f_bmp     .word 0               ; the glyph bitmaps

f_gi      .byte 0               ; the glyph being cached / drawn
f_phase   .byte 0
f_row     .byte 0
f_c       .byte 0
f_bits    .byte 0
f_cov     .res 3, 0
f_idx     .byte 0               ; the string index
f_ch      .byte 0

; k = phase + c, 0..10. The two bits pixel k occupies, and which of the
; three cache bytes they live in.
f_kbits   .byte $C0, $30, $0C, $03, $C0, $30, $0C, $03, $C0, $30, $0C
f_kbyte   .byte   0,   0,   0,   0,   1,   1,   1,   1,   2,   2,   2

f_poff    .byte 0, 48, 96, 144  ; phase p starts at p*48
