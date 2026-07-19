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
.include "sdk/include_ca65/cxgeos.inc"

EV_KEY        = 5
EV_WIDGET     = 8
EV_MOUSE_DOWN = 2
WG_HIT        = 7
WH_RECT       = 0
WH_CIRCLE     = 1
WH_ELLIPSE    = 2
WH_CLICK      = %001
WH_HOVER      = %100

STATUS_Y = 54

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    jsr cx_gfx_init
    lda #0                      ; white paper (default theme index 0)
    jsr cx_gfx_clear

    lda #<s_title
    ldx #>s_title
    ldy #20
    jsr say
    lda #<s_help
    ldx #>s_help
    ldy #36
    jsr say
    jsr status_idle

    jsr draw_shapes             ; the app owns the pixels

    jsr cx_ev_init
    lda #1
    jsr cx_mouse_show
    lda #<hits                  ; the invisible regions over the shapes
    ldx #>hits
    jsr cx_wg_set
    lda #<handlers
    ldx #>handlers
    jsr cx_ev_handlers

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
    jsr cx_ev_dispatch
    ply
    dey
    bne @sd
    cli
.endif

    jmp cx_ev_mainloop

; ---------------------------------------------------------------------
; drawing -- the three outlines and their captions
; ---------------------------------------------------------------------
draw_shapes
    lda #<50                    ; rectangle: frame at (50,130) 150x130
    sta X16_P0
    stz X16_P1
    lda #130
    sta X16_P2
    stz X16_P3
    lda #<150
    sta X16_P4
    stz X16_P5
    lda #130
    sta X16_P6
    stz X16_P7
    lda #3
    jsr cx_gfx_frame

    lda #<330                   ; circle: centre (330,195) r 75
    sta X16_P0
    lda #>330
    sta X16_P1
    lda #195
    sta X16_P2
    stz X16_P3
    lda #75
    sta X16_P4
    lda #3
    jsr cx_gfx_circle

    lda #<540                   ; ellipse: centre (540,195) rx 90 ry 65
    sta X16_P0
    lda #>540
    sta X16_P1
    lda #195
    sta X16_P2
    stz X16_P3
    lda #90
    sta X16_P4
    lda #65
    sta X16_P5
    lda #3
    jsr cx_gfx_ellipse

    lda #<70                    ; captions (row 280 > 255, so word coords)
    ldx #>70
    ldy #<s_rect
    sty X16_T0
    ldy #>s_rect
    sty X16_T0+1
    jsr caption
    lda #<305
    ldx #>305
    ldy #<s_circ
    sty X16_T0
    ldy #>s_circ
    sty X16_T0+1
    jsr caption
    lda #<505
    ldx #>505
    ldy #<s_elli
    sty X16_T0
    ldy #>s_elli
    sty X16_T0+1
    jmp caption

; caption -- A/X = x (word), X16_T0 = string; drawn on row 280
caption
    sta X16_P0
    stx X16_P1
    lda #<280
    sta X16_P2
    lda #>280
    sta X16_P3
    lda X16_T0
    ldx X16_T0+1
    jmp cx_font_draw

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
    lda #<s_idle
    ldx #>s_idle
    ldy #STATUS_Y
    jmp say

; status_name -- A = shape index: the shape's name on the status line
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
    lda #24
    sta X16_P0
    stz X16_P1
    lda #STATUS_Y
    sta X16_P2
    stz X16_P3
    lda #<600
    sta X16_P4
    lda #>600
    sta X16_P5
    lda #12
    sta X16_P6
    stz X16_P7
    lda #0
    jmp cx_gfx_rect

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
    lda #EV_MOUSE_DOWN
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

; the invisible hit regions, one per shape (click + hover)
hits
    .byte 3
    ; rectangle: box (50,130) 150x130
    .byte WG_HIT, 0
    .word 50, 130
    .word 150
    .byte 130
    .byte WH_RECT
    .byte WH_CLICK | WH_HOVER
    .word 0
    .byte 0, 0, 0              ; pad to WG_SIZE (16 bytes)
    ; circle: box (255,120) 150x150 -> centre (330,195) r 75
    .byte WG_HIT, 0
    .word 255, 120
    .word 150
    .byte 150
    .byte WH_CIRCLE
    .byte WH_CLICK | WH_HOVER
    .word 0
    .byte 0, 0, 0              ; pad to WG_SIZE (16 bytes)
    ; ellipse: box (450,130) 180x130 -> centre (540,195) rx 90 ry 65
    .byte WG_HIT, 0
    .word 450, 130
    .word 180
    .byte 130
    .byte WH_ELLIPSE
    .byte WH_CLICK | WH_HOVER
    .word 0
    .byte 0, 0, 0              ; pad to WG_SIZE (16 bytes)
