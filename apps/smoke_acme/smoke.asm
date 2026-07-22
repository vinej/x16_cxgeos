;ACME
; =====================================================================
; CXRF :: apps/smoke_acme/smoke.asm -- the ACME SDK smoke test
; =====================================================================
; Proves the GENERATED asmsdk/acme layer assembles with the real ACME
; and drives the kernel through the jump table. Prints a start marker,
; makes a spread of kernel calls through the cxm_* macros, prints an OK
; marker, and exits. Headless: the boot smoke greps for "SMOKE ACME OK".
;   acme -I . -I <x16_library/src_acme> -f cbm -o SMOKEACME.PRG smoke.asm
; =====================================================================

!cpu 65c02
!source "x16.asm"                       ; from src_acme: X16_P0.., CHROUT, +basic_stub
!source "asmsdk/acme/cxrf.inc"        ; the generated friendly layer

* = $0801
    +basic_stub

main
    ldx #0
up_lp
    lda s_up, x
    beq up_done
    jsr CHROUT
    inx
    bne up_lp
up_done
    +cxm_gfx_init
    +cxm_gfx_clear 0
    +cxm_say s_hello, 24, 200
    +cxm_gfx_frame 20, 20, 300, 160, 3
    +cxm_gfx_circle 160, 120, 40, 3
    +cxm_gfx_disc 260, 120, 20, 2

    ldx #0
ok_lp
    lda s_ok, x
    beq ok_done
    jsr CHROUT
    inx
    bne ok_lp
ok_done
    +cxm_exit

s_up    !text "SMOKE ACME UP"
        !byte 13, 0
s_ok    !text "SMOKE ACME OK"
        !byte 13, 0
s_hello !text "hi from acme, through the jump table"
        !byte 0

widgets
    +cxm_wcount widgets, widgets_end
    +cxm_wg_button 40, 240, 100, 24, s_btn
    +cxm_wg_hit   200, 240, 80, 80, CX_WH_CIRCLE, CX_WH_CLICK | CX_WH_HOVER
widgets_end
s_btn   !text "ok"
        !byte 0
