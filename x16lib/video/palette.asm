;ACME
; =====================================================================
; x16lib :: video/palette.asm -- VERA palette
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; 256 entries of two bytes at $1FA00:
;       byte 0 = Green<<4 | Blue
;       byte 1 = Red             (high nibble unused)
;
; So a 12-bit $0RGB colour stores little-endian exactly as written:
; $0F00 is pure red, $00F0 pure green, $000F pure blue.
;
; Caution: $1F9C0-$1FFFF is write-only. Reading an entry returns the
; last value the host wrote there, not what the hardware holds -- fine
; for reading back your own writes, useless for discovering the state
; after a reset.
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; pal_set
;   in:  X = palette index (0-255)
;        A = low byte  (Green<<4 | Blue)
;        Y = high byte (Red)
;
;   To set entry 1 to pure red ($0F00):
;       ldx #1 : lda #$00 : ldy #$0F : jsr pal_set
; ---------------------------------------------------------------------
pal_set
    sta X16_T0                  ; colour low
    sty X16_T1                  ; colour high

    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL               ; ADDRSEL = 0 (leaves DCSEL alone)

    txa
    asl                         ; entry index * 2; carry = address bit 8
    tax
    lda #>VRAM_PALETTE          ; $FA
    adc #0                      ; carry from the asl rolls it to $FB
    stx VERA_ADDR_L
    sta VERA_ADDR_M
    lda #(VERA_ADDR_H_BANK | (VERA_INC_1 << 4))   ; $1FA00 is in bank 1
    sta VERA_ADDR_H

    lda X16_T0
    sta VERA_DATA0
    lda X16_T1
    sta VERA_DATA0
    rts

; ---------------------------------------------------------------------
; pal_load -- bulk-load palette entries from RAM.
;   in:  X16_PTR0 = source address (2 bytes per entry, low byte first)
;        A = first palette index
;        X = entry count (1-128; 0 loads nothing)
; ---------------------------------------------------------------------
pal_load
    cpx #0                      ; count 0 loads nothing -- without this
    beq @done                   ; guard the loop would run 256 times and
    stx X16_T2                  ; shred the whole palette

    tax                         ; X = first index
    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL
    txa
    asl
    tax
    lda #>VRAM_PALETTE
    adc #0
    stx VERA_ADDR_L
    sta VERA_ADDR_M
    lda #(VERA_ADDR_H_BANK | (VERA_INC_1 << 4))
    sta VERA_ADDR_H

    ldy #0
@loop
    lda (X16_PTR0),y
    sta VERA_DATA0              ; low byte
    iny
    lda (X16_PTR0),y
    sta VERA_DATA0              ; high byte
    iny
    dec X16_T2
    bne @loop
@done
    rts

; (end zone)
