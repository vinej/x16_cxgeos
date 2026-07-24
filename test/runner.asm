; ca65
; =====================================================================
; CXRF :: test/runner.asm -- on-target regression tests
; =====================================================================
;   .\build.ps1 -Test
;
; The x16lib pattern: drive the code one way, verify through an
; independent path (write via port 0, read back via port 1). Runs
; headless under -testbench (nothing here needs VSYNC).
;
; The 2bpp engine itself is tested where it lives -- the x16_library
; gfx2 module and its runner2 suite. These tests pin the CXRF side:
; the vendored module boots our screen, and the framebuffer geometry
; the OS is built around holds.
; =====================================================================

.include "x16.asm"
.include "kernel/resident/zp.inc"
.include "kernel/resident/banks.inc"

X16_USE_BITMAP2H = 1            ; pulls in VERA and VERAFX_FILL
X16_USE_VERAFX_COPY = 1         ; the menu engine's save-under
X16_USE_IRQ     = 1             ; the event system's raster hook
X16_USE_INPUT   = 1             ; ...and its mouse and keyboard

CX_NO_OVERLAY   = 1             ; the runner links flat: the 2bpp engine
                                ; sits in CODE (the gate above) and the
                                ; graphics-port names alias it directly
.include "kernel/video/ovl.inc"

FB_STRIDE   = 160

; framebuffer byte addresses the tests probe
ROW100   = 100 * FB_STRIDE
ROW200B1 = 200 * FB_STRIDE + 1
FB_LAST  = 480 * FB_STRIDE - 1

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

; ---------------------------------------------------------------------
main
    jsr t_init

    jsr test_gfx2h_init
    jsr test_fb_roundtrip
    jsr test_gfx2h_draws

    jsr test_dr_add
    jsr test_dr_merge
    jsr test_dr_separate
    jsr test_dr_cascade
    jsr test_dr_full

    jsr test_font_set
    jsr test_font_bad
    jsr test_font_cache
    jsr test_font_measure
    jsr test_font_draw
    jsr test_font_pen
    jsr test_font_bold
    jsr test_font_under
    jsr test_font_pen_bold
    jsr test_font_banked

    jsr test_ev_queue
    jsr test_ev_coalesce
    jsr test_ev_overflow
    jsr test_ev_wrap
    jsr test_ev_dispatch
    jsr test_ev_null
    jsr test_ev_joy_reset
    jsr test_ev_mask
    jsr test_spr_collide
    jsr test_ev_borrow
    jsr test_ev_modal_tables

    jsr test_abi_header
    jsr test_abi_table
    jsr test_abi_call
    jsr test_menu_active
    jsr test_dlg_prompt_zero

    jsr test_rg_stack
    jsr test_rg_route
    jsr test_ev_region
    jsr test_wg_hit
    jsr test_shp_hit
    jsr test_wg_scroll
    jsr test_wg_hit_route
    jsr test_farcall
    jsr test_vrows
    jsr test_mouse

    jsr test_app_missing
    jsr test_app_badmagic
    jsr test_app_toonew
    jsr test_dir
    jsr test_dir_irq
    jsr test_file_load
    jsr test_as_vload
    jsr test_as_bload
    jsr test_clip
    jsr test_clip_span
    jsr test_vram_stream
    jsr test_font_bank

    jsr t_summary
    rts

; ---------------------------------------------------------------------
; dirty-rectangle list (kernel/gfx2/dirty.asm) -- pure data structure,
; nothing on screen. dr_put is a helper: A/X/Y = x, w, h with y fixed
; per test via P2/P3 beforehand? No -- each test loads the block.
; ---------------------------------------------------------------------

; add rect from an 8-byte table at A/X (x,y,w,h as words, little-endian)
dr_put
    sta X16_T6
    stx X16_T7
    ldy #7
@copy
    lda (X16_TPTR3),y
    sta X16_P0,y
    dey
    bpl @copy
    jmp dr_add

; WG_HIT: the ellipse hit test (kernel/ui/widget.asm). An ellipse at box
; (100,100,80,40) -> centre (140,120), rx 40, ry 20. Points inside/outside,
; on the edge, and one in the box but outside the ellipse.
test_wg_hit
    lda #<@rec
    sta CX_M_PTR
    lda #>@rec
    sta CX_M_PTR+1
    ldy #1                      ; Y = fail; cleared to 0 only if all pass

    lda #140                    ; centre -> inside
    sta X16_P2
    stz X16_P3
    lda #120
    sta X16_P4
    stz X16_P5
    jsr wg_hit_ellipse
    bcc @report

    lda #<300                   ; far outside -> outside
    sta X16_P2
    lda #>300
    sta X16_P3
    lda #<300
    sta X16_P4
    lda #>300
    sta X16_P5
    jsr wg_hit_ellipse
    bcs @report

    lda #180                    ; the +x vertex (cx+rx) -> inside (boundary)
    sta X16_P2
    stz X16_P3
    lda #120
    sta X16_P4
    stz X16_P5
    jsr wg_hit_ellipse
    bcc @report

    lda #181                    ; one past the vertex -> outside
    sta X16_P2
    stz X16_P3
    lda #120
    sta X16_P4
    stz X16_P5
    jsr wg_hit_ellipse
    bcs @report

    lda #175                    ; inside the box, outside the ellipse
    sta X16_P2
    stz X16_P3
    lda #135
    sta X16_P4
    stz X16_P5
    jsr wg_hit_ellipse
    bcs @report

    ldy #0                      ; every case matched
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "WG_HIT", 0
@rec
    .byte WG_HIT, 0             ; type, flags
    .word 100, 100             ; x, y
    .word 80                   ; w
    .byte 40                   ; h
    .byte WH_ELLIPSE           ; WG_VAL = shape
    .byte 0                    ; WG_GRP
    .word 0                    ; WG_LBL
    .byte 0, 0, 0              ; pad to WG_SIZE (16)

; SHP_HIT: the polygon and pie point tests (kernel/video/shphit.asm), the
; bank-19 refine reached for WH_POLYGON/WH_PIE. Both sit in box
; (100,100,80,80) -> centre (140,140), r 40. The hexagon (rotation 0) puts a
; vertex due east and a flat side due north; the wedge faces east (224..32).
; Cases hand-computed against sin8/cos8/atan2 -- the point of the shapes is
; that a point in the BOX but outside the shape is rejected.
test_shp_hit
    stz @f
    lda #<@hex
    sta CX_M_PTR
    lda #>@hex
    sta CX_M_PTR+1
    lda #140                    ; centre -> inside
    ldx #140
    jsr @pt
    jsr shp_hit
    jsr @want_in
    lda #140                    ; 30px north: inside the apothem
    ldx #110
    jsr @pt
    jsr shp_hit
    jsr @want_in
    lda #140                    ; 38px north: past the flat side (in box) -> out
    ldx #102
    jsr @pt
    jsr shp_hit
    jsr @want_out
    lda #180                    ; the east vertex (cx+r) -> inside (boundary)
    ldx #140
    jsr @pt
    jsr shp_hit
    jsr @want_in
    lda #181                    ; one past the vertex -> outside
    ldx #140
    jsr @pt
    jsr shp_hit
    jsr @want_out
    lda #105                    ; a box corner -> outside the hexagon
    ldx #105
    jsr @pt
    jsr shp_hit
    jsr @want_out

    lda #<@pie                  ; --- the east-facing wedge (224..32) ---
    sta CX_M_PTR
    lda #>@pie
    sta CX_M_PTR+1
    lda #170                    ; due east, within r -> inside the wedge
    ldx #140
    jsr @pt
    jsr shp_hit
    jsr @want_in
    lda #140                    ; due south -> right radius, wrong angle -> out
    ldx #170
    jsr @pt
    jsr shp_hit
    jsr @want_out
    lda #140                    ; due north -> wrong angle -> out
    ldx #110
    jsr @pt
    jsr shp_hit
    jsr @want_out
    lda #190                    ; due east but past r -> outside
    ldx #140
    jsr @pt
    jsr shp_hit
    jsr @want_out

    lda @f                      ; A = failure count (0 = every case matched)
    ldx #<@name
    ldy #>@name
    jmp t_result
@pt                             ; A = x, X = y -> the event point P2..P5
    sta X16_P2
    stz X16_P3
    stx X16_P4
    stz X16_P5
    rts
@want_in                        ; carry set expected (inside)
    bcs @wi
    inc @f
@wi
    rts
@want_out                       ; carry clear expected (outside)
    bcc @wo
    inc @f
@wo
    rts
@f      .byte 0
@name   .byte "SHP_HIT", 0
@hex
    .byte WG_HIT, 0
    .word 100, 100
    .word 80
    .byte 80
    .byte WH_POLYGON
    .byte 0
    .word 0
    .byte 6, 0, 0              ; WH_SIDES = 6, WH_ROT = 0
@pie
    .byte WG_HIT, 0
    .word 100, 100
    .word 80
    .byte 80
    .byte WH_PIE
    .byte 0
    .word 0
    .byte 224, 32, 0          ; WH_A0 = 224 (NE), WH_A1 = 32 (SE)

