; ca65
; =====================================================================
; CXGEOS :: kernel/ui/menu.asm -- the menu engine
; =====================================================================
; Resident: four five-byte stubs. Everything else is B2CODE, runs in
; bank 2 through cxb_call, and costs the resident budget nothing
; (docs/ui.md). The menu tree lives in the APP's memory and is read in
; place -- $0801-$7FFF is always mapped. Format: docs/formats.md.
;
; The interaction model, deliberately minimal for 5a:
;
;   cx_menu_set   draws the bar, pushes the bar region. Once per app.
;   click in bar  opens that menu: full rows under the box are saved to
;                 the VRAM strip at $12C00 (full rows, because a linear
;                 fx_copy beats a rectangle walk and the strip can hold
;                 102 of them), the box is drawn, and a full-screen
;                 MODAL region is pushed -- menus own the machine while
;                 open, which is what makes closing them simple.
;   click again   on an item: restore, pop, post EV_MENU with the item
;                 in `detail` (P1) and the menu index in P2. Anywhere
;                 else: restore, pop, no event. Either way the machine
;                 is back the pixel it was.
;   cx_menu_off   removes the bar region. Only meaningful with no menu
;                 open; call it from handlers, not from inside a menu.
;
; Only an app that called cx_menu_set can ever receive EV_MENU, so apps
; built before the type existed cannot be handed one.
; =====================================================================

CX_MENU_H    = 12               ; the bar strip's height
CX_MENU_ROWH = 10               ; a drop-down row
CX_MENU_MAXI = 10               ; items per menu; 10 rows of save fit
CX_MENU_SAVE = $13100           ; the VRAM save-under strips. NOT $12C00:
                                ; the KERNAL mouse pointer image sits at
                                ; $13000, and a first draft that saved
                                ; from $12C00 would have written through
                                ; it with any box over six rows. The
                                ; ledger had it right all along.

; --- the resident stubs ------------------------------------------------
; The first two are what the ABI slots jump to; the second two are what
; the region stack calls. Five bytes each; the addresses are bank 2's
; local table, which ships in the same build as these stubs.

cx_do_menu_set
    jsr cxb_call
    .byte 2
    .addr $A000 + 0*3
cx_do_menu_off
    jsr cxb_call
    .byte 2
    .addr $A000 + 1*3
mn_bar_vec
    jsr cxb_call
    .byte 2
    .addr $A000 + 2*3
mn_drop_vec
    jsr cxb_call
    .byte 2
    .addr $A000 + 3*3
cx_do_menu_key
    jsr cxb_call
    .byte 2
    .addr $A000 + 11*3

; =====================================================================
; bank 2 from here on
; =====================================================================
.segment "B2CODE"

; The bank-2 jump table, at $A000. Bank-local, NOT the ABI: only the
; resident stubs name these slots ($A000 + n*3). SIXTEEN entries, with
; room to spare, so a new module fills a reserved slot without moving
; the state block behind it -- the table grew from 4 to 8 twice before,
; and each time the peekable state moved and a test's address went
; stale. Reserved slots land on mn_off, a safe near-no-op.
;
; SLOT MAP -- keep it in step with the stubs in each module's CODE half:
;   0 mn_set   1 mn_off   2 mn_bar   3 mn_drop     (menu.asm)
;   4 th_set                                        (theme.asm)
;   5 dg_alert 6 dg_hit                             (dialog.asm)
;   8 wg_set   9 wg_draw  10 wg_hit                 (widget.asm)
;   11 mn_key                                       (menu.asm, keyboard)
;   12 wg_key                                       (widget.asm, keyboard)
;   7, 13..15 reserved
b2_table
    jmp mn_set                  ; 0
    jmp mn_off                  ; 1
    jmp mn_bar                  ; 2
    jmp mn_drop                 ; 3
    jmp th_set                  ; 4
    jmp dg_alert                ; 5
    jmp dg_hit                  ; 6
    jmp mn_off                  ; 7  reserved
    jmp wg_set                  ; 8
    jmp wg_draw                 ; 9
    jmp wg_hit                  ; 10
    jmp mn_key                  ; 11 kernel/ui/menu.asm (keyboard)
    jmp wg_key                  ; 12 kernel/ui/widget.asm (keyboard)
    jmp mn_off                  ; 13 reserved
    jmp mn_off                  ; 14 reserved
    jmp mn_off                  ; 15 reserved

