;ACME
; =====================================================================
; x16lib :: video/vdc.asm -- VERA display composer helpers
; =====================================================================
; Gate: X16_USE_VERA_DC
;
; The display composer is the DCSEL=0/1 view of $9F29-$9F2C:
; output mode, layer enables, scaling, border colour, active display
; window, and bitstream version registers.
;
; Routines leave DCSEL = 0. A/X/Y and flags are clobbered unless the
; routine documents a return value.
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; vdc_get_video / vdc_set_video
;   get out: A = DC_VIDEO
;   set in:  A = DC_VIDEO value, bit 7 ignored
; ---------------------------------------------------------------------
vdc_get_video
    vera_dcsel 0
    lda VERA_DC_VIDEO
    rts

vdc_set_video
    pha
    vera_dcsel 0
    pla
    and #%01111111
    sta VERA_DC_VIDEO
    rts

; ---------------------------------------------------------------------
; vdc_set_output
;   in: A = VERA_VIDEO_MODE_* value, preserving other DC_VIDEO bits
; ---------------------------------------------------------------------
vdc_set_output
    and #%00000011
    sta X16_T0
    vera_dcsel 0
    lda VERA_DC_VIDEO
    and #%01111100
    ora X16_T0
    sta VERA_DC_VIDEO
    rts

; ---------------------------------------------------------------------
; vdc_set_layers
;   in: A = any mix of VERA_VIDEO_LAYER0_EN/LAYER1_EN/SPRITES_EN
; ---------------------------------------------------------------------
vdc_set_layers
    and #(VERA_VIDEO_LAYER0_EN | VERA_VIDEO_LAYER1_EN | VERA_VIDEO_SPRITES_EN)
    sta X16_T0
    vera_dcsel 0
    lda VERA_DC_VIDEO
    and #%00001111
    ora X16_T0
    sta VERA_DC_VIDEO
    rts

; ---------------------------------------------------------------------
; vdc_layer_on / vdc_layer_off
;   in: A = layer/sprite enable mask
; ---------------------------------------------------------------------
vdc_layer_on
    and #(VERA_VIDEO_LAYER0_EN | VERA_VIDEO_LAYER1_EN | VERA_VIDEO_SPRITES_EN)
    pha
    vera_dcsel 0
    pla
    tsb VERA_DC_VIDEO
    rts

vdc_layer_off
    and #(VERA_VIDEO_LAYER0_EN | VERA_VIDEO_LAYER1_EN | VERA_VIDEO_SPRITES_EN)
    pha
    vera_dcsel 0
    pla
    trb VERA_DC_VIDEO
    rts

; ---------------------------------------------------------------------
; vdc_get_scale / vdc_set_scale
;   get out: A = HSCALE, X = VSCALE
;   set in:  A = HSCALE, X = VSCALE
;            $80 means one output pixel per input pixel.
; ---------------------------------------------------------------------
vdc_get_scale
    vera_dcsel 0
    lda VERA_DC_HSCALE
    ldx VERA_DC_VSCALE
    rts

vdc_set_scale
    sta X16_T0
    stx X16_T1
    vera_dcsel 0
    lda X16_T0
    sta VERA_DC_HSCALE
    lda X16_T1
    sta VERA_DC_VSCALE
    rts

; ---------------------------------------------------------------------
; vdc_get_border / vdc_set_border
;   get out: A = border palette index
;   set in:  A = border palette index
; ---------------------------------------------------------------------
vdc_get_border
    vera_dcsel 0
    lda VERA_DC_BORDER
    rts

vdc_set_border
    pha
    vera_dcsel 0
    pla
    sta VERA_DC_BORDER
    rts

; ---------------------------------------------------------------------
; vdc_get_active_raw
;   out: A = HSTART, X = HSTOP, Y = VSTART, r0L = VSTOP
;
; Raw registers are native display coordinates with low bits omitted:
; HSTART/HSTOP = pixel / 4, VSTART/VSTOP = pixel / 2.
; ---------------------------------------------------------------------
vdc_get_active_raw
    vera_dcsel 1
    lda VERA_DC_HSTART
    sta X16_T0
    lda VERA_DC_HSTOP
    sta X16_T1
    lda VERA_DC_VSTART
    sta X16_T2
    lda VERA_DC_VSTOP
    sta r0L
    vera_dcsel 0
    lda X16_T0
    ldx X16_T1
    ldy X16_T2
    rts

; ---------------------------------------------------------------------
; vdc_set_active_raw
;   in: A = HSTART, X = HSTOP, Y = VSTART, r0L = VSTOP
; ---------------------------------------------------------------------
vdc_set_active_raw
    sta X16_T0
    stx X16_T1
    sty X16_T2
    lda r0L
    sta X16_T3
    jmp _vdc_store_active_t

; ---------------------------------------------------------------------
; vdc_set_active
;   in: X16_P0/P1 = HSTART pixels, X16_P2/P3 = HSTOP pixels
;       X16_P4/P5 = VSTART pixels, X16_P6/P7 = VSTOP pixels
;
; Pixel values are converted to composer register values:
; horizontal / 4, vertical / 2.
; ---------------------------------------------------------------------
vdc_set_active
    lda X16_P0
    lsr
    lsr
    sta X16_T0
    lda X16_P1
    and #%00000011
    asl
    asl
    asl
    asl
    asl
    asl
    ora X16_T0
    sta X16_T0

    lda X16_P2
    lsr
    lsr
    sta X16_T1
    lda X16_P3
    and #%00000011
    asl
    asl
    asl
    asl
    asl
    asl
    ora X16_T1
    sta X16_T1

    lda X16_P4
    lsr
    sta X16_T2
    lda X16_P5
    and #%00000001
    asl
    asl
    asl
    asl
    asl
    asl
    asl
    ora X16_T2
    sta X16_T2

    lda X16_P6
    lsr
    sta X16_T3
    lda X16_P7
    and #%00000001
    asl
    asl
    asl
    asl
    asl
    asl
    asl
    ora X16_T3
    sta X16_T3
    jmp _vdc_store_active_t

; ---------------------------------------------------------------------
; vdc_fullscreen -- active area = 0,0 to 640,480
; ---------------------------------------------------------------------
vdc_fullscreen
    stz X16_T0
    lda #160
    sta X16_T1
    stz X16_T2
    lda #240
    sta X16_T3
    jmp _vdc_store_active_t

_vdc_store_active_t
    vera_dcsel 1
    lda X16_T0
    sta VERA_DC_HSTART
    lda X16_T1
    sta VERA_DC_HSTOP
    lda X16_T2
    sta VERA_DC_VSTART
    lda X16_T3
    sta VERA_DC_VSTOP
    vera_dcsel 0
    rts

; ---------------------------------------------------------------------
; vdc_get_version
;   out: carry set if version is valid
;        A = major, X = minor, Y = build
;        carry clear and A/X/Y = 0 if DC_VER0 is not 'V'
; ---------------------------------------------------------------------
vdc_get_version
    vera_dcsel VERA_DCSEL_FX_VERSION
    lda VERA_DC_VER0
    cmp #VERA_VERSION_MAGIC
    bne @no
    lda VERA_DC_VER1
    sta X16_T0
    lda VERA_DC_VER2
    sta X16_T1
    lda VERA_DC_VER3
    sta X16_T2
    vera_dcsel 0
    lda X16_T0
    ldx X16_T1
    ldy X16_T2
    sec
    rts
@no
    vera_dcsel 0
    lda #0
    tax
    tay
    clc
    rts

; (end zone)
