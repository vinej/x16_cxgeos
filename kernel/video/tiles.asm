; ca65
; =====================================================================
; CXRF :: kernel/video/tiles.asm -- mode 2: the tile engine
; =====================================================================
; The third personality behind the graphics port, and the one games
; want: two VERA tile layers at 320x240 with hardware scrolling, plus
; the sprites and audio the ABI already carries. It is NOT a bitmap --
; the port's drawing entries refuse here (carry), and the real API is
; the cx_tile_* slots, far-called into bank 17 beside the shapes.
; (The mode-2 engine IMAGE stays in bank 5 storage -- OV2CODE below --
; because cx_msrc reads it from __OV2CODE_LOAD__ there; only the
; machinery the stubs far-call moved.)
;
; The mode's VRAM ledger (the framebuffer region is free -- no bitmap).
; The maps sit ABOVE the tileset so an 8bpp set (64 KB, 1024 tiles) has
; room; the mapbase is the same constant at every depth (docs/remap.md):
;   $00000  tile images: 8x8, 16/32/64 bytes each at 2/4/8bpp, up to 1024
;           tiles (upload with cx_vram_write / cx_vram_stream)
;   $10000  layer 0's map: 64x32 cells, 2 bytes each (4 KB)
;   $11000  layer 1's map: same shape
;   $12000  the tile-text overlay map (cx_tile_text)
;
; A cell word is VERA's: tile index low byte; high byte = index bits
; 9:8, then h-flip(2), v-flip(3), palette offset(7:4).
; =====================================================================

.ifndef CX_NO_OVERLAY

CX_T2_BANK = CX_GFXX_BANK       ; bank 17 (banks.inc)

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
cx_do_tile_text
    jsr cxb_call
    .byte CX_T2_BANK
    .addr tile2_text
cx_do_tile_dbuf
    jsr cxb_call
    .byte CX_T2_BANK
    .addr tile2_dbuf
cx_do_tile_flip
    jsr cxb_call
    .byte CX_T2_BANK
    .addr tile2_flip

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
    .word 0
    .byte 0, 0, 0, 0, 0, 0                     ; dialog metrics (gated off)

.assert ov2_vector = CX_OVL, error, "OV2CODE must start at CX_OVL"

ov2_init                        ; 320x240, both layers off until asked
    ; Stage the PETSCII upper/lower charset at $1F000 -- the same one
    ; mode 1/3 use, the only set with BOTH box glyphs and mixed case.
    ; A game never sees this: it runs ONCE at mode entry, before any
    ; tile is drawn, and cx_tile_text later points a layer's tilebase
    ; here for the pause/dialog overlay. Safe like ov1/ov3_init: this
    ; runs in the overlay (low RAM, always mapped), so the bank-unsafe
    ; KERNAL screen calls cannot corrupt banked code.
    php
    sei
    vera_addrsel 0
    jsr CINT                    ; CINT: the editor up, its ROM charset at $1F000
    vera_addrsel 0              ; ADDRSEL first: the macro clobbers A, and A is
    lda #3                      ; the charset number below.
    jsr SCREEN_SET_CHARSET      ; charset 3 = PETSCII upper/lower, uploaded to
                                ; $1F000 in SCREEN-CODE order: a-z at $01-$1A,
                                ; A-Z at $41-$5A -- exactly what ov3t_say and the
                                ; T3_* box glyphs read. CHR$(14) alone will NOT
                                ; do this: on the X16 the case toggle only sets
                                ; the editor's mode FLAG, it does not re-upload
                                ; the VRAM charset, so $1F000 kept CINT's upper/
                                ; GRAPHICS set and ov3t_say's upper-case A-Z
                                ; ($41-$5A) landed on graphic tiles.
    plp

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

; --- the tile machinery (bank 17, with the shapes) --------------------
.segment "B17CODE"

.include "video/tile.asm"

