; ca65
; =====================================================================
; CXRF :: spikes/spike_a.asm -- Phase 0 risk spike A
; =====================================================================
; Brings up the CXRF screen mode (640x480 @ 2bpp on VERA layer 0,
; framebuffer at VRAM $00000, 160 bytes/row, 76,800 bytes) and measures
; the raw bandwidth of the three bulk paths the OS will live on:
;
;   VFILL8   8 full-screen fills via vera_fill (CPU byte loop, port 0)
;   FXFILL8  8 full-screen fills via fx_fill (32-bit cache, 4 B/write)
;   FXCOPY8H 8 half-screen VRAM->VRAM moves via fx_copy (save-unders)
;
; Results print through CHROUT in jiffies (60ths), captured by
; build.ps1 -Capture. The screen ends on four color bands: visual
; proof the mode, palette, and addressing are right.
;
;   .\build.ps1 -Source spikes\spike_a.asm -Capture
; =====================================================================

.include "x16.asm"

X16_USE_VERA    = 1
X16_USE_VERAFX  = 1
X16_USE_PALETTE = 1
X16_USE_NUMBER  = 1

; CXRF screen geometry (the numbers the whole OS is built around).
FB_BASE     = $00000            ; framebuffer VRAM address
FB_STRIDE   = 160               ; bytes per row (640 px / 4 px per byte)
FB_HALF     = 38400             ; half a screen in bytes ($9600)

; Spike-private zero page: CXRF app space ($60-$7F).
STR_PTR     = $60               ; print_str pointer
BENCH_T0    = $62               ; RDTIM at bench start (2 bytes)
REP         = $64               ; benchmark repetition counter

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

; ---------------------------------------------------------------------
main
    jsr mode_2bpp_640
    jsr draw_bands              ; something visible while warping

    lda #<sa_banner
    ldx #>sa_banner
    jsr print_str

    jsr timer_alive
    bcs @timer_ok
    lda #<sa_skip
    ldx #>sa_skip
    jsr print_str
    bra @done
@timer_ok

    jsr bench_vfill
    lda #<sa_vfill
    ldx #>sa_vfill
    jsr print_str
    jsr print_elapsed

    jsr bench_fxfill
    lda #<sa_fxfill
    ldx #>sa_fxfill
    jsr print_str
    jsr print_elapsed

    jsr bench_fxcopy
    lda #<sa_fxcopy
    ldx #>sa_fxcopy
    jsr print_str
    jsr print_elapsed

@done
    lda #<sa_done
    ldx #>sa_done
    jsr print_str

    jsr draw_bands              ; leave the pretty screen up
@forever
    bra @forever

; ---------------------------------------------------------------------
; mode_2bpp_640 -- the CXRF screen mode, programmed on bare VERA.
; No KERNAL screen mode exists for 640x480@2bpp: layer 0 bitmap, 2bpp,
; 640-wide, full 1:1 scale. Layer 1 and sprites off. 4-entry palette.
; ---------------------------------------------------------------------
mode_2bpp_640
    vera_dcsel 0
    lda #$80                    ; 1:1 -> full 640x480
    sta VERA_DC_HSCALE
    sta VERA_DC_VSCALE
    stz VERA_DC_BORDER

    lda #(VERA_LAYER_BITMAP | VERA_LAYER_BPP_2)
    sta VERA_L0_CONFIG
    lda #((FB_BASE >> 11) << 2) | $01   ; base $00000, bitmap width 640
    sta VERA_L0_TILEBASE
    stz VERA_L0_HSCROLL_L
    stz VERA_L0_HSCROLL_H       ; bits 3:0 = palette offset for bitmaps
    stz VERA_L0_VSCROLL_L
    stz VERA_L0_VSCROLL_H

    ; palette 0-3: white paper, two grays, black ink (GEOS-ish)
    ldx #0
    lda #$FF                    ; $0FFF white
    ldy #$0F
    jsr pal_set
    ldx #1
    lda #$AA                    ; $0AAA light gray
    ldy #$0A
    jsr pal_set
    ldx #2
    lda #$55                    ; $0555 dark gray
    ldy #$05
    jsr pal_set
    ldx #3
    lda #$00                    ; $0000 black
    ldy #$00
    jsr pal_set

    ; layer 0 on, layer 1 and sprites off; keep output mode bits
    lda VERA_DC_VIDEO
    and #%00001111
    ora #VERA_VIDEO_LAYER0_EN
    sta VERA_DC_VIDEO
    rts

