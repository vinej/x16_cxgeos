; ca65
; =====================================================================
; CXRF :: kernel/video/ov3t.asm -- mode-2 tile-text port engine (OV3T)
; =====================================================================
; A FIFTH graphics-port image, and the one that turns the tile mode into
; a place a dialog can live. It is NOT a mode: cx_vmode stays 2 (tiles)
; the whole time. cx_tile_text swaps THIS image into the port (cx_ov_load
; index 4) without reprogramming VERA, so layer 0's game world is
; untouched; the dialog module (cx_panel / cx_dlg_alert, bank 5) then
; draws through the port and lands on the 1bpp TEXT layer cx_tile_text
; put up on layer 1. cx_tile_text swaps OV2 back when it lowers the layer.
;
; Where OV3 (mode 3) drives the KERNAL editor's 80x60 screen at VRAM
; $1B000, OV3T writes cells DIRECTLY into the tile-text map at $12000 --
; the same map cx_tile_cell uses -- because that is what layer 1 shows in
; mode 2, at the tile geometry (40x30 cells at 320x240), not the KERNAL's
; 80x60. The charset is the one ov2_init staged at $1F000, so a cell is a
; SCREEN code (low byte) plus a 16-colour attribute fg | bg<<4 (high).
;
; Interrupts are masked per op: the event IRQ touches VERA (the mouse),
; and these ops assume ADDRSEL = 0 and the data port across their run.
; =====================================================================

.ifndef CX_NO_OVERLAY

; the box-drawing glyphs, as SCREEN codes for the $1F000 charset (the
; PETSCII values OV3 feeds screen_chrout, already run through the KERNAL's
; PETSCII->screencode map, which is why they match OV3 on screen)
T3_TL = $70                     ; top-left      (PETSCII $B0)
T3_TR = $6E                     ; top-right     (PETSCII $AE)
T3_BL = $6D                     ; bottom-left   (PETSCII $AD)
T3_BR = $7D                     ; bottom-right  (PETSCII $BD)
T3_HB = $40                     ; horizontal bar(PETSCII $C0)
T3_VB = $5D                     ; vertical bar  (PETSCII $DD)