; every entry is mode-gated: the maps and layer registers only mean
; this when the tile personality owns the screen
tile2_guard
    lda cx_vmode
    cmp #2
    rts

; cx_tile_setup -- A = layer (0/1), X = bpp (2/4/8): the ledger config,
; layer on. bpp picks the config's depth ($11/$12/$13); anything else
; (an old caller, a stray value) defaults to 4bpp, so nothing that passed
; only the layer changes. The depth is remembered per layer so
; cx_tile_text restores it, not a hardcoded 4bpp.
tile2_setup
    pha
    jsr tile2_guard
    beq @ok
    pla
    sec
    rts
@ok
    cpx #2                      ; an explicit depth (2/4/8) wins; anything
    beq @havebpp                ; else (0, a stray value) adopts the tile
    cpx #4                      ; mode's default depth, cx_tbpp -- which
    beq @havebpp                ; cx_gfx_mode(2, bpp) set, or 4 by default
    cpx #8
    beq @havebpp
    ldx cx_tbpp
@havebpp
    lda #$12                    ; 64x32 map, 8x8 tiles, default 4bpp
    cpx #2
    bne @cfg2
    lda #$11                    ; 2bpp
@cfg2
    cpx #8
    bne @cfg8
    lda #$13                    ; 8bpp
@cfg8
    sta t2_cfgtmp
    pla
    and #1
    pha
    tax
    lda t2_cfgtmp               ; remember the depth for cx_tile_text
    sta t2_lcfg,x
    jsr layer_set_config        ; A = config, X = layer
    plx
    phx
    lda t2_mapb,x               ; mapbase $10000 / $11000 (addr >> 9)
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

; cx_tile_text -- A = layer (0/1), X = on (0 = graphics, 1 = text).
; Flip a tile layer between its game map and a 1bpp TEXT map at VRAM
; $12000, using the charset ov2_init staged at $1F000. The game's map
; ($10000/$11000) is never touched, so switching back is instant -- the
; game world stays visible on the other layer the whole time.
;   ON : save the layer's scroll and enable bit; config ->$10 (1bpp),
;        mapbase to the text map, tilebase to the charset, scroll 0, layer
;        on. t2_point's base is redirected so cx_tile_cell/fill now address
;        the text map.
;   OFF: restore the layer's REAL depth (t2_lcfg, set by cx_tile_setup --
;        not a hardcoded 4bpp), the game mapbase, tilebase 0, t2_point's
;        base, the saved scroll AND the saved enable -- so a layer that was
;        off (the common case: a game that uses only layer 0) goes dark
;        again, and a layer that was a live HUD comes back on. Either way
;        the game map reappears untouched.
T2_TXTMAP = $90                 ; text map $12000 (addr >> 9)
T2_TXTHI  = $20                 ; ...its high byte for t2_point (bit 16 set)
T2_CHARSET = $F8                ; charset $1F000 ((>>11)<<2), 8x8 tiles
tile2_text
    pha
    jsr tile2_guard
    beq @ok
    pla
    sec
    rts
@ok
    pla
    and #1
    sta t2_txlyr
    cpx #0
    bne @on                     ; (the ON path outgrew a short branch to @off)
    jmp @off