; The state block, at a FIXED spot behind the 48-byte table ($A030), so
; a test -- or a debugger, or a desperate evening -- can peek it from
; outside the bank without knowing where the code ends.
mn_bar_p .word 0                ; $A030  the app's bar; high 0 = none
mn_count .byte 0                ; $A032
mn_open  .byte 0                ; $A033
mn_cur   .byte 0                ; $A034  the open menu
mn_it_p  .word 0                ; $A035  ...its items
mn_n     .byte 0                ; $A037
mn_x0    .word 0                ; $A038  ...its box
mn_w     .word 0                ; $A03A
mn_h     .byte 0                ; $A03C
mn_pick  .byte 0                ; $A03D
mn_trace .byte 0                ; $A03E  breadcrumbs: mn_bar +1, open +$10
mn_hot   .byte 0                ; $A03F  the highlighted row; $FF = none
mn_i     .byte 0
mn_t     .byte 0, 0
mn_t2    .byte 0, 0
mn_band  .byte 0                ; the title band's colour, mid-paint
mn_mx0l  .res 8, 0              ; the bar spans, for the hit search
mn_mx0h  .res 8, 0
mn_mx1l  .res 8, 0
mn_mx1h  .res 8, 0

; ---------------------------------------------------------------------
; mn_set -- A/X = the menu bar (docs/formats.md). Draws the bar, pushes
; the bar region. Carry set if the region stack is full.
; ---------------------------------------------------------------------
mn_set
    sta mn_bar_p
    stx mn_bar_p+1
    stz mn_open

    lda mn_bar_p                ; the count, BEFORE anything loops over
    sta CX_M_PTR                ; it -- mn_entry also parks it, but
    lda mn_bar_p+1              ; mn_entry only runs inside loops that
    sta CX_M_PTR+1              ; compare against it first
    ldy #0
    lda (CX_M_PTR),y
    sta mn_count

    jsr mn_draw_bar

    stz X16_P0                  ; the bar region: 0,0 to 639,H-1
    stz X16_P1
    stz X16_P2
    stz X16_P3
    lda #<639
    sta X16_P4
    lda #>639
    sta X16_P5
    lda #CX_MENU_H-1
    sta X16_P6
    stz X16_P7
    lda #<mn_bar_vec
    ldx #>mn_bar_vec
    jmp rg_push

; ---------------------------------------------------------------------
; mn_off -- forget the menu. Pops the bar region, which is only correct
; when it is on top: call this from an event handler, never mid-menu.
; ---------------------------------------------------------------------
mn_off
    stz mn_bar_p+1              ; a null bar pointer = no menu
    jmp rg_pop

; ---------------------------------------------------------------------
; mn_draw_bar -- the strip and the titles, and the hit spans the bar
; click will search. Title m starts 8px in, then measured width plus
; 16px of air between neighbours.
; ---------------------------------------------------------------------
mn_draw_bar
    stz X16_P0                  ; the strip: paper 0
    stz X16_P1
    stz X16_P2
    stz X16_P3
    lda #<640
    sta X16_P4
    lda #>640
    sta X16_P5
    lda #CX_MENU_H
    sta X16_P6
    stz X16_P7
    lda th_paper
    jsr gfx2_rect
    stz X16_P0                  ; ...ruled off along its bottom
    stz X16_P1
    lda #CX_MENU_H-1
    sta X16_P2
    stz X16_P3
    lda #<640
    sta X16_P4
    lda #>640
    sta X16_P5
    lda th_frame
    jsr gfx2_hline

    lda #8                      ; the pen
    sta mn_t
    stz mn_t+1

    stz mn_i
