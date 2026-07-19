;ACME
; =====================================================================
; x16lib :: gfx/verafx.asm -- VERA FX: hardware multiply, fast fills
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; Requires VERA firmware v0.3.1+ (emulator R44+). Probe with vera_has_fx
; before calling anything here; on older VERA these routines write to
; registers that do not exist and quietly do the wrong thing.
;
; The FX registers are $9F29-$9F2C banked behind DCSEL 2..6. Always
; select the bank with +vera_dcsel, which preserves ADDRSEL -- writing
; VERA_CTRL directly (as the reference manual's examples do) would
; deselect whatever data port the caller had chosen.
;
; Every routine here leaves FX disabled (FX_CTRL = 0, Addr1 Mode 0) and
; DCSEL back at 0. Leaving Addr1 Mode set would silently change how
; ordinary VRAM addressing behaves for everyone downstream.
; =====================================================================

; (zone: file scope in ca65)


; --- fx_off: every part of this module leaves FX through it, so it
; --- is here whenever any of them is.
.ifdef X16_USE_VERAFX_ANY
; ---------------------------------------------------------------------
; fx_off -- disable FX; leave DCSEL = 0 and ADDRSEL = 0.
; Safe to call whether or not FX was ever enabled.
;
; ADDRSEL is forced back to port 0 because the line and polygon
; helpers work through port 1: returning with port 1 selected would
; hand the next CHROUT the exact ADDRSEL trap video/screen.asm warns
; about.
; ---------------------------------------------------------------------
fx_off
    vera_dcsel 2
    stz VERA_FX_CTRL            ; cache off, transparency off, Addr1 mode 0
    stz VERA_FX_MULT            ; multiplier off
    vera_dcsel 0
    vera_addrsel 0
    rts

.endif

.ifdef X16_USE_VERAFX_MULT
; ---------------------------------------------------------------------
; fx_mult -- signed 16 x 16 -> 32 in hardware
;   in:  X16_P0/P1 = a, X16_P2/P3 = b
;   out: X16_P4..P7 = product, low byte first
;
; The two operands go into the halves of the 32-bit cache. The result
; is not readable from a register: triggering the multiply writes four
; bytes to VRAM, so we park them at VRAM_FX_SCRATCH and read them back.
;
; Only ADDR0/DATA0 is used. VERA pre-fetches whenever an address pointer
; changes or increments -- even with increment 0 -- so touching the same
; VRAM through the other port here would risk reading a stale latch.
; ---------------------------------------------------------------------
fx_mult
    vera_dcsel 2
    stz VERA_FX_CTRL            ; Addr1 Mode 0
    lda #VERA_FX_MULT_ENABLE
    sta VERA_FX_MULT

    vera_dcsel 6
    lda VERA_FX_ACCUM_RESET     ; a *read* clears the accumulator
    lda X16_P0
    sta VERA_FX_CACHE_L
    lda X16_P1
    sta VERA_FX_CACHE_M         ; cache 15:0  = a
    lda X16_P2
    sta VERA_FX_CACHE_H
    lda X16_P3
    sta VERA_FX_CACHE_U         ; cache 31:16 = b

    vera_dcsel 2
    lda #VERA_FX_CACHE_WRITE
    sta VERA_FX_CTRL            ; with multiplier on, writes the product

    ; Trigger: any store to DATA0 emits the 32-bit result. The stored
    ; value itself is ignored.
    vera_addr 0, VRAM_FX_SCRATCH, VERA_INC_0
    stz VERA_DATA0

    ; Read it back, now advancing one byte at a time.
    vera_addr 0, VRAM_FX_SCRATCH, VERA_INC_1
    lda VERA_DATA0
    sta X16_P4
    lda VERA_DATA0
    sta X16_P5
    lda VERA_DATA0
    sta X16_P6
    lda VERA_DATA0
    sta X16_P7

    jmp fx_off

.endif

.ifdef X16_USE_VERAFX_FILL
; ---------------------------------------------------------------------
; fx_fill -- fill VRAM through the 32-bit write cache (~4x a byte loop)
;   in:  A = byte value
;        X16_P0/P1/P2 = destination VRAM address (17-bit)
;        X16_P3/P4    = byte count
;
; With Cache Write Enable set, one store to DATA0 writes all four cache
; bytes. Stepping the port by 4 covers the region a quad at a time; any
; remaining 1-3 bytes are written normally with FX switched back off.
; ---------------------------------------------------------------------
fx_fill
    sta X16_T0                  ; fill value

    vera_dcsel 2
    stz VERA_FX_MULT            ; multiplier off: write the cache itself
    lda #VERA_FX_CACHE_WRITE
    sta VERA_FX_CTRL

    vera_dcsel 6
    lda X16_T0
    sta VERA_FX_CACHE_L
    sta VERA_FX_CACHE_M
    sta VERA_FX_CACHE_H
    sta VERA_FX_CACHE_U
    vera_dcsel 0

    ; Point port 0 at the destination, stepping 4 bytes per write.
    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL
    lda X16_P0
    sta VERA_ADDR_L
    lda X16_P1
    sta VERA_ADDR_M
    lda X16_P2
    and #VERA_ADDR_H_BANK
    ora #(VERA_INC_4 << 4)
    sta VERA_ADDR_H

    ; quads = count >> 2, remainder = count & 3
    lda X16_P3
    and #$03
    sta X16_T3
    lda X16_P4
    sta X16_T2
    lda X16_P3
    sta X16_T1
    lsr X16_T2
    ror X16_T1
    lsr X16_T2
    ror X16_T1

    lda X16_T1
    ora X16_T2
    beq @tail                   ; fewer than four bytes

    ldx X16_T1
    ldy X16_T2
    txa
    beq @full
    iny
@full
@loop
    stz VERA_DATA0              ; writes the four cache bytes
    dex
    bne @loop
    dey
    bne @loop

@tail
    ; FX off first: the leftover bytes must be written singly.
    vera_dcsel 2
    stz VERA_FX_CTRL
    vera_dcsel 0

    lda X16_T3
    beq @done

    ; Port 0 already sits just past the quads. Keep its bank and DECR
    ; bits, switch the increment back to 1.
    lda VERA_ADDR_H
    and #$0F
    ora #(VERA_INC_1 << 4)
    sta VERA_ADDR_H

    ldx X16_T3
    lda X16_T0
@rest
    sta VERA_DATA0
    dex
    bne @rest
@done
    rts

; ---------------------------------------------------------------------
; fx_clear -- zero a VRAM region
;   in:  X16_P0/P1/P2 = address, X16_P3/P4 = byte count
; ---------------------------------------------------------------------
fx_clear
    lda #0
    jmp fx_fill

.endif

.ifdef X16_USE_VERAFX_COPY
; ---------------------------------------------------------------------
; fx_copy -- VRAM to VRAM through the 32-bit cache (~4x a byte loop)
;   in:  X16_P0/P1/P2 = source address (17-bit)
;        X16_P3/P4/P5 = destination address, 4-BYTE ALIGNED
;        X16_P6/P7    = byte count
;
; With Cache Fill enabled, each DATA1 read latches a byte into the
; cache; after four, one DATA0 write (mask 0) flushes all four to the
; aligned destination. The 0-3 leftover bytes are copied singly with
; FX off. The source needs no alignment.
; ---------------------------------------------------------------------
fx_copy
    vera_dcsel 2
    stz VERA_FX_CTRL            ; mode 0 while the ports are aimed
    stz VERA_FX_MULT            ; multiplier off, cache index to 0

    vera_addrsel 1             ; port 1 reads the source
    lda X16_P0
    sta VERA_ADDR_L
    lda X16_P1
    sta VERA_ADDR_M
    lda X16_P2
    and #VERA_ADDR_H_BANK
    ora #(VERA_INC_1 << 4)
    sta VERA_ADDR_H
    vera_addrsel 0             ; port 0 writes quads
    lda X16_P3
    sta VERA_ADDR_L
    lda X16_P4
    sta VERA_ADDR_M
    lda X16_P5
    and #VERA_ADDR_H_BANK
    ora #(VERA_INC_4 << 4)
    sta VERA_ADDR_H

    vera_dcsel 2
    lda #(VERA_FX_CACHE_FILL | VERA_FX_CACHE_WRITE)
    sta VERA_FX_CTRL

    ; quads = count >> 2, remainder = count & 3
    lda X16_P6
    and #$03
    sta X16_T3
    lda X16_P7
    sta X16_T2
    lda X16_P6
    sta X16_T1
    lsr X16_T2
    ror X16_T1
    lsr X16_T2
    ror X16_T1

    lda X16_T1
    ora X16_T2
    beq @tail

    ldx X16_T1
    ldy X16_T2
    txa
    beq @full
    iny
@full
@quad
    lda VERA_DATA1              ; four reads fill the cache...
    lda VERA_DATA1
    lda VERA_DATA1
    lda VERA_DATA1
    stz VERA_DATA0              ; ...one write flushes it (mask 0)
    dex
    bne @quad
    dey
    bne @quad

@tail
    vera_dcsel 2
    stz VERA_FX_CTRL            ; leftovers are plain byte copies
    vera_dcsel 0

    lda X16_T3
    beq @done
    lda VERA_ADDR_H             ; port 0 sits just past the quads:
    and #$0F                    ; step it by 1 for the tail
    ora #(VERA_INC_1 << 4)
    sta VERA_ADDR_H
    ldx X16_T3
@rest
    lda VERA_DATA1
    sta VERA_DATA0
    dex
    bne @rest
@done
    vera_addrsel 0
    rts

.endif

.ifdef X16_USE_VERAFX_TRANSP
; ---------------------------------------------------------------------
; fx_transp_on / fx_transp_off -- transparent VRAM writes
;
; While on, a ZERO byte written to DATA0/DATA1 (or sitting in a flushed
; cache) leaves the target byte alone -- colour 0 acts as transparency
; for blits done with plain writes or fx_copy-style cache flushes.
;
; NOTE: the other fx_* helpers reset FX_CTRL on exit, which turns
; transparency off again. Enable it, do your writes, disable it.
; ---------------------------------------------------------------------
fx_transp_on
    vera_dcsel 2
    lda VERA_FX_CTRL
    ora #VERA_FX_TRANSPARENT
    sta VERA_FX_CTRL
    vera_dcsel 0
    rts

fx_transp_off
    vera_dcsel 2
    lda VERA_FX_CTRL
    and #($FF - VERA_FX_TRANSPARENT)
    sta VERA_FX_CTRL
    vera_dcsel 0
    rts

; =====================================================================
; FX affine helper (Addr1 Mode 3) -- the rotozoom/mode-7 sampler.
;
; VERA turns port 1's reads into texture fetches: an 8x8-tile map
; (one byte per tile, no attributes) defines a square texture, and
; two fixed-point counters walk a sampling ray across it. Every
; DATA1 read returns the texel under the ray and steps it. A rotated,
; scaled scanline is then just:
;
;       jsr fx_affine_ray               ; start + direction
;       +vera_addr 0, dest, VERA_INC_1
;       ... X16_P0/P1 = pixel count ...
;       jsr fx_affine_span              ; DATA1 -> DATA0, that's mode 7
;
; with the ray's dx/dy per scanline coming from sin8/cos8 and the
; zoom factor. Tiles are 8 bpp here (64 bytes each, up to 256 tiles).
; =====================================================================

.endif

.ifdef X16_USE_VERAFX_AFFINE
; ---------------------------------------------------------------------
; fx_affine_on -- enter affine mode and describe the texture
;   in:  X16_P0/P1/P2 = tile data VRAM address (2 KB aligned)
;        X16_P3/P4/P5 = tile map VRAM address (2 KB aligned)
;        X16_P6 = map size code: 0=2x2, 1=8x8, 2=32x32, 3=128x128 tiles
;        X16_P7 = bit 0: 1 = clip (outside the map reads tile 0),
;                        0 = wrap around the map edges
; ---------------------------------------------------------------------
fx_affine_on
    vera_dcsel 2
    lda #VERA_FX_ADDR1_AFFINE
    sta VERA_FX_CTRL

    ; FX_TILEBASE: bits 7:2 = address 16:11, bit 1 = clip enable
    lda X16_P1
    lsr
    lsr
    lsr                         ; address bits 15:11 -> 4:0
    sta X16_T0
    lda X16_P2
    and #$01
    beq @tb_low
    lda #%00100000              ; address bit 16 -> value bit 5
@tb_low
    ora X16_T0
    asl
    asl                         ; the register wants them in bits 7:2
    sta X16_T0
    lda X16_P7
    and #$01
    asl                         ; clip enable is bit 1
    ora X16_T0
    sta VERA_FX_TILEBASE

    ; FX_MAPBASE: bits 7:2 = address 16:11, bits 1:0 = map size
    lda X16_P4
    lsr
    lsr
    lsr
    sta X16_T0
    lda X16_P5
    and #$01
    beq @mb_low
    lda #%00100000
@mb_low
    ora X16_T0
    asl
    asl
    sta X16_T0
    lda X16_P6
    and #$03
    ora X16_T0
    sta VERA_FX_MAPBASE
    vera_dcsel 0
    rts

; ---------------------------------------------------------------------
; fx_affine_ray -- aim the sampler
;   in:  X16_P0/P1 = starting x texel (0-1023)
;        X16_P2/P3 = starting y texel
;        X16_P4/P5 = dx per read, X16_P6/P7 = dy per read
;                    (signed, 1/512 texel units: 512 = one texel per
;                    read; bit 15 = x32, the line/poly encoding)
;
; Samples from texel centres (the subpixel part starts at 0.5).
; Requires fx_affine_on first. Every DATA1 read afterwards returns a
; texel and advances the ray.
; ---------------------------------------------------------------------
fx_affine_ray
    vera_dcsel 3
    lda X16_P4
    sta VERA_FX_X_INCR_L
    lda X16_P5
    sta VERA_FX_X_INCR_H
    lda X16_P6
    sta VERA_FX_Y_INCR_L
    lda X16_P7
    sta VERA_FX_Y_INCR_H
    vera_dcsel 5
    lda #$80                    ; subpixel 0.5: sample texel centres
    sta VERA_FX_X_POS_S
    sta VERA_FX_Y_POS_S
    vera_dcsel 4
    lda X16_P0                  ; positions last: writing them makes
    sta VERA_FX_X_POS_L         ; VERA prefetch the first texel
    lda X16_P1
    and #$07
    sta VERA_FX_X_POS_H
    lda X16_P2
    sta VERA_FX_Y_POS_L
    lda X16_P3
    and #$07
    sta VERA_FX_Y_POS_H
    vera_dcsel 0
    rts

; ---------------------------------------------------------------------
; fx_affine_span -- fetch texels along the ray into VRAM
;   in:  X16_P0/P1 = texel count (>= 1)
;   pre: fx_affine_ray aimed; the caller pointed port 0 at the
;        destination with the increment it wants
;
; The mode-7 inner loop: one read, one write per pixel.
; ---------------------------------------------------------------------
fx_affine_span
    ldx X16_P0
    ldy X16_P1
    txa
    beq @full
    iny
@full
@span
    lda VERA_DATA1
    sta VERA_DATA0
    dex
    bne @span
    dey
    bne @span
    rts

; =====================================================================
; FX line draw helper (Addr1 Mode 1)
;
; VERA tracks the Bresenham error internally: ADDR1 steps one pixel
; along the major axis on every DATA1 write, and a 9.9 fixed-point
; accumulator (seeded to half a pixel) carries it one step along the
; minor axis whenever the slope fraction overflows. The CPU's whole
; job is one `sta VERA_DATA1` per pixel.
;
; Increment registers hold 15-bit signed 6.9 fixed point: write the
; value in 1/512ths, low byte to INCR_L, high 7 bits to INCR_H (bit 7
; of INCR_H multiplies by 32 -- not needed for a line's 0.0..1.0).
; =====================================================================

; ---------------------------------------------------------------------
; fx_line -- hardware-assisted line draw
;   in:  X16_P0/P1 = x0, X16_P2 = y0
;        X16_P3/P4 = x1, X16_P5 = y1
;        X16_P6    = colour
;
; Same arguments and endpoints as gfx_line, drawn by the FX helper.
; Assumes the 320x240@8bpp framebuffer at VRAM $00000 (gfx_init's
; mode). Does NOT clip; keep both endpoints on screen. Probe
; vera_has_fx before relying on any fx_* routine.
.endif

.ifdef X16_USE_VERAFX_LINE
; ---------------------------------------------------------------------
fx_line
    ; |dx| and the x direction
    stz fxl_sx
    sec
    lda X16_P3
    sbc X16_P0
    sta fxl_dx
    lda X16_P4
    sbc X16_P1
    sta fxl_dx+1
    bpl @dx_done
    inc fxl_sx                  ; x runs right to left
    sec
    lda #0
    sbc fxl_dx
    sta fxl_dx
    lda #0
    sbc fxl_dx+1
    sta fxl_dx+1
@dx_done

    ; |dy| and the y direction, in 16 bits (239 - 0 overflows a byte)
    stz fxl_sy
    sec
    lda X16_P5
    sbc X16_P2
    sta fxl_dy
    lda #0
    sbc #0
    sta fxl_dy+1
    bpl @dy_done
    inc fxl_sy
    sec
    lda #0
    sbc fxl_dy
    sta fxl_dy
    lda #0
    sbc fxl_dy+1
    sta fxl_dy+1
@dy_done

    ; Encode the two step bytes once, as if Y-major: h1 = a row per
    ; step (ADDR1, down or up), h0 = a pixel (ADDR0, right or left).
    ; An X-major line swaps their roles below.
    lda #(VERA_INC_320 << 4)
    ldx fxl_sy
    beq @e320
    ora #VERA_ADDR_H_DECR
@e320
    sta fxl_h1
    lda #(VERA_INC_1 << 4)
    ldx fxl_sx
    beq @e1
    ora #VERA_ADDR_H_DECR
@e1
    sta fxl_h0

    ; pick the octant: ADDR1 steps the major axis every pixel, ADDR0's
    ; increment is borrowed for the sometimes-step along the minor axis
    lda fxl_dy+1
    cmp fxl_dx+1
    bne @which
    lda fxl_dy
    cmp fxl_dx
@which
    bcc @x_major

    lda fxl_dy                  ; Y-major: major = dy, minor = dx
    sta fxl_major
    lda fxl_dy+1
    sta fxl_major+1
    lda fxl_dx
    sta fxl_minor
    lda fxl_dx+1
    sta fxl_minor+1
    bra @slope

@x_major
    lda fxl_dx                  ; X-major: major = dx, minor = dy...
    sta fxl_major
    lda fxl_dx+1
    sta fxl_major+1
    lda fxl_dy
    sta fxl_minor
    lda fxl_dy+1
    sta fxl_minor+1
    lda fxl_h1                  ; ...and the step bytes swap roles
    ldx fxl_h0
    stx fxl_h1
    sta fxl_h0

@slope
    ; slope = minor/major in 1/512ths (0..512); a point has no slope
    stz fxl_v
    stz fxl_v+1
    lda fxl_major
    ora fxl_major+1
    beq @program
    stz fxd_num                 ; dividend = minor * 512
    lda fxl_minor
    asl
    sta fxd_num+1
    lda fxl_minor+1
    rol
    sta fxd_num+2
    lda fxl_major
    sta fxd_den
    lda fxl_major+1
    sta fxd_den+1
    jsr verafx_udiv24
    lda fxd_num
    sta fxl_v
    lda fxd_num+1
    sta fxl_v+1

@program
    jsr verafx_pix_addr               ; fxa = address of (P0/P1, P2)

    ; An axis-aligned line (minor delta 0) is just a run along port
    ; 1's increment -- no FX needed.
    lda fxl_minor
    ora fxl_minor+1
    beq @plain

    ; ORDER IS LOAD-BEARING. Every ADDRx register write makes VERA
    ; prefetch, and with line mode already enabled a prefetch steps
    ; the helper using whatever slope happens to be lingering in the
    ; increment registers -- bending the first pixels of the line. So:
    ; all addresses while the mode is still off, then the mode, and
    ; the slope very last (writing X_INCR_H seeds the subpixel
    ; accumulator to half a pixel).
    vera_dcsel 2
    stz VERA_FX_CTRL            ; addr1 mode 0 while addressing
    jsr verafx_set_addr1
    vera_addrsel 0             ; only ADDR0's increment matters here
    lda fxl_h0
    sta VERA_ADDR_H
    vera_dcsel 2
    lda #VERA_FX_ADDR1_LINE
    sta VERA_FX_CTRL
    vera_dcsel 3
    lda fxl_v
    sta VERA_FX_X_INCR_L
    lda fxl_v+1
    sta VERA_FX_X_INCR_H        ; seeds the fraction to 0.5...
    vera_dcsel 4
    stz VERA_FX_X_POS_L         ; ...but NOT the integer/carry bits: a
    stz VERA_FX_X_POS_H         ; leftover carry from an earlier FX op
    bra @count                  ; would eat the line's first minor-step

@plain
    jsr verafx_set_addr1

@count

    ; draw major+1 pixels
    clc
    lda fxl_major
    adc #1
    tax
    lda fxl_major+1
    adc #0
    tay
    txa
    beq @full
    iny
@full
    lda X16_P6
@draw
    sta VERA_DATA1
    dex
    bne @draw
    dey
    bne @draw
    jmp fx_off

; point port 1 at the start pixel with the major-axis increment
verafx_set_addr1
    vera_addrsel 1
    lda fxa
    sta VERA_ADDR_L
    lda fxa+1
    sta VERA_ADDR_M
    lda fxa+2
    and #VERA_ADDR_H_BANK
    ora fxl_h1
    sta VERA_ADDR_H
    rts

fxl_dx    .word 0
fxl_dy    .word 0
fxl_major .word 0
fxl_minor .word 0
fxl_v     .word 0
fxl_sx    .byte 0
fxl_sy    .byte 0
fxl_h1    .byte 0
fxl_h0    .byte 0

; =====================================================================
; FX polygon filler (Addr1 Mode 2)
;
; VERA walks two edges at once: the X and Y/X2 position registers
; carry the left and right x, each advanced by its own signed slope
; twice per row (hence: program HALF the per-row increment). Reading
; DATA1 latches the row -- VERA points ADDR1 at the left edge and
; computes the span width, read back from POLY_FILL_L/H. The CPU
; fills that many pixels and a DATA0 read advances to the next row.
; =====================================================================

.endif

.ifdef X16_USE_VERAFX_TRI
; ---------------------------------------------------------------------
; fx_triangle -- filled triangle via the polygon helper
;   in:  tri_x0/tri_y0, tri_x1/tri_y1, tri_x2/tri_y2 = vertices
;        (x 0-319, y 0-239; written directly, like collide16's block)
;        tri_color = fill colour
;
; Vertices may come in any order. The rasterisation is half-open: the
; bottom row (max y) is not drawn, so triangles sharing an edge do not
; double-paint it. Assumes the 320x240@8bpp framebuffer at $00000.
; Does NOT clip.
; ---------------------------------------------------------------------
fx_triangle
    ; sort the vertices by y (three compare-swaps; X names the pair)
    lda tri_y1
    cmp tri_y0
    bcs @s1
    ldx #0
    jsr verafx_swapv
@s1
    lda tri_y2
    cmp tri_y1
    bcs @s2
    ldx #3
    jsr verafx_swapv
@s2
    lda tri_y1
    cmp tri_y0
    bcs @s3
    ldx #0
    jsr verafx_swapv
@s3
    sec                         ; row counts of the two parts
    lda tri_y1
    sbc tri_y0
    sta fxt_n1
    sec
    lda tri_y2
    sbc tri_y1
    sta fxt_n2
    lda fxt_n1
    ora fxt_n2
    bne @go
    rts                         ; a single row: nothing (half-open)
@go
    ; slope of the long edge v0 -> v2 (always needed)
    lda fxt_n1
    clc
    adc fxt_n2
    sta fxs_dy
    sec
    lda tri_x2
    sbc tri_x0
    sta fxs_dxl
    lda tri_x2+1
    sbc tri_x0+1
    sta fxs_dxh
    jsr verafx_slope
    jsr verafx_save_a                 ; edge A = the long edge

    lda fxt_n1
    bne @two_parts
    jmp @flat_top               ; out of branch range from here
@two_parts

    ; slope of the top short edge v0 -> v1
    lda fxt_n1
    sta fxs_dy
    sec
    lda tri_x1
    sbc tri_x0
    sta fxs_dxl
    lda tri_x1+1
    sbc tri_x0+1
    sta fxs_dxh
    jsr verafx_slope                  ; edge B, still in fxs_*

    jsr verafx_cmp_b_lt_a             ; carry set: B is the left edge
    bcs @b_left
    jsr verafx_a_x_b_y                ; A (long) left in the X slot,
    lda #1                      ; B right in the Y/X2 slot
    sta fxt_swap                ; part 2 replaces the Y/X2 slot
    bra @pos
@b_left
    jsr verafx_b_x_a_y                ; B left, A (long) right
    stz fxt_swap                ; part 2 replaces the X slot
@pos
    lda tri_x0                  ; both edges start at the apex
    sta fxt_px
    sta fxt_py
    lda tri_x0+1
    sta fxt_px+1
    sta fxt_py+1
    jsr verafx_poly_setup
    lda fxt_n1
    jsr verafx_poly_rows

    lda fxt_n2
    bne @have_part2
    jmp fx_off                  ; flat bottom: one part was the triangle
@have_part2

    ; part 2: the finished short edge becomes v1 -> v2
    lda fxt_n2
    sta fxs_dy
    sec
    lda tri_x2
    sbc tri_x1
    sta fxs_dxl
    lda tri_x2+1
    sbc tri_x1+1
    sta fxs_dxh
    jsr verafx_slope
    vera_dcsel 3
    lda fxt_swap
    beq @repl_x
    lda fxs_el
    sta VERA_FX_Y_INCR_L
    lda fxs_eh
    sta VERA_FX_Y_INCR_H        ; resets that edge's subpixel to 0.5
    vera_dcsel 4
    lda tri_x1
    sta VERA_FX_Y_POS_L
    lda tri_x1+1
    and #$07
    sta VERA_FX_Y_POS_H
    bra @part2
@repl_x
    lda fxs_el
    sta VERA_FX_X_INCR_L
    lda fxs_eh
    sta VERA_FX_X_INCR_H
    vera_dcsel 4
    lda tri_x1
    sta VERA_FX_X_POS_L
    lda tri_x1+1
    and #$07
    sta VERA_FX_X_POS_H
@part2
    vera_dcsel 5               ; back to the fill-length window
    lda fxt_n2
    jsr verafx_poly_rows
@finish
    jmp fx_off

@flat_top
    ; v0 and v1 share the top row; the second edge is v1 -> v2
    lda fxt_n2
    sta fxs_dy
    sec
    lda tri_x2
    sbc tri_x1
    sta fxs_dxl
    lda tri_x2+1
    sbc tri_x1+1
    sta fxs_dxh
    jsr verafx_slope                  ; edge B = v1 -> v2

    lda tri_x0+1                ; the leftmost vertex owns the X slot
    cmp tri_x1+1
    bne @ft_pick
    lda tri_x0
    cmp tri_x1
@ft_pick
    bcc @ft_v0_left
    jsr verafx_b_x_a_y                ; v1 left: B in X at x1, A in Y at x0
    lda tri_x1
    sta fxt_px
    lda tri_x1+1
    sta fxt_px+1
    lda tri_x0
    sta fxt_py
    lda tri_x0+1
    sta fxt_py+1
    bra @ft_run
@ft_v0_left
    jsr verafx_a_x_b_y                ; v0 left: A in X at x0, B in Y at x1
    lda tri_x0
    sta fxt_px
    lda tri_x0+1
    sta fxt_px+1
    lda tri_x1
    sta fxt_py
    lda tri_x1+1
    sta fxt_py+1
@ft_run
    jsr verafx_poly_setup
    lda fxt_n2
    jsr verafx_poly_rows
    jmp fx_off

; Box A, box B... the triangle's vertices and fill colour, written by
; the caller (see collide16 for the same convention).
tri_x0    .word 0
tri_y0    .byte 0
tri_x1    .word 0
tri_y1    .byte 0
tri_x2    .word 0
tri_y2    .byte 0
tri_color .byte 0

fxt_n1    .byte 0
fxt_n2    .byte 0
fxt_swap  .byte 0
fxt_xl    .byte 0               ; encoded increments for the two slots
fxt_xh    .byte 0
fxt_yl    .byte 0
fxt_yh    .byte 0
fxt_px    .word 0               ; starting x of each edge
fxt_py    .word 0
fxt_a_l   .byte 0               ; the long edge, parked
fxt_a_h   .byte 0
fxt_a_sgn .byte 0
fxt_a_mag .res 3, 0

; program the polygon helper: mode, both slopes, both positions,
; ADDR0 at the top row (+320/row), ADDR1 stepping +1, DCSEL left at 5.
verafx_poly_setup
    vera_dcsel 2
    lda #VERA_FX_ADDR1_POLY
    sta VERA_FX_CTRL
    vera_dcsel 3
    lda fxt_xl
    sta VERA_FX_X_INCR_L
    lda fxt_xh
    sta VERA_FX_X_INCR_H        ; seeds the subpixel to 0.5
    lda fxt_yl
    sta VERA_FX_Y_INCR_L
    lda fxt_yh
    sta VERA_FX_Y_INCR_H
    vera_dcsel 4
    lda fxt_px
    sta VERA_FX_X_POS_L
    lda fxt_px+1
    and #$07
    sta VERA_FX_X_POS_H
    lda fxt_py
    sta VERA_FX_Y_POS_L
    lda fxt_py+1
    and #$07
    sta VERA_FX_Y_POS_H

    stz X16_P0                  ; ADDR0 = row base of the top row
    stz X16_P1
    lda tri_y0
    sta X16_P2
    jsr verafx_pix_addr
    vera_addrsel 0
    lda fxa
    sta VERA_ADDR_L
    lda fxa+1
    sta VERA_ADDR_M
    lda fxa+2
    and #VERA_ADDR_H_BANK
    ora #(VERA_INC_320 << 4)
    sta VERA_ADDR_H
    vera_addrsel 1             ; ADDR1: VERA sets the address, we set +1
    lda #(VERA_INC_1 << 4)
    sta VERA_ADDR_H
    vera_dcsel 5
    rts

fxt_rows  .byte 0
fxt_fl    .byte 0
fxt_fh    .byte 0
fxt_len   .word 0

; draw A rows. DCSEL must be 5 (poly_setup leaves it there).
verafx_poly_rows
    sta fxt_rows
@prow
    lda fxt_rows
    beq @pdone
    lda VERA_DATA1              ; latch: half-step edges, point ADDR1
    lda VERA_FX_POLY_FILL_L
    sta fxt_fl
    bmi @plong
    lsr                         ; short row: length is bits 4:1
    and #$0F
    sta fxt_len
    stz fxt_len+1
    bra @pdraw
@plong
    lda VERA_FX_POLY_FILL_H
    sta fxt_fh
    and #$C0
    cmp #$C0
    beq @pskip                  ; bits 9+8 set: negative width, no row
    lda fxt_fl
    lsr
    and #$0F
    sta fxt_len
    stz fxt_len+1
    lda fxt_fh
    lsr                         ; H bits 7:1 are length bits 9:3
    asl                         ; ...so shift them up by 3 in 16 bits
    rol fxt_len+1
    asl
    rol fxt_len+1
    asl
    rol fxt_len+1
    ora fxt_len
    sta fxt_len
@pdraw
    ldx fxt_len
    ldy fxt_len+1
    txa
    ora fxt_len+1
    beq @pskip                  ; zero-width row
    txa
    beq @pfull
    iny
@pfull
    lda tri_color
@ploop
    sta VERA_DATA1
    dex
    bne @ploop
    dey
    bne @ploop
@pskip
    lda VERA_DATA0              ; second half-step, ADDR0 to the next row
    dec fxt_rows
    bra @prow
@pdone
    rts

fxs_dxl   .byte 0
fxs_dxh   .byte 0
fxs_dy    .byte 0
fxs_sgn   .byte 0
fxs_32    .byte 0
fxs_mag   .res 3, 0
fxs_el    .byte 0
fxs_eh    .byte 0

; signed (fxs_dxl/h * 256) / fxs_dy -> the 15-bit (+32x) register
; format in fxs_el/eh, with sign and 24-bit magnitude kept for the
; left/right comparison. *256, not *512: the poly filler wants HALF
; the per-row increment because it steps each edge twice per row.
verafx_slope
    stz fxs_sgn
    lda fxs_dxh
    bpl @sl_abs
    inc fxs_sgn
    sec
    lda #0
    sbc fxs_dxl
    sta fxs_dxl
    lda #0
    sbc fxs_dxh
    sta fxs_dxh
@sl_abs
    stz fxd_num                 ; dividend = |dx| * 256
    lda fxs_dxl
    sta fxd_num+1
    lda fxs_dxh
    sta fxd_num+2
    lda fxs_dy
    sta fxd_den
    stz fxd_den+1
    jsr verafx_udiv24

    lda fxd_num                 ; keep the magnitude for verafx_cmp_b_lt_a
    sta fxs_mag
    lda fxd_num+1
    sta fxs_mag+1
    lda fxd_num+2
    sta fxs_mag+2

    stz fxs_32                  ; encode: 14 bits direct, else /32
    lda fxd_num+2
    bne @sl_big
    lda fxd_num+1
    cmp #$40
    bcc @sl_small
@sl_big
    ldx #5
@sl_shift
    lsr fxd_num+2
    ror fxd_num+1
    ror fxd_num
    dex
    bne @sl_shift
    inc fxs_32
@sl_small
    lda fxd_num
    sta fxs_el
    lda fxd_num+1
    sta fxs_eh
    lda fxs_sgn
    beq @sl_pos
    sec                         ; two's complement within the 15 bits
    lda #0
    sbc fxs_el
    sta fxs_el
    lda #0
    sbc fxs_eh
    and #$7F
    sta fxs_eh
@sl_pos
    lda fxs_32
    beq @sl_done
    lda fxs_eh
    ora #$80                    ; the 32x flag rides on bit 15
    sta fxs_eh
@sl_done
    rts

; hand the two edge slopes to the polygon's position slots
verafx_b_x_a_y
    lda fxs_el
    sta fxt_xl
    lda fxs_eh
    sta fxt_xh
    lda fxt_a_l
    sta fxt_yl
    lda fxt_a_h
    sta fxt_yh
    rts
verafx_a_x_b_y
    lda fxt_a_l
    sta fxt_xl
    lda fxt_a_h
    sta fxt_xh
    lda fxs_el
    sta fxt_yl
    lda fxs_eh
    sta fxt_yh
    rts

; park the fxs_* result as edge A
verafx_save_a
    lda fxs_el
    sta fxt_a_l
    lda fxs_eh
    sta fxt_a_h
    lda fxs_sgn
    sta fxt_a_sgn
    lda fxs_mag
    sta fxt_a_mag
    lda fxs_mag+1
    sta fxt_a_mag+1
    lda fxs_mag+2
    sta fxt_a_mag+2
    rts

; carry set if edge B (fxs_*) is a smaller signed slope than edge A.
; Ties go to A-left, which for coincident edges makes no difference.
verafx_cmp_b_lt_a
    lda fxs_sgn
    cmp fxt_a_sgn
    beq @cmp_same
    lda fxs_sgn                 ; different signs: the negative one is less
    bne @cmp_yes
    clc
    rts
@cmp_same
    lda fxt_a_sgn
    bne @cmp_neg
    lda fxs_mag+2               ; both positive: B < A iff |B| < |A|
    cmp fxt_a_mag+2
    bne @cmp_p
    lda fxs_mag+1
    cmp fxt_a_mag+1
    bne @cmp_p
    lda fxs_mag
    cmp fxt_a_mag
@cmp_p
    bcc @cmp_yes
    clc
    rts
@cmp_neg
    lda fxt_a_mag+2             ; both negative: B < A iff |A| < |B|
    cmp fxs_mag+2
    bne @cmp_n
    lda fxt_a_mag+1
    cmp fxs_mag+1
    bne @cmp_n
    lda fxt_a_mag
    cmp fxs_mag
@cmp_n
    bcc @cmp_yes
    clc
    rts
@cmp_yes
    sec
    rts

; swap two adjacent vertex records (x.w y.b, stride 3): X = 0 swaps
; v0/v1, X = 3 swaps v1/v2
verafx_swapv
    ldy #3
verafx_swl
    lda tri_x0,x
    pha
    lda tri_x0+3,x
    sta tri_x0,x
    pla
    sta tri_x0+3,x
    inx
    dey
    bne verafx_swl
    rts
.endif

; --- shared by the line and polygon helpers --------------------------
; Both fx_line and fx_triangle divide through verafx_udiv24 and find their
; framebuffer start through verafx_pix_addr, so these are emitted whenever
; EITHER gate is on (X16_USE_VERAFX_LINETRI, derived in x16_code.asm --
; a LINE-only build must not need the whole triangle filler for them).
.ifdef X16_USE_VERAFX_LINETRI

fxd_num .res 3, 0
fxd_den .word 0
fxd_rem .word 0

; fxd_num(24) / fxd_den(16) -> quotient in fxd_num, remainder fxd_rem
verafx_udiv24
    stz fxd_rem
    stz fxd_rem+1
    ldx #24
@dv
    asl fxd_num
    rol fxd_num+1
    rol fxd_num+2
    rol fxd_rem
    rol fxd_rem+1
    sec
    lda fxd_rem
    sbc fxd_den
    tay
    lda fxd_rem+1
    sbc fxd_den+1
    bcc @dv_no
    sta fxd_rem+1
    sty fxd_rem
    inc fxd_num
@dv_no
    dex
    bne @dv
    rts

fxa .res 3, 0

; fxa = X16_P0/P1 + X16_P2 * 320  (the 17-bit bitmap pixel address)
verafx_pix_addr
    lda X16_P2                  ; y << 6
    stz X16_T3
    asl
    rol X16_T3
    asl
    rol X16_T3
    asl
    rol X16_T3
    asl
    rol X16_T3
    asl
    rol X16_T3
    asl
    rol X16_T3
    sta fxa                     ; low byte of y*64 (and of y*320)
    clc                         ; + y << 8
    lda X16_P2
    adc X16_T3
    sta fxa+1
    lda #0
    adc #0
    sta fxa+2
    clc                         ; + x
    lda fxa
    adc X16_P0
    sta fxa
    lda fxa+1
    adc X16_P1
    sta fxa+1
    lda fxa+2
    adc #0
    sta fxa+2
    rts
.endif

; (end zone)