@on

    ; --- ON: 1bpp text on the layer, charset at $1F000 ---
    ldx t2_txlyr                ; save the layer's 12-bit scroll
    jsr layer_index             ; X = 0 or 7
    lda VERA_L0_HSCROLL_L,x
    sta t2_txsave+0
    lda VERA_L0_HSCROLL_H,x
    sta t2_txsave+1
    lda VERA_L0_VSCROLL_L,x
    sta t2_txsave+2
    lda VERA_L0_VSCROLL_H,x
    sta t2_txsave+3
    stz VERA_L0_HSCROLL_L,x     ; text sits at the origin
    stz VERA_L0_HSCROLL_H,x
    stz VERA_L0_VSCROLL_L,x
    stz VERA_L0_VSCROLL_H,x

    vera_dcsel 0                ; remember whether the layer was showing
    jsr t2_enmask               ; A = this layer's DC_VIDEO enable bit
    and VERA_DC_VIDEO           ; nonzero if it was on
    sta t2_txwason

    ldx t2_txlyr
    lda #$10                    ; 64x32 map, 8x8 tiles, 1bpp
    jsr layer_set_config
    ldx t2_txlyr
    lda #T2_TXTMAP
    jsr layer_set_mapbase
    ldx t2_txlyr
    lda #T2_CHARSET
    jsr layer_set_tilebase

    ldx t2_txlyr                ; redirect cx_tile_cell/fill to the text map
    lda #T2_TXTHI
    sta t2_base,x
    lda t2_txlyr
    jsr layer_on

    ; hand the graphics port to OV3T so cx_panel / cx_dlg_alert (and the
    ; menu / widgets) draw onto these text cells, and tell the toolkit the
    ; canvas is a 40x30 CELL grid (the dialog centres in cxov_m units).
    lda #40
    sta cx_cur_w
    stz cx_cur_w+1
    lda #30
    sta cx_cur_h
    stz cx_cur_h+1
    lda #1
    sta cx_txtport             ; menu_gate now lets the toolkit draw here
    lda #3                     ; the mouse (a 40x30/320px field) reports in
    sta cx_cshift+2            ; CELLS on the overlay: pixel >> 3 = the column
    lda #CX_OV_TILETEXT
    jsr cx_ov_load              ; OV3T into the port -- no VERA reprogram
    clc
    rts

    ; --- OFF: the game map back at its real depth, scroll restored ---
@off
    ldx t2_txlyr
    lda t2_lcfg,x               ; the layer's depth cx_tile_setup recorded
    jsr layer_set_config
    ldx t2_txlyr
    lda t2_mapb,x               ; the game mapbase ($40/$48)
    jsr layer_set_mapbase
    ldx t2_txlyr
    lda #0                      ; tilebase $00000
    jsr layer_set_tilebase

    ldx t2_txlyr                ; t2_point back to the game map
    lda t2_base_def,x
    sta t2_base,x

    ldx t2_txlyr                ; the saved scroll back
    jsr layer_index
    lda t2_txsave+0
    sta VERA_L0_HSCROLL_L,x
    lda t2_txsave+1
    sta VERA_L0_HSCROLL_H,x
    lda t2_txsave+2
    sta VERA_L0_VSCROLL_L,x
    lda t2_txsave+3
    sta VERA_L0_VSCROLL_H,x

    lda t2_txwason              ; the layer as the game left it
    beq @wasoff
    lda t2_txlyr
    jsr layer_on
    bra @porttail
@wasoff
    lda t2_txlyr
    jsr layer_off
@porttail
    stz cx_txtport             ; the toolkit is refused on plain tiles again
    stz cx_cshift+2            ; the mouse back to pixels for the game
    lda #CX_OV_TILE             ; OV2 (the tile refuse-port) back in the port
    jsr cx_ov_load
    jsr cx_ov_bounds            ; cx_cur_w/h back to the tile canvas
    clc
    rts

; t2_enmask -- A = the DC_VIDEO enable bit for layer t2_txlyr
t2_enmask
    lda #VERA_VIDEO_LAYER0_EN
    ldx t2_txlyr
    beq @m
    lda #VERA_VIDEO_LAYER1_EN
@m
    rts

; cx_tile_dbuf -- A = layer (0/1), X = on (0/1). Enable/disable double
; buffering for a layer. ON: cx_tile_cell/cx_tile_fill draw to the HIDDEN
; shadow map ($14000 / $15000); the primary map stays shown until
; cx_tile_flip presents it. OFF: back to single-buffered on the primary.
; The app should draw a full frame after enabling, before the first flip.
tile2_dbuf
    pha
    jsr tile2_guard
    beq @ok
    pla
    sec
    rts