@title
    lda mn_i
    cmp mn_count
    bcs @done
    jsr mn_entry                ; CX_M_PTR = entry mn_i

    ldy mn_i                    ; the span opens where the pen stands
    lda mn_t
    sta mn_mx0l,y
    lda mn_t+1
    sta mn_mx0h,y

    ldy #0                      ; the title, measured then drawn
    lda (CX_M_PTR),y
    sta mn_t2
    iny
    lda (CX_M_PTR),y
    sta mn_t2+1
    lda mn_t2
    ldx mn_t2+1
    jsr font_measure            ; P0/P1 = width
    clc                         ; span close = pen + width
    lda mn_t
    adc X16_P0
    ldy mn_i
    sta mn_mx1l,y
    lda mn_t+1
    adc X16_P1
    sta mn_mx1h,y

    lda mn_t                    ; draw at the pen, 2 down
    sta X16_P0
    lda mn_t+1
    sta X16_P1
    lda #2
    sta X16_P2
    stz X16_P3
    lda mn_t2
    ldx mn_t2+1
    jsr font_draw               ; hands back the pen in P0/P1

    clc                         ; 16px of air to the next title
    lda X16_P0
    adc #16
    sta mn_t
    lda X16_P1
    adc #0
    sta mn_t+1

    inc mn_i
    bra @title
@done
    rts

; ---------------------------------------------------------------------
; mn_title_band -- A = a colour index. Paints the OPEN menu's title
; span in the bar with it and redraws the title on top, so the bar
; itself says which menu is open: th_hi when a drop-down opens,
; th_paper when it closes. The band stops a pixel short of the bar's
; rule. The bar is not under any save-under strip, so the close path
; must paint it back by hand -- that is the th_paper call.
; ---------------------------------------------------------------------
mn_title_band
    sta mn_band
    ldy mn_cur                  ; x0 = span open - 4 (the air), w = span
    sec                         ; width + 8
    lda mn_mx0l,y
    sbc #4
    sta X16_P0
    lda mn_mx0h,y
    sbc #0
    sta X16_P1
    sec
    lda mn_mx1l,y
    sbc mn_mx0l,y
    sta X16_P4
    lda mn_mx1h,y
    sbc mn_mx0h,y
    sta X16_P5
    clc
    lda X16_P4
    adc #8
    sta X16_P4
    bcc @wnc
    inc X16_P5
@wnc
    stz X16_P2
    stz X16_P3
    lda #CX_MENU_H-1
    sta X16_P6
    stz X16_P7
    lda mn_band
    jsr gfx2_rect

    lda mn_cur                  ; the title back on top, where the bar
    sta mn_i                    ; drew it: its span's start, 2 down
    jsr mn_entry
    ldy mn_cur
    lda mn_mx0l,y
    sta X16_P0
    lda mn_mx0h,y
    sta X16_P1
    lda #2
    sta X16_P2
    stz X16_P3
    ldy #0
    lda (CX_M_PTR),y
    tax
    iny
    lda (CX_M_PTR),y
    stx CX_M_PTR
    sta CX_M_PTR+1
    lda CX_M_PTR
    ldx CX_M_PTR+1
    jmp font_draw

; ---------------------------------------------------------------------
; mn_entry -- CX_M_PTR = bar entry mn_i (4 bytes each, after the count),
; and mn_count loaded while passing. Uses the app's tree in place.
; ---------------------------------------------------------------------
mn_entry
    lda mn_bar_p
    sta CX_M_PTR
    lda mn_bar_p+1
    sta CX_M_PTR+1
    ldy #0
    lda (CX_M_PTR),y
    sta mn_count
    lda mn_i                    ; 1 + i*4
    asl
    asl
    sec                         ; +1 via carry
    adc CX_M_PTR
    sta CX_M_PTR
    bcc @nc
    inc CX_M_PTR+1
