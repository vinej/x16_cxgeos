; ca65
; =====================================================================
; CXGEOS :: spikes/spike_c.asm -- Phase 0 risk spike C
; =====================================================================
; The event heartbeat, on the CXGEOS screen mode:
;
;   1. irq_install chains CINV over the 2bpp bitmap mode; proof that
;      the KERNAL jiffy clock still ticks (FRAMES60 / JIFFY60 both 60).
;   2. KERNAL mouse pointer (hardware sprite 0) rides over the bitmap:
;      zero-latency cursor for free, VRAM pointer image at $13000 sits
;      just past our framebuffer.
;   3. A raster-line IRQ at scanline 0 samples mouse_get every frame
;      (bracketed by irq_save_regs -- library calls inside an IRQ) and
;      pushes 5-byte events into the rb_* ring buffer.
;   4. The mainloop pops events and reads the current scanline: the
;      IRQ->mainloop dispatch latency in scanlines (31.7 us each),
;      min/max over 120 frames.
;
; After DONE it stays interactive: run with -Run, move the mouse,
; hold the left button to paint black marks at the pointer.
;
;   .\build.ps1 -Source spikes\spike_c.asm -Capture   # numbers
;   .\build.ps1 -Source spikes\spike_c.asm -Run       # play with it
; =====================================================================

.include "x16.asm"

X16_USE_VERA    = 1
X16_USE_PALETTE = 1
X16_USE_IRQ     = 1
X16_USE_INPUT   = 1
X16_USE_BUFFERS = 1
X16_USE_NUMBER  = 1

FB_BASE     = $00000
FB_STRIDE   = 160

; spike-private zero page (CXGEOS app space $60-$7F)
STR_PTR     = $60
BENCH_T0    = $62
CNT         = $64
MINL        = $65
MAXL        = $66
EBTN        = $67
EX          = $68               ; event x (16-bit)
EY          = $6A               ; event y (16-bit)
SQ          = $6C               ; paint address (24-bit: L/M/bank)
F0          = $6F

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

; ---------------------------------------------------------------------
main
    jsr mode_2bpp_640
    jsr draw_bands

    lda #<sc_banner
    ldx #>sc_banner
    jsr print_str

    jsr irq_install

    jsr timer_alive
    bcs @timer_ok
    lda #<sc_skip
    ldx #>sc_skip
    jsr print_str
    jmp done_print
@timer_ok

    ; --- 1: does the chain keep the KERNAL alive, do frames count? ---
    jsr RDTIM
    sta BENCH_T0
    jsr irq_frames
    sta F0
    lda #60
    sta CNT
@sixty
    jsr vsync_wait
    dec CNT
    bne @sixty
    jsr irq_frames
    sec
    sbc F0
    sta X16_P0
    stz X16_P1
    lda #<sc_frames
    ldx #>sc_frames
    jsr print_str
    jsr print_val
    jsr RDTIM
    sec
    sbc BENCH_T0
    sta X16_P0
    stz X16_P1
    lda #<sc_jiffy
    ldx #>sc_jiffy
    jsr print_str
    jsr print_val

    ; --- 2: hardware mouse pointer over the bitmap ---
    lda VERA_DC_VIDEO
    ora #VERA_VIDEO_SPRITES_EN
    sta VERA_DC_VIDEO
    jsr mouse_show

    ; --- 3: sample mouse into the event queue at scanline 0 ---
    jsr rb_init
    stz X16_P0                  ; scanline 0
    stz X16_P1
    lda #<line_handler
    ldx #>line_handler
    jsr irq_line_install

    ; --- 4: dispatch latency, min/max over 120 frames ---
    lda #120
    sta CNT
    lda #$FF
    sta MINL
    stz MAXL
@measure
    jsr wait_event
    lda VERA_IRQ_LINE_L         ; reads back the CURRENT scanline (low)
    cmp MINL
    bcs @notmin
    sta MINL
@notmin
    cmp MAXL
    bcc @notmax
    sta MAXL
@notmax
    jsr pop_event
    dec CNT
    bne @measure

    lda #<sc_latmin
    ldx #>sc_latmin
    jsr print_str
    lda MINL
    sta X16_P0
    stz X16_P1
    jsr print_val
    lda #<sc_latmax
    ldx #>sc_latmax
    jsr print_str
    lda MAXL
    sta X16_P0
    stz X16_P1
    jsr print_val

done_print
    lda #<sc_done
    ldx #>sc_done
    jsr print_str

    ; --- interactive: hold left button to paint at the pointer ---
@loop
    jsr wait_event
    jsr pop_event
    lda EBTN
    and #$01
    beq @loop
    jsr paint_mark
    bra @loop

; ---------------------------------------------------------------------
; line_handler -- runs INSIDE the IRQ once per frame at scanline 0.
; Samples the mouse and queues one 5-byte event: btn, xl, xh, yl, yh.
; mouse_get uses the library parameter block, so bracket with
; irq_save_regs/irq_restore_regs.
; ---------------------------------------------------------------------
line_handler
    jsr irq_save_regs
    jsr rb_count
    cmp #250                    ; room for a whole event, or drop it:
    bcs @out                    ; a torn event would desync the stream
    jsr mouse_get               ; X16_P0/P1 = x, P2/P3 = y, A = buttons
    jsr rb_put
    lda X16_P0
    jsr rb_put
    lda X16_P1
    jsr rb_put
    lda X16_P2
    jsr rb_put
    lda X16_P3
    jsr rb_put
@out
    jsr irq_restore_regs
    rts

; ---------------------------------------------------------------------
; wait_event / pop_event -- consumer side. rb_* is not IRQ-safe on the
; consumer side, so bracket with sei.
; ---------------------------------------------------------------------
wait_event
    php
    sei
    jsr rb_count
    plp
    cmp #5
    bcc wait_event
    rts

