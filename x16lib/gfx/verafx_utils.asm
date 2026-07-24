;ACME
; =====================================================================
; x16lib :: gfx/verafx_utils.asm -- low-level VERA FX primitives
; =====================================================================
; Gate: X16_USE_VERAFX_UTILS
;
; These are raw building blocks for custom FX workflows: FX_CTRL/MULT
; control, cache fill/write/cycle toggles, 32-bit cache loading,
; multiplier accumulator triggers, increment/position registers, 16-bit
; hop, and polygon-fill reads.
;
; They are deliberately separate from X16_USE_VERAFX. The existing gate
; remains the high-level helper bundle; this file is for code that wants
; to compose the documented FX registers directly.
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; fxu_off -- disable FX helpers and return to DCSEL 0
; ---------------------------------------------------------------------
fxu_off
    vera_dcsel 2
    stz VERA_FX_CTRL
    stz VERA_FX_MULT
    vera_dcsel 0
    rts

; ---------------------------------------------------------------------
; FX_CTRL helpers
; ---------------------------------------------------------------------
fxu_get_ctrl
    vera_dcsel 2
    lda VERA_FX_CTRL
    sta X16_T0
    vera_dcsel 0
    lda X16_T0
    rts

fxu_set_ctrl
    pha
    vera_dcsel 2
    pla
    sta VERA_FX_CTRL
    vera_dcsel 0
    rts

fxu_ctrl_on
    pha
    vera_dcsel 2
    pla
    tsb VERA_FX_CTRL
    vera_dcsel 0
    rts

fxu_ctrl_off
    pha
    vera_dcsel 2
    pla
    trb VERA_FX_CTRL
    vera_dcsel 0
    rts

; fxu_addr1_mode -- set only the FX_CTRL Addr1 Mode field
;   in: A = VERA_FX_ADDR1_* value
fxu_addr1_mode
    and #%00000011
    sta X16_T0
    vera_dcsel 2
    lda VERA_FX_CTRL
    and #%11111100
    ora X16_T0
    sta VERA_FX_CTRL
    vera_dcsel 0
    rts

fxu_cache_write_on
    lda #VERA_FX_CACHE_WRITE
    jmp fxu_ctrl_on

fxu_cache_write_off
    lda #VERA_FX_CACHE_WRITE
    jmp fxu_ctrl_off

fxu_cache_fill_on
    lda #VERA_FX_CACHE_FILL
    jmp fxu_ctrl_on

fxu_cache_fill_off
    lda #VERA_FX_CACHE_FILL
    jmp fxu_ctrl_off

fxu_cache_cycle_on
    lda #VERA_FX_CACHE_CYCLE
    jmp fxu_ctrl_on

fxu_cache_cycle_off
    lda #VERA_FX_CACHE_CYCLE
    jmp fxu_ctrl_off

fxu_transparent_on
    lda #VERA_FX_TRANSPARENT
    jmp fxu_ctrl_on

fxu_transparent_off
    lda #VERA_FX_TRANSPARENT
    jmp fxu_ctrl_off

fxu_4bit_on
    lda #VERA_FX_4BIT_MODE
    jmp fxu_ctrl_on

fxu_4bit_off
    lda #VERA_FX_4BIT_MODE
    jmp fxu_ctrl_off

fxu_hop_on
    lda #VERA_FX_16BIT_HOP
    jmp fxu_ctrl_on

fxu_hop_off
    lda #VERA_FX_16BIT_HOP
    jmp fxu_ctrl_off

; ---------------------------------------------------------------------
; FX_MULT / cache helpers
; ---------------------------------------------------------------------
fxu_set_mult
    pha
    vera_dcsel 2
    pla
    sta VERA_FX_MULT
    vera_dcsel 0
    rts

; fxu_set_cache -- set all four bytes of the 32-bit cache
;   in: X16_P0..P3 = cache L, M, H, U
fxu_set_cache
    vera_dcsel 6
    lda X16_P0
    sta VERA_FX_CACHE_L
    lda X16_P1
    sta VERA_FX_CACHE_M
    lda X16_P2
    sta VERA_FX_CACHE_H
    lda X16_P3
    sta VERA_FX_CACHE_U
    vera_dcsel 0
    rts

; fxu_reset_accum -- clear the multiplier accumulator
fxu_reset_accum
    vera_dcsel 6
    lda VERA_FX_ACCUM_RESET
    vera_dcsel 0
    rts

; fxu_accumulate -- trigger multiply-then-accumulate
fxu_accumulate
    vera_dcsel 6
    lda VERA_FX_ACCUM
    vera_dcsel 0
    rts

; fxu_cache_fill0/1 -- read DATA0/1, filling the cache when enabled
;   out: A = byte read from the selected data port
fxu_cache_fill0
    lda VERA_DATA0
    rts

fxu_cache_fill1
    lda VERA_DATA1
    rts

; fxu_cache_write0/1 -- write DATA0/1, flushing the cache when enabled
;   in: A = cache nibble mask
fxu_cache_write0
    sta VERA_DATA0
    rts

fxu_cache_write1
    sta VERA_DATA1
    rts

; ---------------------------------------------------------------------
; Increment, position, tile/map, and polygon-fill helpers
; ---------------------------------------------------------------------
; fxu_set_incr -- set X/Y increment registers
;   in: X16_P0/P1 = X increment, X16_P2/P3 = Y increment
fxu_set_incr
    vera_dcsel 3
    lda X16_P0
    sta VERA_FX_X_INCR_L
    lda X16_P1
    sta VERA_FX_X_INCR_H
    lda X16_P2
    sta VERA_FX_Y_INCR_L
    lda X16_P3
    sta VERA_FX_Y_INCR_H
    vera_dcsel 0
    rts

; fxu_set_pos -- set X/Y position registers
;   in: X16_P0/P1 = X position, X16_P2/P3 = Y position
fxu_set_pos
    vera_dcsel 4
    lda X16_P0
    sta VERA_FX_X_POS_L
    lda X16_P1
    sta VERA_FX_X_POS_H
    lda X16_P2
    sta VERA_FX_Y_POS_L
    lda X16_P3
    sta VERA_FX_Y_POS_H
    vera_dcsel 0
    rts

; fxu_set_subpos -- set X/Y subpixel registers
;   in: A = X subpixel, X = Y subpixel
fxu_set_subpos
    sta X16_T0
    stx X16_T1
    vera_dcsel 5
    lda X16_T0
    sta VERA_FX_X_POS_S
    lda X16_T1
    sta VERA_FX_Y_POS_S
    vera_dcsel 0
    rts

; fxu_get_poly_fill -- read polygon fill length
;   out: A = low byte/nibble pattern, X = high byte
fxu_get_poly_fill
    vera_dcsel 5
    lda VERA_FX_POLY_FILL_L
    sta X16_T0
    lda VERA_FX_POLY_FILL_H
    sta X16_T1
    vera_dcsel 0
    lda X16_T0
    ldx X16_T1
    rts

; fxu_set_tilebase / fxu_set_mapbase -- raw affine base register writes
;   in: A = precomposed FX_TILEBASE/FX_MAPBASE value
fxu_set_tilebase
    pha
    vera_dcsel 2
    pla
    sta VERA_FX_TILEBASE
    vera_dcsel 0
    rts

fxu_set_mapbase
    pha
    vera_dcsel 2
    pla
    sta VERA_FX_MAPBASE
    vera_dcsel 0
    rts

; (end zone)
