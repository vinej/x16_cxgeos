; ca65
; =====================================================================
; CXGEOS :: apps/hittest/hittest.asm -- the invisible hit-region demo
; =====================================================================
; Shows WG_HIT: a hotspot the app draws itself while the toolkit only
; routes the mouse. Three outlines -- a rectangle, a circle, an ellipse --
; each backed by an invisible WG_HIT region of the matching shape, with
; the click AND hover triggers on. Hover a shape and its name shows on the
; status line; click it and a dot is stamped inside. The point: the fill
; only lands where the pointer is really inside the shape, not merely in
; its bounding box -- the toolkit did the circle/ellipse math.
;
; Mouse throughout; ESC quits. Assemble with -DHITTEST_SELFTEST to have it
; synthesize a click in each shape at start-up (for a headless capture).
; =====================================================================

.include "x16.asm"
.include "asmsdk/ca65/cxgeos.inc"

STATUS_Y = 54

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    cxm_gfx_init
    cxm_gfx_clear 0                 ; white paper (default theme index 0)

    cxm_say s_title, 24, 20
    cxm_say s_help,  24, 36
    jsr status_idle

    jsr draw_shapes             ; the app owns the pixels

    cxm_ev_init
    cxm_mouse_show 1
    cxm_wg_set hits             ; the invisible regions over the shapes
    cxm_ev_handlers handlers

.ifdef HITTEST_SELFTEST
    sei                         ; mask the sampler so only our clicks queue
    lda #0                      ; headless proof: click inside each shape
    jsr synth_click
    lda #1
    jsr synth_click
    lda #2
    jsr synth_click
    ldy #12                     ; a handler stamps a disc (clobbers X), so the
@sd                             ; drain counter lives in Y across the dispatch
    phy
    cxm_ev_dispatch
    ply
    dey
    bne @sd
    cli
.endif

    cxm_ev_mainloop

; ---------------------------------------------------------------------
; drawing -- the three outlines and their captions
; ---------------------------------------------------------------------
draw_shapes
    cxm_gfx_frame   50, 130, 150, 130, 3    ; rectangle at (50,130) 150x130
    cxm_gfx_circle  330, 195, 75, 3         ; circle:  centre (330,195) r 75
    cxm_gfx_ellipse 540, 195, 90, 65, 3     ; ellipse: centre (540,195) rx 90 ry 65

    cxm_say s_rect, 70,  280    ; captions under each shape, on row 280
    cxm_say s_circ, 305, 280
    cxm_say s_elli, 505, 280
    rts

; ---------------------------------------------------------------------
; events
; ---------------------------------------------------------------------
; on_widget -- a WG_HIT fired: P1 = region index, P2 = phase (2 click,
; 1 hover-in, 0 hover-out).
on_widget
    lda X16_P2
    cmp #2
    beq @click
    cmp #1
    beq @hover
    jsr status_idle             ; hover-out: back to the prompt
    rts
@hover
    lda X16_P1                  ; hover-in: name the shape
    jmp status_name
@click
    lda X16_P1                  ; the region index; status_name draws (which
    pha                         ; clobbers the P block), so keep it on the stack
    jsr status_name             ; name the shape...
    pla
    jmp stamp                   ; ...and stamp a dot in THAT shape, not P1's leftover

on_key
    lda X16_P1
    cmp #$1B                    ; ESC quits
    bne @out
    jmp cx_exit
@out
    rts

; stamp -- A = shape index: a filled disc at that shape's centre
stamp
    asl
    tax
    lda cxs,x
    sta X16_P0
    lda cxs+1,x
    sta X16_P1
    txa
    lsr
    tax
    lda cys,x
    sta X16_P2
    stz X16_P3
    lda #16
    sta X16_P4
    lda #2
    jmp cx_gfx_disc

; ---------------------------------------------------------------------
; the status line: erase its strip, then a single string (no register
; juggling across the erase, which clobbers A/X/Y)
; ---------------------------------------------------------------------
status_idle
    jsr status_erase
    cxm_say s_idle, 24, STATUS_Y
    rts

; status_name -- A = shape index: the shape's name on the status line. The
; name comes from a table (A/X), so this one keeps the register-based say.
status_name
    sta wtmp                    ; the index, safe across the erase
    jsr status_erase
    lda wtmp
    asl
    tay
    lda names,y
    ldx names+1,y
    ldy #STATUS_Y
    jmp say

status_erase                    ; the status strip back to paper
    cxm_gfx_rect 24, STATUS_Y, 600, 12, 0
    rts

; say -- A/X = string, Y = row; column 24
say
    sty X16_P2
    stz X16_P3
    ldy #24
    sty X16_P0
    stz X16_P1
    jmp cx_font_draw

handlers                        ; NULL MOVE DOWN UP DBL KEY TIMER MENU WIDGET JOY
    .addr 0, 0, 0, 0, 0
    .addr on_key
    .addr 0
    .addr 0
    .addr on_widget
    .addr 0

.ifdef HITTEST_SELFTEST
; synth_click -- A = shape index: post EV_MOUSE_DOWN at its centre
synth_click
    asl
    tax
    lda cxs,x
    sta X16_P2
    lda cxs+1,x
    sta X16_P3
    txa
    lsr
    tax
    lda cys,x
    sta X16_P4
    stz X16_P5
    lda #CX_ET_DOWN
    sta X16_P0
    stz X16_P1
    jmp cx_ev_post
.endif

; shape centres (index order: rect, circle, ellipse)
cxs   .word 125, 330, 540
cys   .byte 195, 195, 195

names .addr s_rect, s_circ, s_elli

wtmp   .byte 0

s_title .byte "CXGEOS -- invisible hit regions (WG_HIT)", 0
s_help  .byte "the app draws the shapes; the toolkit routes the mouse. hover or click; ESC quits.", 0
s_idle  .byte "move the pointer over a shape.", 0
s_rect  .byte "rectangle", 0
s_circ  .byte "circle", 0
s_elli  .byte "ellipse", 0

; the invisible hit regions, one per shape (click + hover). Each cxm_wg_hit
; lays down exactly one 16-byte record -- the pad can't be miscounted.
hits
    cxm_wcount hits, hits_end
    ;            x    y    w    h   shape          triggers
    cxm_wg_hit  50, 130, 150, 130, CX_WH_RECT,    CX_WH_CLICK | CX_WH_HOVER
    cxm_wg_hit 255, 120, 150, 150, CX_WH_CIRCLE,  CX_WH_CLICK | CX_WH_HOVER
    cxm_wg_hit 450, 130, 180, 130, CX_WH_ELLIPSE, CX_WH_CLICK | CX_WH_HOVER
hits_end:
