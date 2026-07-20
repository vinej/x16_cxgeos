; MADS
; =====================================================================
; CXGEOS :: apps/smoke_mads/smoke.asm -- the MADS SDK smoke test
; =====================================================================
; Proves the GENERATED asmsdk/mads layer assembles with the real MADS and
; drives the kernel through the jump table. MADS has no linker and writes
; a flat image (x16.asm sets opt h-); build.ps1 prepends the CBM load
; address. Headless: the boot smoke greps stdout for "SMOKE MADS OK".
;   mads smoke.asm -c -i:. -i:<x16_library/src_mads> -o:smoke.raw
; =====================================================================

    icl "x16.asm"                       ; from src_mads: X16_P0.., CHROUT, basic_stub
    icl "asmsdk/mads/cxgeos.inc"        ; the generated friendly layer

    org $0801
    basic_stub

main
    ldx #0
up_lp
    lda s_up, x
    beq up_done
    jsr CHROUT
    inx
    bne up_lp
up_done
    cxm_gfx_init
    cxm_gfx_clear 0
    cxm_say s_hello, 24, 200
    cxm_gfx_frame 20, 20, 300, 160, 3
    cxm_gfx_circle 160, 120, 40, 3
    cxm_gfx_disc 260, 120, 20, 2

    ldx #0
ok_lp
    lda s_ok, x
    beq ok_done
    jsr CHROUT
    inx
    bne ok_lp
ok_done
    cxm_exit

; MADS translates .byte "..." to ATASCII, so the headless marker and the
; greeting are emitted as explicit ASCII bytes instead
s_up    .byte $53, $4D, $4F, $4B, $45, $20, $4D, $41, $44, $53, $20, $55, $50, $0D, $00
s_ok    .byte $53, $4D, $4F, $4B, $45, $20, $4D, $41, $44, $53, $20, $4F, $4B, $0D, $00
s_hello .byte $68, $69, $20, $66, $72, $6F, $6D, $20, $6D, $61, $64, $73, $2C, $20, $74, $68, $72, $6F, $75, $67, $68, $20, $74, $68, $65, $20, $6A, $75, $6D, $70, $20, $74, $61, $62, $6C, $65, $00

widgets
    cxm_wcount widgets, widgets_end
    cxm_wg_button 40, 240, 100, 24, s_btn
    cxm_wg_hit   200, 240, 80, 80, CX_WH_CIRCLE, CX_WH_CLICK | CX_WH_HOVER
widgets_end
s_btn   .byte $6F, $6B, 0
