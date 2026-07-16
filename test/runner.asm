; ca65
; =====================================================================
; CXGEOS :: test/runner.asm -- on-target regression tests
; =====================================================================
;   .\build.ps1 -Test
;
; The x16lib pattern: drive the code one way, verify through an
; independent path (write via port 0, read back via port 1). Runs
; headless under -testbench (nothing here needs VSYNC).
;
; The 2bpp engine itself is tested where it lives -- the x16_library
; gfx2 module and its runner2 suite. These tests pin the CXGEOS side:
; the vendored module boots our screen, and the framebuffer geometry
; the OS is built around holds.
; =====================================================================

.include "x16.asm"
.include "kernel/resident/zp.inc"

X16_USE_BITMAP2 = 1             ; pulls in VERA and VERAFX
X16_USE_IRQ     = 1             ; the event system's raster hook
X16_USE_INPUT   = 1             ; ...and its mouse and keyboard

FB_STRIDE   = 160

; framebuffer byte addresses the tests probe
ROW100   = 100 * FB_STRIDE
ROW200B1 = 200 * FB_STRIDE + 1
FB_LAST  = 480 * FB_STRIDE - 1

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

; ---------------------------------------------------------------------
main
    jsr t_init

    jsr test_gfx2_init
    jsr test_fb_roundtrip
    jsr test_gfx2_draws

    jsr test_dr_add
    jsr test_dr_merge
    jsr test_dr_separate
    jsr test_dr_cascade
    jsr test_dr_full

    jsr test_font_set
    jsr test_font_cache
    jsr test_font_measure
    jsr test_font_draw
    jsr test_font_pen
    jsr test_font_bold
    jsr test_font_under
    jsr test_font_pen_bold
    jsr test_font_banked

    jsr test_ev_queue
    jsr test_ev_coalesce
    jsr test_ev_overflow
    jsr test_ev_wrap
    jsr test_ev_dispatch
    jsr test_ev_null

    jsr test_abi_header
    jsr test_abi_table
    jsr test_abi_call

    jsr t_summary
    rts

; ---------------------------------------------------------------------
; dirty-rectangle list (kernel/gfx2/dirty.asm) -- pure data structure,
; nothing on screen. dr_put is a helper: A/X/Y = x, w, h with y fixed
; per test via P2/P3 beforehand? No -- each test loads the block.
; ---------------------------------------------------------------------

; add rect from an 8-byte table at A/X (x,y,w,h as words, little-endian)
dr_put
    sta X16_T6
    stx X16_T7
    ldy #7
@copy
    lda (X16_TPTR3),y
    sta X16_P0,y
    dey
    bpl @copy
    jmp dr_add

; DR_ADD: one rect stored with inclusive corners
test_dr_add
    jsr dr_reset
    lda #<@r1
    ldx #>@r1
    jsr dr_put
    ldy #1
    jsr dr_count
    cmp #1
    bne @report
    lda #0
    jsr dr_get
    ldy #1
    lda X16_P0                  ; x0 = 10
    cmp #10
    bne @report
    lda X16_P4                  ; x1 = 29
    cmp #29
    bne @report
    lda X16_P2                  ; y0 = 10
    cmp #10
    bne @report
    lda X16_P6                  ; y1 = 29
    cmp #29
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "DR_ADD", 0
@r1 .word 10, 10, 20, 20

; DR_MERGE: an overlapping rect unions; a touching rect unions too
test_dr_merge
    jsr dr_reset
    lda #<@m1
    ldx #>@m1
    jsr dr_put
    lda #<@m2                   ; overlaps m1
    ldx #>@m2
    jsr dr_put
    ldy #1
    jsr dr_count
    cmp #1
    bne @report
    lda #0
    jsr dr_get
    ldy #1
    lda X16_P4                  ; x1 = max(29, 44) = 44
    cmp #44
    bne @report
    lda #<@m3                   ; x0 = 45 touches x1 = 44
    ldx #>@m3
    jsr dr_put
    ldy #1
    jsr dr_count
    cmp #1
    bne @report
    lda #0
    jsr dr_get
    ldy #1
    lda X16_P4                  ; x1 = 49 now
    cmp #49
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "DR_MERGE", 0
@m1 .word 10, 10, 20, 20
@m2 .word 25, 15, 20, 10
@m3 .word 45, 10,  5,  5

