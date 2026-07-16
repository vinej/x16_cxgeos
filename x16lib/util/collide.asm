;ACME
; =====================================================================
; x16lib :: util/collide.asm -- axis-aligned bounding-box overlap
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; collide8 -- do two boxes overlap?
;   in:  X16_P0 = ax, X16_P1 = ay, X16_P2 = aw, X16_P3 = ah
;        X16_P4 = bx, X16_P5 = by, X16_P6 = bw, X16_P7 = bh
;   out: carry set if the boxes overlap, clear otherwise
;
; Coordinates and sizes are unsigned bytes; the edge sums are computed
; in 9 bits so a box may legitimately run past x=255.
;
; Edges that merely touch do NOT overlap: a box at x=0 width 10 and one
; at x=10 are adjacent, not colliding. Overlap on an axis is
;       ax < bx+bw  AND  bx < ax+aw
; and both must hold on x and on y.
; ---------------------------------------------------------------------
; Coordinates fit in a byte, so this cannot describe the right-hand half
; of a 640-wide display. Use collide16 there.
collide8
    ; --- x axis ---
    lda X16_P4
    clc
    adc X16_P6                  ; bx + bw
    bcs @ax_lt                  ; past 255, so ax is certainly less
    cmp X16_P0                  ; carry set if (bx+bw) >= ax
    bcc @apart
    beq @apart                  ; equal means touching, not overlapping
@ax_lt
    lda X16_P0
    clc
    adc X16_P2                  ; ax + aw
    bcs @bx_lt
    cmp X16_P4
    bcc @apart
    beq @apart
@bx_lt

    ; --- y axis ---
    lda X16_P5
    clc
    adc X16_P7                  ; by + bh
    bcs @ay_lt
    cmp X16_P1
    bcc @apart
    beq @apart
@ay_lt
    lda X16_P1
    clc
    adc X16_P3                  ; ay + ah
    bcs @by_lt
    cmp X16_P5
    bcc @apart
    beq @apart
@by_lt

    sec
    rts
@apart
    clc
    rts

; ---------------------------------------------------------------------
; collide16 -- the same test with 16-bit unsigned coordinates and sizes.
;
; Needed for anything positioned in display space: in the default 80x60
; text mode the X16's screen is 640x480, and sprite coordinates are in
; those units. Only screen modes 2, 3 and $80 halve it to 320x240.
;
; Eight 16-bit fields, more than the parameter block holds, so the
; caller writes them directly:
;
;       lda #<x : sta cl_ax : lda #>x : sta cl_ax+1
;       ... cl_ay, cl_aw, cl_ah, cl_bx, cl_by, cl_bw, cl_bh ...
;       jsr collide16
;
;   out: carry set if the boxes overlap
;
; The edge sums are 17-bit, so a box may legitimately run past x=65535.
; Touching edges do not overlap, exactly as in collide8.
; ---------------------------------------------------------------------
collide16
    ; ax < bx + bw ?
    clc
    lda cl_bx
    adc cl_bw
    sta cl_t0
    lda cl_bx+1
    adc cl_bw+1
    sta cl_t1
    bcs @ax_lt                  ; sum overflowed 16 bits: ax is less
    lda cl_ax
    cmp cl_t0
    lda cl_ax+1
    sbc cl_t1
    bcs @apart16                ; ax >= sum, so touching or clear
@ax_lt

    ; bx < ax + aw ?
    clc
    lda cl_ax
    adc cl_aw
    sta cl_t0
    lda cl_ax+1
    adc cl_aw+1
    sta cl_t1
    bcs @bx_lt
    lda cl_bx
    cmp cl_t0
    lda cl_bx+1
    sbc cl_t1
    bcs @apart16
@bx_lt

    ; ay < by + bh ?
    clc
    lda cl_by
    adc cl_bh
    sta cl_t0
    lda cl_by+1
    adc cl_bh+1
    sta cl_t1
    bcs @ay_lt
    lda cl_ay
    cmp cl_t0
    lda cl_ay+1
    sbc cl_t1
    bcs @apart16
@ay_lt

    ; by < ay + ah ?
    clc
    lda cl_ay
    adc cl_ah
    sta cl_t0
    lda cl_ay+1
    adc cl_ah+1
    sta cl_t1
    bcs @by_lt
    lda cl_by
    cmp cl_t0
    lda cl_by+1
    sbc cl_t1
    bcs @apart16
@by_lt

    sec
    rts
@apart16
    clc
    rts

; Box A, box B, and scratch. Written by the caller.
cl_ax .word 0
cl_ay .word 0
cl_aw .word 0
cl_ah .word 0
cl_bx .word 0
cl_by .word 0
cl_bw .word 0
cl_bh .word 0
cl_t0 .byte 0
cl_t1 .byte 0

; (end zone)
