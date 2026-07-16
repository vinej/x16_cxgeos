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

X16_USE_BITMAP2 = 1             ; pulls in VERA and VERAFX

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

; ---------------------------------------------------------------------
.include "kernel/gfx2/dirty.asm"
.include "testlib.asm"
.include "x16_code.asm"
