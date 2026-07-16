; ca65
; =====================================================================
; CXGEOS :: kernel/boot/auto.asm -- AUTOBOOT.X16, the stage-0 loader
; =====================================================================
; The stock KERNAL runs AUTOBOOT.X16 from the SD root at power-on --
; that is the entire boot hook, and the reason CXGEOS needs no ROM
; patch. This program:
;
;   1. LOADs CXKERNEL.PRG, whose own header says $8000, and checks the
;      "CXOS" magic before believing a word of it.
;   2. LOADs PXL8.CXF headerless into CX_SYSFONT_BANK:$A000, where
;      cx_init expects the system font (docs/memory-map.md).
;   3. Calls the init vector at $8008. If cx_init refuses the font it
;      says so here, in text mode, because cx_init judges the font
;      before touching the video mode for exactly this moment.
;   4. Hands off: AUTORUN.CXA if the disk has one -- a deliberate
;      override, and how the boot smoke test drives the whole chain --
;      otherwise cx_exit, which IS "go to the shell".
;
; Every failure path ends at an rts with a message: back to BASIC,
; where the machine still works and the words can be read.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

CX_SYSFONT_BANK = 1             ; the boot half of cx_init's contract

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

boot
    lda #<s_banner
    ldx #>s_banner
    jsr pmsg

    lda #s_kernel_len           ; the kernel, where its header says
    ldx #<s_kernel
    ldy #>s_kernel
    jsr SETNAM
    lda #1
    ldx #8
    ldy #1
    jsr SETLFS
    lda #0
    jsr LOAD
    bcs @nokernel

    ldy #3                      ; believe nothing without the magic
@magic
    lda $8000,y
    cmp s_cxos,y
    bne @nokernel
    dey
    bpl @magic

    lda #CX_SYSFONT_BANK        ; the font, raw, into the banked window
    sta RAM_BANK
    lda #s_font_len
    ldx #<s_font
    ldy #>s_font
    jsr SETNAM
    lda #1
    ldx #8
    ldy #2                      ; headerless: every byte, at the address
    jsr SETLFS                  ; given here
    lda #0
    ldx #<$A000
    ldy #>$A000
    jsr LOAD
    bcs @nofont

    jsr init                    ; the vector at $8008; carry back means
    bcs @nofont                 ; cx_init would not accept the font

    lda #<s_autorun             ; the override first; on a normal disk
    ldx #>s_autorun             ; it is not there and this returns at
    ldy #s_autorun_len          ; once with carry
    jsr cx_app_load
    jmp cx_exit                 ; and cx_exit IS "go to the shell"

@nokernel
    lda #<s_nok
    ldx #>s_nok
    jmp pmsg                    ; rts to BASIC

@nofont
    lda #<s_nof
    ldx #>s_nof
    jmp pmsg

init
    jmp ($8008)

; ---------------------------------------------------------------------
pmsg                            ; A/X = a string for the KERNAL
    sta $02                     ; r0: caller-save scratch
    stx $03
    ldy #0
@loop
    lda ($02),y
    beq @done
    jsr CHROUT
    iny
    bne @loop
@done
    rts

s_banner  .byte $0D, "CXGEOS BOOT", $0D, 0
s_cxos    .byte "CXOS"
s_kernel  .byte "CXKERNEL.PRG"
s_kernel_len = * - s_kernel
s_font    .byte "PXL8.CXF"
s_font_len = * - s_font
s_autorun .byte "AUTORUN.CXA"
s_autorun_len = * - s_autorun
s_nok     .byte "CXGEOS: NO CXKERNEL.PRG ON THIS DISK.", $0D, 0
s_nof     .byte "CXGEOS: PXL8.CXF IS MISSING OR NOT A FONT.", $0D, 0