pop_event
    php
    sei
    jsr rb_get
    sta EBTN
    jsr rb_get
    sta EX
    jsr rb_get
    sta EX+1
    jsr rb_get
    sta EY
    jsr rb_get
    sta EY+1
    plp
    rts

; ---------------------------------------------------------------------
; paint_mark -- 4x8 black mark at the event position.
; fb address = EY*160 + EX>>2, a 17-bit result: EY*160 = t + 4t where
; t = EY*32 fits in 16 bits, the sum may carry into the VRAM bank bit.
; ---------------------------------------------------------------------
paint_mark
    lda EY+1                    ; clamp y to 472 so the mark fits
    cmp #>472
    bcc @yok
    lda EY
    cmp #<472
    bcc @yok
    lda #<472
    sta EY
    lda #>472
    sta EY+1
@yok
    ; t = y*32
    lda EY
    sta SQ
    lda EY+1
    sta SQ+1
    .repeat 5
    asl SQ
    rol SQ+1
    .endrepeat
    ; SQ(24) = t*4 + t
    lda SQ+1
    sta SQ+2                    ; borrow SQ+2 as t4 high while shifting
    lda SQ
    asl
    rol SQ+2
    asl
    rol SQ+2                    ; A = t4 low, SQ+2 = t4 high (9 bits max)
    php                         ; second rol's carry = bit 16 of t4
    clc
    adc SQ
    sta SQ
    lda SQ+2
    adc SQ+1
    sta SQ+1
    lda #0
    adc #0                      ; carry out of the 16-bit add
    plp
    adc #0                      ; ...plus t4's own bit 16 (from php? no:
    sta SQ+2                    ; plp restored flags; see note below)
    ; NOTE: t4 = y*128 <= 60416, bit 16 is never set for y <= 472, so
    ; the php/plp pair is belt-and-braces; only the add carry matters.

    ; + EX>>2
    lda EX+1
    lsr
    sta EBTN                    ; scratch: high bits of x>>2
    lda EX
    ror
    lsr EBTN
    ror
    clc
    adc SQ
    sta SQ
    lda EBTN
    adc SQ+1
    sta SQ+1
    lda #0
    adc SQ+2
    sta SQ+2

    lda #VERA_CTRL_ADDRSEL      ; port 0, one row down per write
    trb VERA_CTRL
    lda SQ
    sta VERA_ADDR_L
    lda SQ+1
    sta VERA_ADDR_M
    lda SQ+2
    and #VERA_ADDR_H_BANK
    ora #(VERA_INC_160 << 4)
    sta VERA_ADDR_H
    lda #$FF                    ; 4 pixels of color 3
    ldx #8
@rows
    sta VERA_DATA0
    dex
    bne @rows
    rts

; ---------------------------------------------------------------------
; mode + bands (same bring-up as spikes A/B)
; ---------------------------------------------------------------------
mode_2bpp_640
    vera_dcsel 0
    lda #$80
    sta VERA_DC_HSCALE
    sta VERA_DC_VSCALE
    stz VERA_DC_BORDER

    lda #(VERA_LAYER_BITMAP | VERA_LAYER_BPP_2)
    sta VERA_L0_CONFIG
    lda #((FB_BASE >> 11) << 2) | $01
    sta VERA_L0_TILEBASE
    stz VERA_L0_HSCROLL_L
    stz VERA_L0_HSCROLL_H
    stz VERA_L0_VSCROLL_L
    stz VERA_L0_VSCROLL_H

    ldx #0
    lda #$FF
    ldy #$0F
    jsr pal_set
    ldx #1
    lda #$AA
    ldy #$0A
    jsr pal_set
    ldx #2
    lda #$55
    ldy #$05
    jsr pal_set
    ldx #3
    lda #$00
    ldy #$00
    jsr pal_set

    lda VERA_DC_VIDEO
    and #%00001111
    ora #VERA_VIDEO_LAYER0_EN
    sta VERA_DC_VIDEO
    rts

draw_bands
    vera_addr 0, FB_BASE, VERA_INC_1
    lda #$00
    jsr fill_band
    lda #$55
    jsr fill_band
    lda #$AA
    jsr fill_band
    lda #$FF
fill_band
    ldx #<(120 * FB_STRIDE)
    ldy #>(120 * FB_STRIDE)
    jmp vera_fill

; ---------------------------------------------------------------------
; plumbing
; ---------------------------------------------------------------------
timer_alive
    jsr RDTIM
    sta BENCH_T0
    ldx #0
    ldy #0
@spin
    jsr RDTIM
    cmp BENCH_T0
    bne @alive
    dex
    bne @spin
    dey
    bne @spin
    clc
    rts
@alive
    sec
    rts

print_val                       ; X16_P0/P1 -> decimal + CR
    jsr u16_to_dec
    jsr print_str
    lda #$0D
    jmp CHROUT

print_str
    sta STR_PTR
    stx STR_PTR+1
    ldy #0
@loop
    lda (STR_PTR),y
    beq @done
    jsr CHROUT
    iny
    bne @loop
@done
    rts

sc_banner .byte $0D, "CXGEOS SPIKE C: EVENTS + MOUSE", $0D, 0
sc_frames .byte "FRAMES60 ", 0
sc_jiffy  .byte "JIFFY60 ", 0
sc_latmin .byte "QLATMIN ", 0
sc_latmax .byte "QLATMAX ", 0
sc_skip   .byte "SKIP TIMER DEAD", $0D, 0
sc_done   .byte "DONE", $0D, 0

; ---------------------------------------------------------------------
.include "x16_code.asm"
