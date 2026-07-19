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
;   font_style   in:  A = FONT_BOLD | FONT_UNDER (0 = plain)
;                Sticky until changed.
;   font_measure in:  A/X = NUL-terminated string
;                out: X16_P0/P1 = width in pixels
;   font_draw    in:  X16_P0/P1 = x, X16_P2/P3 = y, A/X = string
;                out: X16_P0/P1 = the pen, one past the last glyph
;                No clipping: the caller keeps the string on screen.
;
; Both walk the string with an 8-bit index, so a string is 255 chars.
;
; Text is drawn transparently: only the ink lands, and whatever was
; under the glyph shows through. To erase what was there, fill the box
; first -- font_measure gives the width, f_height the height, and
; gfx2_rect does it in one call. The engine does not do that for you
; because a per-glyph opaque fill costs more than one rect for the line.
;
; STYLES. Bold is a double strike: the glyph is blitted again one pixel
; right, which the masked blit ORs into the first. That widens every
; glyph by one, so the advance grows too -- and it grows inside
; f_advance, which is the single place both font_measure and font_draw
; ask. Anywhere else and the two would disagree the moment bold was set,
; which is exactly the bug FONT_PEN exists to catch.
;
; Underline is one hline under the whole string, drawn once at the end
; rather than per glyph, so it runs unbroken through the spaces. It sits
; at y + height -- one row below the cell, inside the line's leading, so
; it clears the descenders. A line box needs height + 1 rows for it.
; =====================================================================

FONT_BOLD   = $01
FONT_UNDER  = $02

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
; font_set -- adopt a CXF and build its cache. RESIDENT FRONT-END.
;
; The CXF must be addressable at the given pointer under the RAM_BANK
; that is live on entry -- that bank is captured HERE, before the far
; call flips it, and every later read of the font (widths at draw time,
; rows while caching) switches back to it. A font in low RAM works under
; any bank; a font in banked RAM must sit entirely inside the $A000
; window, which holds it to 8 KB. The kernel's own font arrives in bank
; CX_SYSFONT_BANK, put there by the boot loader.
;
; The cold half -- magic, header, cache build -- rides bank 18 (fs_parse
; below), reached only when a font is adopted, which is boot and the
; rare cx_font_set. It reads the CXF through the resident f_peek helpers
; so it never has to page the font's bank in from its own window. The
; public label stays `font_set`, so impl.inc, font_sys and the ABI are
; unchanged.
; ---------------------------------------------------------------------
font_set
    sta CX_F_CXF
    stx CX_F_CXF+1
    lda RAM_BANK                ; where the font lives, captured BEFORE the
    sta f_bank                  ; far call flips RAM_BANK to bank 18
    lda #1                      ; the loader restores the system font on the
    sta f_dirty                 ; next launch, so this one does not leak
.ifndef CX_NO_OVERLAY
    jsr cxb_call                ; carry (bad magic) survives cxb_call
    .byte CX_FS_BANK
    .addr fs_parse
.else
    jsr fs_parse                ; the flat runner links it in CODE
.endif
    rts

; ---------------------------------------------------------------------
; f_peek -- A = CXF byte Y, read under the font's bank and the caller's
; RAM_BANK put back. RESIDENT, so the bank-18 cold half can read a font
; that lives in a bank (the system font is in bank 1) without paging
; that bank in from its own execution window. (Callable from bank 18
; because resident code executes from always-mapped low RAM.)
; ---------------------------------------------------------------------
f_peek
    lda RAM_BANK
    pha
    lda f_bank
    sta RAM_BANK
    lda (CX_F_CXF),y
    tax
    pla
    sta RAM_BANK
    txa
    rts

; f_peek_row -- A = bitmap byte Y (of the glyph row pointer), same deal.
f_peek_row
    lda RAM_BANK
    pha
    lda f_bank
    sta RAM_BANK
    lda (CX_F_ROWP),y
    tax
    pla
    sta RAM_BANK
    txa
    rts

; ---------------------------------------------------------------------
; f_slot_addr -- RAM_BANK + CX_F_SRC for glyph f_gi. The HOT entry
; (f_blit_at): compute the slot and leave RAM_BANK on its cache bank.
; ---------------------------------------------------------------------
f_slot_addr
    jsr f_slot_calc
    ldx f_cbank
    stx RAM_BANK
    rts

