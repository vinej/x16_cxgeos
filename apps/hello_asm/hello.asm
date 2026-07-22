; ca65
; =====================================================================
; CXRF :: apps/hello_asm/hello.asm -- the assembly hello
; =====================================================================
; The Phase 4 milestone app: built from the SDK alone, launched by the
; shell, draws through the jump table, and leaves through cx_exit --
; which reloads the shell, closing the loop the whole phase exists to
; prove. Any key returns at once; three seconds return anyway, so the
; loop closes even with nobody at the keyboard.
;
; Written with the asmsdk macros (asmsdk/ca65): one line a call, so the
; drawing reads as what it draws.
; =====================================================================

.include "x16.asm"
.include "asmsdk/ca65/cxrf.inc"

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    ldx #0
@mk
    lda s_marker,x
    beq @go
    jsr CHROUT
    inx
    bne @mk
@go
    cxm_gfx_clear 1                 ; a different paper than the shell's, so the
                               ; handoff is visible from across the room
    cxm_version                ; the kernel introduces itself: A is the
    clc                        ; version low byte, and under ten it is
    adc #'0'                   ; one digit
    sta s_ver

    cxm_say s_hello, 24, 200
    cxm_say s_abi,   24, 224
    cxm_say s_bye,   24, 260

    cxm_ev_init
    cxm_ev_frames
    sta frame0

wait
    cxm_ev_get
    bcs @tick
    lda X16_P0
    cmp #CX_ET_KEY
    beq bye
@tick
    cxm_ev_frames
    sec
    sbc frame0
    cmp #180                    ; three seconds at 60 Hz
    bcc wait
bye
    cxm_exit

frame0   .byte 0
s_marker .byte "HELLO ASM UP", $0D, 0
s_hello  .byte "hello from ca65, through the jump table.", 0
s_abi    .byte "the kernel says this is ABI version "
s_ver    .byte "?", 0
s_bye    .byte "a key -- or three seconds -- returns to the shell.", 0
