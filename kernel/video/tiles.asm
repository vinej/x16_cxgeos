; ca65
; =====================================================================
; CXGEOS :: kernel/video/tiles.asm -- mode 2: the tile engine
; =====================================================================
; The third personality behind the graphics port, and the one games
; want: two VERA tile layers at 320x240 with hardware scrolling, plus
; the sprites and audio the ABI already carries. It is NOT a bitmap --
; the port's drawing entries refuse here (carry), and the real API is
; the cx_tile_* slots, far-called into bank 5 beside the shapes.
;
; The mode's VRAM ledger (the framebuffer region is free -- no bitmap):
;   $00000  tile images: 4bpp 8x8, 32 bytes each, up to 1024 tiles
;           (upload with cx_vram_write)
;   $08000  layer 0's map: 64x32 cells, 2 bytes each (4 KB)
;   $09000  layer 1's map: same shape
;
; A cell word is VERA's: tile index low byte; high byte = index bits
; 9:8, then h-flip(2), v-flip(3), palette offset(7:4).
; =====================================================================

.ifndef CX_NO_OVERLAY

CX_T2_BANK = 5

cx_do_tile_setup
    jsr cxb_call
    .byte CX_T2_BANK
    .addr tile2_setup
cx_do_tile_scroll
    jsr cxb_call
    .byte CX_T2_BANK
    .addr tile2_scroll
cx_do_tile_cell
    jsr cxb_call
    .byte CX_T2_BANK
    .addr tile2_cell
cx_do_tile_fill
    jsr cxb_call
    .byte CX_T2_BANK
    .addr tile2_fill

; --- the engine image: a vector of refusals around a real init --------
.segment "OV2CODE"

ov2_vector
    jmp ov2_init
    jmp ov2_no                  ; clear      } bitmap drawing has no
    jmp ov2_no                  ; pset       } meaning on a tile canvas:
    jmp ov2_no                  ; read       } the map IS the picture.
    jmp ov2_no                  ; hline      } cx_tile_* is the API here,
    jmp ov2_no                  ; vline      } and cx_gfx_info still
    jmp ov2_no                  ; rect       } answers (320x240, 0 bpp)
    jmp ov2_no                  ; frame
    jmp ov2_no                  ; line
    jmp ov2_no                  ; pattern set
    jmp ov2_no                  ; pattern rect
    jmp ov2_no                  ; blit
    jmp ov2_no                  ; masked blit
    jmp ov2_no                  ; text -- tile-based text is future
    jmp ov2_no                  ; measure -- likewise
    jmp ov2_no                  ; rsave -- no save-under on a tile canvas
    jmp ov2_no                  ; rrest
    .byte 1                     ; cxov_ink -- unused here, carried so the
                                ; port layout is the same in every image
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0            ; UI metrics (toolkit gated off)

.assert ov2_vector = CX_OVL, error, "OV2CODE must start at CX_OVL"

ov2_init                        ; 320x240, both layers off until asked
    vera_dcsel 0
    lda #$40
    sta VERA_DC_HSCALE
    sta VERA_DC_VSCALE
    stz VERA_DC_BORDER
    lda #(VERA_VIDEO_LAYER0_EN | VERA_VIDEO_LAYER1_EN)
    trb VERA_DC_VIDEO           ; cx_tile_setup turns a layer on
    rts

ov2_no
    sec
    rts

; --- the tile machinery (bank 5, with the shapes) ---------------------
.segment "B5CODE"

.include "video/tile.asm"

; every entry is mode-gated: the maps and layer registers only mean
; this when the tile personality owns the screen
tile2_guard
    lda cx_vmode
    cmp #2
    rts

; cx_tile_setup -- A = layer (0/1): the ledger config, layer on
tile2_setup
    pha
    jsr tile2_guard
    beq @ok
    pla
    sec
    rts
@ok
    pla
    and #1
    pha
    tax
    lda #$12                    ; 64x32 map, 8x8 tiles, 4bpp
    jsr layer_set_config
    plx
    phx
    lda t2_mapb,x               ; mapbase $08000 / $09000 (addr >> 9)
    jsr layer_set_mapbase
    plx
    phx
    lda #0                      ; tilebase $00000, 8x8
    jsr layer_set_tilebase
    pla
    jsr layer_on
    clc
    rts

; cx_tile_scroll -- A = layer, P0/P1 = h, P2/P3 = v
tile2_scroll
    pha
    jsr tile2_guard
    beq @ok
    pla
    sec
    rts
@ok
    pla
    and #1
    pha
    tax
    jsr layer_scroll_x          ; reads P0/P1
    lda X16_P2
    sta X16_P0
    lda X16_P3
    sta X16_P1
    plx
    jsr layer_scroll_y          ; ...which also reads P0/P1
    clc
    rts

; cx_tile_cell -- A = layer, X = col (0-63), Y = row (0-31),
;                 P0/P1 = the cell word
tile2_cell
    pha
    jsr tile2_guard
    beq @ok
    pla
    sec
    rts
@ok
    pla
    jsr t2_point                ; port 0 at the cell, INC_1
    lda X16_P0
    sta VERA_DATA0
    lda X16_P1
    sta VERA_DATA0
    clc
    rts

; cx_tile_fill -- A = layer, P0/P1 = the cell word, every cell
tile2_fill
    pha
    jsr tile2_guard
    beq @ok
    pla
    sec
    rts
@ok
    pla
    ldx #0
    ldy #0
    jsr t2_point
    ldx #<2048                  ; 64 x 32 cells
    ldy #>2048
@cell
    lda X16_P0
    sta VERA_DATA0
    lda X16_P1
    sta VERA_DATA0
    dex
    bne @cell
    dey
    bne @cell
    clc
    rts

; t2_point -- A = layer, X = col, Y = row: data port 0 at the cell,
; auto-increment 1. addr = mapbase + row*128 + col*2 (17-bit, bit 16 0).
t2_point
    and #1
    sta t2_t
    txa
    asl                         ; col*2 (0-126)
    sta t2_lo
    tya                         ; row*128: bit 0 of row into the high
    lsr                         ; byte, the rest shifted up
    sta t2_hi
    lda #0
    ror
    ora t2_lo
    sta t2_lo
    ldx t2_t
    lda t2_hi
    clc
    adc t2_base,x               ; + $80 / $90 (the map's high byte)
    sta t2_hi
    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL
    lda t2_lo
    sta VERA_ADDR_L
    lda t2_hi
    sta VERA_ADDR_M
    lda #(VERA_INC_1 << 4)      ; bit 16 = 0: the maps sit low
    sta VERA_ADDR_H
    rts

t2_mapb .byte $40, $48          ; mapbase register values (addr >> 9)
t2_base .byte $80, $90          ; map address high bytes ($08000/$09000)
t2_t    .byte 0
t2_lo   .byte 0
t2_hi   .byte 0

.segment "CODE"

.else
; the runner links flat: mode 2 never engages (cx_vmode stays 0), so the
; entries exist for the jump table and refuse honestly at run time.
.include "video/tile.asm"
tile2_guard
    lda cx_vmode
    cmp #2
    rts
cx_do_tile_setup
tile2_setup
cx_do_tile_scroll
tile2_scroll
cx_do_tile_cell
tile2_cell
cx_do_tile_fill
tile2_fill
    sec
    rts
.endif
