; ca65
; =====================================================================
; CXRF :: spikes/spike_b.asm -- Phase 0 risk spike B
; =====================================================================
; The project-critical number: how fast can we blit a proportional-font
; glyph into the 640x480@2bpp framebuffer at an ARBITRARY x position?
;
; Method (the plan for the real font engine):
;   - glyphs pre-shifted to all 4 pixel phases (x & 3), stored
;     column-major (3 columns of 8 rows) so each column is drawn with
;     one port aim and VERA_INC_160 walking down the rows
;   - masked (transparent) blit: read-modify-write through both data
;     ports -- DATA1 reads the framebuffer, DATA0 writes it back
;     fb' = (fb AND mask) OR glyph
;   - opaque blit on color-0 background: pure writes, no reads
;
; Benchmarks (8x8 glyph "A", 100 glyphs per line, x advancing 6 px so
; every phase is exercised):
;   MASK1600  1600 masked glyphs   (16 lines' worth)
;   OPAQ1600  1600 opaque glyphs
;
; Ends with a visible line of masked glyphs straddling two color bands:
; transparency and per-phase alignment proof.
;
;   .\build.ps1 -Source spikes\spike_b.asm -Capture
; =====================================================================

.include "x16.asm"

X16_USE_VERA    = 1
X16_USE_PALETTE = 1
X16_USE_NUMBER  = 1

FB_BASE     = $00000
FB_STRIDE   = 160
FB_HALF     = 38400

; the bench line sits at y=116: glyph rows 116-123 straddle the color
; band boundary at y=120, so transparency shows over two backgrounds
ROW_BASE    = 116 * FB_STRIDE

; spike-private zero page (CXRF app space $60-$7F)
STR_PTR     = $60
BENCH_T0    = $62
REP         = $64
GLY         = $66               ; -> glyph phase table
MSK         = $68               ; -> mask phase table
FBA         = $6A               ; framebuffer byte address (16-bit)
XCUR        = $6C               ; current x position (16-bit)
GCNT        = $6E               ; glyphs left on this line

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

; ---------------------------------------------------------------------
main
    jsr mode_2bpp_640
    jsr draw_bands

    lda #<sb_banner
    ldx #>sb_banner
    jsr print_str

    jsr timer_alive
    bcs @timer_ok
    lda #<sb_skip
    ldx #>sb_skip
    jsr print_str
    bra @done
@timer_ok

    jsr bench_masked
    lda #<sb_mask
    ldx #>sb_mask
    jsr print_str
    jsr print_elapsed

    jsr bench_opaque
    lda #<sb_opaq
    ldx #>sb_opaq
    jsr print_str
    jsr print_elapsed

@done
    jsr draw_bands              ; final visual: glyphs over the bands
    jsr glyph_line_masked
    jsr dump_fb                 ; hex dump of the glyph rows for host-
                                ; side pixel verification
    lda #<sb_done
    ldx #>sb_done
    jsr print_str
@forever
    bra @forever

; ---------------------------------------------------------------------
; dump_fb -- print the 8 glyph rows (first 40 bytes each, covers the
; first 8 glyphs = phases 0,1,2,3,0,1,2,3) as hex "D:..." lines.
; ---------------------------------------------------------------------
dump_fb
    stz REP                     ; row 0..7
@row
    lda #'D'
    jsr CHROUT
    lda #':'
    jsr CHROUT
    ; FBA = ROW_BASE + row*160  (row*160 = row*128 + row*32)
    lda REP
    asl
    asl
    asl
    asl
    asl                         ; row*32 (row <= 7: fits in 8 bits)
    sta FBA
    stz FBA+1
    asl
    rol FBA+1
    asl
    rol FBA+1                   ; A = row*128 low, FBA+1 = carry bits
    clc
    adc FBA
    sta FBA
    lda FBA+1
    adc #0
    sta FBA+1
    lda FBA                     ; + ROW_BASE
    clc
    adc #<ROW_BASE
    sta FBA
    lda FBA+1
    adc #>ROW_BASE
    sta FBA+1

    lda #VERA_CTRL_ADDRSEL      ; aim port 1 (read), +1 per byte
    tsb VERA_CTRL
    lda FBA
    sta VERA_ADDR_L
    lda FBA+1
    sta VERA_ADDR_M
    lda #(VERA_INC_1 << 4)
    sta VERA_ADDR_H

    ; read the whole row into RAM FIRST: CHROUT repositions the VERA
    ; data ports, so reading and printing must never interleave
    ldx #0
@read
    lda VERA_DATA1
    sta dump_buf,x
    inx
    cpx #40
    bne @read

    ldx #0
@byte
    lda dump_buf,x
    phx
    jsr print_hex
    plx
    inx
    cpx #40
    bne @byte
    lda #$0D
    jsr CHROUT
    inc REP
    lda REP
    cmp #8
    bne @row
    rts

print_hex                       ; A = byte -> two hex chars
    pha
    lsr
    lsr
    lsr
    lsr
    jsr @nib
    pla
    and #$0F
@nib
    cmp #10
    bcc @dig
    adc #('A' - 10 - 1)         ; carry is set: +'A'-10
    jmp CHROUT
@dig
    adc #'0'
    jmp CHROUT

; ---------------------------------------------------------------------
; benchmarks: 16 x (100 glyphs at x = 0,6,12..594)
; ---------------------------------------------------------------------
bench_masked
    jsr time_start
    lda #16
    sta REP
@rep
    jsr glyph_line_masked
    dec REP
    bne @rep
    jmp time_end

bench_opaque
    jsr time_start
    lda #16
    sta REP
@rep
    jsr glyph_line_opaque
    dec REP
    bne @rep
    jmp time_end

glyph_line_masked
    stz XCUR
    stz XCUR+1
    lda #100
    sta GCNT
@glyph
    jsr blit_masked
    lda XCUR                    ; advance 5 px: hits all 4 phases
    clc
    adc #5
    sta XCUR
    bcc @nc
    inc XCUR+1
@nc
    dec GCNT
    bne @glyph
    rts

glyph_line_opaque
    stz XCUR
    stz XCUR+1
    lda #100
    sta GCNT
@glyph
    jsr blit_opaque
    lda XCUR
    clc
    adc #5
    sta XCUR
    bcc @nc
    inc XCUR+1
@nc
    dec GCNT
    bne @glyph
    rts

; ---------------------------------------------------------------------
; blit_masked -- one 8x8 glyph, transparent, at x = XCUR on the fixed
; bench line. fb' = (fb AND mask) OR glyph, column-major, both ports
; walking down rows with VERA_INC_160.
; ---------------------------------------------------------------------
blit_masked
    jsr glyph_setup             ; FBA = fb byte address, GLY/MSK = phase

    ldy #0                      ; walks 0..23 through the phase tables
    ldx #3                      ; three framebuffer columns
@col
    jsr aim_ports_rw
    .repeat 8
    lda VERA_DATA1              ; read fb byte (port 1, +160)
    and (MSK),y                 ; keep background where transparent
    ora (GLY),y                 ; lay in the ink
    sta VERA_DATA0              ; write back (port 0, +160)
    iny
    .endrepeat
    inc FBA                     ; next column byte
    bne @nc
    inc FBA+1
@nc
    dex
    bne @col
    rts

; ---------------------------------------------------------------------
; blit_opaque -- same glyph, background assumed color 0: pure writes.
; ---------------------------------------------------------------------
blit_opaque
    jsr glyph_setup

    ldy #0
    ldx #3
@col
    jsr aim_port_w
    .repeat 8
    lda (GLY),y
    sta VERA_DATA0
    iny
    .endrepeat
    inc FBA
    bne @nc
    inc FBA+1
@nc
    dex
    bne @col
    rts

; ---------------------------------------------------------------------
; glyph_setup -- FBA = ROW_BASE + (XCUR >> 2); GLY/MSK aimed at the
; phase (XCUR & 3) tables.
; ---------------------------------------------------------------------
glyph_setup
    lda XCUR
    and #3
    tax
    lda gly_ptr_lo,x
    sta GLY
    lda gly_ptr_hi,x
    sta GLY+1
    lda msk_ptr_lo,x
    sta MSK
    lda msk_ptr_hi,x
    sta MSK+1

    lda XCUR+1                  ; FBA = XCUR >> 2 (x < 1024)
    sta FBA+1
    lda XCUR
    lsr FBA+1
    ror
    lsr FBA+1
    ror
    clc                         ; + ROW_BASE
    adc #<ROW_BASE
    sta FBA
    lda FBA+1
    adc #>ROW_BASE
    sta FBA+1
    rts

; ---------------------------------------------------------------------
; aim_ports_rw -- point port 1 (read) and port 0 (write) at FBA, both
; stepping one row (+160) per access. Preserves X/Y.
; ---------------------------------------------------------------------
aim_ports_rw
    lda #VERA_CTRL_ADDRSEL
    tsb VERA_CTRL               ; port 1
    lda FBA
    sta VERA_ADDR_L
    lda FBA+1
    sta VERA_ADDR_M
    lda #(VERA_INC_160 << 4)
    sta VERA_ADDR_H
aim_port_w
    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL               ; port 0
    lda FBA
    sta VERA_ADDR_L
    lda FBA+1
    sta VERA_ADDR_M
    lda #(VERA_INC_160 << 4)
    sta VERA_ADDR_H
    rts

; ---------------------------------------------------------------------
; mode + bands (same bring-up as spike A)
; ---------------------------------------------------------------------
mode_2bpp_640
    vera_dcsel 0
    lda #$80
    sta VERA_DC_HSCALE
    sta VERA_DC_VSCALE
    stz VERA_DC_BORDER

    lda #(VERA_LAYER_BITMAP | VERA_LAYER_BPP_2)
    sta VERA_L0_CONFIG
    lda #((FB_BASE >> 11) << 2) | $01
    sta VERA_L0_TILEBASE
    stz VERA_L0_HSCROLL_L
    stz VERA_L0_HSCROLL_H
    stz VERA_L0_VSCROLL_L
    stz VERA_L0_VSCROLL_H

    ldx #0
    lda #$FF                    ; white paper
    ldy #$0F
    jsr pal_set
    ldx #1
    lda #$AA                    ; light gray
    ldy #$0A
    jsr pal_set
    ldx #2
    lda #$55                    ; dark gray
    ldy #$05
    jsr pal_set
    ldx #3
    lda #$00                    ; black ink
    ldy #$00
    jsr pal_set

    lda VERA_DC_VIDEO
    and #%00001111
    ora #VERA_VIDEO_LAYER0_EN
    sta VERA_DC_VIDEO
    rts

draw_bands
    vera_addr 0, FB_BASE, VERA_INC_1
    lda #$00
    jsr fill_band
    lda #$55
    jsr fill_band
    lda #$AA
    jsr fill_band
    lda #$FF
fill_band
    ldx #<(120 * FB_STRIDE)
    ldy #>(120 * FB_STRIDE)
    jmp vera_fill

; ---------------------------------------------------------------------
; timing + printing plumbing (as spike A)
; ---------------------------------------------------------------------
timer_alive
    jsr RDTIM
    sta BENCH_T0
    ldx #0
    ldy #0
@spin
    jsr RDTIM
    cmp BENCH_T0
    bne @alive
    dex
    bne @spin
    dey
    bne @spin
    clc
    rts
@alive
    sec
    rts

time_start
    jsr RDTIM
    sta BENCH_T0
    stx BENCH_T0+1
    rts

time_end
    jsr RDTIM
    sec
    sbc BENCH_T0
    sta X16_P0
    txa
    sbc BENCH_T0+1
    sta X16_P1
    rts

print_elapsed
    jsr u16_to_dec
    jsr print_str
    lda #<sb_jf
    ldx #>sb_jf
    jmp print_str

print_str
    sta STR_PTR
    stx STR_PTR+1
    ldy #0
@loop
    lda (STR_PTR),y
    beq @done
    jsr CHROUT
    iny
    bne @loop
@done
    rts

dump_buf  .res 40, 0

sb_banner .byte $0D, "CXRF SPIKE B: 2BPP GLYPH BLIT", $0D, 0
sb_mask   .byte "MASK1600 ", 0
sb_opaq   .byte "OPAQ1600 ", 0
sb_jf     .byte " JF", $0D, 0
sb_skip   .byte "SKIP TIMER DEAD", $0D, 0
sb_done   .byte "DONE", $0D, 0

; =====================================================================
; Glyph tables, generated at assembly time.
;
; Source glyph: 8x8 1bpp "A". Leftmost pixel = most significant bits
; (VERA packs 2bpp pixels MSB-first). Ink = color 3 (bits 11).
;
; For each phase p (x & 3), the 16-bit 2bpp row is placed in a 24-bit
; window shifted right by 2p bits, then split into 3 column bytes.
; Layout per phase: 24 glyph bytes (col0 rows 0-7, col1, col2), and a
; parallel 24-byte mask table (11 where background survives).
; =====================================================================

GR0 = %00111100
GR1 = %01100110
GR2 = %01100110
GR3 = %01111110
GR4 = %01100110
GR5 = %01100110
GR6 = %01100110
GR7 = %00000000

; expand an 8-bit row to 16-bit 2bpp coverage (11 per set pixel) -> _e16
.macro EXPAND16 rowval
_e16 .set 0
.repeat 8, j
    .if ((rowval) >> (7-j)) & 1
_e16 .set _e16 | (3 << (14 - 2*j))
    .endif
.endrepeat
.endmacro

.macro GLYPH_PHASE p
.ident(.sprintf("gly_p%d", p)):
.repeat 3, c
.repeat 8, r
    EXPAND16 .ident(.sprintf("GR%d", r))
    .byte ((_e16 << (8 - 2*(p))) >> (8*(2-c))) & $FF
.endrepeat
.endrepeat
.ident(.sprintf("msk_p%d", p)):
.repeat 3, c
.repeat 8, r
    EXPAND16 .ident(.sprintf("GR%d", r))
    .byte ((~(_e16 << (8 - 2*(p)))) >> (8*(2-c))) & $FF
.endrepeat
.endrepeat
.endmacro

GLYPH_PHASE 0
GLYPH_PHASE 1
GLYPH_PHASE 2
GLYPH_PHASE 3

gly_ptr_lo .byte <gly_p0, <gly_p1, <gly_p2, <gly_p3
gly_ptr_hi .byte >gly_p0, >gly_p1, >gly_p2, >gly_p3
msk_ptr_lo .byte <msk_p0, <msk_p1, <msk_p2, <msk_p3
msk_ptr_hi .byte >msk_p0, >msk_p1, >msk_p2, >msk_p3

; ---------------------------------------------------------------------
.include "x16_code.asm"