@ok
    pla                         ; A = layer, X = on
    and #1
    sta t2_dbtmp
    cpx #0
    beq @off
    ldx t2_dbtmp                ; --- ON: show primary, draw the shadow ---
    lda #1
    sta t2_dbuf,x
    sta t2_drawsh,x             ; 1 = draw shadow / show primary
    lda t2_mapb,x
    jsr layer_set_mapbase       ; shown = primary
    ldx t2_dbtmp
    lda t2_shbase,x             ; cx_tile_cell/fill -> the shadow
    sta t2_base,x
    clc
    rts
@off
    ldx t2_dbtmp
    stz t2_dbuf,x
    lda t2_mapb,x
    jsr layer_set_mapbase       ; shown = primary
    ldx t2_dbtmp
    lda t2_base_def,x           ; draw = primary
    sta t2_base,x
    clc
    rts

; cx_tile_flip -- A = layer (0/1). Present the hidden buffer: wait for the
; next vsync (irq_frame_count ticks in vblank), swap the layer's MAPBASE
; shown<->draw, and redirect cx_tile_cell/fill to the now-hidden map. One
; call per frame is a tear-free present that also paces to 60 Hz. A no-op
; on a layer that is not double-buffered.
tile2_flip
    pha
    jsr tile2_guard
    beq @ok
    pla
    sec
    rts
@ok
    pla
    and #1
    sta t2_dbtmp
    tax
    lda t2_dbuf,x
    bne @go
    clc                         ; not double-buffered: nothing to flip
    rts
@go
    lda irq_frame_count         ; wait for the next vsync = the vblank window
@wait
    cmp irq_frame_count
    beq @wait
    lda t2_drawsh,x             ; toggle which buffer is shown vs drawn
    eor #1
    sta t2_drawsh,x
    beq @showshadow
    lda t2_mapb,x               ; drawsh 1: show primary, draw shadow
    jsr layer_set_mapbase
    ldx t2_dbtmp
    lda t2_shbase,x
    sta t2_base,x
    clc
    rts
@showshadow
    lda t2_shmapb,x             ; drawsh 0: show shadow, draw primary
    jsr layer_set_mapbase
    ldx t2_dbtmp
    lda t2_base_def,x
    sta t2_base,x
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
    lda #((VERA_INC_1 << 4) | 1) ; bit 16 = 1: the maps sit at $10000+
    sta VERA_ADDR_H
    rts

t2_mapb .byte $80, $88          ; mapbase register values (addr >> 9)
t2_base .byte $00, $10          ; map address bits 8-15 ($10000/$11000, bit
                                ; 16 set in t2_point); cx_tile_text swaps one
                                ; to $20 (the $12000 text map) while up
t2_base_def .byte $00, $10      ; the defaults cx_tile_text restores
t2_lcfg .byte $12, $12          ; each layer's depth config ($11/$12/$13),
                                ; set by cx_tile_setup; cx_tile_text restores it
t2_dbuf .byte 0, 0              ; per layer: is double-buffering on?
t2_drawsh .byte 1, 1            ; on: 1 = draw the shadow / show primary, else swapped
t2_shmapb .byte $A0, $A8        ; shadow mapbase ($14000 / $15000, addr >> 9)
t2_shbase .byte $40, $50        ; shadow map bits 8-15 (bit 16 set in t2_point)
t2_dbtmp .byte 0                ; scratch: the layer, across layer_set_mapbase
t2_txlyr .byte 0                ; the layer cx_tile_text is overlaying
t2_txsave .res 4                ; its saved 12-bit h/v scroll
t2_txwason .byte 0              ; ...and whether it was enabled (to restore)
t2_cfgtmp .byte 0               ; scratch: the config byte being built
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
cx_do_tile_text
tile2_text
cx_do_tile_dbuf
tile2_dbuf
cx_do_tile_flip
tile2_flip
    sec
    rts
.endif
