; ca65
; =====================================================================
; CXRF :: demos/torture.asm -- the Phase 1 milestone demo
; =====================================================================
; Every gfx2 primitive in one composite scene, timed. This is also the
; perf regression gate: docs/perf.md pins the SCENE4 number.
;
;   scene = checkered pattern flood (full screen)
;         + 8 filled rects with frames
;         + a 16-line starburst
;         + 32 raster-op blits
;         + 200 masked pre-shifted glyphs (2 rows of 100)
;
;   .\build.ps1 -Source demos\torture.asm -Capture   # SCENE4 n JF
;   .\build.ps1 -Source demos\torture.asm -Run       # look at it
; =====================================================================

.include "x16.asm"

X16_USE_BITMAP2H = 1
X16_USE_NUMBER  = 1

STR_PTR  = $60                  ; app zero page
BENCH_T0 = $62
REP      = $64
IDX      = $65
XCUR     = $66                  ; 16-bit
GCNT     = $68

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    jsr gfx2h_init

    lda #<tt_banner
    ldx #>tt_banner
    jsr print_str

    jsr timer_alive
    bcs @timer_ok
    lda #<tt_skip
    ldx #>tt_skip
    jsr print_str
    bra @done
@timer_ok

    jsr RDTIM
    sta BENCH_T0
    stx BENCH_T0+1
    lda #4
    sta REP
@scene
    jsr draw_scene
    dec REP
    bne @scene
    jsr RDTIM
    sec
    sbc BENCH_T0
    sta X16_P0
    txa
    sbc BENCH_T0+1
    sta X16_P1
    lda #<tt_scene
    ldx #>tt_scene
    jsr print_str
    jsr u16_to_dec
    jsr print_str
    lda #<tt_jf
    ldx #>tt_jf
    jsr print_str

@done
    lda #<tt_done
    ldx #>tt_done
    jsr print_str
@forever
    bra @forever

; =====================================================================
; the scene
; =====================================================================
draw_scene
    ; --- checker background, full screen -----------------------------
    lda #<checker
    ldx #>checker
    ldy #%0001                  ; background 0, foreground 1
    jsr gfx2h_pattern_set
    stz X16_P0
    stz X16_P1
    stz X16_P2
    stz X16_P3
    lda #<640
    sta X16_P4
    lda #>640
    sta X16_P5
    lda #<480
    sta X16_P6
    lda #>480
    sta X16_P7
    jsr gfx2h_pattern_rect

    ; --- 8 filled rects with black frames, colors cycling ------------
    stz IDX
@rects
    lda IDX
    jsr rect_args               ; P0..P7 = (20 + i*76, 20, 60, 40)
    ldx IDX
    lda col_cycle,x             ; color 1,2,3,1,...
    jsr gfx2h_rect
    lda IDX
    jsr rect_args
    lda #3
    jsr gfx2h_frame
    inc IDX
    lda IDX
    cmp #8
    bne @rects

    ; --- starburst: 16 lines out of (320,240) -------------------------
    stz IDX
@lines
    lda IDX
    asl
    asl                         ; 4 bytes per endpoint
    tax
    lda #<320
    sta X16_P0
    lda #>320
    sta X16_P1
    lda #<240
    sta X16_P2
    stz X16_P3
    lda star,x
    sta X16_P4
    lda star+1,x
    sta X16_P5
    lda star+2,x
    sta X16_P6
    lda star+3,x
    sta X16_P7
    lda IDX
    and #3                      ; color 0..3 (0 punches holes: fine)
    jsr gfx2h_line
    inc IDX
    lda IDX
    cmp #16
    bne @lines

    ; --- 32 raster-op blits along the bottom --------------------------
    stz IDX
@blits
    lda IDX                     ; x = i*16 + 64 (16-bit: i reaches 31)
    lsr
    lsr
    lsr
    lsr
    sta X16_P1
    lda IDX
    asl
    asl
    asl
    asl
    clc
    adc #64
    sta X16_P0
    bcc @bx_ok
    inc X16_P1