@nc
    rts

; ---------------------------------------------------------------------
; mn_bar -- the bar region's handler: a mouse record in X16_P0..P7.
; Only a press does anything; finding which span the x falls in picks
; the menu to open.
; ---------------------------------------------------------------------
mn_bar
    inc mn_trace
    lda X16_P0
    cmp #EV_MOUSE_DOWN
    bne @out
    lda mn_bar_p+1
    beq @out                    ; no bar set: a stale region, ignore

    stz mn_i
@span
    lda mn_i
    cmp mn_count
    bcs @out                    ; the gap between titles: nothing
    ldy mn_i
    lda X16_P2                  ; x >= span open
    cmp mn_mx0l,y
    lda X16_P3
    sbc mn_mx0h,y
    bcc @next
    lda mn_mx1l,y               ; x <= span close
    cmp X16_P2
    lda mn_mx1h,y
    sbc X16_P3
    bcc @next
    lda mn_i
    jmp mn_drop_open
@next
    inc mn_i
    bra @span
@out
    rts

; ---------------------------------------------------------------------
; mn_drop_open -- A = the menu to open. Geometry, save-under, paint,
; and the modal region.
; ---------------------------------------------------------------------
mn_drop_open
    pha
    lda mn_trace
    clc
    adc #$10
    sta mn_trace
    pla
    sta mn_cur
    sta mn_i
    jsr mn_entry
    ldy #2                      ; the items list
    lda (CX_M_PTR),y
    sta mn_it_p
    iny
    lda (CX_M_PTR),y
    sta mn_it_p+1

    lda mn_it_p                 ; item count, capped to what the strip
    sta CX_M_PTR                ; can save under
    lda mn_it_p+1
    sta CX_M_PTR+1
    ldy #0
    lda (CX_M_PTR),y
    cmp #CX_MENU_MAXI+1
    bcc @nok
    lda #CX_MENU_MAXI
@nok
    sta mn_n

    ; the box: x0 = the title's span, w = widest item + 8, h = n rows +2
    ldy mn_cur
    lda mn_mx0l,y
    sta mn_x0
    lda mn_mx0h,y
    sta mn_x0+1

    stz mn_w
    stz mn_w+1
    stz mn_i
@wide
    lda mn_i
    cmp mn_n
    bcs @wdone
    jsr mn_item                 ; CX_M_PTR = label mn_i
    lda CX_M_PTR
    ldx CX_M_PTR+1
    jsr font_measure
    lda X16_P0                  ; keep the widest
    cmp mn_w
    lda X16_P1
    sbc mn_w+1
    bcc @thin
    lda X16_P0
    sta mn_w
    lda X16_P1
    sta mn_w+1
@thin
    inc mn_i
    bra @wide
@wdone
    clc
    lda mn_w
    adc #8
    sta mn_w
    bcc @wnc
    inc mn_w+1
@wnc

    lda mn_n                    ; h = n * CX_MENU_ROWH + 2
    asl
    asl
    adc mn_n                    ; n*5 (n <= 10: no carry out of asl)
    asl                         ; n*10
    adc #2
    sta mn_h

    lda #1                      ; save the rows the box will cover
    jsr mn_strip

    lda mn_x0                   ; paper...
    sta X16_P0
    lda mn_x0+1
    sta X16_P1
    lda #CX_MENU_H
    sta X16_P2
    stz X16_P3
    lda mn_w
    sta X16_P4
    lda mn_w+1
    sta X16_P5
    lda mn_h
    sta X16_P6
    stz X16_P7
    lda th_paper
    jsr gfx2_rect
    lda mn_x0                   ; ...framed...
    sta X16_P0
    lda mn_x0+1
    sta X16_P1
    lda #CX_MENU_H
    sta X16_P2
    stz X16_P3
    lda mn_w
    sta X16_P4
    lda mn_w+1
    sta X16_P5
    lda mn_h
    sta X16_P6
    stz X16_P7
    lda th_frame
    jsr gfx2_frame

    stz mn_i                    ; ...and the items
