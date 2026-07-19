; ca65
; =====================================================================
; CXGEOS :: kernel/boot/auto.asm -- AUTOBOOT.X16, the stage-0 loader
; =====================================================================
; The stock KERNAL runs AUTOBOOT.X16 from the SD root at power-on --
; that is the entire boot hook, and the reason CXGEOS needs no ROM
; patch. This program:
;
;   1. LOADs CXKERNEL.PRG, whose own header says $8000, and checks the
;      "CXOS" magic AND the build word at $815C before believing a
;      word of it -- four kernel files ship together, and a card with
;      yesterday's copy of one must refuse here, in text mode, not
;      crash in a far call later.
;   2. LOADs CXBANKS.BIN raw into banks 2-5 and checks its signature
;      at 2:$A040 against the same build word.
;   3. LOADs CXBANKS2.BIN raw into banks 16-19 and checks the
;      signature at $A000 of EVERY bank -- the KERNAL wraps a banked
;      LOAD at $BFFF on its own, and a bank whose signature is missing
;      means the wrap stopped short of it.
;   4. LOADs PXL8.CXF headerless into CX_SYSFONT_BANK:$A000, where
;      cx_init expects the system font (docs/memory-map.md).
;   5. Calls the init vector at $8008. If cx_init refuses the font it
;      says so here, in text mode, because cx_init judges the font
;      before touching the video mode for exactly this moment.
;   6. Hands off: AUTORUN.CXA if the disk has one -- a deliberate
;      override, and how the boot smoke test drives the whole chain --
;      otherwise cx_exit, which IS "go to the shell".
;
; Every failure path ends at an rts with a message: back to BASIC,
; where the machine still works and the words can be read.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"
.include "kernel/resident/banks.inc"

CX_SYSFONT_BANK = 1             ; the boot half of cx_init's contract
SIGP = $04                      ; r1: sigchk's pointer, scratch at boot

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

    lda $81A5                   ; ...or without the build word: the KB
    cmp #<CX_KBUILD             ; region in kernel.cfg, compared against
    bne @skew                   ; the CX_KBUILD this stage-0 was built
    lda $81A6                   ; with -- a stale CXKERNEL.PRG stops here
    cmp #>CX_KBUILD
    bne @skew
    bra @banks

; -- near error exits: a 6502 branch reaches 127 bytes and the boot
;    walk outgrew one island at the end, so the early checks land here --
@nokernel
    lda #<s_nok
    ldx #>s_nok
    jmp pmsg                    ; rts to BASIC
@skew
    lda #<s_skew
    ldx #>s_skew
    jmp pmsg
@nobanks
    lda #<s_nob
    ldx #>s_nob
    jmp pmsg

@banks
    lda #2                      ; the kernel's banked code, raw, into
    sta RAM_BANK                ; bank 2 -- the KERNAL wraps into bank 3
    lda #s_banks_len            ; and onward by itself when it grows
    ldx #<s_banks
    ldy #>s_banks
    jsr SETNAM
    lda #1
    ldx #8
    ldy #2
    jsr SETLFS
    lda #0
    ldx #<$A000
    ldy #>$A000
    jsr LOAD
    bcs @nobanks

    lda #$40                    ; its signature, at 2:$A040 behind the
    sta SIGP                    ; peekable state block (menu.asm b2_sig)
    lda #$A0
    sta SIGP+1
    lda #2
    jsr sigchk
    bcs @skew

    lda #16                     ; the second banked file, raw, into
    sta RAM_BANK                ; banks 16-19 -- the same KERNAL wrap
    lda #s_banks2_len
    ldx #<s_banks2
    ldy #>s_banks2
    jsr SETNAM
    lda #1
    ldx #8
    ldy #2
    jsr SETLFS
    lda #0
    ldx #<$A000
    ldy #>$A000
    jsr LOAD
    bcs @nobanks2

    stz SIGP                    ; every bank made it? "CXB",bank,build
    lda #$A0                    ; opens each of 16-19; a bank without
    sta SIGP+1                  ; its signature means the wrap stopped
    lda #16                     ; short, or the file is from another
@probe                          ; build
    jsr sigchk
    bcs @stale
    inc
    cmp #20
    bne @probe

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

@nofont
    lda #<s_nof
    ldx #>s_nof
    jmp pmsg

@nobanks2
    lda #<s_nob2
    ldx #>s_nob2
    jmp pmsg

@stale
    lda #<s_stale
    ldx #>s_stale
    jmp pmsg

init
    jmp ($8008)

; ---------------------------------------------------------------------
; sigchk -- the six-byte bank signature: "CXB", the bank, CX_KBUILD.
; A = the expected bank (also set into RAM_BANK); SIGP = the address.
; Carry set on any mismatch; A holds the bank again on the way out.
; ---------------------------------------------------------------------
sigchk
    sta RAM_BANK
    sta sig_exp+3
    ldy #5
@cmp
    lda (SIGP),y
    cmp sig_exp,y
    bne @bad
    dey
    bpl @cmp
    clc
    lda sig_exp+3
    rts
@bad
    sec
    rts

sig_exp   .byte "CXB", 0
          .word CX_KBUILD

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
s_banks   .byte "CXBANKS.BIN"
s_banks_len = * - s_banks
s_banks2  .byte "CXBANKS2.BIN"
s_banks2_len = * - s_banks2
s_autorun .byte "AUTORUN.CXA"
s_autorun_len = * - s_autorun
s_nok     .byte "CXGEOS: NO CXKERNEL.PRG ON THIS DISK.", $0D, 0
s_nof     .byte "CXGEOS: PXL8.CXF IS MISSING OR NOT A FONT.", $0D, 0
s_nob     .byte "CXGEOS: NO CXBANKS.BIN ON THIS DISK.", $0D, 0
s_nob2    .byte "CXGEOS: NO CXBANKS2.BIN ON THIS DISK.", $0D, 0
s_skew    .byte "CXGEOS: KERNEL FILES OUT OF STEP.", $0D, 0
s_stale   .byte "CXGEOS: CXBANKS2.BIN IS STALE OR SHORT.", $0D, 0
