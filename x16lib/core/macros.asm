; ca65
; =====================================================================
; x16lib :: core/macros.asm -- inlined plumbing (ca65 edition)
; =====================================================================
; The ca65 port of src_acme/core/macros.asm; the macro layer is the
; same one the dist bindings carry (dist/templates/ca65-macros.inc).
; =====================================================================

.ifndef X16_MACROS_INC
X16_MACROS_INC = 1

; ---------------------------------------------------------------------
; x16lib macro layer, hand-ported from src/core/macros.asm for ca65.
;
; Requires the 65C02 instruction set (trb/tsb):
;       .setcpu "65C02"
; or assemble with:  ca65 --cpu 65C02
;
; Symbols are case sensitive: the jsrfar MACRO wraps the KERNAL's
; JSRFAR entry point CONSTANT.
; ---------------------------------------------------------------------

; select which data port the ADDR registers refer to (clobbers A).
; ADDRSEL is bit 0 of CTRL; a read-modify-write via trb/tsb keeps DCSEL.
.macro vera_addrsel port
        lda #VERA_CTRL_ADDRSEL
        .if (port) = 0
        trb VERA_CTRL
        .else
        tsb VERA_CTRL
        .endif
.endmacro

; select the $9F29-$9F2C register bank (0-63). Preserves ADDRSEL.
; Never writes bit 7 (that resets VERA).
.macro vera_dcsel n
        .if (n) > 63
        .error "DCSEL must be 0-63"
        .endif
        lda VERA_CTRL
        and #VERA_CTRL_ADDRSEL
        ora #((n) << 1)
        sta VERA_CTRL
.endmacro

; point a data port at a 17-bit VRAM address. `inc` is an INDEX, not a
; byte count -- use the VERA_INC_* constants.
.macro vera_addr port, addr, inc
        .if (addr) > $1FFFF
        .error "VRAM address must be 17-bit"
        .endif
        .if (inc) > 15
        .error "use a VERA_INC_* constant, not a byte count"
        .endif
        vera_addrsel port
        lda #<(addr)
        sta VERA_ADDR_L
        lda #>(addr)
        sta VERA_ADDR_M
        lda #((((addr) >> 16) & $01) | ((inc) << 4))
        sta VERA_ADDR_H
.endmacro

; the same, but decrementing.
.macro vera_addr_decr port, addr, inc
        vera_addrsel port
        lda #<(addr)
        sta VERA_ADDR_L
        lda #>(addr)
        sta VERA_ADDR_M
        lda #((((addr) >> 16) & $01) | VERA_ADDR_H_DECR | ((inc) << 4))
        sta VERA_ADDR_H
.endmacro

; one-off VRAM byte write. Clobbers A, flags.
.macro vpoke addr, value
        vera_addr 0, addr, VERA_INC_0
        lda #(value)
        sta VERA_DATA0
.endmacro

.macro set_rambank n
        lda #(n)
        sta RAM_BANK
.endmacro

.macro set_rombank n
        lda #(n)
        sta ROM_BANK
.endmacro

; call a routine in another ROM/RAM bank via the KERNAL's own $FF6E
; mechanism. Preserves A/X/Y and flags, reentrant. Do NOT hand-roll
; the bank switch -- see src/core/macros.asm for why.
.macro jsrfar addr, bank
        jsr JSRFAR
        .word addr
        .byte bank
.endmacro

; ~40 cycles cheaper than jsrfar, but CLOBBERS A and leaves ROM_BANK
; set to `bank`. Not IRQ-safe.
.macro rom_call_fast bank, entry
        lda #(bank)
        sta ROM_BANK
        jsr entry
.endmacro

; load a 16-bit literal into a 2-byte little-endian buffer (i16_a etc.)
.macro i16_const dest, value
        lda #<(value)
        sta dest
        lda #>(value)
        sta dest+1
.endmacro

; load a 32-bit literal into a 4-byte little-endian buffer (i32_a etc.)
.macro i32_const dest, value
        lda #<(value)
        sta dest
        lda #>(value)
        sta dest+1
        lda #(((value) >> 16) & $FF)
        sta dest+2
        lda #(((value) >> 24) & $FF)
        sta dest+3
.endmacro

; emit `10 SYS 2061` so the PRG autoruns. Must land at exactly $0801;
; machine code then begins at $080D (= 2061).
.macro basic_stub
        .word $080B             ; link to the end-of-program marker
        .word 10                ; line number
        .byte $9E               ; SYS token
        .byte "2061"            ; = $080D
        .byte $00               ; end of line
        .word $0000             ; end of program
.endmacro

.endif