@item
    lda mn_i
    cmp mn_n
    bcs @idone
    jsr mn_item
    clc                         ; x0 + 4
    lda mn_x0
    adc #4
    sta X16_P0
    lda mn_x0+1
    adc #0
    sta X16_P1
    lda mn_i                    ; y = H + 2 + i*ROWH
    asl
    asl
    adc mn_i
    asl
    adc #CX_MENU_H+2
    sta X16_P2
    stz X16_P3
    lda CX_M_PTR
    ldx CX_M_PTR+1
    jsr font_draw
    inc mn_i
    bra @item
@idone

    stz X16_P0                  ; the modal region: menus own the
    stz X16_P1                  ; machine while open
    stz X16_P2
    stz X16_P3
    lda #<639
    sta X16_P4
    lda #>639
    sta X16_P5
    lda #<479
    sta X16_P6
    lda #>479
    sta X16_P7
    lda #<mn_drop_vec
    ldx #>mn_drop_vec
    jsr rg_push
    lda #$FF                    ; nothing highlighted until the pointer
    sta mn_hot                  ; says so
    lda #1
    sta mn_open
    lda th_hi                   ; the bar shows which menu is open
    jmp mn_title_band

; ---------------------------------------------------------------------
; mn_item -- CX_M_PTR = item label mn_i: the list is a count, then a
; word per item.
; ---------------------------------------------------------------------
mn_item
    lda mn_it_p
    sta CX_M_PTR
    lda mn_it_p+1
    sta CX_M_PTR+1
    lda mn_i                    ; 1 + i*2
    asl
    sec
    adc CX_M_PTR
    sta CX_M_PTR
    bcc @nc
    inc CX_M_PTR+1
@nc
    ldy #0                      ; resolve to the label itself
    lda (CX_M_PTR),y
    tax
    iny
    lda (CX_M_PTR),y
    sta CX_M_PTR+1
    stx CX_M_PTR
    rts

; ---------------------------------------------------------------------
; mn_drop -- the modal region's handler. A press picks or dismisses;
; either way the pixels come back and the modal region goes.
; ---------------------------------------------------------------------
mn_drop
    lda X16_P0
    cmp #EV_MOUSE_DOWN
    beq @press
    cmp #EV_MOUSE_MOVE
    beq @hover
    rts

@hover                          ; the row under the pointer follows it
    jsr mn_rowat
    cmp mn_hot
    beq @still                  ; the same row: nothing to repaint
    jmp mn_hotswap
@still
    rts

@press
    jsr mn_rowat                ; $FF misses double as "dismiss"
    ; falls into mn_finish

; ---------------------------------------------------------------------
; mn_finish -- A = the chosen item, or $FF to dismiss. Restores the
; pixels, pops the modal region, and -- unless dismissed -- posts
; EV_MENU. Shared by the click, the keyboard, and menu switching.
; ---------------------------------------------------------------------
mn_finish
    sta mn_pick
    lda th_paper                ; the open title's band off the bar (the
    jsr mn_title_band           ; bar is above the save-under strip)
    lda #0                      ; the pixels back, the region gone
    jsr mn_strip
    jsr rg_pop
    stz mn_open

    lda mn_pick
    bmi @out                    ; dismissed: no one hears anything
    sta X16_P1                  ; EV_MENU: detail = item, P2 = menu
    lda #EV_MENU
    sta X16_P0
    lda mn_cur
    sta X16_P2
    stz X16_P3
    stz X16_P4
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jmp ev_post
@out
    rts

