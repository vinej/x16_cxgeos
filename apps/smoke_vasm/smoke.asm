; vasm oldstyle
; =====================================================================
; CXRF :: apps/smoke_vasm/smoke.asm -- the vasm SDK smoke test
; =====================================================================
; Proves the GENERATED asmsdk/vasm layer assembles with the real
; vasm6502_oldstyle and drives the kernel through the jump table.
; -Fbin -cbm-prg writes the PRG (load address + image) directly. Headless:
; the boot smoke greps stdout for "SMOKE VASM OK".
;   vasm6502_oldstyle -c02 -Fbin -cbm-prg -I . -I <src_vasm> -o OUT smoke.asm
; =====================================================================

    include "x16.asm"                   ; from src_vasm: X16_P0.., CHROUT, basic_stub
    include "asmsdk/vasm/cxrf.inc"    ; the generated friendly layer

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

s_up    byte "SMOKE VASM UP", 13, 0
s_ok    byte "SMOKE VASM OK", 13, 0
s_hello byte "hi from vasm, through the jump table", 0

widgets
    cxm_wcount widgets, widgets_end
    cxm_wg_button 40, 240, 100, 24, s_btn
    cxm_wg_hit   200, 240, 80, 80, CX_WH_CIRCLE, CX_WH_CLICK | CX_WH_HOVER
widgets_end
s_btn   byte "ok", 0