; DR_SEPARATE: disjoint rects stay in their own slots
test_dr_separate
    jsr dr_reset
    lda #<@s1
    ldx #>@s1
    jsr dr_put
    lda #<@s2
    ldx #>@s2
    jsr dr_put
    ldy #1
    jsr dr_count
    cmp #2
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "DR_SEPARATE", 0
@s1 .word 0,   0,   10, 10
@s2 .word 100, 100, 10, 10

; DR_CASCADE: a bridge rect swallows two islands into one
test_dr_cascade
    jsr dr_reset
    lda #<@c1
    ldx #>@c1
    jsr dr_put
    lda #<@c2
    ldx #>@c2
    jsr dr_put
    lda #<@c3                   ; spans the gap: touches both
    ldx #>@c3
    jsr dr_put
    ldy #1
    jsr dr_count
    cmp #1
    bne @report
    lda #0
    jsr dr_get
    ldy #1
    lda X16_P0                  ; bbox (0,0)-(39,9)
    bne @report
    lda X16_P4
    cmp #39
    bne @report
    lda X16_P6
    cmp #9
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "DR_CASCADE", 0
@c1 .word 0,  0, 10, 10
@c2 .word 30, 0, 10, 10
@c3 .word 8,  0, 25, 10

; DR_FULL: a ninth disjoint rect folds instead of overflowing
test_dr_full
    jsr dr_reset
    ldx #0
@fill                           ; 8 disjoint rects at x = 0,40,80,...
    phx
    txa
    sta X16_P0                  ; x = i*40 (fits a byte: 0..280? no --
    stz X16_P1                  ; i*40 <= 280 needs 9 bits; use *32)
    stz X16_P2
    stz X16_P3
    lda #10
    sta X16_P4
    stz X16_P5
    lda #10
    sta X16_P6
    stz X16_P7
    jsr dr_add
    pla
    clc
    adc #32
    tax
    cpx #0                      ; 8 * 32 = 256 wraps to 0: done
    bne @fill
    jsr dr_count
    cmp #8
    bne @bad
    lda #<@f9                   ; a ninth, far away: the fold makes a
    ldx #>@f9                   ; bbox that cascades over every slot
    jsr dr_put
    jsr dr_count
    cmp #1                      ; collapsed, coverage intact
    bne @bad
    lda #0
    jsr dr_get
    lda X16_P0                  ; bbox (0,0)-(409,409) covers all nine
    ora X16_P1
    ora X16_P2
    ora X16_P3
    bne @bad
    lda X16_P4
    cmp #<409
    bne @bad
    lda X16_P5
    cmp #>409
    bne @bad
    lda X16_P6
    cmp #<409
    bne @bad
    ldy #0
    bra @report
@bad
    ldy #1
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "DR_FULL", 0
@f9 .word 400, 400, 10, 10

; ---------------------------------------------------------------------
; GFX2_INIT -- the vendored module programs the CXGEOS screen mode
; ---------------------------------------------------------------------
test_gfx2_init
    jsr gfx2_init
    ldy #1                      ; presume failure
    lda VERA_L0_CONFIG
    cmp #(VERA_LAYER_BITMAP | VERA_LAYER_BPP_2)
    bne @report
    lda VERA_L0_TILEBASE
    cmp #$01                    ; base $00000, 640 wide
    bne @report
    vera_dcsel 0
    lda VERA_DC_HSCALE
    cmp #$80
    bne @report
    lda VERA_DC_VSCALE
    cmp #$80
    bne @report
    lda VERA_DC_VIDEO
    and #VERA_VIDEO_LAYER0_EN
    beq @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "GFX2_INIT", 0

