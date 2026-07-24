; ca65
; =====================================================================
; CXRF :: kernel/video/engine_hi.asm -- 640x480 on VERA_2 (mode 0, bpp 4/8)
; =====================================================================
; The 4bpp and 8bpp depths of the 640x480 umbrella (CX_MODE_BMPHIGH, mode 0):
; a bitmap on the SECOND video plane, VERA_2 (the MiSTer core's SDRAM bitmap
; layer, $9F60..$9F6F; the emulator enables it with -bitmap2). Its framebuffer,
; palette and registers are all separate from VERA. cx_gfx_mode with A = 0
; (CX_MODE_BMPHIGH) and X = 4 or 8 swaps the image in (X = 2 is the std-VERA
; desktop, OV0); the module's own init enables VERA_2 at that depth.
;
;   OV4HCODE  640x480 @ 4bpp   (bitmap4h, gfx4h_*)   engine index 7
;   OV8HCODE  640x480 @ 8bpp   (bitmap8h, gfx8h_*)   engine index 8
;
; The gfx*h modules are ABI-native (colour in A, 16-bit y in P2/P3, exactly
; the desktop gfx2h convention), so the port vector is direct JMPs -- no
; adapters. Text and the save-under refuse (a VERA_2 glyph blit and row
; copy are future work); the palette is VERA_2's own (gfx*h_pal_*), NOT the
; VERA palette cx_pal_set writes. cx_ov_load turns VERA_2 OFF on every swap
; (below), so switching to a std-VERA depth restores the normal display;
; these inits turn it back on.
; =====================================================================

.ifndef CX_NO_OVERLAY

; =====================================================================
; OV4HCODE -- 640x480 @ 4bpp
; =====================================================================
.segment "OV4HCODE"

ov4h_vector
    jmp ov4h_init              ; VERA layers off, then VERA_2 on at 4bpp
    jmp gfx4h_clear
    jmp gfx4h_pset
    jmp gfx4h_read
    jmp gfx4h_hline
    jmp gfx4h_vline
    jmp gfx4h_rect
    jmp gfx4h_frame
    jmp gfx4h_line
    jmp gfx4h_pattern_set
    jmp gfx4h_pattern_rect
    jmp gfx4h_blit
    jmp gfx4h_blitm
    jmp ovlo_refuse             ; text: refused (no VERA_2 glyph blit yet)
    jmp ovlo_refuse             ; measure
    jmp ovlo_noop               ; rsave: no save-under
    jmp ovlo_noop               ; rrest
    .byte 1                     ; cxov_ink
    .byte 12, 10,  8, 16,  2,  4,  8,  4,  1
    .word 400
    .byte 96, 72, 16, 80, 12, 34

.assert ov4h_vector = CX_OVL, error, "OV4HCODE must start at CX_OVL"

; VERA_2 composites with the normal VERA display, and these depths want ONLY
; the bitmap -- otherwise the desktop's layer 0 shows instead of (or over) the
; SDRAM plane. Turn both VERA layers off, then let the module enable VERA_2.
; cx_ov_load turns VERA_2 off on the swap back to a std-VERA depth, whose init
; re-enables layer 0, so the desktop comes back intact.
ov4h_init
    vera_dcsel 0
    lda #(VERA_VIDEO_LAYER0_EN | VERA_VIDEO_LAYER1_EN)
    trb VERA_DC_VIDEO
    jmp gfx4h_init

.include "gfx/bitmap4h.asm"

.segment "CODE"

; =====================================================================
; OV8HCODE -- 640x480 @ 8bpp
; =====================================================================
.segment "OV8HCODE"

ov8h_vector
    jmp ov8h_init              ; VERA layers off, then VERA_2 on at 8bpp
    jmp gfx8h_clear
    jmp gfx8h_pset
    jmp gfx8h_read
    jmp gfx8h_hline
    jmp gfx8h_vline
    jmp gfx8h_rect
    jmp gfx8h_frame
    jmp gfx8h_line
    jmp gfx8h_pattern_set
    jmp gfx8h_pattern_rect
    jmp gfx8h_blit
    jmp gfx8h_blitm
    jmp ovlo_refuse             ; text
    jmp ovlo_refuse             ; measure
    jmp ovlo_noop               ; rsave
    jmp ovlo_noop               ; rrest
    .byte 1                     ; cxov_ink
    .byte 12, 10,  8, 16,  2,  4,  8,  4,  1
    .word 400
    .byte 96, 72, 16, 80, 12, 34

.assert ov8h_vector = CX_OVL, error, "OV8HCODE must start at CX_OVL"

; both VERA layers off, then the module enables VERA_2 (see ov4h_init)
ov8h_init
    vera_dcsel 0
    lda #(VERA_VIDEO_LAYER0_EN | VERA_VIDEO_LAYER1_EN)
    trb VERA_DC_VIDEO
    jmp gfx8h_init

.include "gfx/bitmap8h.asm"

.segment "CODE"

.endif
