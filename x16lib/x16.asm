; ca65
; =====================================================================
; x16lib :: x16.asm -- constants and macros (ca65 edition). No code.
; =====================================================================
; The ca65 port of the library mirrors the ACME tree file for file;
; src_acme/ is the reference implementation and this tree must behave
; identically -- the same test suite proves it.
;
;       .include "x16.asm"
;       X16_USE_VERA = 1            ; pick modules or a section gate
;       ...your code...
;       .include "x16_code.asm"     ; library routines land here
;
; Assemble and link (one translation unit, like ACME):
;       ca65 --cpu 65C02 -I src_ca65 -o prog.o prog.s
;       ld65 -C yourprog.cfg -o PROG.PRG prog.o
;
; labels_without_colons keeps the sources in the ACME shape: an
; identifier in column one is a label, no colon needed.
; =====================================================================

.ifndef X16_INC
X16_INC = 1

.setcpu "65C02"
.feature labels_without_colons

.include "core/const_zp.asm"
.include "core/const_vera.asm"
.include "core/const_kernal.asm"
.include "core/const_rom.asm"
.include "core/macros.asm"

.endif