; ---------------------------------------------------------------------
; draw_bands -- four 120-row bands, colors 0..3. Address auto-advances
; across the four sequential fills.
; ---------------------------------------------------------------------
draw_bands
    vera_addr 0, FB_BASE, VERA_INC_1
    lda #$00                    ; 4 pixels of color 0
    jsr fill_band
    lda #$55                    ; color 1
    jsr fill_band
    lda #$AA                    ; color 2
    jsr fill_band
    lda #$FF                    ; color 3
    ; fall through
fill_band                       ; A = byte pattern, 120 rows = 19,200 bytes
    ldx #<(120 * FB_STRIDE)
    ldy #>(120 * FB_STRIDE)
    jmp vera_fill

; ---------------------------------------------------------------------
; timer_alive -- carry set if RDTIM is ticking (it is not under
; -testbench, where no VSYNC IRQ runs).
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
    clc                         ; ~64K polls without a tick: dead
    rts
@alive
    sec
    rts

; ---------------------------------------------------------------------
; benchmarks. Each: t0 = RDTIM, 8 repetitions, elapsed -> X16_P0/P1.
; vera_fill/fx_fill counts are 16-bit, so a 76,800-byte screen is two
; 38,400-byte halves per repetition.
; ---------------------------------------------------------------------
bench_vfill
    jsr time_start
    lda #8
    sta REP
@rep
    vera_addr 0, FB_BASE, VERA_INC_1
    lda #$1B                    ; pixel stripe 0,1,2,3
    ldx #<FB_HALF
    ldy #>FB_HALF
    jsr vera_fill               ; port 0 now sits at $9600...
    lda #$1B
    ldx #<FB_HALF
    ldy #>FB_HALF
    jsr vera_fill               ; ...second half continues from there
    dec REP
    bne @rep
    jmp time_end

bench_fxfill
    jsr time_start
    lda #8
    sta REP
@rep
    stz X16_P0                  ; dst = $00000
    stz X16_P1
    stz X16_P2
    lda #<FB_HALF
    sta X16_P3
    lda #>FB_HALF
    sta X16_P4
    lda #$E4                    ; pixel stripe 3,2,1,0
    jsr fx_fill
    lda #<FB_HALF               ; dst = $09600
    sta X16_P0
    lda #>FB_HALF
    sta X16_P1
    stz X16_P2
    lda #<FB_HALF
    sta X16_P3
    lda #>FB_HALF
    sta X16_P4
    lda #$E4
    jsr fx_fill
    dec REP
    bne @rep
    jmp time_end

bench_fxcopy                    ; half screen $00000 -> $13000, x8
    jsr time_start
    lda #8
    sta REP
@rep
    stz X16_P0                  ; src = $00000
    stz X16_P1
    stz X16_P2
    stz X16_P3                  ; dst = $13000 (4-byte aligned)
    lda #$30
    sta X16_P4
    lda #$01
    sta X16_P5
    lda #<FB_HALF
    sta X16_P6
    lda #>FB_HALF
    sta X16_P7
    jsr fx_copy
    dec REP
    bne @rep
    jmp time_end

; ---------------------------------------------------------------------
; timing plumbing
; ---------------------------------------------------------------------
time_start
    jsr RDTIM                   ; A = lo, X = mid, Y = hi jiffies
    sta BENCH_T0
    stx BENCH_T0+1
    rts

time_end                        ; X16_P0/P1 = elapsed jiffies
    jsr RDTIM
    sec
    sbc BENCH_T0
    sta X16_P0
    txa
    sbc BENCH_T0+1
    sta X16_P1
    rts

print_elapsed                   ; X16_P0/P1 already loaded by time_end
    jsr u16_to_dec              ; A/X = buffer, Y = length
    jsr print_str
    lda #<sa_jf
    ldx #>sa_jf
    jmp print_str

; ---------------------------------------------------------------------
; print_str -- NUL-terminated string via CHROUT. in: A = lo, X = hi
; ---------------------------------------------------------------------
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

sa_banner .byte $0D, "CXRF SPIKE A: 640X480 2BPP", $0D, 0
sa_vfill  .byte "VFILL8 ", 0
sa_fxfill .byte "FXFILL8 ", 0
sa_fxcopy .byte "FXCOPY8H ", 0
sa_jf     .byte " JF", $0D, 0
sa_skip   .byte "SKIP TIMER DEAD", $0D, 0
sa_done   .byte "DONE", $0D, 0

; ---------------------------------------------------------------------
.include "x16_code.asm"
