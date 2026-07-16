;ACME
; =====================================================================
; x16lib :: core/const_zp.asm -- zero page and bank registers
; =====================================================================
; Pure symbol file. Safe to !source any number of times.
;
; X16 zero page (Programmer's Reference / x16-rom-r49 inc/regs.inc):
;   $00       RAM_BANK   - bank visible at $A000-$BFFF
;   $01       ROM_BANK   - bank visible at $C000-$FFFF
;   $02-$21   r0..r15    - KERNAL virtual registers (argument passing)
;   $22-$7F   free for user programs   <-- we claim 16 bytes here
;   $80-$FF   KERNAL / BASIC / DOS     <-- never touch
; =====================================================================

.ifndef X16_CONST_ZP
X16_CONST_ZP = 1

; (!addr block: plain assignments in ca65)
RAM_BANK        = $00
ROM_BANK        = $01

; KERNAL virtual registers. Caller-save: the library uses r0..r5 freely.
r0  = $02
r0L  = $02
r0H  = $03
r1  = $04
r1L  = $04
r1H  = $05
r2  = $06
r2L  = $06
r2H  = $07
r3  = $08
r3L  = $08
r3H  = $09
r4  = $0A
r4L  = $0A
r4H  = $0B
r5  = $0C
r5L  = $0C
r5H  = $0D
r6  = $0E
r6L  = $0E
r6H  = $0F
r7  = $10
r7L  = $10
r7H  = $11
r8  = $12
r8L  = $12
r8H  = $13
r9  = $14
r9L  = $14
r9H  = $15
r10 = $16
r10L = $16
r10H = $17
r11 = $18
r11L = $18
r11H = $19
r12 = $1A
r12L = $1A
r12H = $1B
r13 = $1C
r13L = $1C
r13H = $1D
r14 = $1E
r14L = $1E
r14H = $1F
r15 = $20
r15L = $20
r15H = $21
; (end addr)

; ---------------------------------------------------------------------
; Library scratch block.
;
; Define X16_ZP yourself *before* sourcing x16.asm to relocate it, e.g.
;       X16_ZP = $60
;       .include "x16.asm"
; It must sit inside $22-$7F and needs X16_ZP_SIZE bytes.
; ---------------------------------------------------------------------
.ifndef X16_ZP
X16_ZP = $22
.endif

X16_ZP_SIZE = 16

; (!addr block: plain assignments in ca65)
; P0..P7: routine parameters (for calls that need more than A/X/Y).
X16_P0 = X16_ZP + 0
X16_P1 = X16_ZP + 1
X16_P2 = X16_ZP + 2
X16_P3 = X16_ZP + 3
X16_P4 = X16_ZP + 4
X16_P5 = X16_ZP + 5
X16_P6 = X16_ZP + 6
X16_P7 = X16_ZP + 7

; T0..T7: private scratch. Never live across a library call boundary.
X16_T0 = X16_ZP + 8
X16_T1 = X16_ZP + 9
X16_T2 = X16_ZP + 10
X16_T3 = X16_ZP + 11
X16_T4 = X16_ZP + 12
X16_T5 = X16_ZP + 13
X16_T6 = X16_ZP + 14
X16_T7 = X16_ZP + 15
; (end addr)

; 16-bit aliases over the same bytes.
; (!addr block: plain assignments in ca65)
X16_PTR0 = X16_P0       ; P0/P1 as a pointer
X16_PTR1 = X16_P2       ; P2/P3 as a pointer
X16_PTR2 = X16_P4
X16_PTR3 = X16_P6
X16_TPTR0 = X16_T0
X16_TPTR1 = X16_T2
X16_TPTR2 = X16_T4
X16_TPTR3 = X16_T6
; (end addr)

.if X16_ZP < $22
    !error "X16_ZP must be >= $22 (below that is KERNAL r0..r15)"
.endif
.if (X16_ZP + X16_ZP_SIZE) > $80
    !error "X16_ZP block runs past $7F into KERNAL/BASIC zero page"
.endif

.endif