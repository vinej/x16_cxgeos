; ca65
; =====================================================================
; CXGEOS :: kernel/video/sprite.asm -- VERA hardware sprites, in bank 19
; =====================================================================
; The x16lib sprite module rides bank 19 behind resident far-call stubs,
; sharing the audio/sprites theme bank with kernel/audio/audio.asm
; (banks.inc). The gate X16_USE_SPRITE stays off in kernel.asm; the
; source is .included here inside B19CODE.
;
; Policy: sprite 0 is the KERNAL's mouse pointer (image at $13000). Apps
; drive sprites 1-127 and place their image data in the $1E000 VRAM region
; the ledger reserves (docs/memory-map.md). sprite_init_all is NOT exposed
; -- it zeroes all 128 records, sprite 0 included, and would lose the
; pointer; an app initialises each of its own sprites by setting the
; fields (image, size, position, flags) directly.
; =====================================================================

CX_SPRITE_BANK = CX_AUD_BANK    ; bank 19 (banks.inc)

; --- the resident far-call stubs (CODE) ------------------------------
cx_do_sprite_image
    jsr cxb_call
    .byte CX_SPRITE_BANK
    .addr sprite_image
cx_do_sprite_pos
    jsr cxb_call
    .byte CX_SPRITE_BANK
    .addr sprite_pos
cx_do_sprite_size
    jsr cxb_call
    .byte CX_SPRITE_BANK
    .addr sprite_size
cx_do_sprite_flags
    jsr cxb_call
    .byte CX_SPRITE_BANK
    .addr sprite_flags
cx_do_sprite_z
    jsr cxb_call
    .byte CX_SPRITE_BANK
    .addr sprite_z

; --- sprites_reset (resident) ----------------------------------------
; Disable app sprites 1-127 by zeroing each record's flags byte (Z-depth
; 0 = off). The loader calls it between apps so a sprite one app left on
; does not linger under the next; sprite 0 is the mouse, which mouse_hide
; handles. Write-only VERA, stepping 8 bytes to the next flags byte.
SPR1_FLAGS = VRAM_SPRITE_ATTR + 8 + SPRITE_ATTR_FLAGS
sprites_reset
    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL               ; ADDRSEL = 0, DCSEL untouched
    lda #<SPR1_FLAGS
    sta VERA_ADDR_L
    lda #>SPR1_FLAGS
    sta VERA_ADDR_M
    lda #((^SPR1_FLAGS & $01) | (VERA_INC_8 << 4))
    sta VERA_ADDR_H
    ldx #127
    lda #0
@loop
    sta VERA_DATA0
    dex
    bne @loop
    rts

; --- the banked code (B19CODE) ---------------------------------------
.segment "B19CODE"
.include "sprite/sprite.asm"
.segment "CODE"
