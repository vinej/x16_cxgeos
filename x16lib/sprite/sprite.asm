;ACME
; =====================================================================
; x16lib :: sprite/sprite.asm -- VERA hardware sprites
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; 128 sprites, an 8-byte attribute record each, at $1FC00:
;   0  image address bits 12:5
;   1  mode(7) | image address bits 16:13
;   2  X bits 7:0
;   3  X bits 9:8
;   4  Y bits 7:0
;   5  Y bits 9:8
;   6  collision mask(7:4) | Z-depth(3:2) | vflip(1) | hflip(0)
;   7  height(7:6) | width(5:4) | palette offset(3:0)
;
; That region is write-only: reads return the last value the host wrote.
; Read-modify-write therefore only works on records this program has
; already initialised. sprite_init_all does that.
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; sprite_setptr -- point data port 0 at one byte of a sprite record.
;   in:  X = sprite number (0-127), A = byte offset within the record
;   Leaves the port on auto-increment, so consecutive fields stream.
; ---------------------------------------------------------------------
sprite_setptr
    sta X16_T2                  ; byte offset
    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL               ; ADDRSEL = 0, DCSEL untouched

    stz X16_T1
    txa
    asl
    rol X16_T1
    asl
    rol X16_T1
    asl
    rol X16_T1                  ; T1:A = sprite * 8

    clc
    adc X16_T2
    sta VERA_ADDR_L
    lda X16_T1
    adc #>VRAM_SPRITE_ATTR      ; $FC, plus any carry from the offset
    sta VERA_ADDR_M
    lda #(VERA_ADDR_H_BANK | (VERA_INC_1 << 4))
    sta VERA_ADDR_H
    rts

; ---------------------------------------------------------------------
; sprites_on / sprites_off -- the sprite renderer as a whole
; ---------------------------------------------------------------------
sprites_on
    vera_dcsel 0
    lda #VERA_VIDEO_SPRITES_EN
    tsb VERA_DC_VIDEO
    rts

sprites_off
    vera_dcsel 0
    lda #VERA_VIDEO_SPRITES_EN
    trb VERA_DC_VIDEO
    rts

; ---------------------------------------------------------------------
; sprite_pos -- set a sprite's 10-bit position
;   in:  X = sprite
;        X16_P0/P1 = x, X16_P2/P3 = y
; ---------------------------------------------------------------------
sprite_pos
    lda #SPRITE_ATTR_X_L
    jsr sprite_setptr
    lda X16_P0
    sta VERA_DATA0
    lda X16_P1
    and #$03
    sta VERA_DATA0
    lda X16_P2
    sta VERA_DATA0
    lda X16_P3
    and #$03
    sta VERA_DATA0
    rts

; ---------------------------------------------------------------------
; sprite_get_pos -- read it back
;   in:  X = sprite
;   out: X16_P0/P1 = x, X16_P2/P3 = y
; ---------------------------------------------------------------------
sprite_get_pos
    lda #SPRITE_ATTR_X_L
    jsr sprite_setptr
    lda VERA_DATA0
    sta X16_P0
    lda VERA_DATA0
    and #$03
    sta X16_P1
    lda VERA_DATA0
    sta X16_P2
    lda VERA_DATA0
    and #$03
    sta X16_P3
    rts

; ---------------------------------------------------------------------
; sprite_image -- point a sprite at its pixel data in VRAM
;   in:  X = sprite
;        X16_P0 = addr low, X16_P1 = addr mid, X16_P2 = addr bit 16
;        A = SPRITE_MODE_4BPP or SPRITE_MODE_8BPP
;
; The record stores address bits 16:5, so the data must be 32-byte
; aligned; the low five bits are simply dropped.
; ---------------------------------------------------------------------
sprite_image
    sta X16_T3                  ; mode flag
    lda #SPRITE_ATTR_ADDR_L
    jsr sprite_setptr

    lda X16_P0
    lsr
    lsr
    lsr
    lsr
    lsr                         ; addr bits 7:5 -> 2:0
    sta X16_T4
    lda X16_P1
    asl
    asl
    asl                         ; addr bits 12:8 -> 7:3
    ora X16_T4
    sta VERA_DATA0              ; byte 0 = addr 12:5

    lda X16_P1
    lsr
    lsr
    lsr
    lsr
    lsr                         ; addr bits 15:13 -> 2:0
    sta X16_T4
    lda X16_P2
    and #$01
    asl
    asl
    asl                         ; addr bit 16 -> bit 3
    ora X16_T4
    ora X16_T3                  ; mode in bit 7
    sta VERA_DATA0              ; byte 1
    rts

; ---------------------------------------------------------------------
; sprite_flags -- byte 6: collision mask, Z-depth, flips
;   in:  X = sprite, A = collision<<4 | Z | vflip | hflip
;   e.g. lda #(SPRITE_Z_FRONT | SPRITE_HFLIP)
; ---------------------------------------------------------------------
sprite_flags
    sta X16_T3
    lda #SPRITE_ATTR_FLAGS
    jsr sprite_setptr
    lda X16_T3
    sta VERA_DATA0
    rts

; ---------------------------------------------------------------------
; sprite_z -- change only the Z-depth, preserving the other bits
;   in:  X = sprite, A = SPRITE_Z_DISABLED/BEHIND/MIDDLE/FRONT
;
; Read-modify-write. Only valid once the record has been written at
; least once (see the note at the top of this file).
; ---------------------------------------------------------------------
sprite_z
    sta X16_T3
    lda #SPRITE_ATTR_FLAGS
    jsr sprite_setptr
    lda VERA_DATA0              ; read advances the port past byte 6
    and #%11110011
    ora X16_T3
    sta X16_T4
    lda #SPRITE_ATTR_FLAGS
    jsr sprite_setptr           ; point at byte 6 again to write it
    lda X16_T4
    sta VERA_DATA0
    rts

; ---------------------------------------------------------------------
; sprite_size -- byte 7: size codes and palette offset
;   in:  X = sprite
;        A = width code (SPRITE_SIZE_8/16/32/64)
;        Y = height code
;        X16_P0 = palette offset (0-15)
; ---------------------------------------------------------------------
sprite_size
    and #$03
    asl
    asl
    asl
    asl                         ; width into bits 5:4
    sta X16_T3
    tya
    and #$03
    asl
    asl
    asl
    asl
    asl
    asl                         ; height into bits 7:6
    ora X16_T3
    sta X16_T3
    lda X16_P0
    and #$0F                    ; an offset >15 must not corrupt the size bits
    ora X16_T3
    sta X16_T3

    lda #SPRITE_ATTR_SIZE_PAL
    jsr sprite_setptr
    lda X16_T3
    sta VERA_DATA0
    rts

; ---------------------------------------------------------------------
; sprite_init_all -- zero all 128 attribute records.
;
; Disables every sprite and, more importantly, gives the write-only
; attribute RAM a known host-side shadow so sprite_z's read-modify-write
; is meaningful.
; ---------------------------------------------------------------------
sprite_init_all
    vera_addr 0, VRAM_SPRITE_ATTR, VERA_INC_1
    lda #0
    ldx #<(128 * 8)
    ldy #>(128 * 8)
    jmp vera_fill

; (end zone)