; WG_SCROLL: wg_scroll_to (the slider value from a click x). A scrollbar at
; x=100 w=250 max=10 -> span = w-4-THUMB = 230. The value is the CLAMPED rel
; * max / span, in ANY mode (px/x/w share the mode's units). A drag PAST the
; right end (rel > 255) must CLAMP to max, not wrap toward 0 through rel's low
; byte -- that wrap made the number flicker (1 2 3 1 ...) and the thumb snap
; back to the start on release.
; WG_SCROLL: wg_scroll_to maps a click x to a scrollbar value. Two cases that
; both used to fail: a normal drag, and an over-drag past the right end. The
; latter (rel 298 > span 230) both exercises the wg_dragpx clamp AND divides
; 2300/230 -- whose partial remainder crosses 256, the wg_div16 9th-bit bug
; that made mid-range values collapse toward the start.
test_wg_scroll
    stz @f
    lda #<@rec                  ; px 200: rel 98 -> 98*10/230 = 4
    sta CX_M_PTR
    lda #>@rec
    sta CX_M_PTR+1
    lda #<200
    sta X16_P2
    lda #>200
    sta X16_P3
    stz X16_P4
    stz X16_P5
    jsr wg_scroll_to
    cmp #4
    beq @v1
    inc @f
@v1
    lda #<@rec                  ; wg_paint may move the block; re-point it
    sta CX_M_PTR
    lda #>@rec
    sta CX_M_PTR+1
    lda #<400                   ; px 400: rel 298 > span -> clamp 230; 2300/230
    sta X16_P2                  ; = 10 (NOT 1 from the lost-carry div, NOT ~1
    lda #>400                   ; from the low-byte wrap)
    sta X16_P3
    stz X16_P4
    stz X16_P5
    jsr wg_scroll_to
    cmp #10
    beq @v2
    inc @f
@v2
    lda @f
    ldx #<@name
    ldy #>@name
    jmp t_result
@f    .byte 0
@name .byte "WG_SCROLL", 0
@rec
    .byte WG_SCROLL, 0
    .word 100, 100
    .word 250
    .byte 16
    .byte 0                     ; WG_VAL
    .byte 10                    ; WG_GRP = max
    .word 0
    .byte 0, 0, 0

; WG_HIT_R: the full routing over a TWO-widget list -- a synthetic mouse event
; through wg_hit posts EV_WIDGET with the right index for a hit and nothing for
; a miss. The second region proves wg_rec's 16-byte stride: a short record would
; misalign it onto a real painter (the demo's original bug).
test_wg_hit_route
    jsr ev_init
    lda #$FF
    sta wg_drag                 ; no scrollbar drag in progress
    lda #<@list
    ldx #>@list
    jsr wg_setup                ; two WG_HIT widgets, no-op painted
    ldy #1

    lda #EV_MOUSE_DOWN          ; a press inside widget 0 (the rect)
    sta X16_P0
    lda #40
    sta X16_P2
    stz X16_P3
    lda #30
    sta X16_P4
    stz X16_P5
    jsr wg_hit
    jsr ev_get
    lda X16_P0
    cmp #EV_WIDGET
    bne @r2
    lda X16_P1                  ; index 0
    bne @r2

    lda #EV_MOUSE_DOWN          ; a press inside widget 1 (the ellipse centre)
    sta X16_P0
    lda #140
    sta X16_P2
    stz X16_P3
    lda #120
    sta X16_P4
    stz X16_P5
    jsr wg_hit
    jsr ev_get
    lda X16_P0
    cmp #EV_WIDGET
    bne @r2
    lda X16_P1                  ; index 1 -- the stride is right
    cmp #1
    bne @r2

    lda #EV_MOUSE_DOWN          ; a press outside both -> nothing
    sta X16_P0
    lda #<300
    sta X16_P2
    lda #>300
    sta X16_P3
    lda #<300
    sta X16_P4
    lda #>300
    sta X16_P5
    jsr wg_hit
    jsr ev_count
    bne @r2
    bra @cont
@r2
    jmp @report                 ; the checks above are too far for a short branch
@cont

    lda #<@list                 ; re-park to reset wg_hover
    ldx #>@list
    jsr wg_setup
    lda #$FF
    sta wg_drag
    lda #EV_MOUSE_MOVE          ; a hover-in over widget 1
    sta X16_P0
    lda #140
    sta X16_P2
    stz X16_P3
    lda #120
    sta X16_P4
    stz X16_P5
    jsr wg_hit
    jsr ev_count                ; one enter EV_WIDGET queued?
    cmp #1
    bne @report

    lda #<@click                ; a click-only list: hover is gated OFF, so a
    ldx #>@click                ; MOVE over it does no work and posts nothing
    jsr wg_setup
    lda #$FF
    sta wg_drag
    lda #EV_MOUSE_MOVE
    sta X16_P0
    lda #40
    sta X16_P2
    stz X16_P3
    lda #30
    sta X16_P4
    stz X16_P5
    jsr wg_hit
    jsr ev_count
    bne @report                 ; expected nothing

    ldy #0
@report
    jsr rg_reset
    jsr ev_stop
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "WG_HIT_R", 0
@click                          ; one WG_HIT rect, click-only (no WH_HOVER)
    .byte 1
    .byte WG_HIT, 0
    .word 10, 10
    .word 60
    .byte 40
    .byte WH_RECT
    .byte WH_CLICK
    .word 0
    .byte 0, 0, 0
@list
    .byte 2
    ; widget 0: a rect, box (10,10) 60x40
    .byte WG_HIT, 0
    .word 10, 10
    .word 60
    .byte 40
    .byte WH_RECT
    .byte WH_CLICK | WH_HOVER
    .word 0
    .byte 0, 0, 0
    ; widget 1: an ellipse, box (100,100) 80x40 -> centre (140,120)
    .byte WG_HIT, 0
    .word 100, 100
    .word 80
    .byte 40
    .byte WH_ELLIPSE
    .byte WH_CLICK | WH_HOVER
    .word 0
    .byte 0, 0, 0

; DR_ADD: one rect stored with inclusive corners
test_dr_add
    jsr dr_reset
    lda #<@r1
    ldx #>@r1
    jsr dr_put
    ldy #1
    jsr dr_count
    cmp #1
    bne @report
    lda #0
    jsr dr_get
    ldy #1
    lda X16_P0                  ; x0 = 10
    cmp #10
    bne @report
    lda X16_P4                  ; x1 = 29
    cmp #29
    bne @report
    lda X16_P2                  ; y0 = 10
    cmp #10
    bne @report
    lda X16_P6                  ; y1 = 29
    cmp #29
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "DR_ADD", 0
@r1 .word 10, 10, 20, 20

; DR_MERGE: an overlapping rect unions; a touching rect unions too
test_dr_merge
    jsr dr_reset
    lda #<@m1
    ldx #>@m1
    jsr dr_put
    lda #<@m2                   ; overlaps m1
    ldx #>@m2
    jsr dr_put
    ldy #1
    jsr dr_count
    cmp #1
    bne @report
    lda #0
    jsr dr_get
    ldy #1
    lda X16_P4                  ; x1 = max(29, 44) = 44
    cmp #44
    bne @report
    lda #<@m3                   ; x0 = 45 touches x1 = 44
    ldx #>@m3
    jsr dr_put
    ldy #1
    jsr dr_count
    cmp #1
    bne @report
    lda #0
    jsr dr_get
    ldy #1
    lda X16_P4                  ; x1 = 49 now
    cmp #49
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "DR_MERGE", 0
@m1 .word 10, 10, 20, 20
@m2 .word 25, 15, 20, 10
@m3 .word 45, 10,  5,  5

; DR_SEPARATE: disjoint rects stay in their own slots
test_dr_separate
    jsr dr_reset
    lda #<@s1
    ldx #>@s1
    jsr dr_put
    lda #<@s2
    ldx #>@s2
    jsr dr_put
    ldy #1
    jsr dr_count
    cmp #2
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "DR_SEPARATE", 0
@s1 .word 0,   0,   10, 10
@s2 .word 100, 100, 10, 10

; DR_CASCADE: a bridge rect swallows two islands into one
test_dr_cascade
    jsr dr_reset
    lda #<@c1
    ldx #>@c1
    jsr dr_put
    lda #<@c2
    ldx #>@c2
    jsr dr_put
    lda #<@c3                   ; spans the gap: touches both
    ldx #>@c3
    jsr dr_put
    ldy #1
    jsr dr_count
    cmp #1
    bne @report
    lda #0
    jsr dr_get
    ldy #1
    lda X16_P0                  ; bbox (0,0)-(39,9)
    bne @report
    lda X16_P4
    cmp #39
    bne @report
    lda X16_P6
    cmp #9
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "DR_CASCADE", 0
@c1 .word 0,  0, 10, 10
@c2 .word 30, 0, 10, 10
@c3 .word 8,  0, 25, 10

; DR_FULL: a ninth disjoint rect folds instead of overflowing
test_dr_full
    jsr dr_reset
    ldx #0
@fill                           ; 8 disjoint rects at x = 0,40,80,...
    phx
    txa
    sta X16_P0                  ; x = i*40 (fits a byte: 0..280? no --
    stz X16_P1                  ; i*40 <= 280 needs 9 bits; use *32)
    stz X16_P2
    stz X16_P3
    lda #10
    sta X16_P4
    stz X16_P5
    lda #10
    sta X16_P6
    stz X16_P7
    jsr dr_add
    pla
    clc
    adc #32
    tax
    cpx #0                      ; 8 * 32 = 256 wraps to 0: done
    bne @fill
    jsr dr_count
    cmp #8
    bne @bad
    lda #<@f9                   ; a ninth, far away: the fold makes a
    ldx #>@f9                   ; bbox that cascades over every slot
    jsr dr_put
    jsr dr_count
    cmp #1                      ; collapsed, coverage intact
    bne @bad
    lda #0
    jsr dr_get
    lda X16_P0                  ; bbox (0,0)-(409,409) covers all nine
    ora X16_P1
    ora X16_P2
    ora X16_P3
    bne @bad
    lda X16_P4
    cmp #<409
    bne @bad
    lda X16_P5
    cmp #>409
    bne @bad
    lda X16_P6
    cmp #<409
    bne @bad
    ldy #0
    bra @report
@bad
    ldy #1
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "DR_FULL", 0
@f9 .word 400, 400, 10, 10

; ---------------------------------------------------------------------
; GFX2_INIT -- the vendored module programs the CXRF screen mode
; ---------------------------------------------------------------------
test_gfx2h_init
    jsr gfx2h_init
    ldy #1                      ; presume failure
    lda VERA_L0_CONFIG
    cmp #(VERA_LAYER_BITMAP | VERA_LAYER_BPP_2)
    bne @report
    lda VERA_L0_TILEBASE
    cmp #$01                    ; base $00000, 640 wide
    bne @report
    vera_dcsel 0
    lda VERA_DC_HSCALE
    cmp #$80
    bne @report
    lda VERA_DC_VSCALE
    cmp #$80
    bne @report
    lda VERA_DC_VIDEO
    and #VERA_VIDEO_LAYER0_EN
    beq @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "GFX2_INIT", 0

; ---------------------------------------------------------------------
; FB_RW -- bytes written into the framebuffer via port 0 read back
; identically via port 1 (raw geometry sanity, first and last bytes)
; ---------------------------------------------------------------------
test_fb_roundtrip
    vera_addr 0, ROW100, VERA_INC_1
    ldx #0
@write
    lda @pattern,x
    sta VERA_DATA0
    inx
    cpx #8
    bne @write

    vera_addr 1, ROW100, VERA_INC_1
    ldx #0
@verify
    lda VERA_DATA1
    cmp @pattern,x
    bne @bad
    inx
    cpx #8
    bne @verify

    vera_addr 0, FB_LAST, VERA_INC_1
    lda #$5A
    sta VERA_DATA0
    vera_addr 1, FB_LAST, VERA_INC_1
    lda VERA_DATA1
    cmp #$5A
    bne @bad
    lda #0
    bra @report
@bad
    lda #1
@report
    ldx #<@name
    ldy #>@name
    jmp t_result
@name    .byte "FB_RW", 0
@pattern .byte $00, $1B, $55, $AA, $FF, $E4, $0F, $F0

; ---------------------------------------------------------------------
; GFX2_DRAWS -- clear + a rect land the right bytes where the OS
; expects them (library correctness is runner2's job upstream)
; ---------------------------------------------------------------------
test_gfx2h_draws
    lda #0
    jsr gfx2h_clear              ; colour 0 -> byte $00 everywhere

    lda #4                      ; x=4 y=200 w=8 h=1, colour 3
    sta X16_P0
    stz X16_P1
    lda #<200
    sta X16_P2
    stz X16_P3
    lda #8
    sta X16_P4
    stz X16_P5
    lda #1
    sta X16_P6
    stz X16_P7
    lda #3
    jsr gfx2h_rect

    vera_addr 1, ROW200B1, VERA_INC_1
    lda VERA_DATA1
    cmp #$FF                    ; pixels 4-7
    bne @bad
    lda VERA_DATA1
    cmp #$FF                    ; pixels 8-11
    bne @bad
    lda VERA_DATA1
    bne @bad                    ; pixel 12+: cleared background
    lda #0
    bra @report
@bad
    lda #1
@report
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "GFX2_DRAWS", 0


; =====================================================================
; the font engine (kernel/font/font.asm) against the real system font.
; Expected values come from fonts/pxl8.cxf itself, not from arithmetic
; done here: 'i' is glyph 73, two pixels wide, and its first row is $C0.
; =====================================================================

; FONT_SET: the magic is checked and the header parked
test_font_set
    lda #<pxl8
    ldx #>pxl8
    jsr font_set
    ldy #1
    bcs @report                 ; carry set = magic rejected
    lda f_height
    cmp #8
    bne @report
    lda f_ascent
    cmp #7
    bne @report
    lda f_first
    cmp #32
    bne @report
    lda f_count
    cmp #95
    bne @report
    lda f_spacing
    cmp #1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_SET", 0

; FONT_BAD: rejecting a candidate must leave the previous live font
; pointer intact. The bad magic path used to return carry but leave
; CX_F_CXF/f_bank aimed at the rejected buffer, so the next measure read
; widths from garbage.
test_font_bad
    lda #<pxl8
    ldx #>pxl8
    jsr font_set
    lda #<@str
    ldx #>@str
    jsr font_measure
    lda X16_P0
    sta @w0
    lda X16_P1
    sta @w0+1

    lda #<@badfont
    ldx #>@badfont
    jsr font_set
    ldy #1
    bcc @report                ; bad magic must be refused

    lda #<@str
    ldx #>@str
    jsr font_measure
    lda X16_P0
    cmp @w0
    bne @report
    lda X16_P1
    cmp @w0+1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_BAD", 0
@str .byte "Wig.", 0
@w0 .word 0
@badfont .byte "NOPE", 8, 7, 32, 95, 8, 1, 0, 0, 0, 0, 0, 0

; FONT_CACHE: 'i' row 0 is $C0 -- pixels 0 and 1. At phase 0 that is
; coverage $F0 in column 0 and nothing in columns 1-2; at phase 1 the
; same two pixels have walked right to $3C. Glyph 73 lives in bank 7 at
; $B740, which is (73 % 42) * 192 past the window.
test_font_cache
    lda RAM_BANK
    pha
    lda #7
    sta RAM_BANK
    ldy #1

    lda $B740                   ; phase 0, column 0, row 0: mask
    cmp #$0F
    bne @report
    lda $B741                   ; ...and data
    cmp #$F0
    bne @report
    lda $B750                   ; phase 0, column 1: untouched by a
    cmp #$FF                    ; two-pixel glyph, so all mask
    bne @report
    lda $B751
    bne @report

    lda $B742                   ; row 1 of 'i' is blank
    cmp #$FF
    bne @report
    lda $B743
    bne @report

    lda $B740+48                ; phase 1, column 0, row 0
    cmp #$C3
    bne @report
    lda $B741+48
    cmp #$3C
    bne @report
    ldy #0
@report
    pla
    sta RAM_BANK
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_CACHE", 0

; FONT_MEASURE: W=7 i=2 g=6 .=2, plus one pixel of spacing each = 21.
; A monospace 8 would say 32.
test_font_measure
    lda #<@str
    ldx #>@str
    jsr font_measure
    ldy #1
    lda X16_P0
    cmp #21
    bne @report
    lda X16_P1
    bne @report

    lda #<@empty                ; an empty string measures zero
    ldx #>@empty
    jsr font_measure
    lda X16_P0
    ora X16_P1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name  .byte "FONT_MEASURE", 0
@str   .byte "Wig.", 0
@empty .byte 0

; FONT_DRAW: 'i' at (0,100) on a cleared row lights pixels 0 and 1 of
; byte 0 -- $F0 -- and leaves byte 1 alone. At x=1 the same glyph lands
; on pixels 1 and 2, $3C, which is the pre-shifted phase doing its job.
test_font_draw
    vera_addr 0, ROW100, VERA_INC_1
    lda #$00
    ldx #8
    ldy #0
    jsr vera_fill

    stz X16_P0
    stz X16_P1
    lda #<100
    sta X16_P2
    stz X16_P3
    lda #<@i
    ldx #>@i
    jsr font_draw

    vera_addr 1, ROW100, VERA_INC_1
    ldy #1
    lda VERA_DATA1
    cmp #$F0
    bne @report
    lda VERA_DATA1              ; a 2-pixel glyph never reaches byte 1
    bne @report

    vera_addr 0, ROW100, VERA_INC_1
    lda #$00
    ldx #8
    ldy #0
    jsr vera_fill

    lda #1                      ; x = 1: phase 1
    sta X16_P0
    stz X16_P1
    lda #<100
    sta X16_P2
    stz X16_P3
    lda #<@i
    ldx #>@i
    jsr font_draw

    vera_addr 1, ROW100, VERA_INC_1
    lda VERA_DATA1
    cmp #$3C
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_DRAW", 0
@i    .byte "i", 0

; FONT_PEN: what font_draw advances the pen by must be exactly what
; font_measure promised. If these ever disagree, every layout in the
; system is wrong -- and the two compute it by different routes.
test_font_pen
    vera_addr 0, ROW200B1 - 1, VERA_INC_1
    lda #$00
    ldx #<200
    ldy #>200
    jsr vera_fill

    lda #<@str
    ldx #>@str
    jsr font_measure
    lda X16_P0
    sta @want
    lda X16_P1
    sta @want+1

    lda #<40                    ; draw from a non-zero, non-aligned pen
    sta X16_P0
    stz X16_P1
    lda #<200
    sta X16_P2
    stz X16_P3
    lda #<@str
    ldx #>@str
    jsr font_draw               ; out: P0/P1 = the pen

    ldy #1
    sec                         ; pen - 40 == measured width?
    lda X16_P0
    sbc #40
    cmp @want
    bne @report
    lda X16_P1
    sbc #0
    cmp @want+1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_PEN", 0
@str  .byte "Hamburgefonstiv 123", 0
@want .word 0


; FONT_BOLD: bold strikes the glyph again one pixel right, so 'i' -- two
; pixels at $F0 -- becomes three at $FC. The advance grows with it, and
; that has to come from f_advance or measure and draw would part ways.
test_font_bold
    vera_addr 0, ROW100, VERA_INC_1
    lda #$00
    ldx #8
    ldy #0
    jsr vera_fill

    lda #FONT_BOLD
    jsr font_style
    stz X16_P0
    stz X16_P1
    lda #<100
    sta X16_P2
    stz X16_P3
    lda #<@i
    ldx #>@i
    jsr font_draw

    vera_addr 1, ROW100, VERA_INC_1
    ldy #1
    lda VERA_DATA1
    cmp #$FC                    ; three pixels wide now
    bne @report
    lda VERA_DATA1
    bne @report                 ; and still nowhere near byte 1

    lda #<@i                    ; the advance carries the extra pixel
    ldx #>@i
    jsr font_measure
    lda X16_P0
    cmp #4                      ; i is 2 + 1 spacing + 1 bold
    bne @report
    ldy #0
@report
    lda #0                      ; plain again, whatever happened
    jsr font_style
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_BOLD", 0
@i    .byte "i", 0

; FONT_UNDER: one hline under the whole string, at y + height, running
; the full measured width -- through the space, not broken by it.
test_font_under
    vera_addr 0, ROW100, VERA_INC_1
    lda #$00
    ldx #<(9 * FB_STRIDE)
    ldy #>(9 * FB_STRIDE)
    jsr vera_fill               ; rows 100-108

    lda #FONT_UNDER
    jsr font_style
    stz X16_P0
    stz X16_P1
    lda #<100
    sta X16_P2
    stz X16_P3
    lda #<@str
    ldx #>@str
    jsr font_draw
    lda X16_P0
    sta @pen

    ; the rule sits on row 108 = 100 + height
    vera_addr 1, ROW100 + 8 * FB_STRIDE, VERA_INC_1
    ldy #1
    lda VERA_DATA1
    cmp #$FF                    ; solid from the very first pixel
    bne @report
    lda VERA_DATA1
    cmp #$FF                    ; ...and still solid across the space
    bne @report

    ; and nothing on the row above it that the glyphs did not put there
    lda @pen                    ; the rule stops where the pen did:
    lsr                         ; byte (pen-1)>>2 is the last one lit
    lsr
    tax
    vera_addr 1, ROW100 + 8 * FB_STRIDE, VERA_INC_1
@walk
    lda VERA_DATA1
    cmp #$FF
    bne @report
    dex
    bne @walk
    ldy #0
@report
    lda #0
    jsr font_style
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_UNDER", 0
@str  .byte "in it", 0
@pen  .byte 0

; FONT_PEN_BOLD: the measure/draw invariant, with bold set. This is the
; one that would have caught putting bold's extra pixel in font_draw
; instead of f_advance -- the text would draw wider than anything that
; laid it out believed.
test_font_pen_bold
    vera_addr 0, ROW200B1 - 1, VERA_INC_1
    lda #$00
    ldx #<200
    ldy #>200
    jsr vera_fill

    lda #FONT_BOLD
    jsr font_style

    lda #<@str
    ldx #>@str
    jsr font_measure
    lda X16_P0
    sta @want
    lda X16_P1
    sta @want+1

    lda #<40
    sta X16_P0
    stz X16_P1
    lda #<200
    sta X16_P2
    stz X16_P3
    lda #<@str
    ldx #>@str
    jsr font_draw

    ldy #1
    sec
    lda X16_P0
    sbc #40
    cmp @want
    bne @report
    lda X16_P1
    sbc #0
    cmp @want+1
    bne @report
    ldy #0
@report
    lda #0
    jsr font_style
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_PEN_BOLD", 0
@str  .byte "Hamburgefonstiv 123", 0
@want .word 0

; FONT_BANKED: the path the kernel actually boots through. The font is
; copied to CX_SYSFONT_BANK:$A000 -- where the boot loader puts
; PXL8.CXF -- and adopted from there, so every source read (header,
; rows, widths) crosses the banked window. If any of them forgets to
; switch back to the font's bank, it reads a cache bank's glyph slots
; instead and one of these goes wrong: the header check, the rebuilt
; cache byte, the measure, or the drawn pixels. Runs last in the font
; group on purpose: the tests before it prove the resident-source path,
; and the banked font it leaves behind is the one the suite keeps using.
test_font_banked
    lda RAM_BANK
    pha
    lda #CX_SYSFONT_BANK        ; the 871 bytes, into bank 1 at $A000
    sta RAM_BANK
    lda #<pxl8
    sta X16_T0
    lda #>pxl8
    sta X16_T0+1
    lda #<CX_F_WIN
    sta X16_T2
    lda #>CX_F_WIN
    sta X16_T2+1
    ldx #4                      ; 4 x 256 covers 871
    ldy #0
@copy
    lda (X16_T0),y
    sta (X16_T2),y
    iny
    bne @copy
    inc X16_T0+1
    inc X16_T2+1
    dex
    bne @copy

    lda #<CX_F_WIN              ; adopt it where the kernel will
    ldx #>CX_F_WIN
    jsr font_set
    ldy #1
    bcs @report
    lda f_height                ; the header, read across the window
    cmp #8
    bne @report

    lda #7                      ; 'i' again, cached from the banked rows:
    sta RAM_BANK                ; the same bytes FONT_CACHE proved
    lda $B740
    cmp #$0F
    bne @report
    lda $B741
    cmp #$F0
    bne @report

    lda #<@str                  ; widths across the window: still 21
    ldx #>@str
    jsr font_measure
    lda X16_P0
    cmp #21
    bne @report
    lda X16_P1
    bne @report

    vera_addr 0, ROW100, VERA_INC_1
    lda #$00
    ldx #8
    ldy #0
    jsr vera_fill
    stz X16_P0                  ; 'i' at (0,100): the same $F0 the
    stz X16_P1                  ; resident-source draw test proved
    lda #<100
    sta X16_P2
    stz X16_P3
    lda #<@i
    ldx #>@i
    jsr font_draw
    vera_addr 1, ROW100, VERA_INC_1
    lda VERA_DATA1
    cmp #$F0
    bne @report
    lda VERA_DATA1
    bne @report
    ldy #0
@report
    pla
    sta RAM_BANK
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONT_BANKED", 0
@str  .byte "Wig.", 0
@i    .byte "i", 0


; =====================================================================
; the event system (kernel/event/event.asm).
;
; The raster hook cannot fire under -testbench -- there is no VSYNC, so
; no interrupt at all -- which is exactly why ev_post exists: a
; synthetic record goes down the same path a sampled one does,
; coalescing included. These drive the queue and the dispatcher through
; it. What the interrupt itself decodes (button edges, double clicks) is
; spike C's ground, and demos/evmon.asm shows it running.
; =====================================================================

; ev_fill -- post a record: A = type, X = detail, Y = x low.
ev_fill
    sta X16_P0
    stx X16_P1
    sty X16_P2
    stz X16_P3
    stz X16_P4
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jmp ev_post

; EV_QUEUE: records come back oldest first, byte for byte.
test_ev_queue
    jsr ev_init
    ldy #1
    jsr ev_count
    bne @report                 ; a fresh queue is empty

    lda #EV_KEY
    ldx #65
    ldy #11
    jsr ev_fill
    lda #EV_MOUSE_DOWN
    ldx #1
    ldy #22
    jsr ev_fill
    lda #EV_TIMER
    ldx #0
    ldy #33
    jsr ev_fill

    ldy #1
    jsr ev_count
    cmp #3
    bne @report

    jsr ev_get                  ; FIFO: the key first
    bcs @report
    lda X16_P0
    cmp #EV_KEY
    bne @report
    lda X16_P1
    cmp #65
    bne @report
    lda X16_P2
    cmp #11
    bne @report

    jsr ev_get
    bcs @report
    lda X16_P0
    cmp #EV_MOUSE_DOWN
    bne @report
    lda X16_P2
    cmp #22
    bne @report

    jsr ev_get
    bcs @report
    lda X16_P0
    cmp #EV_TIMER
    bne @report

    jsr ev_get                  ; and then it is empty again
    bcc @report
    jsr ev_count
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_QUEUE", 0

; EV_COALESCE: a move landing on a move overwrites it -- only the newest
; position was ever interesting. A move landing on anything else queues.
test_ev_coalesce
    jsr ev_init

    lda #EV_MOUSE_MOVE
    ldx #0
    ldy #10
    jsr ev_fill
    lda #EV_MOUSE_MOVE
    ldx #0
    ldy #20
    jsr ev_fill
    lda #EV_MOUSE_MOVE
    ldx #0
    ldy #30
    jsr ev_fill

    ldy #1
    jsr ev_count
    cmp #1                      ; three moves, one record
    bne @report
    jsr ev_get
    lda X16_P2
    cmp #30                     ; and it is the newest position
    bne @report

    lda #EV_MOUSE_MOVE          ; a move, then a press, then a move:
    ldx #0                      ; the press breaks the run, so the
    ldy #40                     ; second move cannot fold into the first
    jsr ev_fill
    lda #EV_MOUSE_DOWN
    ldx #1
    ldy #40
    jsr ev_fill
    lda #EV_MOUSE_MOVE
    ldx #0
    ldy #50
    jsr ev_fill
    jsr ev_count
    cmp #3
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_COALESCE", 0

; EV_OVERFLOW: a full queue drops the newest and says so. It must never
; drop a button silently, and it must not corrupt what it already holds.
test_ev_overflow
    jsr ev_init
    ldx #0
@fill
    phx
    txa
    clc
    adc #1                      ; detail 1..17, so the order is checkable
    tax
    lda #EV_MOUSE_DOWN
    ldy #0
    jsr ev_fill
    plx
    inx
    cpx #17                     ; one more than the queue holds
    bne @fill

    ldy #1
    jsr ev_count
    cmp #16
    bne @report
    lda ev_lost
    cmp #1                      ; exactly one, counted
    bne @report

    jsr ev_get                  ; the oldest survived intact
    lda X16_P1
    cmp #1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_OVERFLOW", 0

; EV_WRAP: push and pop past the ring's end. 40 records through a
; 16-record queue walks head and tail over the wrap three times.
test_ev_wrap
    jsr ev_init
    stz @n
@round
    lda #EV_KEY
    ldx @n
    ldy #0
    jsr ev_fill
    jsr ev_get
    bcs @bad
    lda X16_P1
    cmp @n                      ; what went in is what came out
    bne @bad
    inc @n
    lda @n
    cmp #40
    bne @round
    jsr ev_count                ; and nothing is left behind
    bne @bad
    ldy #0
    bra @report
@bad
    ldy #1
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_WRAP", 0
@n    .byte 0

; EV_DISPATCH: the handler for the record's type runs, and sees it.
test_ev_dispatch
    jsr ev_init
    lda #<@table
    ldx #>@table
    jsr ev_handlers

    stz @hits
    stz @saw
    lda #EV_KEY
    ldx #77
    ldy #0
    jsr ev_fill
    jsr ev_dispatch

    ldy #1
    lda @hits
    cmp #1                      ; ran once
    bne @report
    lda @saw
    cmp #77                     ; and the record reached it
    bne @report

    lda #EV_TIMER               ; a type this app ignores: a null vector
    ldx #0                      ; is not a crash
    ldy #0
    jsr ev_fill
    jsr ev_dispatch
    lda @hits
    cmp #1                      ; the key handler did not run again
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_DISPATCH", 0

@key_handler
    inc @hits
    lda X16_P1
    sta @saw
    rts

@table  .word 0, 0, 0, 0, 0, @key_handler, 0   ; only EV_KEY is handled
@hits   .byte 0
@saw    .byte 0

; EV_NULL: an empty queue dispatches EV_NULL with an all-zero record --
; the app's idle time, without polling.
test_ev_null
    jsr ev_init
    lda #<@table
    ldx #>@table
    jsr ev_handlers
    stz @hits

    lda #$FF                    ; poison the block: EV_NULL must clear it
    sta X16_P1
    sta X16_P2
    sta X16_P7
    jsr ev_dispatch

    ldy #1
    lda @hits
    cmp #1
    bne @report
    lda @zeroes                 ; the handler found it all zero
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_NULL", 0

@null_handler
    inc @hits
    lda X16_P0                  ; every byte of the record
    ora X16_P1
    ora X16_P2
    ora X16_P3
    ora X16_P4
    ora X16_P5
    ora X16_P6
    ora X16_P7
    sta @zeroes
    rts

@table   .word @null_handler, 0, 0, 0, 0, 0, 0, 0, 0, 0 ; EV_COUNT vectors
@hits    .byte 0
@zeroes  .byte 0

; EV_JOY_RESET: cx_joy_enable leaks into the NEXT app unless ev_init
; clears it -- the tile app enabled pads, exited, and the reloaded
; desktop's IRQ kept posting EV_JOY records its 9-entry handler table
; never expected: the dispatch read a garbage vector from whatever
; followed the table and jumped wild (the tile-exit desktop crash).
; So: ev_init must clear the subscription and the remembered states,
; and dispatching an EV_JOY through the default null table (which was
; itself one vector short) must come back instead of jumping away.
test_ev_joy_reset
    lda #%0011                  ; subscribe pads 0-1, dirty the states
    jsr ev_joy_enable
    lda #$5A
    sta ev_joy_prev
    sta ev_joy_prev+7

    jsr ev_init                 ; a fresh app: no inherited subscription

    ldy #1
    lda ev_joy_en
    bne @report
    lda ev_joy_prev
    ora ev_joy_prev+7
    bne @report

    lda #EV_JOY                 ; an EV_JOY through the null table: the
    ldx #0                      ; 10th vector exists and is zero, so this
    ldy #0                      ; returns -- it does not read past the
    jsr ev_fill                 ; table and jump into garbage
    jsr ev_dispatch

    ldy #1
    jsr ev_count                ; consumed, nothing exploded
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_JOY_RESET", 0

; EV_MASK: the source mask defaults to mouse+keys, an app cannot inherit
; a stripped one, and a fully masked-down frame tick samples nothing --
; the light path runs (no zp save, no KERNAL calls) and posts nothing.
test_ev_mask
    lda #0                      ; strip everything, then prove ev_init
    jsr ev_set_mask             ; hands the next app the default back
    jsr ev_init
    ldy #1
    lda ev_mask
    cmp #EVS_MOUSE|EVS_KEYS
    bne @report

    lda #0                      ; all sources off (pads are off too):
    jsr ev_set_mask             ; the tick takes the light path
    jsr ev_irq
    jsr ev_count                ; ...and posted nothing
    bne @report

    lda #EVS_MOUSE|EVS_KEYS     ; leave the machine as found
    jsr ev_set_mask
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_MASK", 0

; ---------------------------------------------------------------------
; SPR_COLLIDE: the EVS_SPRCOL mask bit arms/disarms VERA's collision
; interrupt, and cx_spr_collide reads-and-clears the accumulated groups.
; (The collision itself is hardware; here we drive the plumbing that the
; handler and the poll share.)
; ---------------------------------------------------------------------
test_spr_collide
    lda #EVS_MOUSE|EVS_KEYS|EVS_SPRCOL   ; arm collisions
    jsr ev_set_mask
    ldy #1
    lda VERA_IEN                ; the collision source is enabled now
    and #VERA_IRQ_SPRCOL
    beq @report

    lda #$50                    ; stand in for what the handler accumulates
    sta irq_sprcol_mask         ; (groups 4 and 6, ISR bits 7:4)
    jsr cx_do_spr_collide       ; reads them back...
    cmp #$50
    bne @report
    beq @nz                     ; ...nonzero, so Z was clear
    ldy #2
    bne @report
@nz
    jsr cx_do_spr_collide       ; ...and cleared: the second read is 0, Z set
    bne @report

    lda #EVS_MOUSE|EVS_KEYS     ; disarm: the collision source goes off
    jsr ev_set_mask
    lda VERA_IEN
    and #VERA_IRQ_SPRCOL
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "SPR_COLLIDE", 0

; ---------------------------------------------------------------------
; ev_init / ev_suspend (cx_ev_stop) -- lending the raster line to a game.
; A game owns the line for smooth motion; cx_ev_init borrows it for a
; dialog and cx_ev_stop hands it back. Pin the save/restore: the single
; irq_line_vec slot must return to the game's handler, and with no prior
; handler cx_ev_stop must take the line down instead.
; ---------------------------------------------------------------------
test_ev_borrow
    lda #<t_game_irq            ; a game takes the raster line, cx_ev_raster
    ldx #>t_game_irq
    jsr ev_raster
    ldy #1                      ; it holds the armed line now
    lda irq_line_armed
    beq @report
    lda irq_line_vec
    cmp #<t_game_irq
    bne @report
    lda irq_line_vec+1
    cmp #>t_game_irq
    bne @report

    jsr ev_init                 ; borrow the line: ev_irq samples now,
    ldy #2                      ; ...and the sampler holds the slot
    lda irq_line_vec
    cmp #<ev_irq
    bne @report
    lda irq_line_vec+1
    cmp #>ev_irq
    bne @report

    jsr ev_init                 ; a second init must keep the displaced
    ldy #5                      ; game handler saved, not save ev_irq itself
    jsr ev_suspend              ; cx_ev_stop: the game's handler is back
    ldy #3
    lda irq_line_vec
    cmp #<t_game_irq
    bne @report
    lda irq_line_vec+1
    cmp #>t_game_irq
    bne @report

    lda #0                      ; cx_ev_raster(0) removes it; an ordinary
    ldx #0                      ; app then has no handler, so cx_ev_stop
    jsr ev_raster               ; must take the line down, not restore a
    jsr ev_init                 ; stale one
    jsr ev_suspend
    ldy #4
    lda irq_line_armed
    bne @report

    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "EV_BORROW", 0
t_game_irq                      ; a stand-in game handler; never runs here
    rts

; EV_TABLES: the kernel's own modal handler tables must track EV_COUNT.
; EV_JOY is the last slot; a 9-vector table jumps into the data that
; follows it.
test_ev_modal_tables
    jsr ev_init

    lda #<da_table
    ldx #>da_table
    jsr ev_handlers
    jsr @joy
    bne @bad

    lda #<dg_table
    ldx #>dg_table
    jsr ev_handlers
    jsr @joy
    bne @bad

    lda #<dg_ptable
    ldx #>dg_ptable
    jsr ev_handlers
    jsr @joy
    bne @bad

    ldy #0
    bra @report
@bad
    ldy #1
@report
    jsr ev_stop
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@joy
    lda #EV_JOY
    ldx #0
    ldy #0
    jsr ev_fill
    jsr ev_dispatch
    jmp ev_count
@name .byte "EV_TABLES", 0


; =====================================================================
; the ABI (abi/cxrf.abi -> kernel/resident/jumptab.asm).
;
; Here the table is linked into the test PRG rather than pinned at
; $8000, so these check what that placement does not: that the header
; says what the manifest says, that every slot is a JMP to a real
; routine, and that a call through the table reaches the kernel. The
; addresses themselves are kernel.cfg's business.
;
; abi/gen_bindings.py --selftest covers the generator; --check fails a
; build whose sdk/ has drifted from the manifest.
; =====================================================================

; ABI_HEADER: the loader reads this to decide whether an app can run.
test_abi_header
    ldy #1
    lda cx_hdr_magic            ; "CXOS"
    cmp #'C'
    bne @report
    lda cx_hdr_magic+1
    cmp #'X'
    bne @report
    lda cx_hdr_magic+2
    cmp #'O'
    bne @report
    lda cx_hdr_magic+3
    cmp #'S'
    bne @report

    lda cx_hdr_version          ; version 4, and the kernel agrees
    cmp #4
    bne @report
    lda cx_hdr_version+1
    bne @report
    lda cx_hdr_slots
    cmp #105                    ; 31 shipped with the table; loader, events,
    bne @report                 ; menus, pointer, themes, dialogs, widgets,
                                ; keyboard nav, dir, DOS, the prompt, cx_ev_next,
                                ; PSG/YM audio, sprites, PCM, joysticks, the
                                ; graphics port, tiles, ellipses, asset loaders,
                                ; the modal panel, the game raster + its
                                ; borrow/return pair, sprite collision, the icon,
                                ; the palette pair, cx_menu_active, v0.8.0's
                                ; cx_gfx_shape (polygon/arc/pie), and v0.9.0's
                                ; cx_tile_text (the mode-2 text overlay) and
                                ; cx_vram_stream (bank -> VRAM) -- grew it
    lda cx_hdr_slots+1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "ABI_HEADER", 0

; MENU_ACTIVE: cx_menu_active reads mn_open through mn_active, so an app can
; tell a menu is dropped -- opened by the mouse or the keyboard, both set
; mn_open. The far-call stub is exercised by test_farcall and the desktop;
; this pins the bank-2 half's logic and its Z flag.
test_menu_active
    ldy #1                      ; assume fail
    stz mn_open                 ; no menu open -> A = 0, Z set
    jsr mn_active
    bne @report                 ; nonzero: wrong
    lda #1                      ; a menu open -> A = 1, Z clear
    sta mn_open
    jsr mn_active
    beq @report                 ; zero: wrong
    cmp #1
    bne @report
    stz mn_open                 ; leave it closed
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "MENU_ACTIVE", 0

; DLG_P0: a zero-capacity prompt buffer cannot be edited safely, so the
; prompt refuses before drawing or entering its modal loop.
test_dlg_prompt_zero
    lda #<@buf
    sta X16_P0
    lda #>@buf
    sta X16_P1
    stz X16_P2
    lda #<@msg
    ldx #>@msg
    jsr dg_prompt
    ldy #1
    bcc @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "DLG_P0", 0
@msg .byte "x", 0
@buf .byte 0

; ABI_TABLE: every slot is a JMP ($4C), three bytes apart, to somewhere
; that is not zero. A slot whose impl went missing would be caught by
; gen_bindings.py -- this catches the table being built wrong.
test_abi_table
    lda #31
    sta @n
    lda #<cx_jumptab            ; the library's scratch pointer: (zp),y
    sta X16_TPTR3               ; needs zero page, and it is free here
    lda #>cx_jumptab
    sta X16_TPTR3+1
@slot
    ldy #0
    lda (X16_TPTR3),y           ; the opcode
    cmp #$4C                    ; JMP abs
    bne @bad
    iny                         ; ...to a real address
    lda (X16_TPTR3),y
    iny
    ora (X16_TPTR3),y
    beq @bad

    clc                         ; three bytes on
    lda X16_TPTR3
    adc #3
    sta X16_TPTR3
    bcc @nc
    inc X16_TPTR3+1
@nc
    dec @n
    bne @slot
    lda #0
    bra @report
@bad
    lda #1
@report
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "ABI_TABLE", 0
@n    .byte 0

; ABI_CALL: a call through the table reaches the kernel and comes back
; with the right answer. cx_version is slot 0, so this also proves the
; table's base is where the bindings say.
test_abi_call
    ldy #1
    jsr cx_jumptab              ; slot 0 = cx_version
    cmp #4                      ; A/X = the header's version
    bne @report
    cpx #0
    bne @report

    ; slot 24 = cx_ev_count. Post one event, ask through the ABI.
    jsr ev_init
    lda #EV_KEY
    ldx #1
    ldy #0
    jsr ev_fill
    jsr cx_jumptab + 24 * 3
    cmp #1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "ABI_CALL", 0

; =====================================================================
; the region stack (kernel/ui/region.asm) and the far-call trampoline
; (kernel/resident/farcall.asm) -- Phase 5a's foundations.
; =====================================================================

; rg_put -- push a region: A/X/Y = x0, x1 (bytes), vector low byte;
; y0 = 0, y1 = 200, vector high = >rg_stubs. Enough shape for the tests.
rg_put
    sta X16_P0
    stz X16_P1
    stx X16_P4
    stz X16_P5
    stz X16_P2
    stz X16_P3
    lda #200
    sta X16_P6
    stz X16_P7
    tya
    ldx #>$1000                 ; a recognisable fake page
    jmp rg_push

; RG_STACK: eight fit, the ninth is refused, a pop makes room again.
test_rg_stack
    jsr rg_reset
    ldy #1
    ldx #0
@fill
    phx
    lda #10
    ldx #20
    phy
    ldy #0
    jsr rg_put
    ply
    plx
    bcs @report                 ; refused too early
    inx
    cpx #8
    bne @fill

    lda #10                     ; the ninth
    ldx #20
    phy
    ldy #0
    jsr rg_put
    ply
    bcc @report                 ; accepted too late
    jsr rg_pop
    lda #10
    ldx #20
    phy
    ldy #0
    jsr rg_put
    ply
    bcs @report
    ldy #0
@report
    jsr rg_reset
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "RG_STACK", 0

; RG_ROUTE: two overlapping regions; the point in both goes to the one
; pushed last, the point in one goes to it, the point in neither is
; nobody's.
test_rg_route
    jsr rg_reset
    lda #10                     ; bottom: x 10-100, vec low $AA
    ldx #100
    ldy #$AA
    jsr rg_put
    lda #50                     ; top: x 50-150, vec low $BB
    ldx #150
    ldy #$BB
    jsr rg_put

    ldy #1
    lda #EV_MOUSE_DOWN          ; x = 60: inside both, the top wins
    sta X16_P0
    lda #60
    sta X16_P2
    stz X16_P3
    stz X16_P4
    stz X16_P5
    jsr rg_route
    bcs @report
    lda rg_vec
    cmp #$BB
    bne @report

    lda #20                     ; x = 20: only the bottom
    sta X16_P2
    jsr rg_route
    bcs @report
    lda rg_vec
    cmp #$AA
    bne @report

    lda #200                    ; x = 200: nobody
    sta X16_P2
    jsr rg_route
    bcc @report
    ldy #0
@report
    jsr rg_reset
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "RG_ROUTE", 0

; EV_REGION: the dispatcher itself. A pushed region's handler gets the
; mouse record instead of the app's table; a miss falls through to the
; table. Key events ignore regions entirely.
test_ev_region
    jsr ev_init                 ; also resets the region stack
    lda #<@tab
    ldx #>@tab
    jsr ev_handlers
    stz @got_rg
    stz @got_tab
    stz @got_key

    stz X16_P0                  ; region x 0-100, y 0-200
    stz X16_P1
    stz X16_P2
    stz X16_P3
    lda #100
    sta X16_P4
    stz X16_P5
    lda #200
    sta X16_P6
    stz X16_P7
    lda #<@rg_hand
    ldx #>@rg_hand
    jsr rg_push

    lda #EV_MOUSE_DOWN          ; a click inside: the region's
    ldx #1
    ldy #50
    jsr ev_fill
    jsr ev_dispatch

    lda #EV_MOUSE_DOWN          ; a click outside: the table's
    ldx #2
    ldy #250
    jsr ev_fill
    jsr ev_dispatch

    lda #EV_KEY                 ; a key "at" an inside x: geometry
    ldx #3                      ; must not matter
    ldy #50
    jsr ev_fill
    jsr ev_dispatch

    ldy #1
    lda @got_rg
    cmp #1                      ; the inside click, and only it
    bne @report
    lda @got_tab
    cmp #2                      ; the outside click, and only it
    bne @report
    lda @got_key
    cmp #3
    bne @report
    ldy #0
@report
    jsr rg_reset
    jsr ev_stop
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@rg_hand
    lda X16_P1
    sta @got_rg
    rts
@down_hand
    lda X16_P1
    sta @got_tab
    rts
@key_hand
    lda X16_P1
    sta @got_key
    rts
@tab
    .addr 0, 0, @down_hand, 0, 0
    .addr @key_hand
    .addr 0, 0
@got_rg  .byte 0
@got_tab .byte 0
@got_key .byte 0
@name .byte "EV_REGION", 0

; FARCALL: a probe is copied into bank 2's window and called through a
; real stub. Everything the trampoline promises is asserted: the
; arguments arrive in A/X/Y, the code runs under the stub's bank, the
; returns come back in A/X/Y, the carry survives the trip, and the
; caller's RAM_BANK is put back.
test_farcall
    lda RAM_BANK
    pha
    lda #2                      ; the probe, into bank 2 at $A000
    sta RAM_BANK
    ldx #0
@copy
    lda fc_probe,x
    sta $A000,x
    inx
    cpx #fc_probe_len
    bne @copy

    lda #9                      ; a recognisable caller bank
    sta RAM_BANK
    lda #$11
    ldx #$22
    ldy #$33
    jsr @stub

    php                         ; judge the trip
    sta fc_ra
    stx fc_rx
    sty fc_ry
    ldy #1
    plp
    bcc @report                 ; the probe's sec was eaten
    lda fc_ra
    cmp #$77
    bne @report
    lda fc_rx
    cmp #$88
    bne @report
    lda fc_ry
    cmp #$99
    bne @report
    lda fc_a                    ; what the probe saw
    cmp #$11
    bne @report
    lda fc_x
    cmp #$22
    bne @report
    lda fc_y
    cmp #$33
    bne @report
    lda fc_bank
    cmp #2
    bne @report
    lda RAM_BANK                ; the caller's bank, restored
    cmp #9
    bne @report
    ldy #0
@report
    pla
    sta RAM_BANK
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@stub
    jsr cxb_call
    .byte 2
    .addr $A000
@name .byte "FARCALL", 0

; The probe. Copied to $A000, so it may reference low RAM absolutely
; but never itself.
fc_probe
    sta fc_a
    stx fc_x
    sty fc_y
    lda RAM_BANK
    sta fc_bank
    lda #$77
    ldx #$88
    ldy #$99
    sec
    rts
fc_probe_len = * - fc_probe
fc_a    .byte 0
fc_x    .byte 0
fc_y    .byte 0
fc_bank .byte 0
fc_ra   .byte 0
fc_rx   .byte 0
fc_ry   .byte 0

; VROWS: the dialog's save-under (kernel/resident/vrows.asm). Paint a
; witness, save its rows to a bank, clobber them, restore, and the
; witness is back. Row 192 for 96 rows spans two banks (15,360 bytes),
; so this also exercises the $C000 wrap the dialog depends on.
test_vrows
    lda #<300                   ; a witness at (300,192) and (300,286)
    sta X16_P0                  ; -- first and last row of the range,
    lda #>300                   ; so the far one lives past the $C000
    sta X16_P1                  ; bank wrap
    lda #<192
    sta X16_P2
    stz X16_P3
    lda #3
    jsr gfx2h_pset
    lda #<300
    sta X16_P0
    lda #>300
    sta X16_P1
    lda #<286                   ; 286 > 255: the high byte matters
    sta X16_P2
    lda #>286
    sta X16_P3
    lda #2
    jsr gfx2h_pset

    lda #<192                   ; 96 rows: crosses into bank 9
    sta X16_P0
    stz X16_P1
    lda #96
    sta X16_P2
    lda #8
    jsr vrows_save

    lda #<300                   ; clobber both witnesses
    sta X16_P0
    lda #>300
    sta X16_P1
    lda #<192
    sta X16_P2
    stz X16_P3
    lda #0
    jsr gfx2h_pset
    lda #<300
    sta X16_P0
    lda #>300
    sta X16_P1
    lda #<286                   ; 286 > 255: the high byte matters
    sta X16_P2
    lda #>286
    sta X16_P3
    lda #0
    jsr gfx2h_pset

    lda #<192                   ; restore both from the banks
    sta X16_P0
    stz X16_P1
    lda #96
    sta X16_P2
    lda #8
    jsr vrows_restore

    ldy #1
    lda #<300                   ; the near witness (bank 8): 3
    sta X16_P0
    lda #>300
    sta X16_P1
    lda #<192
    sta X16_P2
    stz X16_P3
    jsr gfx2h_read
    cmp #3
    bne @report
    lda #<300                   ; the far witness (past the wrap): 2
    sta X16_P0
    lda #>300
    sta X16_P1
    lda #<286                   ; 286 > 255: the high byte matters
    sta X16_P2
    lda #>286
    sta X16_P3
    jsr gfx2h_read
    cmp #2
    bne @report

    lda RAM_BANK                ; zero rows: return without mapping the
    sta @bank                   ; save bank or walking a wrapped counter
    stz X16_P0
    stz X16_P1
    stz X16_P2
    lda #8
    jsr vrows_save
    lda RAM_BANK
    cmp @bank
    bne @report
    lda #8
    jsr vrows_restore
    lda RAM_BANK
    cmp @bank
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "VROWS", 0
@bank .byte 0

; MOUSE: cx_mouse_show(1) must configure VERA sprite 0 as the KERNAL
; pointer -- image at $13000, 16x16, in front of the layers -- and turn
; sprite output on in DC_VIDEO. This is what an invisible pointer looks
; like when it regresses: A=$FF leaves the sprite at address 0, size
; 8x8 (found the hard way). Sprite 0's attributes are 8 bytes at VRAM
; $1FC00; the image address is byte0 bits 12:5 plus byte1 bits 3:0 as
; bits 16:13, so $13000 reads back as byte0=$80, byte1 low nibble=9.
test_mouse
    lda #1
    jsr cx_do_mouse_show
    ldy #1

    lda VERA_DC_VIDEO           ; sprite output on
    and #VERA_VIDEO_SPRITES_EN
    beq @report

    vera_addr 1, $1FC00, VERA_INC_1
    lda VERA_DATA1              ; byte 0: address bits 12:5 = $13000>>5
    cmp #$80                    ; ...low part = $80
    bne @report
    lda VERA_DATA1              ; byte 1: bits 3:0 = address bits 16:13
    and #$0F                    ; = 9
    cmp #$09
    bne @report
    lda VERA_DATA1              ; bytes 2-5: X, Y position -- skip
    lda VERA_DATA1
    lda VERA_DATA1
    lda VERA_DATA1
    lda VERA_DATA1              ; byte 6: Z-depth (bits 3:2) must be set
    and #$0C
    beq @report                ; Z 0 = disabled, behind everything
    lda VERA_DATA1              ; byte 7: height/width bits = 16x16 = $50
    cmp #$50
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "MOUSE", 0

; =====================================================================
; the app loader (kernel/fs/loader.asm), against real DOS -- the suite
; runs with -fsroot, so these opens hit an actual filesystem. Only the
; refusals can be tested here: a load that SUCCEEDS resets the stack
; and jumps to the new program, and the new program would be standing
; where this suite is. The success path is the boot smoke test's job,
; which runs it end to end off a staged SD root. What matters in a
; refusal is the second half of the contract: carry, the right reason
; in A, and a caller still standing -- these three tests ARE the caller,
; and they report their own survival.
; =====================================================================

; APP_MISSING: no such file. DOS never produces the 32 header bytes,
; so the judge refuses before anything is touched.
test_app_missing
    lda #<@nm
    ldx #>@nm
    ldy #@nmlen
    jsr cxl_load
    ldy #1
    bcc @report                 ; came back without carry: very wrong
    cmp #1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "APP_MISSING", 0
@nm   .byte "NOSUCH.CXA"
@nmlen = * - @nm

; APP_BADMAGIC: the fixture the harness drops into fsroot is a real
; file whose header does not say CXAP.
test_app_badmagic
    lda #<@nm
    ldx #>@nm
    ldy #@nmlen
    jsr cxl_load
    ldy #1
    bcc @report
    cmp #1
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "APP_BADMAGIC", 0
@nm   .byte "BADAPP.CXA"
@nmlen = * - @nm

; APP_TOONEW: a well-formed CXAP whose min-ABI is $7FFF. The refusal
; must be the version one -- A = 2 -- so a user sees "needs a newer
; kernel" and not "broken file".
test_app_toonew
    lda #<@nm
    ldx #>@nm
    ldy #@nmlen
    jsr cxl_load
    ldy #1
    bcc @report
    cmp #2
    bne @report
    ldy #0
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "APP_TOONEW", 0
@nm   .byte "NEWAPP.CXA"
@nmlen = * - @nm

; DIR: read the directory (kernel/fs/dir.asm) against the real fsroot,
; which the harness has stocked with BADAPP.CXA and NEWAPP.CXA. The
; walk must open, hand back the header then the entries, find the two
; fixtures by name, and end with carry. cx_dir_next clobbers X/Y, so
; the counters live in memory.
test_dir
    lda #<@pat
    ldx #>@pat
    ldy #1
    jsr cx_do_dir_open
    ldy #1
    bcs @report                 ; open failed

    stz @count
    stz @found
    lda #<@nb                   ; the header first -- discarded
    sta X16_P0
    lda #>@nb
    sta X16_P1
    jsr cx_do_dir_next
    bcs @close                  ; a listing with no header at all
@loop
    lda #<@nb
    sta X16_P0
    lda #>@nb
    sta X16_P1
    jsr cx_do_dir_next
    bcs @done
    inc @count
    ldy #6                      ; is it a fixture? both "BADAPP.CXA" and
@cmp                            ; "NEWAPP.CXA" end "APP.CXA" at offset 3
    lda @nb+3,y
    cmp @tail,y
    bne @loop
    dey
    bpl @cmp
    inc @found
    bra @loop
@done
    jsr cx_do_dir_close
    lda @count                  ; at least the two fixtures
    cmp #2
    bcc @fail
    lda @found                  ; and both matched the tail
    cmp #2
    bcc @fail
    ldy #0
    bra @report
@close
    jsr cx_do_dir_close
@fail
    ldy #1
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name  .byte "DIR", 0
@pat   .byte "$"
@tail  .byte "APP.CXA"
@count .byte 0
@found .byte 0
@nb    .res 35, 0

; ---------------------------------------------------------------------
; cx_dir_open must MASK interrupts and cx_dir_close restore them: the
; event IRQ's GETIN reads the current channel, so a firing IRQ steals
; bytes out of the open directory (it drew ghost "PRG" lines in the file
; browser). This checks the guard is in place; without it the browser
; corrupts on every refresh.
; ---------------------------------------------------------------------
test_dir_irq
    cli                         ; start with interrupts enabled
    lda #<@pat
    ldx #>@pat
    ldy #1
    jsr cx_do_dir_open
    bcs @fail
    php                         ; open must have masked them
    pla
    and #$04                    ; the I flag
    beq @failclose
    jsr cx_do_dir_close
    php                         ; close must have restored them
    pla
    and #$04
    bne @fail
    ldy #0
    bra @report
@failclose
    jsr cx_do_dir_close
@fail
    cli                         ; leave interrupts as we found them
    ldy #1
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "DIRIRQ", 0
@pat  .byte "$"

; ---------------------------------------------------------------------
; the clipboard -- put, ask, get back, truncate, empty, and a payload
; long enough to roll from bank 10 into bank 11.
; ---------------------------------------------------------------------
; FILE_LOAD: the generic asset loader against real DOS. BADAPP.CXA is a
; known 35-byte fixture (build.ps1 stages it: "XXAP", 28 zeros, $01 $08
; $EA): a whole load returns exactly those bytes and that length; a
; 10-byte capacity refuses with A = 3 and the first 10 bytes in; a
; missing name refuses with A = 1. The poison byte past the buffer must
; survive everything.
test_file_load
    lda #$5A                    ; poison one past the full read
    sta @buf+35
    lda #<@buf
    sta X16_P0
    lda #>@buf
    sta X16_P1
    lda #40                     ; room to spare: the file ends it
    sta X16_P2
    stz X16_P3
    lda #<@name_f
    ldx #>@name_f
    ldy #@name_f_len
    jsr cx_do_file_load
    ldy #1
    bcs @r1
    lda X16_P4                  ; 35 bytes, exactly
    cmp #35
    bne @r1
    lda X16_P5
    bne @r1
    lda @buf                    ; "XXAP" leads...
    cmp #'X'
    bne @r1
    lda @buf+3
    cmp #'P'
    bne @r1
    lda @buf+34                 ; ...$EA ends...
    cmp #$EA
    bne @r1
    lda @buf+35                 ; ...and the poison survived
    cmp #$5A
    bne @r1
    ldy #0
@r1
    phy
    tya
    ldx #<@n1
    ldy #>@n1
    jsr t_result
    ply
    bne @skip2                  ; the fixture read failed: skip the rest

    lda #<@buf                  ; the same file into 10 bytes of room
    sta X16_P0
    lda #>@buf
    sta X16_P1
    lda #10
    sta X16_P2
    stz X16_P3
    lda #<@name_f
    ldx #>@name_f
    ldy #@name_f_len
    jsr cx_do_file_load
    ldy #1
    bcc @r2                     ; must refuse
    cmp #3                      ; ...as "bigger than the capacity"
    bne @r2
    lda X16_P4                  ; with the capacity consumed
    cmp #10
    bne @r2
    ldy #0
@r2
@skip2
    tya
    ldx #<@n2
    ldy #>@n2
    jsr t_result

    lda #<@buf                  ; a name the disk does not have
    sta X16_P0
    lda #>@buf
    sta X16_P1
    lda #40
    sta X16_P2
    stz X16_P3
    lda #<@name_m
    ldx #>@name_m
    ldy #@name_m_len
    jsr cx_do_file_load
    ldy #1
    bcc @r3
    cmp #1
    bne @r3
    ldy #0
@r3
    tya
    ldx #<@n3
    ldy #>@n3
    jmp t_result
@n1     .byte "FL_WHOLE", 0
@n2     .byte "FL_CAP", 0
@n3     .byte "FL_MISSING", 0
@name_f .byte "BADAPP.CXA"
@name_f_len = * - @name_f
@name_m .byte "NOFILE.BIN"
@name_m_len = * - @name_m
@buf    .res 40, 0

; AS_VLOAD: a file straight into VRAM (bank 1, $3000 -- above the 2bpp
; framebuffer's $12BFF). Headered semantics skip BADAPP.CXA's first two
; bytes ("XX") and land the other 33; the raw flag lands all 35.
AS_VDEST = $13000
test_as_vload
    vera_addr 0, AS_VDEST, VERA_INC_1
    ldx #40                     ; a poisoned runway
@poison
    lda #$77
    sta VERA_DATA0
    dex
    bne @poison

    lda #<$3000                 ; headered: 33 bytes from "AP" on
    sta X16_P0
    lda #>$3000
    sta X16_P1
    lda #1                      ; VRAM bank 1
    sta X16_P2
    stz X16_P3                  ; the ecosystem default: skip the header
    lda #<@vn
    ldx #>@vn
    ldy #@vn_len
    jsr cx_do_vload
    ldy #1
    bcs @r1
    lda X16_P4                  ; one past: $3021
    cmp #$21
    bne @r1
    lda X16_P5
    cmp #$30
    bne @r1
    ldy #0
@r1
    tya
    ldx #<@n1
    ldy #>@n1
    jsr t_result

    ldy #1                      ; the bytes, read in one clean burst
    vera_addr 1, AS_VDEST, VERA_INC_1
    lda VERA_DATA1              ; "AP", then zeros
    cmp #'A'
    bne @r2
    lda VERA_DATA1
    cmp #'P'
    bne @r2
    lda VERA_DATA1
    bne @r2
    vera_addr 1, AS_VDEST + 32, VERA_INC_1
    lda VERA_DATA1              ; the last payload byte...
    cmp #$EA
    bne @r2
    lda VERA_DATA1              ; ...and the poison right after
    cmp #$77
    bne @r2
    ldy #0
@r2
    tya
    ldx #<@n2
    ldy #>@n2
    jsr t_result

    lda #<$3000                 ; raw: all 35 bytes, "XXAP" leading
    sta X16_P0
    lda #>$3000
    sta X16_P1
    lda #1
    sta X16_P2
    lda #1                      ; the raw flag
    sta X16_P3
    lda #<@vn
    ldx #>@vn
    ldy #@vn_len
    jsr cx_do_vload
    ldy #1
    bcs @r3
    lda X16_P4                  ; one past: $3023
    cmp #$23
    bne @r3
    vera_addr 1, AS_VDEST, VERA_INC_1
    lda VERA_DATA1
    cmp #'X'
    bne @r3
    ldy #0
@r3
    tya
    ldx #<@n3
    ldy #>@n3
    jmp t_result
@n1   .byte "AV_END", 0
@n2   .byte "AV_BYTES", 0
@n3   .byte "AV_RAW", 0
@vn   .byte "BADAPP.CXA"
@vn_len = * - @vn

; AS_BLOAD: the same file into banked RAM at 20:$A000 (the first bank
; that is an app's to use -- CX_APP_BANK_FLOOR); the kernel's own banks
; refuse with A = 0.
test_as_bload
    lda RAM_BANK
    pha
    lda #CX_APP_BANK_FLOOR      ; poison one past the payload
    sta RAM_BANK
    lda #$5A
    sta $A021
    pla
    sta RAM_BANK

    lda #CX_APP_BANK_FLOOR
    sta X16_P0
    lda #<$A000
    sta X16_P1
    lda #>$A000
    sta X16_P2
    stz X16_P3
    lda #<@bn
    ldx #>@bn
    ldy #@bn_len
    jsr cx_do_bload
    ldy #1
    bcs @r1
    lda X16_P4                  ; one past: $A021
    cmp #$21
    bne @r1
    lda X16_P5
    cmp #$A0
    bne @r1
    lda X16_P6                  ; ended in the bank it started in
    cmp #CX_APP_BANK_FLOOR
    bne @r1
    ldy #0
@r1
    tya
    ldx #<@n1
    ldy #>@n1
    jsr t_result

    ldy #1
    lda RAM_BANK
    pha
    lda #CX_APP_BANK_FLOOR
    sta RAM_BANK
    lda $A000                   ; "AP" leads, the poison survived
    cmp #'A'
    bne @unbank
    lda $A001
    cmp #'P'
    bne @unbank
    lda $A020
    cmp #$EA
    bne @unbank
    lda $A021
    cmp #$5A
    bne @unbank
    ldy #0
@unbank
    pla
    sta RAM_BANK
    tya
    ldx #<@n2
    ldy #>@n2
    jsr t_result

    lda #CX_APP_BANK_FLOOR-1    ; the last kernel bank: not on offer
    sta X16_P0                  ; (19 was an app's until CXBANKS2 -- this
                                ; pins the moved floor, not the old one)
    lda #<$A000
    sta X16_P1
    lda #>$A000
    sta X16_P2
    stz X16_P3
    lda #<@bn
    ldx #>@bn
    ldy #@bn_len
    jsr cx_do_bload
    ldy #1
    bcc @r3                     ; must refuse...
    cmp #0                      ; ...with the not-your-bank code
    bne @r3
    ldy #0
@r3
    tya
    ldx #<@n3
    ldy #>@n3
    jmp t_result
@n1   .byte "AB_END", 0
@n2   .byte "AB_BYTES", 0
@n3   .byte "AB_GUARD", 0
@bn   .byte "BADAPP.CXA"
@bn_len = * - @bn

test_clip
    lda #<@msg                  ; put 5 bytes of TEXT
    sta X16_P0
    lda #>@msg
    sta X16_P1
    lda #5
    sta X16_P2
    stz X16_P3
    lda #1
    jsr cx_do_clip_put
    bcs @fail

    jsr cx_do_clip_type         ; type 1, length 5 waiting
    cmp #1
    bne @fail
    lda X16_P2
    cmp #5
    bne @fail
    lda X16_P3
    bne @fail

    lda #<@buf                  ; get it back whole
    sta X16_P0
    lda #>@buf
    sta X16_P1
    lda #16
    sta X16_P2
    stz X16_P3
    jsr cx_do_clip_get
    cmp #1
    bne @fail
    lda X16_P2
    cmp #5
    bne @fail
    ldy #4
@cmp
    lda @buf,y
    cmp @msg,y
    bne @fail
    dey
    bpl @cmp

    lda #<@buf                  ; a 3-byte pocket: truncated to fit
    sta X16_P0
    lda #>@buf
    sta X16_P1
    lda #3
    sta X16_P2
    stz X16_P3
    jsr cx_do_clip_get
    lda X16_P2
    cmp #3
    bne @fail

    ldy #0
    bra @report
@fail
    ldy #1
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "CLIP", 0
@msg  .byte "HELLO"
@buf  .res 16, 0

; the long haul: a payload that rolls from bank 10 into bank 11, and
; the empty-put that clears it all away
test_clip_span
    lda #<$0801                 ; $2010 bytes from $0801: byte $2005 of
    sta X16_P0                  ; the source must land at bank 11's $A005
    lda #>$0801
    sta X16_P1
    lda #<$2010
    sta X16_P2
    lda #>$2010
    sta X16_P3
    lda #1
    jsr cx_do_clip_put
    bcs @fail
    lda RAM_BANK
    pha
    lda #11
    sta RAM_BANK
    lda $A005
    sta @got
    pla
    sta RAM_BANK
    lda $0801 + $2005
    cmp @got
    bne @fail

    lda #1                      ; and length 0 empties it
    sta X16_P0                  ; (pointer irrelevant)
    stz X16_P2
    stz X16_P3
    lda #1
    jsr cx_do_clip_put
    jsr cx_do_clip_type
    bne @fail
    lda X16_P2
    bne @fail

    ldy #0
    bra @report
@fail
    ldy #1
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "CLIPSPAN", 0
@got  .byte 0

; ---------------------------------------------------------------------
; VRAM_STREAM: the bank -> VRAM copy (kernel/resident/vstream.asm),
; INCLUDING the 8 KB window crossing. Sentinels at bank20:$A000 ($DE) and
; bank21:$A000 ($5A); stream 8193 bytes from bank 20 to VRAM $12000 (bit
; 16 set), then confirm byte 0 ($DE) and byte 8192 ($5A, which forced the
; RAM_BANK roll) landed -- and the caller's RAM_BANK came back.
; ---------------------------------------------------------------------
test_vram_stream
    stz @f
    lda #20                     ; sentinel at the start of bank 20's window
    sta RAM_BANK
    lda #$DE
    sta $A000
    lda #21                     ; ...and the start of bank 21's
    sta RAM_BANK
    lda #$5A
    sta $A000
    lda #7                      ; a "caller" bank, to prove it is restored
    sta RAM_BANK

    stz X16_P0                  ; dst = $12000 (P0/P1 = $2000, P2 bit 16 = 1)
    lda #$20
    sta X16_P1
    lda #1
    sta X16_P2
    lda #20                     ; source: bank 20 onward
    sta X16_P3
    lda #<8193                  ; 8192 (one bank) + 1 -> crosses into bank 21
    sta X16_P4
    lda #>8193
    sta X16_P5
    jsr cx_do_vram_stream

    lda RAM_BANK                ; restored to the caller's bank?
    cmp #7
    beq @bankok
    inc @f
@bankok
    lda #$20                    ; VRAM $12000 -> byte 0
    ldx #$00
    jsr @vread
    cmp #$DE
    beq @b0ok
    inc @f
@b0ok
    lda #$40                    ; VRAM $14000 = $12000 + 8192 -> byte 8192
    ldx #$00
    jsr @vread
    cmp #$5A
    beq @b8ok
    inc @f
@b8ok
    lda @f
    ldx #<@name
    ldy #>@name
    jmp t_result
@vread                          ; A = mid byte, X = low byte -> A = VRAM[bit16=1]
    pha
    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL
    stx VERA_ADDR_L
    pla
    sta VERA_ADDR_M
    lda #((VERA_INC_1 << 4) | 1)
    sta VERA_ADDR_H
    lda VERA_DATA0
    rts
@f    .byte 0
@name .byte "VRAM_STREAM", 0

; ---------------------------------------------------------------------
; font_measure must read a string that lives in a bank correctly -- the
; same width as its low-RAM twin. Before the fix, drawing/measuring
; left RAM_BANK on the font's bank between characters, so every char
; after the first was read from the wrong bank (this is what drew the
; dialog's bank-2 button labels as garbage).
; ---------------------------------------------------------------------
test_font_bank
    lda RAM_BANK
    pha
    lda #CX_APP_BANK_FLOOR      ; copy "WIDE" into an app bank at $A000
    sta RAM_BANK
    ldy #0
@cp
    lda @s,y
    sta $A000,y
    beq @measured_ref
    iny
    bne @cp
@measured_ref
    pla                         ; the reference width, from low RAM
    pha
    sta RAM_BANK
    lda #<@s
    ldx #>@s
    jsr font_measure
    lda X16_P0
    sta @refw
    lda X16_P1
    sta @refw+1

    lda #CX_APP_BANK_FLOOR      ; the same string, from the bank
    sta RAM_BANK
    lda #<$A000
    ldx #>$A000
    jsr font_measure
    pla
    sta RAM_BANK
    lda X16_P0                  ; must match, byte for byte
    cmp @refw
    bne @fail
    lda X16_P1
    cmp @refw+1
    bne @fail
    lda X16_P0                  ; and be nonzero -- a real measurement
    ora X16_P1
    beq @fail
    ldy #0
    bra @report
@fail
    ldy #1
@report
    tya
    ldx #<@name
    ldy #>@name
    jmp t_result
@name .byte "FONTBANK", 0
@s    .byte "WIDE", 0
@refw .word 0

; ---------------------------------------------------------------------
.include "kernel/font/font.asm"
.include "kernel/ui/region.asm"
.include "kernel/ui/menu.asm"
; menu.asm FIRST among the bank-2 contributors: it owns the local jump
; table, and B2CODE fills in include order -- a file ahead of it would
; shove the table off $A000 and every stub with it
.include "kernel/ui/theme.asm"
.include "kernel/ui/dialog.asm"
.include "kernel/ui/widget.asm"
.include "kernel/ui/icon.asm"
.include "kernel/ui/da.asm"
.include "kernel/audio/audio.asm"
.include "kernel/video/sprite.asm"
.include "kernel/video/engine0.asm"
.include "kernel/video/shapes.asm"
.include "kernel/video/tiles.asm"
.include "kernel/video/pal.asm"
.include "kernel/video/text.asm"
.include "kernel/fs/dosglue.asm"
.include "kernel/event/event.asm"
.include "kernel/audio/pcm.asm"
.include "kernel/resident/core.asm"
.include "kernel/resident/farcall.asm"
.include "kernel/resident/vrows.asm"
.include "kernel/resident/clip.asm"
.include "kernel/resident/vstream.asm"
.include "kernel/fs/loader.asm"
.include "kernel/fs/dir.asm"
.include "kernel/fs/fileload.asm"
.include "kernel/fs/assets.asm"
.include "kernel/gfx2/dirty.asm"
.include "kernel/resident/jumptab.asm"

; The system font, linked in so the suite needs no SD card. The kernel
; image carries no font at all -- the boot loader puts this same file at
; CX_SYSFONT_BANK:$A000, and FONT_BANKED walks that path.
pxl8
    .incbin "fonts/pxl8.cxf"
.include "testlib.asm"
.include "x16_code.asm"