; ---------------------------------------------------------------------
; mn_key -- A = a key. Drives the menus from the keyboard: DOWN opens
; the bar; once open, UP/DOWN move the highlight, LEFT/RIGHT switch
; menus, RETURN picks, ESC dismisses. Carry set if the key was a menu
; key (the app should not also act on it), clear to pass it through.
;
; The same open/highlight/finish routines the mouse uses, so a menu
; driven blind by the keyboard behaves exactly like a clicked one --
; including the EV_MENU it posts.
; ---------------------------------------------------------------------
KEY_DOWN  = $11
KEY_UP    = $91
KEY_RIGHT = $1D
KEY_LEFT  = $9D
KEY_ENTER = $0D
KEY_ESC   = $1B

mn_key
    ldx mn_bar_p+1
    beq @no                     ; no bar set: not ours
    ldx mn_open
    bne @open

    cmp #KEY_DOWN               ; closed: DOWN drops the first menu
    bne @no
    lda #0
    jsr mn_kopen
    bra @yes

@open
    cmp #KEY_ESC
    beq @dismiss
    cmp #KEY_ENTER
    beq @pick
    cmp #KEY_DOWN
    beq @down
    cmp #KEY_UP
    beq @up
    cmp #KEY_RIGHT
    beq @right
    cmp #KEY_LEFT
    beq @left
    bra @no                     ; a typing key: the app's, not ours

@dismiss
    lda #$FF
    jsr mn_finish
    bra @yes
@pick
    lda mn_hot
    jsr mn_finish
    bra @yes
@down
    ldx mn_hot
    inx                         ; $FF (none) wraps to 0 too
    cpx mn_n
    bcc @seth
    ldx #0
@seth
    txa
    jsr mn_hotswap
    bra @yes
@up
    ldx mn_hot
    bmi @last                   ; none highlighted: wrap to the last
    dex
    bpl @seth2
@last
    ldx mn_n
    dex
@seth2
    txa
    jsr mn_hotswap
    bra @yes
@right
    ldx mn_cur
    inx
    cpx mn_count
    bcc @switch
    ldx #0
@switch
    txa
    jsr mn_switch
    bra @yes
@left
    ldx mn_cur
    bne @decm
    ldx mn_count
@decm
    dex
    txa
    jsr mn_switch
@yes
    sec
    rts
@no
    clc
    rts

; mn_kopen -- A = menu: open its drop-down and highlight item 0.
mn_kopen
    jsr mn_drop_open
    lda #0
    jmp mn_hotswap

; mn_switch -- A = menu: close the open drop-down (no pick) and open
; the given one. LEFT/RIGHT walk the bar this way.
mn_switch
    pha
    lda #$FF
    jsr mn_finish
    pla
    jmp mn_kopen

; ---------------------------------------------------------------------
; mn_rowat -- the record's point (X16_P2..P5) against the open box:
; A = the item row it lands on, or $FF -- outside, on the frame, or
; past the last item. The press and the hover share this verdict.
; ---------------------------------------------------------------------
mn_rowat
    lda X16_P2                  ; x >= x0
    cmp mn_x0
    lda X16_P3
    sbc mn_x0+1
    bcc @no
    clc                         ; x < x0 + w
    lda mn_x0
    adc mn_w
    sta mn_t
    lda mn_x0+1
    adc mn_w+1
    sta mn_t+1
    lda X16_P2
    cmp mn_t
    lda X16_P3
    sbc mn_t+1
    bcs @no
    lda X16_P5                  ; rows start at H+1, ROWH each
    bne @no
    lda X16_P4
    sec
    sbc #CX_MENU_H+1
    bcc @no
    ldx #0
@row
    cmp #CX_MENU_ROWH
    bcc @got
    sbc #CX_MENU_ROWH           ; carry known set
    inx
    bra @row
@got
    cpx mn_n
    bcs @no
    txa
    rts
@no
    lda #$FF
    rts

; ---------------------------------------------------------------------
; mn_hotswap -- A = the row the highlight moves to ($FF = none). The
; old row is repainted plain, the new one on paper 1; the label rides
; on top both times, because the masked blit keeps whatever paper it
; lands on.
; ---------------------------------------------------------------------
mn_hotswap
    pha
    lda mn_hot
    bmi @nold
    ldy th_paper
    jsr mn_row_paint
@nold
    pla
    sta mn_hot
    bmi @done
    ldy th_hi
    jsr mn_row_paint
@done
    rts

; ---------------------------------------------------------------------
; mn_row_paint -- A = row, Y = its paper. The band inside the frame,
; then the label again.
; ---------------------------------------------------------------------
mn_row_paint
    sta mn_i
    sty mn_t2
    clc                         ; the band: x0+1, w-2 -- off the frame
    lda mn_x0
    adc #1
    sta X16_P0
    lda mn_x0+1
    adc #0
    sta X16_P1
    lda mn_i                    ; y = H + 1 + row*ROWH
    asl
    asl
    adc mn_i
    asl
    adc #CX_MENU_H+1
    sta X16_P2
    stz X16_P3
    sec
    lda mn_w
    sbc #2
    sta X16_P4
    lda mn_w+1
    sbc #0
    sta X16_P5
    lda #CX_MENU_ROWH
    sta X16_P6
    stz X16_P7
    lda mn_t2
    jsr gfx2_rect

    jsr mn_item                 ; the label, back on top
    clc
    lda mn_x0
    adc #4
    sta X16_P0
    lda mn_x0+1
    adc #0
    sta X16_P1
    lda mn_i
    asl
    asl
    adc mn_i
    asl
    adc #CX_MENU_H+2
    sta X16_P2
    stz X16_P3
    lda CX_M_PTR
    ldx CX_M_PTR+1
    jmp font_draw

; ---------------------------------------------------------------------
; mn_strip -- A = 1 saves, 0 restores: the full rows from CX_MENU_H for
; mn_h rows, between the framebuffer and the VRAM strip. Full rows make
; it one linear fx_copy; both directions are 4-aligned because 160*row
; always is.
; ---------------------------------------------------------------------
mn_strip
    tax                         ; the direction, for later

    lda mn_h                    ; count = mn_h * 160 = h*128 + h*32
    stz mn_t
    lsr                         ; h/2 * 256 + (h%2)*128 = h*128
    sta mn_t+1
    bcc @even
    lda #128
    sta mn_t
@even
    lda mn_h                    ; + h*32
    stz mn_t2
    .repeat 3
    lsr
    ror mn_t2
    .endrepeat                  ; A:mn_t2 = h*32 in hi:lo
    tay
    clc
    lda mn_t2
    adc mn_t
    sta mn_t
    tya
    adc mn_t+1
    sta mn_t+1

    lda mn_t
    sta X16_P6
    lda mn_t+1
    sta X16_P7

    cpx #0
    beq @restore
    lda #<(CX_MENU_H*160)       ; framebuffer -> strip
    sta X16_P0
    lda #>(CX_MENU_H*160)
    sta X16_P1
    stz X16_P2
    lda #<CX_MENU_SAVE
    sta X16_P3
    lda #>CX_MENU_SAVE
    sta X16_P4
    lda #^CX_MENU_SAVE
    sta X16_P5
    jmp fx_copy
@restore
    lda #<CX_MENU_SAVE          ; strip -> framebuffer
    sta X16_P0
    lda #>CX_MENU_SAVE
    sta X16_P1
    lda #^CX_MENU_SAVE
    sta X16_P2
    lda #<(CX_MENU_H*160)
    sta X16_P3
    lda #>(CX_MENU_H*160)
    sta X16_P4
    stz X16_P5
    jmp fx_copy

.segment "CODE"
