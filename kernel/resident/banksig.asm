; ca65
; =====================================================================
; CXGEOS :: kernel/resident/banksig.asm -- who is in each bank, signed
; =====================================================================
; Two kinds of pin, both checked by stage-0 (kernel/boot/auto.asm):
;
;   KBUILD  the build word at $81A5 -- the tail of the jump-table
;           reserve, so it rides CXKERNEL.PRG and costs the resident
;           budget nothing. Stage-0 compares it against its own
;           CX_KBUILD right after the CXOS magic. (It moves with the
;           reserve's end; auto.asm reads the same address.)
;
;   BnnSIG  an 8-byte header at $A000 of every CXBANKS2 bank:
;           "CXB", the bank number, the build word, then the bank's
;           code size as a change fingerprint (not checked at boot;
;           it is there for debuggers and future loaders).
;           CXBANKS.BIN's twin lives at 2:$A040 in kernel/ui/menu.asm,
;           behind the peekable state block.
;
; The anchors: one rts per BnnCODE keeps each segment alive so ld65
; defines __BnnCODE_SIZE__ before any real module moves in. They cost
; one byte each and the far-called modules that arrive later land
; right behind them.

.import __B16CODE_SIZE__, __B17CODE_SIZE__
.import __B18CODE_SIZE__, __B19CODE_SIZE__

.segment "KBUILD"
    .word CX_KBUILD

.segment "B16SIG"
    .byte "CXB", CX_WG_BANK
    .word CX_KBUILD
    .word __B16CODE_SIZE__
.segment "B16CODE"
b16_anchor
    rts

.segment "B17SIG"
    .byte "CXB", CX_GFXX_BANK
    .word CX_KBUILD
    .word __B17CODE_SIZE__
.segment "B17CODE"
b17_anchor
    rts

.segment "B18SIG"
    .byte "CXB", CX_FS_BANK
    .word CX_KBUILD
    .word __B18CODE_SIZE__
.segment "B18CODE"
b18_anchor
    rts

.segment "B19SIG"
    .byte "CXB", CX_AUD_BANK
    .word CX_KBUILD
    .word __B19CODE_SIZE__
.segment "B19CODE"
b19_anchor
    rts

.segment "CODE"
