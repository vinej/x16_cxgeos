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
; Phase 0 scope: the 640x480@2bpp bring-up that the spikes proved,
; pinned as regression tests. The real gfx2 suite arrives with the
; x16_library gfx2 module in Phase 1.
; =====================================================================

.include "x16.asm"

X16_USE_VERA    = 1
X16_USE_PALETTE = 1

FB_BASE     = $00000
FB_STRIDE   = 160

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

; ---------------------------------------------------------------------
main
    jsr t_init

    jsr test_mode2bpp
    jsr test_fb_roundtrip
    jsr test_bands

    jsr t_summary
    rts

; ---------------------------------------------------------------------
; MODE2BPP -- the CXGEOS screen mode registers land as programmed
; ---------------------------------------------------------------------
test_mode2bpp
    jsr mode_2bpp_640
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
@name .byte "MODE2BPP", 0

; ---------------------------------------------------------------------
; FB_RW -- bytes written into the framebuffer via port 0 read back
; identically via port 1
; ---------------------------------------------------------------------
test_fb_roundtrip
    vera_addr 0, (100 * FB_STRIDE), VERA_INC_1
    ldx #0
@write
    lda @pattern,x
    sta VERA_DATA0
    inx
    cpx #8
    bne @write

    vera_addr 1, (100 * FB_STRIDE), VERA_INC_1
    ldx #0
@verify
    lda VERA_DATA1
    cmp @pattern,x
    bne @bad
    inx
    cpx #8
    bne @verify
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
; BANDS -- draw_bands puts the right byte in every band (one row each)
; ---------------------------------------------------------------------
test_bands
    jsr draw_bands

    vera_addr 1, (0 * FB_STRIDE), VERA_INC_1
    lda #$00
    ldx #160
    jsr t_vcmp_const
    bne @bad
    vera_addr 1, (120 * FB_STRIDE), VERA_INC_1
    lda #$55
    ldx #160
    jsr t_vcmp_const
    bne @bad
    vera_addr 1, (240 * FB_STRIDE), VERA_INC_1
    lda #$AA
    ldx #160
    jsr t_vcmp_const
    bne @bad
    vera_addr 1, (360 * FB_STRIDE), VERA_INC_1
    lda #$FF
    ldx #160
    jsr t_vcmp_const
    bne @bad
    lda #0
    bra @report
@bad
    lda #1
@report
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "BANDS", 0

; ---------------------------------------------------------------------
; the code under test (Phase 0: inline; Phase 1: x16lib gfx2 module)
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
    lda #$FF
    ldy #$0F
    jsr pal_set
    ldx #1
    lda #$AA
    ldy #$0A
    jsr pal_set
    ldx #2
    lda #$55
    ldy #$05
    jsr pal_set
    ldx #3
    lda #$00
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
.include "testlib.asm"
.include "x16_code.asm"