@bx_ok
    lda #<430
    sta X16_P2
    lda #>430
    sta X16_P3
    lda #2                      ; 2 bytes wide (8 px)
    sta X16_P4
    lda #8                      ; 8 rows
    sta X16_P5
    lda #<blitimg
    sta X16_P6
    lda #>blitimg
    sta X16_P7
    lda IDX
    and #3                      ; copy / or / and / xor, cycling
    jsr gfx2h_blit
    inc IDX
    lda IDX
    cmp #32
    bne @blits

    ; --- 200 masked glyphs over the checker ---------------------------
    lda #<200
    sta X16_P2
    lda #>200
    sta X16_P3
    jsr glyph_line
    lda #<212
    sta X16_P2
    lda #>212
    sta X16_P3
    ; fall through
glyph_line                      ; 100 glyphs, x = 0,5,10..495 at y=P2/3
    stz XCUR
    stz XCUR+1
    lda #100
    sta GCNT
@glyph
    lda XCUR
    sta X16_P0
    and #3                      ; phase picks the pre-shifted table
    tax
    lda XCUR+1
    sta X16_P1
    lda gly_ptr_lo,x
    sta X16_P6
    lda gly_ptr_hi,x
    sta X16_P7
    lda #8                      ; 8 rows
    sta X16_P4
    lda #3                      ; 3 columns
    sta X16_P5
    jsr gfx2h_blitm              ; consumes P0/P1 (x) and P6/P7 (src)
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

; P0..P7 = rect i: x = 20 + i*76, y = 20, w = 60, h = 40
rect_args
    sta IDX2
    stz X16_P1
    asl                         ; i*4
    asl
    sta X16_T0
    lda IDX2
    asl                         ; i*8
    asl
    asl
    clc
    adc X16_T0                  ; i*12
    sta X16_T0
    lda IDX2
    asl                         ; i*64
    asl
    asl
    asl
    asl
    asl
    rol X16_P1                  ; may carry into the high byte (i >= 4)
    clc
    adc X16_T0                  ; i*76
    sta X16_P0
    bcc @add_base
    inc X16_P1
@add_base
    lda X16_P0
    clc
    adc #20
    sta X16_P0
    bcc @based
    inc X16_P1
@based
    lda #20
    sta X16_P2
    stz X16_P3
    lda #60
    sta X16_P4
    stz X16_P5
    lda #40
    sta X16_P6
    stz X16_P7
    rts

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

IDX2      .byte 0

tt_banner .byte $0D, "CXRF TORTURE: GFX2 COMPOSITE SCENE", $0D, 0
tt_scene  .byte "SCENE4 ", 0
tt_jf     .byte " JF", $0D, 0
tt_skip   .byte "SKIP TIMER DEAD", $0D, 0
tt_done   .byte "DONE", $0D, 0

checker   .byte $AA, $55, $AA, $55, $AA, $55, $AA, $55
col_cycle .byte 1, 2, 3, 1, 2, 3, 1, 2
blitimg   .byte $E4, $E4, $1B, $1B, $E4, $E4, $1B, $1B
          .byte $E4, $E4, $1B, $1B, $E4, $E4, $1B, $1B

; 16 starburst endpoints around (320,240), radius 200
star      .word 520,240, 505,317, 461,381, 397,425
          .word 320,440, 243,425, 179,381, 115,317
          .word 120,240, 135,163, 179, 99, 243, 55
          .word 320, 40, 397, 55, 461, 99, 505,163

; =====================================================================
; the glyph, pre-shifted to 4 phases in gfx2h_blitm's (mask,data)
; column-major pair format: for each of 3 columns, 8 pairs.
; =====================================================================
GR0 = %00111100
GR1 = %01100110
GR2 = %01100110
GR3 = %01111110
GR4 = %01100110
GR5 = %01100110
GR6 = %01100110
GR7 = %00000000

.macro EXPAND16 rowval          ; 1bpp row -> 16-bit 2bpp coverage
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
    .byte ((~(_e16 << (8 - 2*(p)))) >> (8*(2-c))) & $FF   ; mask
    .byte ((_e16 << (8 - 2*(p))) >> (8*(2-c))) & $FF      ; data
.endrepeat
.endrepeat
.endmacro

GLYPH_PHASE 0
GLYPH_PHASE 1
GLYPH_PHASE 2
GLYPH_PHASE 3

gly_ptr_lo .byte <gly_p0, <gly_p1, <gly_p2, <gly_p3
gly_ptr_hi .byte >gly_p0, >gly_p1, >gly_p2, >gly_p3

; ---------------------------------------------------------------------
.include "x16_code.asm"