T3_MAPHI = $20                  ; the text map $12000: middle-byte base
                                ; (bit 16 set in t3t_addr; kept in step with
                                ; cx_tile_text's T2_TXTMAP / T2_TXTHI)

.segment "OV3TCODE"

ov3t_vector                     ; the 14+ port entries, in slot order
    jmp ov3t_init
    jmp ov3t_clear
    jmp ov3t_refuse             ; pset  -- a cell is char+attr, not a pixel
    jmp ov3t_refuse             ; read
    jmp ov3t_hline
    jmp ov3t_vline
    jmp ov3t_rect
    jmp ov3t_frame
    jmp ov3t_line               ; horizontal / vertical only
    jmp ov3t_refuse             ; pattern set
    jmp ov3t_refuse             ; pattern rect
    jmp ov3t_refuse             ; blit
    jmp ov3t_refuse             ; masked blit
    jmp ov3t_say                ; text: a string at (col,row)
    jmp ov3t_measure            ; measure: one cell per character
    jmp ov3t_noop               ; rsave -- no save-under: the whole layer
    jmp ov3t_noop               ; rrest    reverts to graphics on exit
    .byte 1                     ; cxov_ink -- cx_say's ink attribute (0-15)
    ; UI metrics, in CELLS (barh rowh barx airx barty bandpad boxwpad
    ; itemx itemdy) -- the menu laid out on the 40x30 text grid
    .byte  1,  1,  1,  2,  0,  1,  2,  1,  0
    ; dialog metrics: dgw(word) dgh dgbw dgbh dgbsp dgpad dgfldy -- sized
    ; for 40x30 (mode 3's are for 80x60 and would overflow 40 columns)
    .word 34
    .byte 11,  9,  3, 11,  2,  4

.assert ov3t_vector = CX_OVL, error, "OV3TCODE must start at CX_OVL"

ov3t_refuse
    sec
    rts
ov3t_noop
    clc
    rts

; init is not reached by cx_tile_text (it swaps the image in without a
; VERA reprogram); it only resets the ink if something calls the port's
; slot 0 directly.
ov3t_init
    lda #1
    sta cxov_ink
    clc
    rts

; --- the cell primitives ---------------------------------------------
; t3t_addr -- point data port 0 at cell (t3t_col, t3t_row), INC_1.
; addr = $12000 + row*128 + col*2  (col<64 so col*2 < 128: bit 7 is free
; for row's low bit, no carry into the middle byte).
t3t_addr
    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL
    lda t3t_col
    asl                         ; col*2 (0-126), C = 0
    sta t3t_lo
    lda t3t_row
    lsr                         ; row>>1 -> middle offset, C = row&1
    sta t3t_hi
    lda #0
    bcc @nlo
    lda #$80                    ; row&1 -> bit 7 of the low byte
@nlo
    ora t3t_lo
    sta VERA_ADDR_L
    lda t3t_hi
    clc
    adc #T3_MAPHI
    sta VERA_ADDR_M
    lda #((VERA_INC_1 << 4) | 1) ; bit 16 = 1: the text map is at $12000
    sta VERA_ADDR_H
    rts

; t3t_emit -- A = screen code: write the glyph + the current attribute,
; the data port auto-advancing to the next cell.
t3t_emit
    sta VERA_DATA0
    lda t3t_attr
    sta VERA_DATA0
    rts

; t3t_setfill -- A = paper colour: white ink on that paper, the space
; glyph (only the paper shows). Remembers the paper for later ink work.
; A tile layer's colour 0 is TRANSPARENT (it shows the game below), so a
; text-mode "black paper" (th_paper = 0, opaque in mode 3) would vanish
; here -- substitute an opaque blue so a dialog or panel stays readable
; over the game. An app that wants a see-through overlay uses cx_tile_fill.
t3t_setfill
    cmp #0
    bne @op
    lda #6                      ; 0 (transparent) -> opaque blue paper
@op
    sta t3t_bg
    asl
    asl
    asl
    asl                         ; colour << 4 = the bg nibble
    ora #$01                    ; fg = white (irrelevant under a space)
    sta t3t_attr
    lda #' '
    sta t3t_chr
    rts

; t3t_setink -- A = ink colour: that ink on the current paper (t3t_bg)
t3t_setink
    and #$0F
    sta t3t_hi                  ; scratch
    lda t3t_bg
    asl
    asl
    asl
    asl
    ora t3t_hi
    sta t3t_attr
    rts

; t3t_hrun -- t3t_cnt cells of t3t_chr at (t3t_col,t3t_row), horizontal
t3t_hrun
    jsr t3t_addr
    ldx t3t_cnt
    beq @done
@lp
    lda t3t_chr
    jsr t3t_emit
    dex
    bne @lp
@done
    rts

; t3t_vcol -- t3t_h cells of t3t_chr down a column from (P0, P2)
t3t_vcol
    lda X16_P4
    beq @done
    sta t3t_h
    lda X16_P2
    sta t3t_row
@row
    lda X16_P0
    sta t3t_col
    jsr t3t_addr
    lda t3t_chr
    jsr t3t_emit
    inc t3t_row
    dec t3t_h
    bne @row
@done
    rts

; --- the port entries -------------------------------------------------
; ov3t_clear -- A = colour: the whole 64x32 map to spaces on that paper
ov3t_clear
    php
    sei
    jsr t3t_setfill
    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL
    stz VERA_ADDR_L
    lda #T3_MAPHI
    sta VERA_ADDR_M
    lda #(VERA_INC_1 << 4)
    sta VERA_ADDR_H
    ldx #0                      ; 2048 cells = 8 x 256
    ldy #8
@lp
    lda t3t_chr
    jsr t3t_emit
    dex
    bne @lp
    dey
    bne @lp
    plp
    clc
    rts

; ov3t_rect -- P0=col, P2=row, P4=w, P6=h, A=colour: a paper panel
ov3t_rect
    php
    sei
    jsr t3t_setfill
    lda X16_P6
    beq @done
    sta t3t_h
    lda X16_P2
    sta t3t_row
@row
    lda X16_P0
    sta t3t_col
    lda X16_P4
    sta t3t_cnt
    jsr t3t_hrun
    inc t3t_row
    dec t3t_h
    bne @row
@done
    plp
    clc
    rts

; ov3t_hline -- P0=col, P2=row, P4=len, A=colour
ov3t_hline
    php
    sei
    jsr t3t_setink
    lda X16_P0
    sta t3t_col
    lda X16_P2
    sta t3t_row
    lda X16_P4
    sta t3t_cnt
    lda #T3_HB
    sta t3t_chr
    jsr t3t_hrun
    plp
    clc
    rts

; ov3t_vline -- P0=col, P2=row, P4=len, A=colour
ov3t_vline
    php
    sei
    jsr t3t_setink
    lda #T3_VB
    sta t3t_chr
    jsr t3t_vcol
    plp
    clc
    rts

; ov3t_frame -- P0=col, P2=row, P4=w, P6=h, A=colour: a box in the frame
; glyphs. Degenerate sizes fall back: w<2 a bar column, h<2 a ruled row.
ov3t_frame
    php
    sei
    jsr t3t_setink

    lda X16_P4
    cmp #2
    bcc @thin_w
    lda X16_P6
    cmp #2
    bcc @thin_h

    lda X16_P2                  ; the top edge, in one continuous run
    sta t3t_row
    jsr t3t_edge_at
    lda #T3_TL
    jsr t3t_emit
    jsr t3t_bars                ; (w-2) horizontal bars
    lda #T3_TR
    jsr t3t_emit

    lda X16_P2                  ; the bottom edge: row + h - 1
    clc
    adc X16_P6
    sec
    sbc #1
    sta t3t_row
    jsr t3t_edge_at
    lda #T3_BL
    jsr t3t_emit
    jsr t3t_bars
    lda #T3_BR
    jsr t3t_emit

    lda X16_P6                  ; the sides: rows row+1 .. row+h-2
    sec
    sbc #2
    beq @sides_done
    sta t3t_h
    lda X16_P2
    inc a
    sta t3t_row
@side
    lda X16_P0                  ; left bar
    sta t3t_col
    jsr t3t_addr
    lda #T3_VB
    jsr t3t_emit
    lda X16_P0                  ; right bar at col + w - 1
    clc
    adc X16_P4
    sec
    sbc #1
    sta t3t_col
    jsr t3t_addr
    lda #T3_VB
    jsr t3t_emit
    inc t3t_row
    dec t3t_h
    bne @side
@sides_done
    plp
    clc
    rts

@thin_w                         ; w <= 1: a bar column, h tall
    lda X16_P6
    sta X16_P4
    lda #T3_VB
    sta t3t_chr
    jsr t3t_vcol
    plp
    clc
    rts

@thin_h                         ; h <= 1 (w >= 2): one ruled row
    lda X16_P0
    sta t3t_col
    lda X16_P2
    sta t3t_row
    lda X16_P4
    sta t3t_cnt
    lda #T3_HB
    sta t3t_chr
    jsr t3t_hrun
    plp
    clc
    rts

; t3t_edge_at -- point the port at (P0, t3t_row) so an edge can stream
t3t_edge_at
    lda X16_P0
    sta t3t_col
    jmp t3t_addr

; t3t_bars -- write (w - 2) horizontal bars at the current port position
t3t_bars
    lda X16_P4
    sec
    sbc #2
    tax
    beq @done
@lp
    lda #T3_HB
    jsr t3t_emit
    dex
    bne @lp
@done
    rts

; ov3t_line -- P0=x0, P2=y0, P4=x1, P6=y1 (cells), A=colour. Horizontal
; or vertical only; a diagonal refuses (carry), the module policy.
ov3t_line
    pha
    lda X16_P2
    cmp X16_P6
    beq @horiz
    lda X16_P0
    cmp X16_P4
    beq @vert
    pla
    sec
    rts
@horiz                          ; col = min(x0,x1), len = |dx|+1
    lda X16_P0
    cmp X16_P4
    bcc @h_ord
    lda X16_P4
    ldx X16_P0
    sta X16_P0
    stx X16_P4
@h_ord
    lda X16_P4
    sec
    sbc X16_P0
    inc a
    sta X16_P4
    pla
    jmp ov3t_hline
@vert                           ; row = min(y0,y1), len = |dy|+1
    lda X16_P2
    cmp X16_P6
    bcc @v_ord
    lda X16_P6
    ldx X16_P2
    sta X16_P2
    stx X16_P6
@v_ord
    lda X16_P6
    sec
    sbc X16_P2
    inc a
    sta X16_P4
    pla
    jmp ov3t_vline

; ov3t_say -- A/X = string, P0 = col, P2 = row: print at the cell with
; the cx_ink attribute on the current paper. ASCII in; the $1F000 charset
; is screen-code order, so 'a'-'z' map to $01-$1A and everything else
; (upper case, digits, punctuation) is its own code. Returns the pen in
; P0 (col + characters printed).
ov3t_say
    php
    sei
    sta t3t_sl
    stx t3t_sh
    lda cxov_ink
    jsr t3t_setink
    lda X16_P0
    sta t3t_col
    lda X16_P2
    sta t3t_row
    jsr t3t_addr
    lda t3t_sl
    sta X16_TPTR0
    lda t3t_sh
    sta X16_TPTR0+1
    ldy #0
@ch
    lda (X16_TPTR0),y
    beq @done
    cmp #'a'
    bcc @notlow
    cmp #'z'+1
    bcs @notlow
    sec
    sbc #$60                    ; a-z -> screen $01-$1A
    bra @emit
@notlow
    cmp #'['                    ; [ \ ] ^ _  ($5B-$5F) live at screen $1B-$1F
    bcc @emit                  ; in charset 2 -- $5B-$5F there are graphics
    cmp #'_'+1                  ; (+ | etc.), which is why a widget's [X] came
    bcs @emit                  ; out as +X|. Space/digits/punct/A-Z pass as-is.
    sec
    sbc #$40                    ; [ \ ] ^ _ -> $1B-$1F
@emit
    phy
    jsr t3t_emit
    ply
    iny
    bne @ch
@done
    tya                         ; pen = col + characters printed
    clc
    adc X16_P0
    sta X16_P0
    plp
    clc
    rts

; ov3t_measure -- A/X = string -> P0/P1 = width in cells (its length)
ov3t_measure
    sta X16_TPTR0
    stx X16_TPTR0+1
    ldy #0
@len
    lda (X16_TPTR0),y
    beq @done
    iny
    bne @len
@done
    sty X16_P0
    stz X16_P1
    clc
    rts

t3t_col  .byte 0
t3t_row  .byte 0
t3t_lo   .byte 0
t3t_hi   .byte 0
t3t_bg   .byte 0
t3t_attr .byte 0
t3t_chr  .byte 0
t3t_cnt  .byte 0
t3t_h    .byte 0
t3t_sl   .byte 0
t3t_sh   .byte 0

.segment "CODE"

.endif