; f_slot_calc -- the pure computation: f_cbank + CX_F_SRC for glyph
; f_gi, with NO RAM_BANK write, so the bank-18 cache builder can call it
; and stay in its own window. bank = CX_F_BANK0 + gi/42 (a subtract
; loop, three at most), offset = (gi%42)*192 = (n*3)<<6.
f_slot_calc
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
    stx f_cbank                 ; A = gi % 42; the cache bank, remembered

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
; f_store_row -- write f_cov into the slot as (mask, data) pairs.
; RESIDENT, and it switches to the cache bank itself (restoring the
; caller's) so the bank-18 builder can call it without leaving its own
; window. offset = phase*48 + col*16 + row*2 fits Y.
; ---------------------------------------------------------------------
f_store_row
    lda RAM_BANK
    pha
    lda f_cbank                 ; the slot lives in the cache's bank
    sta RAM_BANK
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
    pla
    sta RAM_BANK                ; the builder's bank (18) back
    rts

; ---------------------------------------------------------------------
; font_style -- A = FONT_BOLD | FONT_UNDER, or 0 for plain.
; ---------------------------------------------------------------------
font_style
    sta f_style
    rts

; ---------------------------------------------------------------------
; f_advance -- A = character; out: A = its advance, or 0 if the font has
; no such glyph. Preserves nothing.
;
; The ONLY place an advance is decided. font_measure and font_draw both
; come here, so bold's extra pixel cannot make them disagree.
; ---------------------------------------------------------------------
f_advance
    ldx f_bank                  ; the widths live with the font, whose
    stx RAM_BANK                ; bank the cache walk has moved off
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
    pha
    lda f_style                 ; bold strikes one pixel right, so every
    and #FONT_BOLD              ; glyph is a pixel wider
    beq @plain
    pla
    inc
    rts
@plain
    pla
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
    lda RAM_BANK                ; f_advance reads the font's bank, so the
    pha                         ; caller's comes back like font_draw's
    sta f_sbank                 ; ...and the string is read under it too
    stz X16_P0
    stz X16_P1
    stz f_idx
@loop
    lda f_sbank                 ; the string may live in a bank
    sta RAM_BANK
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
    pla
    sta RAM_BANK
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

    lda CX_F_PEN                ; where the underline will start
    sta f_ux
    lda CX_F_PEN+1
    sta f_ux+1

    lda RAM_BANK
    pha
    sta f_sbank                 ; the string is read under the caller's
    stz f_idx                   ; bank; drawing a glyph moves RAM_BANK off

@loop
    lda f_sbank                 ; back to the string's bank each char
    sta RAM_BANK
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

    lda CX_F_PEN
    sta f_bx
    lda CX_F_PEN+1
    sta f_bx+1
    jsr f_blit_at

    lda f_style                 ; bold: the same glyph again, one right.
    and #FONT_BOLD              ; The masked blit keeps what is already
    beq @advance                ; there, so the two strikes OR together.
    inc f_bx
    bne @bold
    inc f_bx+1
@bold
    jsr f_blit_at

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

    lda f_style
    and #FONT_UNDER
    beq @nounder

    lda f_ux                    ; one hline under the whole string, so it
    sta X16_P0                  ; runs unbroken through the spaces
    lda f_ux+1
    sta X16_P1
    clc                         ; y + height: below the cell, inside the
    lda CX_F_Y                  ; line's leading, clear of descenders
    adc f_height
    sta X16_P2
    lda CX_F_Y+1
    adc #0
    sta X16_P3
    sec                         ; length = pen - start
    lda CX_F_PEN
    sbc f_ux
    sta X16_P4
    lda CX_F_PEN+1
    sbc f_ux+1
    sta X16_P5
    lda #3
    jsr gfx2_hline
@nounder

    lda CX_F_PEN                ; hand the pen back
    sta X16_P0
    lda CX_F_PEN+1
    sta X16_P1
    rts

; ---------------------------------------------------------------------
; f_blit_at -- glyph f_gi at (f_bx, CX_F_Y). Picks the pre-shifted phase
; f_bx lands on and hands blitm the slot; RAM_BANK is left on the
; glyph's bank, which the caller restores once for the whole string.
; ---------------------------------------------------------------------
f_blit_at
    jsr f_slot_addr             ; RAM_BANK + CX_F_SRC = the slot
    lda f_bx                    ; + the phase this x lands on
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
    lda f_bx                    ; blitm consumes P0..P7, so they are
    sta X16_P0                  ; rebuilt for every strike
    lda f_bx+1
    sta X16_P1
    lda CX_F_Y
    sta X16_P2
    lda CX_F_Y+1
    sta X16_P3
    lda f_height
    sta X16_P4
    jsr f_columns               ; only the columns this glyph reaches
    sta X16_P5
    ldx f_cbank                 ; f_columns read the font's bank; the
    stx RAM_BANK                ; slot blitm reads is in the cache's
    lda CX_F_SRC
    sta X16_P6
    lda CX_F_SRC+1
    sta X16_P7
    jmp gfx2_blitm

; ---------------------------------------------------------------------
; f_columns -- how many byte columns glyph f_gi covers at f_phase:
; ceil((phase + width) / 4). A 2-pixel glyph at phase 0 touches one
; column, not three, and the blit is a third of the work.
; ---------------------------------------------------------------------
f_columns
    ldx f_bank                  ; the width is the font's; the caller
    stx RAM_BANK                ; puts the cache bank back for the blit
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

f_style   .byte 0               ; FONT_BOLD | FONT_UNDER

f_bank    .byte 0               ; where the CXF lives, from font_set
f_dirty   .byte 0               ; an app changed the font -> loader resets it
f_cbank   .byte 0               ; the cache bank of the glyph in hand
f_sbank   .byte 0               ; the bank the STRING is read under (the
                                ; caller's) -- restored before every char,
                                ; since drawing a glyph leaves RAM_BANK on
                                ; the font/cache bank. Lets a caller pass a
                                ; string in a bank (dialog labels in bank 2)

f_gi      .byte 0               ; the glyph being cached / drawn
f_phase   .byte 0
f_row     .byte 0
f_c       .byte 0
f_bits    .byte 0
f_cov     .res 3, 0
f_idx     .byte 0               ; the string index
f_ch      .byte 0
f_bx      .word 0               ; where a strike lands (bold moves it)
f_ux      .word 0               ; where the underline starts

; k = phase + c, 0..10. The two bits pixel k occupies, and which of the
; three cache bytes they live in.
f_kbits   .byte $C0, $30, $0C, $03, $C0, $30, $0C, $03, $C0, $30, $0C
f_kbyte   .byte   0,   0,   0,   0,   1,   1,   1,   1,   2,   2,   2

f_poff    .byte 0, 48, 96, 144  ; phase p starts at p*48

; =====================================================================
; the cold half -- bank 18 (the fs/system theme bank, banks.inc)
; =====================================================================
; Adopting a font is boot and the rare cx_font_set; drawing with it is
; every character. So the magic check, the header parse and the cache
; build live out here, far-called once, and the resident image keeps
; only the draw path. None of this code writes RAM_BANK: it reads the
; CXF through f_peek/f_peek_row and writes the cache through f_store_row,
; all resident helpers that page the right bank in and put ours back --
; because bank-18 code cannot page a bank into the window it is running
; from. The flat runner links the block in CODE and calls it directly.
; ---------------------------------------------------------------------
.ifndef CX_NO_OVERLAY
.segment "B18CODE"
.endif

; fs_parse -- the CXF's magic and header, then the cache. Carry set if
; the magic is wrong (font_set hands it back through cxb_call).
fs_parse
    ldy #3                      ; magic "CXF1", read under the font's bank
@magic
    jsr f_peek
    cmp f_magic,y
    bne @bad
    dey
    bpl @magic

    ldy #CXF_HEIGHT             ; park the header: read once, used often
    jsr f_peek
    sta f_height
    ldy #CXF_ASCENT
    jsr f_peek
    sta f_ascent
    ldy #CXF_FIRST
    jsr f_peek
    sta f_first
    ldy #CXF_COUNT
    jsr f_peek
    sta f_count
    ldy #CXF_SPACING
    jsr f_peek
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

    lda cx_vmode                ; the pre-shifted 2bpp cache is mode 0's;
    bne @nocache                ; the bitmap modes read the glyphs raw
    jsr font_cache              ; (mode 1's ov1_ctext) or ignore them (2/3),
@nocache                        ; and a non-8px cache would corrupt mode 0's
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
; a gi*height multiply out of the loop. It never touches RAM_BANK: the
; row reads go through f_peek_row, the slot writes through f_store_row,
; and f_slot_calc computes the slot without paging -- so the loop stays
; in bank 18 the whole way.
; ---------------------------------------------------------------------
font_cache
    lda f_bmp                   ; glyph 0's rows
    sta CX_F_ROWP
    lda f_bmp+1
    sta CX_F_ROWP+1
    stz f_gi

@glyph
    jsr f_slot_calc             ; f_cbank + CX_F_SRC = this glyph's slot

    stz f_phase
@phase
    stz f_row
@row
    jsr f_row_cov               ; f_cov = the row's three coverage bytes
    jsr f_store_row             ; ...into the slot (it pages the cache bank)
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
    rts

; ---------------------------------------------------------------------
; f_row_cov -- f_cov[0..2] = row f_row of glyph f_gi, expanded to 2bpp
; and shifted to phase f_phase.
;
; The row byte comes through f_peek_row (the font's bank, ours put
; back); the rest is pure computation on resident tables, so this runs
; in bank 18 without a single RAM_BANK write. Source pixel c lands at
; screen pixel k = phase + c, bits 6-2*(k&3) of cache byte k>>2.
; ---------------------------------------------------------------------
f_row_cov
    stz f_cov
    stz f_cov+1
    stz f_cov+2

    ldy f_row
    jsr f_peek_row
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

.ifndef CX_NO_OVERLAY
.segment "CODE"
.endif
