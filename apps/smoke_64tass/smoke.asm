; 64tass
; =====================================================================
; CXGEOS :: apps/smoke_64tass/smoke.asm -- the 64tass SDK smoke test
; =====================================================================
; Proves the GENERATED asmsdk/64tass layer assembles with the real
; 64tass and drives the kernel through the jump table. It prints a start
; marker, makes a spread of kernel calls through the cxm_* macros (word
; args, byte args, a pointer arg, the shape math, a descriptor builder),
; prints an OK marker if it survived them, and exits to the shell.
; Headless: the boot smoke greps stdout for "SMOKE 64TASS OK".
;
; x16lib's 64tass edition supplies X16_P0..P7, CHROUT and #basic_stub;
; the CXGEOS asmsdk/64tass supplies the cxm_* macros and CX_* constants.
;   64tass -C -a --cbm-prg -I . -I <x16_library/src_64tass> smoke.asm
; =====================================================================

.include "x16.asm"                      ; from src_64tass: X16_P0.., CHROUT, macros
.include "asmsdk/64tass/cxgeos.inc"     ; the generated friendly layer

* = $0801
    #basic_stub

main:
    ldx #0                              ; "started" marker -- load + run worked
up_lp:
    lda s_up, x
    beq up_done
    jsr CHROUT
    inx
    bne up_lp
up_done:
    #cxm_gfx_init                       ; a no-arg call
    #cxm_gfx_clear 0                    ; a byte arg (A)
    #cxm_say s_hello, 24, 200           ; a pointer arg + two word args
    #cxm_gfx_frame 20, 20, 300, 160, 3  ; four word args + a byte
    #cxm_gfx_circle 160, 120, 40, 3     ; a byte-into-P arg + the shape call
    #cxm_gfx_disc 260, 120, 20, 2

    ldx #0                              ; survived every call -> the pass line
ok_lp:
    lda s_ok, x
    beq ok_done
    jsr CHROUT
    inx
    bne ok_lp
ok_done:
    #cxm_exit                           ; back to the shell (self-exit)

s_up:    .text "SMOKE 64TASS UP", $0D, $00
s_ok:    .text "SMOKE 64TASS OK", $0D, $00
s_hello: .text "hi from 64tass, through the jump table", $00

; a descriptor list built with the generated builders -- proves they lay
; the records down (not exercised at runtime here; wg_set needs the event
; system, which this minimal smoke does not start)
widgets:
    #cxm_wcount widgets, widgets_end
    #cxm_wg_button 40, 240, 100, 24, s_btn
    #cxm_wg_hit   200, 240, 80, 80, CX_WH_CIRCLE, CX_WH_CLICK | CX_WH_HOVER
widgets_end:
s_btn:   .text "ok", $00
