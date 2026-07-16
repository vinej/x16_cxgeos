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

    jsr t_summary
    rts

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
.include "testlib.asm"
.include "x16_code.asm"