; ---------------------------------------------------------------------
; FB_RW -- bytes written into the framebuffer via port 0 read back
; identically via port 1 (raw geometry sanity, first and last bytes)
; ---------------------------------------------------------------------
test_fb_roundtrip
    vera_addr 0, ROW100, VERA_INC_1
    ldx #0
@write
    lda @pattern,x
    sta VERA_DATA0
    inx
    cpx #8
    bne @write

    vera_addr 1, ROW100, VERA_INC_1
    ldx #0
@verify
    lda VERA_DATA1
    cmp @pattern,x
    bne @bad
    inx
    cpx #8
    bne @verify

    vera_addr 0, FB_LAST, VERA_INC_1
    lda #$5A
    sta VERA_DATA0
    vera_addr 1, FB_LAST, VERA_INC_1
    lda VERA_DATA1
    cmp #$5A
    bne @bad
    lda #0
    bra @report
@bad
    lda #1
@report
    ldx #<@name
    ldy #>@name
    jmp t_result
@name    .byte "FB_RW", 0
@pattern .byte $00, $1B, $55, $AA, $FF, $E4, $0F, $F0

; ---------------------------------------------------------------------
; GFX2_DRAWS -- clear + a rect land the right bytes where the OS
; expects them (library correctness is runner2's job upstream)
; ---------------------------------------------------------------------
test_gfx2_draws
    lda #0
    jsr gfx2_clear              ; colour 0 -> byte $00 everywhere

    lda #4                      ; x=4 y=200 w=8 h=1, colour 3
    sta X16_P0
    stz X16_P1
    lda #<200
    sta X16_P2
    stz X16_P3
    lda #8
    sta X16_P4
    stz X16_P5
    lda #1
    sta X16_P6
    stz X16_P7
    lda #3
    jsr gfx2_rect

    vera_addr 1, ROW200B1, VERA_INC_1
    lda VERA_DATA1
    cmp #$FF                    ; pixels 4-7
    bne @bad
    lda VERA_DATA1
    cmp #$FF                    ; pixels 8-11
    bne @bad
    lda VERA_DATA1
    bne @bad                    ; pixel 12+: cleared background
    lda #0
    bra @report
@bad
    lda #1
@report
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "GFX2_DRAWS", 0


; =====================================================================
; the font engine (kernel/font/font.asm) against the real system font.
; Expected values come from fonts/pxl8.cxf itself, not from arithmetic
; done here: 'i' is glyph 73, two pixels wide, and its first row is $C0.
; =====================================================================

; FONT_SET: the magic is checked and the header parked
test_font_set
    lda #<pxl8
    ldx #>pxl8
    jsr font_set
    ldy #1
    bcs @report                 ; carry set = magic rejected
    lda f_height
    cmp #8
    bne @report
    lda f_ascent
    cmp #7
    bne @report
    lda f_first
    cmp #32
    bne @report
    lda f_count
    cmp #95
    bne @report
    lda f_spacing
    cmp #1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_SET", 0

; FONT_CACHE: 'i' row 0 is $C0 -- pixels 0 and 1. At phase 0 that is
; coverage $F0 in column 0 and nothing in columns 1-2; at phase 1 the
; same two pixels have walked right to $3C. Glyph 73 lives in bank 7 at
; $B740, which is (73 % 42) * 192 past the window.
test_font_cache
    lda RAM_BANK
    pha
    lda #7
    sta RAM_BANK
    ldy #1

    lda $B740                   ; phase 0, column 0, row 0: mask
    cmp #$0F
    bne @report
    lda $B741                   ; ...and data
    cmp #$F0
    bne @report
    lda $B750                   ; phase 0, column 1: untouched by a
    cmp #$FF                    ; two-pixel glyph, so all mask
    bne @report
    lda $B751
    bne @report

    lda $B742                   ; row 1 of 'i' is blank
    cmp #$FF
    bne @report
    lda $B743
    bne @report

    lda $B740+48                ; phase 1, column 0, row 0
    cmp #$C3
    bne @report
    lda $B741+48
    cmp #$3C
    bne @report
    ldy #0
@report
    pla
    sta RAM_BANK
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_CACHE", 0

; FONT_MEASURE: W=7 i=2 g=6 .=2, plus one pixel of spacing each = 21.
; A monospace 8 would say 32.
test_font_measure
    lda #<@str
    ldx #>@str
    jsr font_measure
    ldy #1
    lda X16_P0
    cmp #21
    bne @report
    lda X16_P1
    bne @report

    lda #<@empty                ; an empty string measures zero
    ldx #>@empty
    jsr font_measure
    lda X16_P0
    ora X16_P1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name  .byte "FONT_MEASURE", 0
@str   .byte "Wig.", 0
@empty .byte 0

; FONT_DRAW: 'i' at (0,100) on a cleared row lights pixels 0 and 1 of
; byte 0 -- $F0 -- and leaves byte 1 alone. At x=1 the same glyph lands
; on pixels 1 and 2, $3C, which is the pre-shifted phase doing its job.
test_font_draw
    vera_addr 0, ROW100, VERA_INC_1
    lda #$00
    ldx #8
    ldy #0
    jsr vera_fill

    stz X16_P0
    stz X16_P1
    lda #<100
    sta X16_P2
    stz X16_P3
    lda #<@i
    ldx #>@i
    jsr font_draw

    vera_addr 1, ROW100, VERA_INC_1
    ldy #1
    lda VERA_DATA1
    cmp #$F0
    bne @report
    lda VERA_DATA1              ; a 2-pixel glyph never reaches byte 1
    bne @report

    vera_addr 0, ROW100, VERA_INC_1
    lda #$00
    ldx #8
    ldy #0
    jsr vera_fill

    lda #1                      ; x = 1: phase 1
    sta X16_P0
    stz X16_P1
    lda #<100
    sta X16_P2
    stz X16_P3
    lda #<@i
    ldx #>@i
    jsr font_draw

    vera_addr 1, ROW100, VERA_INC_1
    lda VERA_DATA1
    cmp #$3C
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_DRAW", 0
@i    .byte "i", 0

; FONT_PEN: what font_draw advances the pen by must be exactly what
; font_measure promised. If these ever disagree, every layout in the
; system is wrong -- and the two compute it by different routes.
test_font_pen
    vera_addr 0, ROW200B1 - 1, VERA_INC_1
    lda #$00
    ldx #<200
    ldy #>200
    jsr vera_fill

    lda #<@str
    ldx #>@str
    jsr font_measure
    lda X16_P0
    sta @want
    lda X16_P1
    sta @want+1

    lda #<40                    ; draw from a non-zero, non-aligned pen
    sta X16_P0
    stz X16_P1
    lda #<200
    sta X16_P2
    stz X16_P3
    lda #<@str
    ldx #>@str
    jsr font_draw               ; out: P0/P1 = the pen

    ldy #1
    sec                         ; pen - 40 == measured width?
    lda X16_P0
    sbc #40
    cmp @want
    bne @report
    lda X16_P1
    sbc #0
    cmp @want+1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_PEN", 0
@str  .byte "Hamburgefonstiv 123", 0
@want .word 0


; FONT_BOLD: bold strikes the glyph again one pixel right, so 'i' -- two
; pixels at $F0 -- becomes three at $FC. The advance grows with it, and
; that has to come from f_advance or measure and draw would part ways.
test_font_bold
    vera_addr 0, ROW100, VERA_INC_1
    lda #$00
    ldx #8
    ldy #0
    jsr vera_fill

    lda #FONT_BOLD
    jsr font_style
    stz X16_P0
    stz X16_P1
    lda #<100
    sta X16_P2
    stz X16_P3
    lda #<@i
    ldx #>@i
    jsr font_draw

    vera_addr 1, ROW100, VERA_INC_1
    ldy #1
    lda VERA_DATA1
    cmp #$FC                    ; three pixels wide now
    bne @report
    lda VERA_DATA1
    bne @report                 ; and still nowhere near byte 1

    lda #<@i                    ; the advance carries the extra pixel
    ldx #>@i
    jsr font_measure
    lda X16_P0
    cmp #4                      ; i is 2 + 1 spacing + 1 bold
    bne @report
    ldy #0
@report
    lda #0                      ; plain again, whatever happened
    jsr font_style
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_BOLD", 0
@i    .byte "i", 0

; FONT_UNDER: one hline under the whole string, at y + height, running
; the full measured width -- through the space, not broken by it.
test_font_under
    vera_addr 0, ROW100, VERA_INC_1
    lda #$00
    ldx #<(9 * FB_STRIDE)
    ldy #>(9 * FB_STRIDE)
    jsr vera_fill               ; rows 100-108

    lda #FONT_UNDER
    jsr font_style
    stz X16_P0
    stz X16_P1
    lda #<100
    sta X16_P2
    stz X16_P3
    lda #<@str
    ldx #>@str
    jsr font_draw
    lda X16_P0
    sta @pen

    ; the rule sits on row 108 = 100 + height
    vera_addr 1, ROW100 + 8 * FB_STRIDE, VERA_INC_1
    ldy #1
    lda VERA_DATA1
    cmp #$FF                    ; solid from the very first pixel
    bne @report
    lda VERA_DATA1
    cmp #$FF                    ; ...and still solid across the space
    bne @report

    ; and nothing on the row above it that the glyphs did not put there
    lda @pen                    ; the rule stops where the pen did:
    lsr                         ; byte (pen-1)>>2 is the last one lit
    lsr
    tax
    vera_addr 1, ROW100 + 8 * FB_STRIDE, VERA_INC_1
@walk
    lda VERA_DATA1
    cmp #$FF
    bne @report
    dex
    bne @walk
    ldy #0
@report
    lda #0
    jsr font_style
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_UNDER", 0
@str  .byte "in it", 0
@pen  .byte 0

; FONT_PEN_BOLD: the measure/draw invariant, with bold set. This is the
; one that would have caught putting bold's extra pixel in font_draw
; instead of f_advance -- the text would draw wider than anything that
; laid it out believed.
test_font_pen_bold
    vera_addr 0, ROW200B1 - 1, VERA_INC_1
    lda #$00
    ldx #<200
    ldy #>200
    jsr vera_fill

    lda #FONT_BOLD
    jsr font_style

    lda #<@str
    ldx #>@str
    jsr font_measure
    lda X16_P0
    sta @want
    lda X16_P1
    sta @want+1

    lda #<40
    sta X16_P0
    stz X16_P1
    lda #<200
    sta X16_P2
    stz X16_P3
    lda #<@str
    ldx #>@str
    jsr font_draw

    ldy #1
    sec
    lda X16_P0
    sbc #40
    cmp @want
    bne @report
    lda X16_P1
    sbc #0
    cmp @want+1
    bne @report
    ldy #0
@report
    lda #0
    jsr font_style
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_PEN_BOLD", 0
@str  .byte "Hamburgefonstiv 123", 0
@want .word 0

; FONT_BANKED: the path the kernel actually boots through. The font is
; copied to CX_SYSFONT_BANK:$A000 -- where the boot loader puts
; PXL8.CXF -- and adopted from there, so every source read (header,
; rows, widths) crosses the banked window. If any of them forgets to
; switch back to the font's bank, it reads a cache bank's glyph slots
; instead and one of these goes wrong: the header check, the rebuilt
; cache byte, the measure, or the drawn pixels. Runs last in the font
; group on purpose: the tests before it prove the resident-source path,
; and the banked font it leaves behind is the one the suite keeps using.
test_font_banked
    lda RAM_BANK
    pha
    lda #CX_SYSFONT_BANK        ; the 871 bytes, into bank 1 at $A000
    sta RAM_BANK
    lda #<pxl8
    sta X16_T0
    lda #>pxl8
    sta X16_T0+1
    lda #<CX_F_WIN
    sta X16_T2
    lda #>CX_F_WIN
    sta X16_T2+1
    ldx #4                      ; 4 x 256 covers 871
    ldy #0
@copy
    lda (X16_T0),y
    sta (X16_T2),y
    iny
    bne @copy
    inc X16_T0+1
    inc X16_T2+1
    dex
    bne @copy

    lda #<CX_F_WIN              ; adopt it where the kernel will
    ldx #>CX_F_WIN
    jsr font_set
    ldy #1
    bcs @report
    lda f_height                ; the header, read across the window
    cmp #8
    bne @report

    lda #7                      ; 'i' again, cached from the banked rows:
    sta RAM_BANK                ; the same bytes FONT_CACHE proved
    lda $B740
    cmp #$0F
    bne @report
    lda $B741
    cmp #$F0
    bne @report

    lda #<@str                  ; widths across the window: still 21
    ldx #>@str
    jsr font_measure
    lda X16_P0
    cmp #21
    bne @report
    lda X16_P1
    bne @report

    vera_addr 0, ROW100, VERA_INC_1
    lda #$00
    ldx #8
    ldy #0
    jsr vera_fill
    stz X16_P0                  ; 'i' at (0,100): the same $F0 the
    stz X16_P1                  ; resident-source draw test proved
    lda #<100
    sta X16_P2
    stz X16_P3
    lda #<@i
    ldx #>@i
    jsr font_draw
    vera_addr 1, ROW100, VERA_INC_1
    lda VERA_DATA1
    cmp #$F0
    bne @report
    lda VERA_DATA1
    bne @report
    ldy #0
@report
    pla
    sta RAM_BANK
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_BANKED", 0
@str  .byte "Wig.", 0
@i    .byte "i", 0


; =====================================================================
; the event system (kernel/event/event.asm).
;
; The raster hook cannot fire under -testbench -- there is no VSYNC, so
; no interrupt at all -- which is exactly why ev_post exists: a
; synthetic record goes down the same path a sampled one does,
; coalescing included. These drive the queue and the dispatcher through
; it. What the interrupt itself decodes (button edges, double clicks) is
; spike C's ground, and demos/evmon.asm shows it running.
; =====================================================================

; ev_fill -- post a record: A = type, X = detail, Y = x low.
ev_fill
    sta X16_P0
    stx X16_P1
    sty X16_P2
    stz X16_P3
    stz X16_P4
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jmp ev_post

; EV_QUEUE: records come back oldest first, byte for byte.
test_ev_queue
    jsr ev_init
    ldy #1
    jsr ev_count
    bne @report                 ; a fresh queue is empty

    lda #EV_KEY
    ldx #65
    ldy #11
    jsr ev_fill
    lda #EV_MOUSE_DOWN
    ldx #1
    ldy #22
    jsr ev_fill
    lda #EV_TIMER
    ldx #0
    ldy #33
    jsr ev_fill

    ldy #1
    jsr ev_count
    cmp #3
    bne @report

    jsr ev_get                  ; FIFO: the key first
    bcs @report
    lda X16_P0
    cmp #EV_KEY
    bne @report
    lda X16_P1
    cmp #65
    bne @report
    lda X16_P2
    cmp #11
    bne @report

    jsr ev_get
    bcs @report
    lda X16_P0
    cmp #EV_MOUSE_DOWN
    bne @report
    lda X16_P2
    cmp #22
    bne @report

    jsr ev_get
    bcs @report
    lda X16_P0
    cmp #EV_TIMER
    bne @report

    jsr ev_get                  ; and then it is empty again
    bcc @report
    jsr ev_count
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_QUEUE", 0

; EV_COALESCE: a move landing on a move overwrites it -- only the newest
; position was ever interesting. A move landing on anything else queues.
test_ev_coalesce
    jsr ev_init

    lda #EV_MOUSE_MOVE
    ldx #0
    ldy #10
    jsr ev_fill
    lda #EV_MOUSE_MOVE
    ldx #0
    ldy #20
    jsr ev_fill
    lda #EV_MOUSE_MOVE
    ldx #0
    ldy #30
    jsr ev_fill

    ldy #1
    jsr ev_count
    cmp #1                      ; three moves, one record
    bne @report
    jsr ev_get
    lda X16_P2
    cmp #30                     ; and it is the newest position
    bne @report

    lda #EV_MOUSE_MOVE          ; a move, then a press, then a move:
    ldx #0                      ; the press breaks the run, so the
    ldy #40                     ; second move cannot fold into the first
    jsr ev_fill
    lda #EV_MOUSE_DOWN
    ldx #1
    ldy #40
    jsr ev_fill
    lda #EV_MOUSE_MOVE
    ldx #0
    ldy #50
    jsr ev_fill
    jsr ev_count
    cmp #3
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_COALESCE", 0

; EV_OVERFLOW: a full queue drops the newest and says so. It must never
; drop a button silently, and it must not corrupt what it already holds.
test_ev_overflow
    jsr ev_init
    ldx #0
@fill
    phx
    txa
    clc
    adc #1                      ; detail 1..17, so the order is checkable
    tax
    lda #EV_MOUSE_DOWN
    ldy #0
    jsr ev_fill
    plx
    inx
    cpx #17                     ; one more than the queue holds
    bne @fill

    ldy #1
    jsr ev_count
    cmp #16
    bne @report
    lda ev_lost
    cmp #1                      ; exactly one, counted
    bne @report

    jsr ev_get                  ; the oldest survived intact
    lda X16_P1
    cmp #1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_OVERFLOW", 0

; EV_WRAP: push and pop past the ring's end. 40 records through a
; 16-record queue walks head and tail over the wrap three times.
test_ev_wrap
    jsr ev_init
    stz @n
@round
    lda #EV_KEY
    ldx @n
    ldy #0
    jsr ev_fill
    jsr ev_get
    bcs @bad
    lda X16_P1
    cmp @n                      ; what went in is what came out
    bne @bad
    inc @n
    lda @n
    cmp #40
    bne @round
    jsr ev_count                ; and nothing is left behind
    bne @bad
    ldy #0
    bra @report
@bad
    ldy #1
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_WRAP", 0
@n    .byte 0

; EV_DISPATCH: the handler for the record's type runs, and sees it.
test_ev_dispatch
    jsr ev_init
    lda #<@table
    ldx #>@table
    jsr ev_handlers

    stz @hits
    stz @saw
    lda #EV_KEY
    ldx #77
    ldy #0
    jsr ev_fill
    jsr ev_dispatch

    ldy #1
    lda @hits
    cmp #1                      ; ran once
    bne @report
    lda @saw
    cmp #77                     ; and the record reached it
    bne @report

    lda #EV_TIMER               ; a type this app ignores: a null vector
    ldx #0                      ; is not a crash
    ldy #0
    jsr ev_fill
    jsr ev_dispatch
    lda @hits
    cmp #1                      ; the key handler did not run again
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_DISPATCH", 0

@key_handler
    inc @hits
    lda X16_P1
    sta @saw
    rts

@table  .word 0, 0, 0, 0, 0, @key_handler, 0   ; only EV_KEY is handled
@hits   .byte 0
@saw    .byte 0

; EV_NULL: an empty queue dispatches EV_NULL with an all-zero record --
; the app's idle time, without polling.
test_ev_null
    jsr ev_init
    lda #<@table
    ldx #>@table
    jsr ev_handlers
    stz @hits

    lda #$FF                    ; poison the block: EV_NULL must clear it
    sta X16_P1
    sta X16_P2
    sta X16_P7
    jsr ev_dispatch

    ldy #1
    lda @hits
    cmp #1
    bne @report
    lda @zeroes                 ; the handler found it all zero
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_NULL", 0

@null_handler
    inc @hits
    lda X16_P0                  ; every byte of the record
    ora X16_P1
    ora X16_P2
    ora X16_P3
    ora X16_P4
    ora X16_P5
    ora X16_P6
    ora X16_P7
    sta @zeroes
    rts

@table   .word @null_handler, 0, 0, 0, 0, 0, 0
@hits    .byte 0
@zeroes  .byte 0


; =====================================================================
; the ABI (abi/cxgeos.abi -> kernel/resident/jumptab.asm).
;
; Here the table is linked into the test PRG rather than pinned at
; $8000, so these check what that placement does not: that the header
; says what the manifest says, that every slot is a JMP to a real
; routine, and that a call through the table reaches the kernel. The
; addresses themselves are kernel.cfg's business.
;
; abi/gen_bindings.py --selftest covers the generator; --check fails a
; build whose sdk/ has drifted from the manifest.
; =====================================================================

; ABI_HEADER: the loader reads this to decide whether an app can run.
test_abi_header
    ldy #1
    lda cx_hdr_magic            ; "CXOS"
    cmp #'C'
    bne @report
    lda cx_hdr_magic+1
    cmp #'X'
    bne @report
    lda cx_hdr_magic+2
    cmp #'O'
    bne @report
    lda cx_hdr_magic+3
    cmp #'S'
    bne @report

    lda cx_hdr_version          ; version 1, and the kernel agrees
    cmp #1
    bne @report
    lda cx_hdr_version+1
    bne @report
    lda cx_hdr_slots
    cmp #31
    bne @report
    lda cx_hdr_slots+1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "ABI_HEADER", 0

; ABI_TABLE: every slot is a JMP ($4C), three bytes apart, to somewhere
; that is not zero. A slot whose impl went missing would be caught by
; gen_bindings.py -- this catches the table being built wrong.
test_abi_table
    lda #31
    sta @n
    lda #<cx_jumptab            ; the library's scratch pointer: (zp),y
    sta X16_TPTR3               ; needs zero page, and it is free here
    lda #>cx_jumptab
    sta X16_TPTR3+1
@slot
    ldy #0
    lda (X16_TPTR3),y           ; the opcode
    cmp #$4C                    ; JMP abs
    bne @bad
    iny                         ; ...to a real address
    lda (X16_TPTR3),y
    iny
    ora (X16_TPTR3),y
    beq @bad

    clc                         ; three bytes on
    lda X16_TPTR3
    adc #3
    sta X16_TPTR3
    bcc @nc
    inc X16_TPTR3+1
@nc
    dec @n
    bne @slot
    lda #0
    bra @report
@bad
    lda #1
@report
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "ABI_TABLE", 0
@n    .byte 0

; ABI_CALL: a call through the table reaches the kernel and comes back
; with the right answer. cx_version is slot 0, so this also proves the
; table's base is where the bindings say.
test_abi_call
    ldy #1
    jsr cx_jumptab              ; slot 0 = cx_version
    cmp #1                      ; A/X = the header's version
    bne @report
    cpx #0
    bne @report

    ; slot 24 = cx_ev_count. Post one event, ask through the ABI.
    jsr ev_init
    lda #EV_KEY
    ldx #1
    ldy #0
    jsr ev_fill
    jsr cx_jumptab + 24 * 3
    cmp #1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "ABI_CALL", 0

; ---------------------------------------------------------------------
.include "kernel/gfx2/dirty.asm"
.include "kernel/font/font.asm"
.include "kernel/event/event.asm"
.include "kernel/resident/core.asm"
.include "kernel/resident/jumptab.asm"

; The system font, linked in so the suite needs no SD card. The kernel
; image carries no font at all -- the boot loader puts this same file at
; CX_SYSFONT_BANK:$A000, and FONT_BANKED walks that path.
pxl8
    .incbin "fonts/pxl8.cxf"
.include "testlib.asm"
.include "x16_code.asm"
