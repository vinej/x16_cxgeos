; ca65
; =====================================================================
; CXRF :: kernel/video/engine_lo.asm -- mode 1 at 4bpp and 2bpp
; =====================================================================
; Two more engine images behind the graphics port, both 320x240 shown
; FULLSCREEN (2:1 scale) like the 8bpp mode-1 engine (engine1.asm) --
; only the depth differs. They ride the port the same way: cx_gfx_mode
; with A = 1 (the 320x240 bitmap personality) and X = the bpp swaps the
; matching image in (cx_ov_load) and runs its init. 8bpp is engine1.
;
;   OV4LCODE  320x240 @ 4bpp   (bitmap4l, gfx4l_*)   engine index 5
;   OV2LCODE  320x240 @ 2bpp   (bitmap2l, gfx2l_*)   engine index 6
;
; Each programs VERA itself (2:1 -> 320x240) and gates the module's own
; init/char/text out (X16_BITMAP*L_NO_INIT / _MIN) -- the toolkit is
; mode-0-only, so these carry the 13 drawing entries and refuse text and
; the save-under (the 4bpp/2bpp glyph blit and row copy are future work).
; The default VERA palette's first 4/16 entries colour them.
; =====================================================================

.ifndef CX_NO_OVERLAY

; --- shared refusals: text/measure refuse (carry), save-under no-ops ---
; (defined once in CODE, both images jmp to them through the port vector)
.segment "CODE"
ovlo_refuse
    sec
    rts
ovlo_noop
    clc
    rts

; =====================================================================
; OV4LCODE -- 320x240 @ 4bpp
; =====================================================================
X16_BITMAP4L_MIN     = 1         ; drop gfx4l_char/text (the port refuses text)
X16_BITMAP4L_NO_INIT = 1         ; ov4l_init programs VERA directly

.segment "OV4LCODE"

ov4l_vector
    jmp ov4l_init
    jmp gfx4l_clear
    jmp ov4l_pset
    jmp gfx4l_read
    jmp ov4l_hline
    jmp ov4l_vline
    jmp ov4l_rect
    jmp ov4l_frame
    jmp ov4l_line
    jmp gfx4l_pattern_set
    jmp gfx4l_pattern_rect
    jmp gfx4l_blit
    jmp gfx4l_blitm
    jmp ovlo_refuse             ; text: refused (no CXF blit at 4bpp yet)
    jmp ovlo_refuse             ; measure
    jmp ovlo_noop               ; rsave: no save-under
    jmp ovlo_noop               ; rrest
    .byte 1                     ; cxov_ink
    .byte 12, 10,  8, 16,  2,  4,  8,  4,  1
    .word 280
    .byte 80, 72, 16, 80, 12, 30

.assert ov4l_vector = CX_OVL, error, "OV4LCODE must start at CX_OVL"

; 320x240 @ 4bpp, fullscreen: 2:1 scale, layer 0 bitmap 4bpp, base $00000,
; 320-wide (tilebase bit 0 = 0). The gfx4l primitives stride 160 bytes.
ov4l_init
    vera_dcsel 0
    lda #$40                    ; 2:1 -> 320x240 fills the 640x480 screen
    sta VERA_DC_HSCALE
    sta VERA_DC_VSCALE
    stz VERA_DC_BORDER
    lda #(VERA_LAYER_BITMAP | VERA_LAYER_BPP_4)
    sta VERA_L0_CONFIG
    stz VERA_L0_TILEBASE        ; base $00000, 320 wide
    stz VERA_L0_HSCROLL_L
    stz VERA_L0_HSCROLL_H
    stz VERA_L0_VSCROLL_L
    stz VERA_L0_VSCROLL_H
    lda #VERA_VIDEO_LAYER1_EN
    trb VERA_DC_VIDEO
    lda #VERA_VIDEO_LAYER0_EN
    tsb VERA_DC_VIDEO
    rts

ov4l_pset                       ; colour A -> P3 (the module's convention)
    sta X16_P3
    jmp gfx4l_pset
ov4l_hline
    sta X16_P3
    jmp gfx4l_hline
ov4l_vline
    sta X16_P3
    jmp gfx4l_vline
ov4l_rect
    sta X16_P3
    jmp gfx4l_rect
ov4l_frame
    sta X16_P3
    jmp gfx4l_frame
ov4l_line                       ; ABI x1 P4/P5, y1 P6, colour A -> module
    pha                         ; x1 P3/P4, y1 P5, colour P6
    lda X16_P4
    sta X16_P3
    lda X16_P5
    sta X16_P4
    lda X16_P6
    sta X16_P5
    pla
    sta X16_P6
    jmp gfx4l_line

.include "gfx/bitmap4l.asm"

.segment "CODE"

; =====================================================================
; OV2LCODE -- 320x240 @ 2bpp
; =====================================================================
X16_BITMAP2L_NO_INIT = 1        ; ov2l_init programs VERA directly

.segment "OV2LCODE"

ov2l_vector
    jmp ov2l_init
    jmp gfx2l_clear
    jmp gfx2l_pset              ; gfx2l is ABI-native: colour in A, 16-bit y
    jmp gfx2l_read             ; in P2/P3 -- direct JMPs, NO adapters (an
    jmp gfx2l_hline            ; `sta P3` here would clobber y's high byte)
    jmp gfx2l_vline
    jmp gfx2l_rect
    jmp gfx2l_frame
    jmp gfx2l_line
    jmp gfx2l_pattern_set
    jmp gfx2l_pattern_rect
    jmp gfx2l_blit
    jmp gfx2l_blitm
    jmp ovlo_refuse             ; text
    jmp ovlo_refuse             ; measure
    jmp ovlo_noop               ; rsave
    jmp ovlo_noop               ; rrest
    .byte 1                     ; cxov_ink
    .byte 12, 10,  8, 16,  2,  4,  8,  4,  1
    .word 280
    .byte 80, 72, 16, 80, 12, 30

.assert ov2l_vector = CX_OVL, error, "OV2LCODE must start at CX_OVL"

; 320x240 @ 2bpp, fullscreen: 2:1 scale, layer 0 bitmap 2bpp, base $00000,
; 320-wide. The gfx2l primitives stride 80 bytes.
ov2l_init
    vera_dcsel 0
    lda #$40
    sta VERA_DC_HSCALE
    sta VERA_DC_VSCALE
    stz VERA_DC_BORDER
    lda #(VERA_LAYER_BITMAP | VERA_LAYER_BPP_2)
    sta VERA_L0_CONFIG
    stz VERA_L0_TILEBASE
    stz VERA_L0_HSCROLL_L
    stz VERA_L0_HSCROLL_H
    stz VERA_L0_VSCROLL_L
    stz VERA_L0_VSCROLL_H
    lda #VERA_VIDEO_LAYER1_EN
    trb VERA_DC_VIDEO
    lda #VERA_VIDEO_LAYER0_EN
    tsb VERA_DC_VIDEO
    rts

.include "gfx/bitmap2l.asm"

.segment "CODE"

.endif
