; ca65
; =====================================================================
; CXGEOS :: kernel/ui/widget.asm -- the widget toolkit (bank 16)
; =====================================================================
; A widget is a 16-byte record the APP owns (docs/formats.md). The app
; hands the kernel a list -- a count, then the records -- and the kernel
; draws them and turns clicks on them into EV_WIDGET events. The record
; carries the widget's own state (checked, pressed, scroll position), so
; the kernel writes back into the app's memory; $0801-$7FFF is always
; mapped, so bank-16 code reaches it directly. The toolkit's own state
; (wg_list &c) lives in this bank too -- code and state together, which
; is why a modal panel in bank 5 must trampoline through wg_setup rather
; than touch wg_list itself.
;
;   cx_wg_set    A/X = the list. Draws it, pushes a region over its
;                bounding box so clicks route here. One list at a time.
;   cx_wg_draw   redraw the list (after a theme change, say).
;
; A click updates the widget under it, redraws just that widget, and
; posts EV_WIDGET with the widget index in detail (P1) and its value in
; P2. A button is momentary (value 1 on click); a checkbox toggles; a
; radio lights and darkens its group-mates; a scrollbar takes the value
; the click position names. All colours come from the live theme, so the
; toolkit is themable for free.
;
; Keyboard: cx_wg_key drives the same list without a mouse -- TAB/UP move
; a focus frame between widgets, SPACE/RETURN activate the focused one
; (the click path exactly), LEFT/RIGHT step a focused scrollbar. Same
; EV_WIDGET either way.
;
; Deliberately not here yet: the text field's caret and the list view.
; Those want the focus model this pass just built, plus keyboard text
; entry, and ride the next one.
; =====================================================================

WG_BUTTON = 0
WG_CHECK  = 1
WG_RADIO  = 2
WG_SCROLL = 3                   ; horizontal, click-to-position
WG_FIELD  = 4                   ; a text field: WG_LBL is a mutable
                                ; buffer, WG_VAL its length, WG_GRP its
                                ; capacity. Typed into when focused.
WG_LIST   = 5                   ; a list: WG_LBL is an array of string
                                ; pointers, WG_GRP the count, WG_VAL the
                                ; selected row, WG_TOP the scroll top.
                                ; UP/DOWN move the selection.
WG_ICON   = 6                   ; an icon tile (the desktop's icon view):
                                ; WG_VAL is the icon id (0-7, kernel/ui/
                                ; icon.asm), WG_LBL the caption, WG_W/WG_H
                                ; the cell. A single click posts
                                ; EV_WIDGET(index, 0), a double-click
                                ; (index, 1) -- select vs open.
WG_HIT    = 7                   ; an INVISIBLE hit region -- a hotspot the app
                                ; draws itself; the toolkit only routes the
                                ; mouse. WG_VAL = shape (WH_*), inscribed in
                                ; WG_X/Y/W/H; WG_GRP = trigger mask (bit0 click,
                                ; bit1 release, bit2 hover; 0 = click-only). It
                                ; posts EV_WIDGET(index, phase) where phase is
                                ; the mouse event (2 down, 3 up, 1 hover-in,
                                ; 0 hover-out) and paints nothing.

; WG_HIT shapes (WG_VAL). Circle and ellipse are inscribed in the box; a
; circle is just an ellipse with a square box. Semi-axes are bytes, so a
; round region spans at most ~510 px -- a bigger one should use WH_RECT.
; POLYGON and PIE are circle-based (use a square box) and tested in bank 19
; (kernel/video/shphit.asm), where the trig they need already lives; their
; two params ride the record's spare pad bytes (WH_SIDES/WH_ROT for a
; polygon, WH_A0/WH_A1 for a wedge -- byte angles, 0 = east, 64 = south).
WH_RECT    = 0
WH_CIRCLE  = 1
WH_ELLIPSE = 2
WH_POLYGON = 3                  ; a regular convex n-gon (WH_SIDES, WH_ROT)
WH_PIE     = 4                  ; an arc/pie wedge (WH_A0, WH_A1)

WH_SIDES   = 13                 ; WH_POLYGON: 3..24 sides       (a pad byte)
WH_ROT     = 14                 ; WH_POLYGON: rotation, byte angle
WH_A0      = 13                 ; WH_PIE: start angle, byte angle
WH_A1      = 14                 ; WH_PIE: end angle

; WG_HIT trigger mask (WG_GRP)
WH_CLICK   = %001
WH_RELEASE = %010
WH_HOVER   = %100

WG_TOP    = 13                  ; list scroll offset (a pad byte)
WL_ROWH   = 10                  ; a list row's height

WG_DISABLED = $01               ; flags bit 0

; record layout, 16 bytes (stride is n<<4)
WG_TYPE  = 0
WG_FLAGS = 1
WG_X     = 2                    ; word
WG_Y     = 4                    ; word
WG_W     = 6                    ; word
WG_H     = 8                    ; byte
WG_VAL   = 9                    ; byte: check 0/1, scroll 0..max
WG_GRP   = 10                   ; byte: radio group id, or scroll max
WG_LBL   = 11                   ; word: the label string
WG_SIZE  = 16

WG_BOX   = 12                   ; the check/radio marker box, a side

; --- the resident stubs ------------------------------------------------
; The whole toolkit body rides bank 16 now -- its own theme bank
; (banks.inc), where new widgets grow -- so the stubs far-call the
; routines by label directly. (They went through bank 2's local table
; while widgets shared that bank; the four b2_table rows they used are
; retired to mn_off. dialog.asm's dlg_wg_* trampolines follow to
; .byte CX_WG_BANK.)
cx_do_wg_set
    jsr cxb_call
    .byte CX_WG_BANK
    .addr wg_set
cx_do_wg_draw
    jsr cxb_call
    .byte CX_WG_BANK
    .addr wg_draw
wg_vec
    jsr cxb_call
    .byte CX_WG_BANK
    .addr wg_hit
cx_do_wg_key
    jsr cxb_call
    .byte CX_WG_BANK
    .addr wg_key

.segment "B16CODE"

; ---------------------------------------------------------------------
; wg_setup -- A/X = the widget list. Parks it and draws it, but pushes
; NO region. cx_wg_set adds the region on top; the modal panel manages
; its own full-screen region instead and just needs the list live so
; wg_hit can act on it.
; ---------------------------------------------------------------------
wg_setup
    pha                         ; park the OLD context first, so a modal
    phx                         ; panel that borrows this single slot can
    lda wg_list                 ; hand it back with wg_restore. wg_list &c
    sta wg_svlist               ; are bank-2 RAM the dialog's bank-5 code
    lda wg_list+1               ; cannot touch, so the save lives here.
    sta wg_svlist+1
    lda wg_n
    sta wg_svn
    lda wg_focus
    sta wg_svf
    plx
    pla
    sta wg_list                 ; indirect reads go through CX_M_PTR, a
    stx wg_list+1               ; zero-page pointer -- wg_list itself is
    sta CX_M_PTR                ; bank-2 RAM and cannot be dereferenced
    stx CX_M_PTR+1
    ldy #0
    lda (CX_M_PTR),y            ; the count
    sta wg_n
    lda #$FF                    ; a fresh list starts unfocused, and over no
    sta wg_focus                ; hit region
    sta wg_hover
    jmp wg_draw_all

; wg_restore -- put back the widget context wg_setup parked. The panel
; calls it (through a trampoline) when it closes, so the app's own
; widgets answer clicks again.
wg_restore
    lda wg_svlist
    sta wg_list
    lda wg_svlist+1
    sta wg_list+1
    lda wg_svn
    sta wg_n
    lda wg_svf
    sta wg_focus
    rts

; ---------------------------------------------------------------------
; wg_pop_own -- if the region on top of the stack is the toolkit's own
; (handler = wg_vec), discard it. Lets wg_set be idempotent: calling
; cx_wg_set again to swap the widget list replaces the click region in
; place instead of leaking a stack slot per swap. The stack (rg_n, rg_tab)
; and rg_pop are resident, reachable from bank 16.
wg_pop_own
    pha                         ; A/X are the caller's list pointer, bound for
    phx                         ; wg_setup next -- this routine must not eat them
    lda rg_n
    beq @out                    ; empty stack: nothing on top
    sec
    sbc #1
    sta wg_t                    ; top slot index
    asl
    asl                         ; slot*4
    clc
    adc wg_t                    ; slot*5
    asl                         ; slot*10 = its byte offset
    tay
    lda rg_tab+8,y              ; the region's handler
    cmp #<wg_vec
    bne @out
    lda rg_tab+9,y
    cmp #>wg_vec
    bne @out
    jsr rg_pop
@out
    plx
    pla
    rts

; wg_set -- A/X = the widget list. Parks it, draws it, and pushes a
; region over the bounding box of all the widgets so their clicks come
; back to wg_hit. Carry set only if the region stack is full.
; ---------------------------------------------------------------------
wg_set
    jsr wg_pop_own              ; a re-set REPLACES our region, it does not
                                ; stack a second (the desktop toggles list <->
                                ; icons through here); the drop-down that
                                ; posted the menu event is already popped, so
                                ; when it is ours on top it is safe to drop
    jsr wg_setup                ; register + draw...
                                ; ...then push the click region:

    ; the bounding box, for the region: min x0/y0, max x1/y1 over the
    ; list. A widget's own click test is exact; this is just the gate.
    lda #$FF
    sta wg_bx0
    sta wg_bx0+1
    sta wg_by0
    sta wg_by0+1
    stz wg_bx1
    stz wg_bx1+1
    stz wg_by1
    stz wg_by1+1

    stz wg_i
@bb
    lda wg_i
    cmp wg_n
    bcc @bbcont                 ; the body is long: branch to it, jmp out
    jmp @bbdone
@bbcont
    jsr wg_rec                  ; CX_M_PTR = record wg_i

    ldy #WG_X                   ; min x0
    lda (CX_M_PTR),y
    sta wg_t
    iny
    lda (CX_M_PTR),y
    sta wg_t+1
    lda wg_t
    cmp wg_bx0
    lda wg_t+1
    sbc wg_bx0+1
    bcs @nx0
    lda wg_t
    sta wg_bx0
    lda wg_t+1
    sta wg_bx0+1
@nx0
    ldy #WG_Y                   ; min y0
    lda (CX_M_PTR),y
    sta wg_t2
    iny
    lda (CX_M_PTR),y
    sta wg_t2+1
    lda wg_t2
    cmp wg_by0
    lda wg_t2+1
    sbc wg_by0+1
    bcs @ny0
    lda wg_t2
    sta wg_by0
    lda wg_t2+1
    sta wg_by0+1
@ny0
    jsr wg_x1y1                 ; wg_t = x1, wg_t2 = y1 (exclusive-1)
    lda wg_bx1                  ; max x1
    cmp wg_t
    lda wg_bx1+1
    sbc wg_t+1
    bcs @nx1
    lda wg_t
    sta wg_bx1
    lda wg_t+1
    sta wg_bx1+1
@nx1
    lda wg_by1                  ; max y1
    cmp wg_t2
    lda wg_by1+1
    sbc wg_t2+1
    bcs @ny1
    lda wg_t2
    sta wg_by1
    lda wg_t2+1
    sta wg_by1+1
@ny1
    inc wg_i
    jmp @bb                     ; the body is over a page: far loop-back
@bbdone

    lda wg_bx0
    sta X16_P0
    lda wg_bx0+1
    sta X16_P1
    lda wg_by0
    sta X16_P2
    lda wg_by0+1
    sta X16_P3
    lda wg_bx1
    sta X16_P4
    lda wg_bx1+1
    sta X16_P5
    lda wg_by1
    sta X16_P6
    lda wg_by1+1
    sta X16_P7
    lda #<wg_vec
    ldx #>wg_vec
    jmp rg_push

; ---------------------------------------------------------------------
; wg_draw -- the ABI redraw entry.
; ---------------------------------------------------------------------
wg_draw
    jmp wg_draw_all

wg_draw_all
    stz wg_hover_on             ; recomputed here: is any WG_HIT asking for
    stz wg_i                    ; hover? If not, the MOVE path skips its walk.
@loop
    lda wg_i
    cmp wg_n
    bcs @done
    jsr wg_rec
    ldy #WG_TYPE
    lda (CX_M_PTR),y
    cmp #WG_HIT
    bne @paint
    ldy #WG_GRP
    lda (CX_M_PTR),y
    and #WH_HOVER
    beq @paint
    sta wg_hover_on            ; a hit region wants hover: arm the flag
@paint
    jsr wg_paint
    inc wg_i
    bra @loop
@done
    rts

; ---------------------------------------------------------------------
; wg_rec -- CX_M_PTR = record wg_i: list + 1 + i*16. The offset is 16-bit
; (i*16 passes 255 at i=16), so a list may hold more than fifteen widgets
; -- the icon desktop lays out dozens. For i < 16 the high byte stays 0,
; so this is bit-identical to the old byte math for every existing caller.
; ---------------------------------------------------------------------
wg_rec
    lda wg_i
    sta CX_M_PTR
    stz CX_M_PTR+1
    asl CX_M_PTR                ; i*16, sixteen bits
    rol CX_M_PTR+1
    asl CX_M_PTR
    rol CX_M_PTR+1
    asl CX_M_PTR
    rol CX_M_PTR+1
    asl CX_M_PTR
    rol CX_M_PTR+1
    sec                         ; + wg_list + 1 (the count byte)
    lda CX_M_PTR
    adc wg_list
    sta CX_M_PTR
    lda CX_M_PTR+1
    adc wg_list+1
    sta CX_M_PTR+1
    rts

; ---------------------------------------------------------------------
; wg_x1y1 -- from the record at CX_M_PTR: wg_t = x + w - 1, wg_t2 = y +
; h - 1. The inclusive far corner, for the bounding box and hit test.
; ---------------------------------------------------------------------
wg_x1y1
    clc
    ldy #WG_X
    lda (CX_M_PTR),y
    ldy #WG_W
    adc (CX_M_PTR),y
    sta wg_t
    ldy #WG_X+1
    lda (CX_M_PTR),y
    ldy #WG_W+1
    adc (CX_M_PTR),y
    sta wg_t+1
    lda wg_t                    ; -1
    bne @xnz
    dec wg_t+1
@xnz
    dec wg_t
    clc
    ldy #WG_Y
    lda (CX_M_PTR),y
    ldy #WG_H
    adc (CX_M_PTR),y
    sta wg_t2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta wg_t2+1
    lda wg_t2
    bne @ynz
    dec wg_t2+1
@ynz
    dec wg_t2
    rts

; wg_is_text -- Z set if the canvas is a text/CELL grid: mode 3, OR mode 2
; while the tile-text overlay (cx_txtport) owns the port. On a cell canvas
; the toolkit draws ASCII-classic widgets ([X] (o) [ok]), not scaled pixel
; boxes -- WG_BOX and the pixel offsets are meaningless on a cell grid.
wg_is_text
    lda cx_vmode
    cmp #CX_MODE_TEXT
    beq @yes
    cmp #2                     ; CX_MODE_TILE with the tile-text overlay up
    bne @no
    lda cx_txtport
    beq @no
@yes
    lda #0                     ; Z set = a cell canvas
    rts
@no
    lda #1                     ; Z clear = a pixel canvas
    rts

; =====================================================================
; painting -- one widget, from its record at CX_M_PTR
; =====================================================================
wg_paint
    jsr wg_is_text             ; a cell canvas gets ASCII-classic widgets,
    bne @gfx                   ; not scaled pixel boxes
    jmp wg_paint_t             ; the text painter shares bank 16 now --
                               ; a plain tail-call, no trampoline
@gfx
    ldy #WG_TYPE
    lda (CX_M_PTR),y
    cmp #WG_HIT                 ; a hit region is invisible: the app owns the
    beq wg_nopaint             ; pixels, the toolkit only routes the mouse
    cmp #WG_BUTTON              ; the painters are pages apart: jmp, not
    bne @nb                     ; branch, to reach them
    jmp wg_p_button
@nb
    cmp #WG_SCROLL
    bne @ns
    jmp wg_p_scroll
@ns
    cmp #WG_FIELD
    bne @nf
    jmp wg_p_field
@nf
    cmp #WG_LIST
    bne @nt
    jmp wg_p_list
@nt
    cmp #WG_ICON
    bne @ntog
    jmp wg_p_icon
@ntog
    jmp wg_p_toggle             ; check and radio share a box and a label
wg_nopaint                      ; WG_HIT and any future invisible type
    rts

; a push button: a framed box, its label centred, filled with the
; highlight when pressed (WG_VAL != 0).
wg_p_button
    jsr wg_load_box             ; P0..P7 = x,y,w,h
    ldy #WG_VAL
    lda (CX_M_PTR),y
    beq @paper
    lda th_hi
    bra @fill
@paper
    lda th_paper
@fill
    jsr cxov_rect
    jsr wg_load_box
    lda th_frame
    jsr cxov_frame
    ; the label, roughly centred: x + (w - width)/2, y + (h-8)/2
    jsr wg_label_ptr            ; X16_T0 = label
    lda X16_T0
    ldx X16_T0+1
    jsr cxov_measure            ; P0/P1 = text width
    ldy #WG_W                   ; (w - tw)/2
    lda (CX_M_PTR),y
    sec
    sbc X16_P0
    ldy #WG_W+1
    lda (CX_M_PTR),y
    sbc X16_P1
    ; A:carry now high byte; assume small -- take (w-tw) in wg_t
    sta wg_t+1
    lda (CX_M_PTR),y            ; recompute low cleanly
    ldy #WG_W
    lda (CX_M_PTR),y
    sec
    sbc X16_P0
    sta wg_t
    lsr wg_t+1                  ; /2
    ror wg_t
    clc                         ; + x
    ldy #WG_X
    lda (CX_M_PTR),y
    adc wg_t
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc wg_t+1
    sta X16_P1
    ldy #WG_H                   ; y + (h-8)/2: the glyphs centred top to
    lda (CX_M_PTR),y            ; bottom, not sat near the top
    sec
    sbc #8
    lsr
    sta wg_t
    clc
    ldy #WG_Y
    lda (CX_M_PTR),y
    adc wg_t
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P3
    lda X16_T0
    ldx X16_T0+1
    jmp cxov_text

; an icon tile: the 24x24 icon centred across the top of the cell, the
; caption centred under it. WG_VAL is the icon id, WG_LBL the caption.
; cx_do_icon is resident and mode-aware (mode 0 blits, mode 1 expands),
; so the one painter serves both bitmap desktops; it clobbers P0..P7, so
; the caption geometry is rebuilt from the record afterwards.
WI_SZ    = 24                   ; keep in step with icon.asm's ICON_W/H
wg_p_icon
    ldy #WG_W                   ; icon_x = x + (w - 24)/2
    lda (CX_M_PTR),y
    sec
    sbc #WI_SZ
    sta wg_t
    ldy #WG_W+1
    lda (CX_M_PTR),y
    sbc #0
    sta wg_t+1
    lsr wg_t+1
    ror wg_t
    clc
    ldy #WG_X
    lda (CX_M_PTR),y
    adc wg_t
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc wg_t+1
    sta X16_P1
    ldy #WG_Y                   ; icon_y = cell top
    lda (CX_M_PTR),y
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    sta X16_P3
    ldy #WG_VAL                 ; the icon id
    lda (CX_M_PTR),y
    jsr cx_do_icon              ; resident; leaves P0..P7 spent

    lda th_paper                ; a contrasting caption (mode 1 honours ink)
    jsr wg_ink
    jsr wg_label_ptr            ; X16_T0 = the caption
    lda X16_T0
    ldx X16_T0+1
    jsr cxov_measure            ; P0/P1 = its width
    ldy #WG_W                   ; label_x = x + (w - tw)/2
    lda (CX_M_PTR),y
    sec
    sbc X16_P0
    sta wg_t
    ldy #WG_W+1
    lda (CX_M_PTR),y
    sbc X16_P1
    sta wg_t+1
    lsr wg_t+1
    ror wg_t
    clc
    ldy #WG_X
    lda (CX_M_PTR),y
    adc wg_t
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc wg_t+1
    sta X16_P1
    clc                         ; label_y = cell top + icon + 2
    ldy #WG_Y
    lda (CX_M_PTR),y
    adc #(WI_SZ + 2)
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P3
    lda X16_T0
    ldx X16_T0+1
    jmp cxov_text

; a checkbox / radio: a small marker box on the left, then the label.
; checked = the box filled with the frame colour.
wg_p_toggle
    ldy #WG_X                   ; the marker box: x, y, WG_BOX square
    lda (CX_M_PTR),y
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    sta X16_P1
    ldy #WG_Y
    lda (CX_M_PTR),y
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    sta X16_P3
    lda #WG_BOX
    sta X16_P4
    stz X16_P5
    lda #WG_BOX
    sta X16_P6
    stz X16_P7
    lda th_paper                ; clear it
    jsr cxov_rect
    jsr wg_toggle_box
    lda th_frame
    jsr cxov_frame
    ldy #WG_VAL                 ; checked: an inner filled square
    lda (CX_M_PTR),y
    beq @label
    ldy #WG_X
    lda (CX_M_PTR),y
    clc
    adc #3
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P1
    ldy #WG_Y
    lda (CX_M_PTR),y
    clc
    adc #3
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P3
    lda #WG_BOX-6
    sta X16_P4
    stz X16_P5
    lda #WG_BOX-6
    sta X16_P6
    stz X16_P7
    lda th_frame
    jsr cxov_rect
@label
    ldy #WG_X                   ; the label, WG_BOX+6 to the right
    lda (CX_M_PTR),y
    clc
    adc #WG_BOX+6
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P1
    ldy #WG_Y
    lda (CX_M_PTR),y
    clc
    adc #2
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P3
    jsr wg_label_ptr
    lda X16_T0
    ldx X16_T0+1
    jmp cxov_text

; a horizontal scrollbar: a framed trough, and a thumb whose left edge
; is val/max across the inner width. A short fixed thumb width.
WG_THUMB = 16
wg_p_scroll
    jsr wg_load_box             ; the trough
    lda th_paper
    jsr cxov_rect
    jsr wg_load_box
    lda th_frame
    jsr cxov_frame
    lda wg_drag                 ; while this bar is dragged the thumb
    cmp wg_i                    ; tracks the mouse pixel by pixel (the
    bne @snapped                ; live offset), snapping to the value only
    clc                         ; when the drag ends
    ldy #WG_X
    lda (CX_M_PTR),y
    adc #2
    adc wg_dragpx
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc #0
    adc wg_dragpx+1
    sta X16_P1
    bra @thumb
@snapped
    jsr wg_thumb_x              ; X16_P0/P1 = the thumb's left
@thumb
    ldy #WG_Y
    lda (CX_M_PTR),y
    clc
    adc #2
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P3
    lda #WG_THUMB
    sta X16_P4
    stz X16_P5
    ldy #WG_H
    lda (CX_M_PTR),y
    sec
    sbc #4
    sta X16_P6
    stz X16_P7
    lda th_hi
    jsr cxov_rect
    rts

; a text field: a framed box, the buffer's text inside, and -- when the
; field is the focused widget -- a caret bar just after the text.
wg_p_field
    jsr wg_load_box
    lda th_paper
    jsr cxov_rect
    jsr wg_load_box
    lda th_frame
    jsr cxov_frame

    clc                         ; the text pen: x+4, y centred
    ldy #WG_X
    lda (CX_M_PTR),y
    adc #4
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P1
    ldy #WG_H                   ; centre the 8px glyphs: y + (h-8)/2
    lda (CX_M_PTR),y
    sec
    sbc #8
    lsr
    sta wg_ch                   ; scratch: the vertical inset
    clc
    ldy #WG_Y
    lda (CX_M_PTR),y
    adc wg_ch
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P3
    lda th_paper                ; ink contrasts the field's paper, or the
    jsr wg_ink                  ; text is black-on-black where the font
                                ; honours the ink (mode 1); mode 0 ignores it.
                                ; wg_ink is the toolkit's own copy of mn_ink
                                ; -- same bank now that menu stayed in 2
    jsr wg_label_ptr            ; X16_T0 = the buffer
    lda X16_T0
    ldx X16_T0+1
    jsr cxov_text               ; hands back the pen past the text in P0/P1

    lda wg_focus                ; a caret only while this field has focus
    cmp wg_i
    bne @done
    ; P0/P1 is the pen after the text; a 2px block caret there
    ldy #WG_Y                   ; y = field y + 2
    lda (CX_M_PTR),y
    clc
    adc #2
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P3
    lda #2                      ; 2px wide so it reads as a cursor
    sta X16_P4
    stz X16_P5
    ldy #WG_H                   ; h - 4 tall
    lda (CX_M_PTR),y
    sec
    sbc #4
    sta X16_P6
    stz X16_P7
    lda th_frame
    jsr cxov_rect
@done
    rts

; ---------------------------------------------------------------------
; wg_field_key -- A = key, CX_M_PTR = the focused text field. A
; printable key appends to the buffer (up to WG_GRP), backspace trims,
; RETURN submits (posts EV_WIDGET with the length). Carry set if the
; key was the field's.
; ---------------------------------------------------------------------
wg_field_key
    cmp #WK_ENTER
    beq @submit
    cmp #$14                    ; DEL (CBM) trims the last char
    beq @bs
    cmp #$08                    ; ...and plain backspace too
    beq @bs
    cmp #$20                    ; printable $20..$7E types
    bcc @nope
    cmp #$7F
    bcs @nope

    sta wg_ch
    ldy #WG_VAL                 ; room? length < capacity
    lda (CX_M_PTR),y
    ldy #WG_GRP
    cmp (CX_M_PTR),y
    bcs @full                   ; no room: swallow the key, do nothing

    jsr wg_bufptr              ; X16_T0 = the buffer
    ldy #WG_VAL
    lda (CX_M_PTR),y           ; the length is the insert index
    tay
    lda wg_ch
    sta (X16_T0),y             ; buffer[len] = char
    iny
    lda #0
    sta (X16_T0),y             ; buffer[len+1] = 0
    ldy #WG_VAL
    lda (CX_M_PTR),y
    clc
    adc #1
    sta (CX_M_PTR),y           ; length++
    jmp @redraw
@bs
    ldy #WG_VAL
    lda (CX_M_PTR),y
    beq @full                  ; empty: nothing to trim, but ours
    sec
    sbc #1
    sta (CX_M_PTR),y           ; length--
    jsr wg_bufptr              ; FIRST -- it uses Y, so the new length
    ldy #WG_VAL                ; must be reloaded into Y after it, or the
    lda (CX_M_PTR),y           ; NUL lands at WG_LBL+1 and the text on
    tay                        ; screen never shortens (the owner's bug)
    lda #0
    sta (X16_T0),y             ; buffer[len] = 0
@redraw
    jsr wg_paint
    jsr wg_refocus_frame
@full
    sec
    rts
@submit
    ldy #WG_VAL
    lda (CX_M_PTR),y           ; report the length as the value
    jsr wg_post_val
    sec
    rts
@nope
    clc
    rts

; wg_bufptr -- X16_T0 = the field's WG_LBL buffer pointer.
wg_bufptr
    ldy #WG_LBL
    lda (CX_M_PTR),y
    sta X16_T0
    ldy #WG_LBL+1
    lda (CX_M_PTR),y
    sta X16_T0+1
    rts

; ---------------------------------------------------------------------
; wg_p_list -- a scrolling list. Adjusts WG_TOP to keep the selected
; row (WG_VAL) inside the box, then draws each visible row's string,
; the selected one on the highlight. WG_LBL is an array of string
; pointers; WG_GRP the count.
; ---------------------------------------------------------------------
wg_p_list
    jsr wg_load_box
    lda th_paper
    jsr cxov_rect
    jsr wg_load_box
    lda th_frame
    jsr cxov_frame

    jsr wg_list_maxrows         ; wg_maxrows = (h-2)/ROWH

    ldy #WG_VAL                 ; keep the selection visible: if it sits
    lda (CX_M_PTR),y            ; above the top, the top becomes it
    ldy #WG_TOP
    cmp (CX_M_PTR),y
    bcs @below
    ldy #WG_VAL
    lda (CX_M_PTR),y
    ldy #WG_TOP
    sta (CX_M_PTR),y
    bra @topok
@below                          ; ...below the last visible row: scroll
    ldy #WG_TOP                 ; so it is the last row
    lda (CX_M_PTR),y
    clc
    adc wg_maxrows
    sta wg_t                    ; top + maxrows
    ldy #WG_VAL
    lda (CX_M_PTR),y
    cmp wg_t
    bcc @topok
    sec                         ; top = sel - maxrows + 1
    sbc wg_maxrows
    clc
    adc #1
    ldy #WG_TOP
    sta (CX_M_PTR),y
@topok

    stz wg_row
@rows
    lda wg_row
    cmp wg_maxrows
    bcc @rowok                  ; the body is long: branch in, jmp out
    jmp @done
@rowok
    ldy #WG_TOP                 ; item = top + row
    lda (CX_M_PTR),y
    clc
    adc wg_row
    sta wg_idx
    ldy #WG_GRP
    cmp (CX_M_PTR),y
    bcc @itemok
    jmp @done                   ; past the last item
@itemok

    ; row band, x0+1 wide by ROWH; highlighted if item == selected
    clc
    ldy #WG_X
    lda (CX_M_PTR),y
    adc #1
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P1
    jsr wg_row_y                ; X16_P2/P3 = box_y + 1 + row*ROWH
    sec
    ldy #WG_W
    lda (CX_M_PTR),y
    sbc #2
    sta X16_P4
    ldy #WG_W+1
    lda (CX_M_PTR),y
    sbc #0
    sta X16_P5
    lda #WL_ROWH
    sta X16_P6
    stz X16_P7
    ldy #WG_VAL
    lda wg_idx
    cmp (CX_M_PTR),y
    bne @plain
    lda th_hi
    bra @band
@plain
    lda th_paper
@band
    pha                         ; remember this row's band colour
    jsr cxov_rect

    ; the item's string at x0+4, row_y+1
    ldy #WG_LBL                 ; reload the array pointer: gfx2_rect above
    lda (CX_M_PTR),y            ; is a library call and T-registers do not
    sta X16_T2                  ; survive one (this is what drew garbage)
    ldy #WG_LBL+1
    lda (CX_M_PTR),y
    sta X16_T2+1
    lda wg_idx                  ; X16_T0 = array[item]
    asl
    tay
    lda (X16_T2),y
    sta X16_T0
    iny
    lda (X16_T2),y
    sta X16_T0+1
    clc
    ldy #WG_X
    lda (CX_M_PTR),y
    adc #4
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P1
    jsr wg_row_y
    inc X16_P2                  ; +1 into the band
    bne @yok
    inc X16_P3
@yok
    pla                         ; ink contrasts the band: the selected row
    jsr wg_ink                  ; draws reverse video where the font honours
    lda X16_T0                  ; the ink (mode 1/3); mode 0 ignores it.
    ldx X16_T0+1                ; wg_ink is the toolkit's same-bank copy of
    jsr cxov_text              ; mn_ink -- calling mn_ink from bank 16 would
                               ; jump into bank-2 territory and draw garbage

    inc wg_row
    jmp @rows                   ; the body is over a page
@done
    rts

; wg_row_y -- X16_P2/P3 = box_y + 1 + wg_row * WL_ROWH (16-bit).
wg_row_y
    lda wg_row                  ; row * 10 = row*8 + row*2
    asl
    sta wg_t                    ; row*2
    lda wg_row
    asl
    asl
    asl                         ; row*8
    clc
    adc wg_t                    ; row*10
    ldy #WG_Y
    adc (CX_M_PTR),y
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P3
    inc X16_P2                  ; +1 inside the frame
    bne @ok
    inc X16_P3
@ok
    rts

; wg_list_maxrows -- wg_maxrows = (WG_H - 2) / WL_ROWH.
wg_list_maxrows
    ldy #WG_H
    lda (CX_M_PTR),y
    sec
    sbc #2
    ldx #0
@d
    cmp #WL_ROWH
    bcc @done
    sbc #WL_ROWH
    inx
    bra @d
@done
    stx wg_maxrows
    rts

; ---------------------------------------------------------------------
; wg_list_key -- A = key, CX_M_PTR = the focused list. UP/DOWN move the
; selection (clamped), RETURN/SPACE post EV_WIDGET with it. Carry set
; if it was the list's key.
; ---------------------------------------------------------------------
wg_list_key
    cmp #WK_UP
    beq @up
    cmp #WK_DOWN
    beq @down
    cmp #WK_ENTER
    beq @enter
    cmp #WK_SPACE
    beq @enter
    clc
    rts
@up
    ldy #WG_VAL
    lda (CX_M_PTR),y
    beq @redraw                 ; already the top item
    sec
    sbc #1
    sta (CX_M_PTR),y
    bra @redraw
@down
    ldy #WG_VAL
    lda (CX_M_PTR),y
    clc
    adc #1
    ldy #WG_GRP
    cmp (CX_M_PTR),y
    bcs @redraw                 ; sel+1 past the end: stay
    ldy #WG_VAL
    sta (CX_M_PTR),y
@redraw
    jsr wg_paint                ; wg_p_list re-scrolls to keep it visible
    jsr wg_refocus_frame
    sec
    rts
@enter
    ldy #WG_VAL
    lda (CX_M_PTR),y
    jsr wg_post_val
    sec
    rts

; ---------------------------------------------------------------------
; wg_thumb_x -- X16_P0/P1 = the scrollbar thumb's left x:
;   x + 2 + (val * (innerw - thumb)) / max
; innerw = w - 4. Kept 8-bit where it can be: val and max are bytes.
; ---------------------------------------------------------------------
wg_thumb_x
    ldy #WG_W                   ; innerw - thumb = w - 4 - THUMB
    lda (CX_M_PTR),y
    sec
    sbc #(4 + WG_THUMB)
    sta wg_t
    ldy #WG_W+1
    lda (CX_M_PTR),y
    sbc #0
    sta wg_t+1                  ; span in wg_t (16-bit)

    ldy #WG_VAL                 ; val * span, 8x16 -> keep 16
    lda (CX_M_PTR),y
    sta wg_mul
    stz wg_res
    stz wg_res+1
    ldx #8
@m
    lsr wg_mul
    bcc @m2
    clc
    lda wg_res
    adc wg_t
    sta wg_res
    lda wg_res+1
    adc wg_t+1
    sta wg_res+1
@m2
    asl wg_t
    rol wg_t+1
    dex
    bne @m
    ; divide by max (WG_GRP), a byte, via repeated subtract on the high
    ; part -- max <= 255 and the product <= span*255, so do a simple
    ; 16/8 restoring divide
    ldy #WG_GRP
    lda (CX_M_PTR),y
    sta wg_div
    beq @zero                   ; max 0: pin the thumb left
    jsr wg_div16
    ; wg_res = quotient
    clc
    ldy #WG_X
    lda (CX_M_PTR),y
    adc #2
    adc wg_res
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc #0
    adc wg_res+1
    sta X16_P1
    rts
@zero
    ldy #WG_X
    lda (CX_M_PTR),y
    clc
    adc #2
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P1
    rts

; wg_div16 -- wg_res (16) / wg_div (8) -> wg_res, remainder discarded.
wg_div16
    lda #0
    sta wg_rem
    ldx #16
@d
    asl wg_res
    rol wg_res+1
    rol wg_rem                  ; the new partial remainder can be 9 bits:
    lda wg_rem                  ; rem<256 always, but (rem<<1)|bit reaches ~459,
    bcs @sub                    ; so a carry out of rol means rem >= 256 > div --
    cmp wg_div                  ; subtract unconditionally. Dropping this carry
    bcc @d2                     ; lost quotient bits whenever rem crossed 256
@sub                            ; (e.g. 2300/230 came out 1 instead of 10).
    sbc wg_div
    sta wg_rem
    inc wg_res
@d2
    dex
    bne @d
    rts

; ---------------------------------------------------------------------
; helpers to load a record's box into the parameter block
; ---------------------------------------------------------------------
wg_load_box                     ; P0..P7 = x, y, w, h (h high byte 0)
    ldy #WG_X
    lda (CX_M_PTR),y
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    sta X16_P1
    ldy #WG_Y
    lda (CX_M_PTR),y
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    sta X16_P3
    ldy #WG_W
    lda (CX_M_PTR),y
    sta X16_P4
    ldy #WG_W+1
    lda (CX_M_PTR),y
    sta X16_P5
    ldy #WG_H
    lda (CX_M_PTR),y
    sta X16_P6
    stz X16_P7
    rts

wg_toggle_box                   ; P0..P7 = the WG_BOX marker square
    ldy #WG_X
    lda (CX_M_PTR),y
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    sta X16_P1
    ldy #WG_Y
    lda (CX_M_PTR),y
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    sta X16_P3
    lda #WG_BOX
    sta X16_P4
    stz X16_P5
    lda #WG_BOX
    sta X16_P6
    stz X16_P7
    rts

; =====================================================================
; wg_paint_t -- the widget in ASCII, for a cell canvas. Reads the record
; and draws a line at its (x, y):  button [label]   check [X]/[ ] label
; radio (*)/( ) label   field [text]   scroll label   list its rows.
; The record's x/y/w/h are cells (the app authors them so), and wg_hit
; tests that same box, so clicks land without any of the pixel geometry.
;
; It shares bank 16 with the rest of the toolkit, so wg_paint reaches it
; with a plain jmp. Everything it touches is reachable from there: the
; record through CX_M_PTR (low RAM), cxov_text and the theme through
; resident addresses, and its strings and locals travel with it.
; (It rode bank 5 while widgets filled bank 2; the restructure gave the
; toolkit its own bank and the far-call became a tail jmp.)
; =====================================================================
.ifndef CX_NO_OVERLAY
.segment "B16CODE"              ; bank 16 with the toolkit; the flat runner
.else                           ; (mode 0 only) never calls it -- park it
.segment "CODE"                 ; in CODE so it just links
.endif

wg_ink                          ; A = the paper -> cxov_ink contrasts (a
    cmp th_hi                   ; local copy of mn_ink; that one is bank 2)
    bne @onpaper
    lda th_paper
    sta cxov_ink
    rts
@onpaper
    lda th_hi
    sta cxov_ink
    rts

wg_paint_t
    lda th_paper                ; light-on-paper text, like the menu items
    jsr wg_ink
    ldy #WG_LBL                 ; PRE-READ the record: the KERNAL screen
    lda (CX_M_PTR),y            ; routines clobber CX_M_PTR ($44/$45), so
    sta wg_lblv                 ; nothing may re-read it once cxov_text runs
    ldy #WG_LBL+1
    lda (CX_M_PTR),y
    sta wg_lblv+1
    ldy #WG_VAL
    lda (CX_M_PTR),y
    sta wg_valv
    ldy #WG_X
    lda (CX_M_PTR),y
    sta wg_xv
    ldy #WG_X+1
    lda (CX_M_PTR),y
    sta wg_xv+1
    ldy #WG_Y
    lda (CX_M_PTR),y
    sta wg_yv
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    sta wg_yv+1
    ldy #WG_GRP
    lda (CX_M_PTR),y
    sta wg_cntv
    ldy #WG_W
    lda (CX_M_PTR),y
    sta wg_wv
    ldy #WG_TYPE
    lda (CX_M_PTR),y
    sta wg_typv

    cmp #WG_HIT                 ; a hit region is invisible in every mode
    bne @shown
    rts
@shown
    jsr wg_t_pos                ; P0/P1 = x, P2/P3 = y
    lda wg_typv
    cmp #WG_CHECK
    beq wg_t_toggle
    cmp #WG_RADIO
    beq wg_t_toggle
    cmp #WG_FIELD
    beq wg_t_field
    cmp #WG_LIST
    bne @nlist                 ; (wg_t_list outgrew a short branch)
    jmp wg_t_list
@nlist
    cmp #WG_SCROLL
    bne @button
    jmp wg_t_scroll             ; a slider: [###----] bar
@button
    ; BUTTON: [ label ]
    lda #<wg_s_lbrk
    ldx #>wg_s_lbrk
    jsr cxov_text
    jsr wg_t_label
    lda #<wg_s_rbrk
    ldx #>wg_s_rbrk
    jmp cxov_text

wg_t_toggle                     ; check/radio: the marker, then the label
    ldx wg_valv
    lda wg_typv
    cmp #WG_RADIO
    beq @rad
    cpx #0
    beq @coff
    lda #<wg_s_con
    ldx #>wg_s_con
    bra @mk
@coff
    lda #<wg_s_coff
    ldx #>wg_s_coff
    bra @mk
@rad
    cpx #0
    beq @roff
    lda #<wg_s_ron
    ldx #>wg_s_ron
    bra @mk
@roff
    lda #<wg_s_roff
    ldx #>wg_s_roff
@mk
    jsr cxov_text               ; the 4-cell marker; the pen advances
    jmp wg_t_label

wg_t_field                      ; [ text ]
    ; clear the field's w cells to paper first, so a shorter buffer (after
    ; a backspace) leaves no ghost of the old bracket/char. The padding is
    ; the panel's paper, so the field still reads as "[ text ]".
    lda wg_xv
    sta X16_P0
    lda wg_xv+1
    sta X16_P1
    lda wg_yv
    sta X16_P2
    lda wg_yv+1
    sta X16_P3
    lda wg_wv
    sta X16_P4
    stz X16_P5
    lda #1
    sta X16_P6
    stz X16_P7
    lda th_paper
    jsr cxov_rect
    jsr wg_t_pos                ; P0/P1 = x, P2/P3 = y -- the pen back
    lda #<wg_s_lbrk
    ldx #>wg_s_lbrk
    jsr cxov_text
    jsr wg_t_label
    lda #<wg_s_rbrk
    ldx #>wg_s_rbrk
    jmp cxov_text

; the list: each row's label down the column, the selected one reversed.
; wg_lblv is the array base; every field is already in a bank-2 local.
wg_t_list
    stz wg_rowv
@row
    lda wg_rowv
    cmp wg_cntv
    bcs @done
    lda wg_xv                   ; fill the row: full width, one cell tall,
    sta X16_P0                  ; in its background colour. This also sets
    lda wg_xv+1                 ; the engine's paper (t_bg), so the label
    sta X16_P1                  ; that lands on the selected row draws in
    clc                         ; reverse video -- a proper selection bar
    lda wg_yv                   ; rather than a dark smudge on the paper.
    adc wg_rowv
    sta X16_P2
    lda wg_yv+1
    adc #0
    sta X16_P3
    lda wg_wv
    sta X16_P4
    stz X16_P5
    lda #1
    sta X16_P6
    stz X16_P7
    lda wg_rowv                 ; the selected row's bar is the highlight
    cmp wg_valv
    bne @plainbg
    lda th_hi
    bra @dofill
@plainbg
    lda th_paper
@dofill
    pha
    jsr cxov_rect
    pla
    jsr wg_ink                  ; contrasting ink for this row's paper
    lda wg_xv                   ; re-establish the pen (cxov_rect used P0-P7)
    sta X16_P0
    lda wg_xv+1
    sta X16_P1
    clc
    lda wg_yv
    adc wg_rowv
    sta X16_P2
    lda wg_yv+1
    adc #0
    sta X16_P3
    lda wg_rowv                 ; label = array[row]: reload the zp ptr,
    asl                         ; read the element, THEN draw (cxov_text
    clc                         ; may clobber the ptr, not the element)
    adc wg_lblv
    sta X16_TPTR0
    lda wg_lblv+1
    adc #0
    sta X16_TPTR0+1
    ldy #0
    lda (X16_TPTR0),y
    pha
    iny
    lda (X16_TPTR0),y
    tax
    pla
    jsr cxov_text
    inc wg_rowv
    jmp @row
@done
    rts

; a slider: "[" + a filled/empty track + "]", filled = val*inner/max.
; inner = W-2 track cells; each drawn as a single glyph so the pen walks.
wg_t_scroll
    lda #<wg_s_lbrk
    ldx #>wg_s_lbrk
    jsr cxov_text
    lda wg_wv                   ; inner track width (guard tiny widgets)
    sec
    sbc #2
    bcs @haveinner
    lda #1
@haveinner
    sta wg_inner
    stz wg_prod                 ; prod = val * inner
    stz wg_prod+1
    ldx wg_valv
    beq @divd
@mul
    clc
    lda wg_prod
    adc wg_inner
    sta wg_prod
    bcc @mnc
    inc wg_prod+1
@mnc
    dex
    bne @mul
@divd
    ldx #0                      ; filled = prod / max (repeated subtraction)
    lda wg_cntv
    beq @qdone                  ; max 0 -> nothing filled
@dloop
    lda wg_prod+1
    bne @sub
    lda wg_prod
    cmp wg_cntv
    bcc @qdone
@sub
    sec
    lda wg_prod
    sbc wg_cntv
    sta wg_prod
    lda wg_prod+1
    sbc #0
    sta wg_prod+1
    inx
    bra @dloop
@qdone
    stx wg_filled
    stz wg_barx                 ; walk the inner cells
@cell
    lda wg_barx
    cmp wg_inner
    bcs @endbar
    cmp wg_filled
    bcc @on
    lda #<wg_s_dot
    ldx #>wg_s_dot
    bra @put
@on
    lda #<wg_s_fill
    ldx #>wg_s_fill
@put
    jsr cxov_text
    inc wg_barx
    bra @cell
@endbar
    lda #<wg_s_rbrk
    ldx #>wg_s_rbrk
    jmp cxov_text

wg_t_pos                        ; P0/P1 = x, P2/P3 = y (from the locals)
    lda wg_xv
    sta X16_P0
    lda wg_xv+1
    sta X16_P1
    lda wg_yv
    sta X16_P2
    lda wg_yv+1
    sta X16_P3
    rts

wg_t_label                      ; the saved label ptr, at the pen
    lda wg_lblv
    ldx wg_lblv+1
    jmp cxov_text

wg_s_lbrk .byte "[", 0
wg_s_rbrk .byte "]", 0
wg_s_con  .byte "[X] ", 0
wg_s_coff .byte "[ ] ", 0
wg_s_ron  .byte "(*) ", 0
wg_s_roff .byte "( ) ", 0
wg_s_fill .byte "#", 0
wg_s_dot  .byte "-", 0
wg_lblv .word 0
wg_valv .byte 0
wg_typv .byte 0
wg_cntv .byte 0
wg_rowv .byte 0
wg_xv   .word 0
wg_yv   .word 0
wg_wv     .byte 0
wg_inner  .byte 0
wg_filled .byte 0
wg_barx   .byte 0
wg_prod   .word 0

; WG_HIT scratch + state
wh_t      .byte 0               ; a semi-axis / a wanted trigger bit
wh_cx     .word 0               ; a shape centre (x or y)
wh_d      .word 0               ; a signed delta / a saved index / a phase
wh_acc    .word 0               ; nx^2 + ny^2
wg_hover  .byte $FF             ; the WG_HIT index the pointer is over ($FF none)
wg_hover_on .byte 0             ; any WG_HIT wants hover? (else MOVE skips the walk)

.segment "B16CODE"

wg_label_ptr                    ; X16_T0 = the record's label pointer
    ldy #WG_LBL
    lda (CX_M_PTR),y
    sta X16_T0
    ldy #WG_LBL+1
    lda (CX_M_PTR),y
    sta X16_T0+1
    rts

; =====================================================================
; hitting -- wg_vec's handler. A DOWN inside a widget acts on it.
; =====================================================================
wg_hit
    lda X16_P0
    cmp #EV_MOUSE_DOWN
    beq @press
    cmp #EV_DBLCLICK            ; a double-click hits too: a list row
    beq @press                  ; selects on DOWN but acts on DBL
    cmp #EV_MOUSE_MOVE          ; a move drags a held scrollbar thumb
    beq @drag
    cmp #EV_MOUSE_UP            ; ...until the button lets go
    beq @release
    rts
@release
    lda wg_drag                 ; finishing a scrollbar drag?
    bmi @rel_hit                ; no: it may be a WG_HIT release
    sta wg_i
    jsr wg_rec
    lda #$FF                    ; clear first, so the repaint snaps the
    sta wg_drag                 ; thumb to the (quantised) value
    jmp wg_paint
@rel_hit
    jsr wg_locate               ; a hit region under the point that wants UP?
    bcc @none
    lda #WH_RELEASE
    ldx #EV_MOUSE_UP
    jmp wg_hit_fire
@drag
    lda wg_drag                 ; a scrollbar being dragged? (else $FF)
    bmi @hover
    sta wg_i
    jsr wg_rec
    jsr wg_scroll_to           ; the thumb follows the mouse x, clamped
    jmp wg_post_val            ; A = value; EV_WIDGET(index, value)
@hover
    jmp wg_hit_hover           ; MOVE with no drag: WG_HIT enter/leave
@press
    sta wg_evt                  ; which press this was, for wg_act
    lda #$FF                    ; a fresh press ends any stale drag (an UP
    sta wg_drag                 ; released outside the region is not seen)
    jsr wg_locate               ; the top widget whose box (+ shape) holds it
    bcc @none
    ldy #WG_TYPE               ; a press on a scrollbar begins a drag:
    lda (CX_M_PTR),y           ; the thumb tracks the mouse until UP
    cmp #WG_SCROLL
    bne @act
    lda wg_i
    sta wg_drag
@act
    jmp wg_act
@none
    rts

; wg_locate -- find the top widget under the event point (P2/P3 x, P4/P5 y):
; carry set with wg_i = its index and CX_M_PTR = its record, else carry clear.
; A disabled widget is skipped; a WG_HIT is refined from its box to its shape.
wg_locate
    stz wg_i
@lp
    lda wg_i
    cmp wg_n
    bcs @miss
    jsr wg_rec
    ldy #WG_FLAGS
    lda (CX_M_PTR),y
    and #WG_DISABLED
    bne @skip
    jsr wg_inside               ; in the bounding box?
    bcc @skip
    jsr wg_hit_refine           ; and inside the actual shape? (WG_HIT only)
    bcs @hit
@skip
    inc wg_i
    bra @lp
@hit
    sec
    rts
@miss
    clc
    rts

; wg_hit_refine -- carry set (accept) unless CX_M_PTR is a WG_HIT whose shape
; rejects the point. Every non-WG_HIT widget and WH_RECT accept on the box.
wg_hit_refine
    ldy #WG_TYPE
    lda (CX_M_PTR),y
    cmp #WG_HIT
    bne @yes
    ldy #WG_VAL                 ; the shape
    lda (CX_M_PTR),y
    beq @yes                    ; WH_RECT = the box itself
    cmp #WH_POLYGON
    bcs @far                    ; polygon / pie: the bank-19 shape math
    jmp wg_hit_ellipse          ; circle (square box) and ellipse share it
@far
    jmp wg_hit_far              ; carry comes back as the answer
@yes
    sec
    rts

; wg_hit_far -- refine a POLYGON/PIE hit region in bank 19 (shphit.asm),
; where sin8/cos8/atan2 already live. cxb_call restores our bank and the
; carry, so a tail-jmp here reads exactly as if the test returned inline.
.ifndef CX_NO_OVERLAY
wg_hit_far
    jsr cxb_call
    .byte CX_SHPX_BANK
    .addr shp_hit
.else
wg_hit_far                      ; the flat runner links shp_hit alongside
    jmp shp_hit
.endif

; wg_hit_fire -- A = a trigger-mask bit, X = the phase to post. If CX_M_PTR is
; a WG_HIT whose WG_GRP enables that trigger (WG_GRP 0 means click-only), post
; EV_WIDGET(wg_i, phase); otherwise do nothing.
wg_hit_fire
    sta wh_t                    ; the wanted bit
    stx wh_d                    ; the phase
    ldy #WG_TYPE
    lda (CX_M_PTR),y
    cmp #WG_HIT
    bne @no
    ldy #WG_GRP                 ; the trigger mask
    lda (CX_M_PTR),y
    bne @have
    lda #WH_CLICK               ; 0 defaults to click-only
@have
    and wh_t
    beq @no
    lda wh_d                    ; phase -> the posted value
    jmp wg_post_val
@no
    rts

; wg_inside -- carry set if the event point (P2..P5) is in record
; CX_M_PTR's box.
wg_inside
    ldy #WG_X                   ; x >= wx
    lda X16_P2
    cmp (CX_M_PTR),y
    ldy #WG_X+1
    lda X16_P3
    sbc (CX_M_PTR),y
    bcc @no
    jsr wg_x1y1                 ; wg_t = x1, wg_t2 = y1
    lda wg_t                    ; x <= x1
    cmp X16_P2
    lda wg_t+1
    sbc X16_P3
    bcc @no
    ldy #WG_Y                   ; y >= wy
    lda X16_P4
    cmp (CX_M_PTR),y
    ldy #WG_Y+1
    lda X16_P5
    sbc (CX_M_PTR),y
    bcc @no
    lda wg_t2                   ; y <= y1
    cmp X16_P4
    lda wg_t2+1
    sbc X16_P5
    bcc @no
    sec
    rts
@no
    clc
    rts

; =====================================================================
; WG_HIT shape tests + hover -- bank 16, so a hit region costs no
; resident bytes. The event point is P2/P3 (x), P4/P5 (y).
; =====================================================================

; wg_hit_ellipse -- carry set if the point lies in the ellipse inscribed in
; CX_M_PTR's box (a circle is the square-box case). Normalised test:
; nx = |dx|*128/rx, ny = |dy|*128/ry; inside when nx^2 + ny^2 <= 128^2.
wg_hit_ellipse
    jsr wg_ell_x                ; A = nx, or carry clear = outside
    bcc @out
    tax
    jsr wg_mul8                 ; wg_prod = nx*nx
    lda wg_prod
    sta wh_acc
    lda wg_prod+1
    sta wh_acc+1
    jsr wg_ell_y
    bcc @out
    tax
    jsr wg_mul8                 ; wg_prod = ny*ny
    clc
    lda wh_acc
    adc wg_prod
    sta wh_acc
    lda wh_acc+1
    adc wg_prod+1
    sta wh_acc+1
    lda wh_acc+1               ; nx^2 + ny^2 <= 16384 ($4000)?
    cmp #$40
    bcc @in
    bne @out
    lda wh_acc
    beq @in
@out
    clc
    rts
@in
    sec
    rts

; wg_ell_x -- A = |px-cx|*128/rx (0..128), carry set; carry clear if outside
; the x extent. rx = WG_W>>1, cx = WG_X + rx.
wg_ell_x
    ldy #WG_W
    lda (CX_M_PTR),y
    sta wh_t
    ldy #WG_W+1
    lda (CX_M_PTR),y
    lsr
    ror wh_t                    ; wh_t = rx = WG_W>>1
    clc
    ldy #WG_X
    lda (CX_M_PTR),y
    adc wh_t
    sta wh_cx
    ldy #WG_X+1
    lda (CX_M_PTR),y
    adc #0
    sta wh_cx+1                 ; wh_cx = cx = WG_X + rx
    sec
    lda X16_P2
    sbc wh_cx
    sta wh_d
    lda X16_P3
    sbc wh_cx+1
    sta wh_d+1                  ; wh_d = px - cx (signed)
    bpl @abs
    sec
    lda #0
    sbc wh_d
    sta wh_d
    lda #0
    sbc wh_d+1
    sta wh_d+1
@abs
    lda wh_d+1
    bne @out                    ; |dx| > 255 -> outside (rx <= 255)
    lda wh_d
    ldx wh_t
    jmp wg_norm
@out
    clc
    rts

; wg_ell_y -- the y axis. WG_H is a byte, so ry = WG_H>>1.
wg_ell_y
    ldy #WG_H
    lda (CX_M_PTR),y
    lsr
    sta wh_t                    ; wh_t = ry
    clc
    ldy #WG_Y
    lda (CX_M_PTR),y
    adc wh_t
    sta wh_cx
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    adc #0
    sta wh_cx+1                 ; wh_cx = cy = WG_Y + ry
    sec
    lda X16_P4
    sbc wh_cx
    sta wh_d
    lda X16_P5
    sbc wh_cx+1
    sta wh_d+1                  ; wh_d = py - cy
    bpl @abs
    sec
    lda #0
    sbc wh_d
    sta wh_d
    lda #0
    sbc wh_d+1
    sta wh_d+1
@abs
    lda wh_d+1
    bne @out
    lda wh_d
    ldx wh_t
    jmp wg_norm
@out
    clc
    rts

; wg_norm -- A = |d| (byte), X = r (byte) -> A = d*128/r (0..128), carry set;
; carry clear if d > r. r = 0 accepts only d = 0.
wg_norm
    stx wg_div
    cpx #0
    bne @rok
    cmp #0
    beq @zero
    clc
    rts
@rok
    cmp wg_div
    beq @edge
    bcs @out
@edge
    sta wg_res                  ; d*128 = d<<7 (fits 16 bits, d <= 255)
    stz wg_res+1
    ldx #7
@sh
    asl wg_res
    rol wg_res+1
    dex
    bne @sh
    jsr wg_div16                ; wg_res = (d*128) / r
    lda wg_res
    sec
    rts
@zero
    lda #0
    sec
    rts
@out
    clc
    rts

; wg_mul8 -- A * X -> wg_prod (16-bit). Here both are <= 128, so it fits.
wg_mul8
    sta wg_t
    stz wg_t+1
    stz wg_prod
    stz wg_prod+1
    ldy #8
@m
    txa
    lsr
    tax
    bcc @m2
    clc
    lda wg_prod
    adc wg_t
    sta wg_prod
    lda wg_prod+1
    adc wg_t+1
    sta wg_prod+1
@m2
    asl wg_t
    rol wg_t+1
    dey
    bne @m
    rts

; wg_hit_hover -- a MOVE with no drag: post enter/leave as the WG_HIT-hover
; region under the pointer changes. wg_hover is the current one ($FF = none).
; Skipped wholesale when no widget wants hover -- a click-only or non-WG_HIT
; list pays nothing on a mouse move.
wg_hit_hover
    lda wg_hover_on
    bne @scan
    rts                         ; no hover regions: no per-move work at all
@scan
    jsr wg_locate
    bcc @leaveall               ; over nothing
    ldy #WG_TYPE
    lda (CX_M_PTR),y
    cmp #WG_HIT
    bne @leaveall               ; a normal widget is not a hover target
    ldy #WG_GRP
    lda (CX_M_PTR),y
    and #WH_HOVER
    beq @leaveall               ; this region does not want hover
    lda wg_i
    cmp wg_hover
    beq @done                   ; unchanged
    sta wh_d                    ; save the new index across the leave
    jsr wg_hover_leave          ; leave the old (clobbers wg_i)
    lda wh_d
    sta wg_hover
    ldx #EV_MOUSE_MOVE          ; enter -> phase 1
    jsr wg_hover_post
@done
    rts
@leaveall
    jsr wg_hover_leave
    lda #$FF
    sta wg_hover
    rts

; wg_hover_leave -- if the pointer was over a hover region, post (it, 0).
wg_hover_leave
    lda wg_hover
    bmi @x
    ldx #0                      ; leave -> phase 0
    jsr wg_hover_post
@x
    rts

; wg_hover_post -- A = the WG_HIT index, X = the phase. Posts EV_WIDGET.
wg_hover_post
    sta wg_i
    txa
    jmp wg_post_val

; wg_act -- the widget at wg_i / CX_M_PTR was pressed. Update it,
; redraw it, and post EV_WIDGET(index, value).
wg_act
    ldy #WG_TYPE
    lda (CX_M_PTR),y
    cmp #WG_CHECK
    beq @toggle
    cmp #WG_RADIO
    beq @radio
    cmp #WG_SCROLL
    beq @scroll
    cmp #WG_LIST
    beq @list
    cmp #WG_FIELD               ; a click focuses a field so it can be typed
    bne @nfield                 ; the last handlers are pages off: jmp, not beq
    jmp @focusfield
@nfield
    cmp #WG_ICON                ; an icon opens on double, selects on single
    bne @nicon
    jmp @icon
@nicon
    cmp #WG_HIT                 ; a hit region fires its click trigger, no paint
    bne @button
    lda #WH_CLICK
    ldx #EV_MOUSE_DOWN
    jmp wg_hit_fire
@button
    ; button: value 1, momentary; redraw pressed then released
    lda #1
    ldy #WG_VAL
    sta (CX_M_PTR),y
    jsr wg_paint
    lda #0
    ldy #WG_VAL
    sta (CX_M_PTR),y
    jsr wg_paint
    lda #1                      ; report "clicked"
    bra @post
@toggle
    ldy #WG_VAL                 ; flip 0<->1
    lda (CX_M_PTR),y
    eor #1
    sta (CX_M_PTR),y
    jsr wg_paint
    ldy #WG_VAL
    lda (CX_M_PTR),y
    bra @post
@radio
    jsr wg_radio_set            ; light this, darken the group
    lda #1
    bra @post
@scroll
    jsr wg_scroll_to            ; A = the new value
    bra @post

@list
    ; the row under the pointer, then + top. The graphical list frames
    ; the box and stacks WL_ROWH-tall rows inside; mode 3's ASCII list
    ; has no frame and one CELL per row, so there the difference IS the
    ; row. wg_inside proved y is in the box, so it fits the row byte.
    ldy #WG_Y
    lda X16_P4
    sec
    sbc (CX_M_PTR),y            ; d = click_y - box_y
    pha                         ; keep d across the canvas check
    jsr wg_is_text             ; Z set = a cell canvas (the pull below would
    bne @gridrows              ; clobber Z, so branch on it FIRST)
    pla                         ; a cell canvas: d IS the row (1 cell, no frame)
    jmp @haverow
@gridrows
    pla                         ; the pixel offset into the box
    beq @haverow                ; on the frame line: row 0
    sec
    sbc #1
    ldx #0
@div
    cmp #WL_ROWH
    bcc @rowed
    sbc #WL_ROWH
    inx
    bra @div
@rowed
    txa
@haverow
    ldy #WG_TOP
    clc
    adc (CX_M_PTR),y
    ldy #WG_GRP                 ; past the last item: not a row at all
    cmp (CX_M_PTR),y
    bcs @none
    ldy #WG_VAL                 ; a click selects...
    sta (CX_M_PTR),y
    jsr wg_paint
    lda wg_evt                  ; ...and only a double-click acts
    cmp #EV_DBLCLICK
    bne @none
    jsr wg_rec                  ; the record pointer back, defensively
    ldy #WG_VAL
    lda (CX_M_PTR),y
    bra @post
@none
    rts

@focusfield
    lda wg_i                    ; a click gives the field the keyboard
    jmp wg_setfocus

@icon
    lda wg_evt                  ; single click selects, double click opens
    cmp #EV_DBLCLICK
    beq @iconopen
    lda #0
    bra @post
@iconopen
    lda #1
@post
    jmp wg_post_val

; wg_post_val -- A = value; posts EV_WIDGET(detail = wg_i, P2 = value).
; Shared by the click path and the keyboard.
wg_post_val
    sta X16_P2                  ; value in P2
    lda wg_i
    sta X16_P1                  ; index in detail
    lda #EV_WIDGET
    sta X16_P0
    stz X16_P3
    stz X16_P4
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jmp ev_post

; =====================================================================
; keyboard -- wg_key. TAB moves focus (forward, wrapping). Every other
; key acts on the focused widget by its type: a field types, a list
; moves its selection with UP/DOWN, a scrollbar steps with LEFT/RIGHT,
; a button/check/radio activates on SPACE/RETURN. A focus frame
; follows. Carry set if the key was ours.
; =====================================================================
WK_TAB   = $09
WK_BTAB  = $18                  ; Shift+TAB: focus backward
WK_SPACE = $20
WK_ENTER = $0D
WK_DOWN  = $11
WK_UP    = $91
WK_LEFT  = $9D
WK_RIGHT = $1D
WK_STEP  = 1                    ; scrollbar arrows move one step; a click
                                ; jumps anywhere, so fine and coarse both

wg_key
    ldx wg_n
    beq @no                     ; no list: not ours
    cmp #WK_TAB                 ; TAB is focus, whatever has it. NOT
    beq @fwd                    ; DOWN -- that opens the menu bar, which
    cmp #WK_BTAB                ; a list only sees once focused. Shift+TAB
    beq @back                   ; steps focus the other way

    ldx wg_focus
    bmi @no                     ; nothing focused: pass the key
    stx wg_i
    pha                         ; wg_rec and the type load both need A;
    jsr wg_rec                  ; keep the key on the stack across them
    ldy #WG_TYPE
    lda (CX_M_PTR),y
    tax                         ; X = the focused widget's type
    pla                         ; the key back in A
    cpx #WG_LIST
    beq @list
    cpx #WG_FIELD
    beq @field
    cpx #WG_SCROLL
    beq @scroll
    cmp #WK_SPACE               ; button / check / radio
    beq @act
    cmp #WK_ENTER
    beq @act
    bra @no

@list
    jsr wg_list_key             ; UP/DOWN select, RETURN posts
    bcc @no
    bra @yes
@field
    jsr wg_field_key            ; type / trim / submit; carry if taken
    bcc @no
    bra @yes
@scroll
    cmp #WK_LEFT
    beq @sl
    cmp #WK_RIGHT
    beq @sr
    bra @no
@sl
    lda #<($100 - WK_STEP)      ; -WK_STEP as a byte
    jsr wg_scroll_key
    bra @yes
@sr
    lda #WK_STEP
    jsr wg_scroll_key
    bra @yes
@act
    jsr wg_act                  ; the click path: updates + posts
    jsr wg_refocus_frame        ; wg_act repainted the widget plain
    bra @yes

@fwd
    lda #1
    jsr wg_focus_move
    bra @yes
@back
    lda #$FF
    jsr wg_focus_move
@yes
    sec
    rts
@no
    clc
    rts

; wg_scroll_key -- A = signed step. If the focused widget is a
; scrollbar, move its value by the step (clamped 0..max), repaint, and
; post. Carry set if it acted.
wg_scroll_key
    sta wg_step
    lda wg_focus
    bmi @miss
    sta wg_i
    jsr wg_rec
    ldy #WG_TYPE
    lda (CX_M_PTR),y
    cmp #WG_SCROLL
    bne @miss
    ldy #WG_VAL                 ; value + step, signed on a byte
    lda (CX_M_PTR),y
    clc
    adc wg_step
    ldx wg_step
    bmi @dn                     ; stepping down: floor at 0
    ldy #WG_GRP                 ; up: ceil at max
    cmp (CX_M_PTR),y
    bcc @put
    lda (CX_M_PTR),y
    bra @put
@dn
    bcs @put                    ; no borrow: still >= 0
    lda #0
@put
    ldy #WG_VAL
    sta (CX_M_PTR),y
    jsr wg_paint
    jsr wg_refocus_frame
    ldy #WG_VAL
    lda (CX_M_PTR),y
    jsr wg_post_val
    sec
    rts
@miss
    clc
    rts

; wg_focus_move -- A = +1 forward or $FF back. Advances focus to the
; next enabled widget (wrapping) via wg_setfocus, which repaints the old
; widget plain and the new one with its caret and frame. Skips disabled
; widgets; a lap with no landing leaves focus put. wg_cand walks the
; candidates so wg_focus is only committed once, in wg_setfocus.
wg_focus_move
    sta wg_step
    lda wg_focus
    bpl @from
    lda #$FF                    ; none yet: forward starts before 0
@from
    sta wg_cand
    ldx wg_n                    ; try at most n candidates
@try
    lda wg_cand
    clc
    adc wg_step
    cmp wg_n
    bcc @inrange
    lda wg_step                 ; wrapped: back is $FF -> n-1, fwd -> 0
    bmi @wraphi
    lda #0
    bra @inrange
@wraphi
    lda wg_n
    sec
    sbc #1
@inrange
    sta wg_cand
    sta wg_i                    ; is this one enabled?
    jsr wg_rec
    ldy #WG_FLAGS
    lda (CX_M_PTR),y
    and #WG_DISABLED
    beq @landed
    dex
    bne @try
    rts                         ; nowhere enabled: leave focus put
@landed
    lda wg_cand
    ; fall into wg_setfocus

; wg_setfocus -- A = the new focused widget index. Repaints the widget
; that had focus without its caret/frame and the new one with them, so a
; focused field shows a caret and the one left behind loses it. Used by
; TAB and by a click landing on a field. CX_M_PTR ends on the new one.
wg_setfocus
    cmp wg_focus
    beq @same
    ldx wg_focus                ; the old focus (may be $FF)
    sta wg_focus                ; commit the new BEFORE repainting, so the
    txa                         ; old one paints without a caret
    bmi @new
    sta wg_i
    jsr wg_rec
    jsr wg_clr_frame
@new
    lda wg_focus
    sta wg_i
    jsr wg_rec
    jsr wg_paint                ; a field draws its caret here
    jsr wg_draw_frame
@same
    rts

; wg_refocus_frame -- redraw the focus frame on the current wg_i (its
; widget was just repainted plain by an action).
wg_refocus_frame
    lda wg_focus
    bmi @none
    cmp wg_i
    bne @none
    jsr wg_draw_frame
@none
    rts

; wg_draw_frame / wg_clr_frame -- the focus outline, a frame 2px outside
; the widget's box in the highlight colour; clearing repaints the box
; over a paper margin. wg_i / CX_M_PTR must be the widget.
wg_draw_frame
    jsr wg_frame_box
    lda th_hi
    jmp cxov_frame
wg_clr_frame
    jsr wg_frame_box            ; a paper margin, then the widget back
    lda th_paper
    jsr cxov_rect
    jmp wg_paint

; wg_frame_box -- P0..P7 = the widget's box grown 2px each way.
wg_frame_box
    sec
    ldy #WG_X
    lda (CX_M_PTR),y
    sbc #2
    sta X16_P0
    ldy #WG_X+1
    lda (CX_M_PTR),y
    sbc #0
    sta X16_P1
    sec
    ldy #WG_Y
    lda (CX_M_PTR),y
    sbc #2
    sta X16_P2
    ldy #WG_Y+1
    lda (CX_M_PTR),y
    sbc #0
    sta X16_P3
    clc
    ldy #WG_W
    lda (CX_M_PTR),y
    adc #4
    sta X16_P4
    ldy #WG_W+1
    lda (CX_M_PTR),y
    adc #0
    sta X16_P5
    ldy #WG_H
    lda (CX_M_PTR),y
    clc
    adc #4
    sta X16_P6
    stz X16_P7
    rts

; wg_radio_set -- the radio at wg_i wins its group: it goes to 1, every
; other radio sharing its WG_GRP goes to 0, and each changed one is
; repainted. Leaves wg_i / CX_M_PTR on the winner.
wg_radio_set
    ldy #WG_GRP
    lda (CX_M_PTR),y
    sta wg_grp
    lda wg_i
    sta wg_win

    stz wg_i
@scan
    lda wg_i
    cmp wg_n
    bcs @done
    jsr wg_rec
    ldy #WG_TYPE
    lda (CX_M_PTR),y
    cmp #WG_RADIO
    bne @nxt
    ldy #WG_GRP
    lda (CX_M_PTR),y
    cmp wg_grp
    bne @nxt
    lda wg_i                    ; the winner -> 1, else -> 0
    cmp wg_win
    beq @on
    lda #0
    bra @setv
@on
    lda #1
@setv
    ldy #WG_VAL
    sta (CX_M_PTR),y
    jsr wg_paint
@nxt
    inc wg_i
    bra @scan
@done
    lda wg_win                  ; restore wg_i / CX_M_PTR to the winner
    sta wg_i
    jmp wg_rec

; wg_scroll_to -- the click x names a value: (px - x - 2) * max /
; (innerw - thumb), clamped. A = the value, also stored and redrawn.
wg_scroll_to
    sec                         ; px - (x + 2)
    lda X16_P2
    ldy #WG_X
    sbc (CX_M_PTR),y
    sta wg_t
    lda X16_P3
    ldy #WG_X+1
    sbc (CX_M_PTR),y
    sta wg_t+1
    lda wg_t                    ; - 2 more
    sec
    sbc #2
    sta wg_t
    lda wg_t+1
    sbc #0
    sta wg_t+1
    bpl @pos
    stz wg_dragpx               ; left of the trough: thumb hard left,
    stz wg_dragpx+1             ; value 0
    lda #0
    jmp @store
@pos
    ; value = rel * max / span, span = innerw - thumb = w - 4 - THUMB
    ldy #WG_W
    lda (CX_M_PTR),y
    sec
    sbc #(4 + WG_THUMB)
    sta wg_div
    ldy #WG_W+1
    lda (CX_M_PTR),y
    sbc #0
    sta wg_dvh                  ; span high

    lda wg_t+1                  ; the live thumb pixel = rel clamped to span
    cmp wg_dvh
    bcc @relok
    bne @relhi
    lda wg_t
    cmp wg_div
    bcc @relok
@relhi
    lda wg_div
    sta wg_dragpx
    lda wg_dvh
    sta wg_dragpx+1
    bra @reld
@relok
    lda wg_t
    sta wg_dragpx
    lda wg_t+1
    sta wg_dragpx+1
@reld
    lda wg_dvh
    bne @slow                   ; span >= 256: rare; pin to max-ish
    lda wg_div
    beq @max                    ; degenerate span
    ; value = CLAMPED rel * max. Use wg_dragpx (already clamped to span,
    ; so < 256 on this path), NOT wg_t: an over-drag past the right end has
    ; rel > 255, and its low byte alone would wrap the value toward 0 --
    ; the thumb then snapped to the start on release.
    ldy #WG_GRP
    lda (CX_M_PTR),y
    sta wg_mul
    lda wg_dragpx
    sta wg_res
    stz wg_res+1
    ; res = rel * max
    lda #0
    sta wg_acc
    sta wg_acc+1
    ldx #8
@ml
    lsr wg_mul
    bcc @ml2
    clc
    lda wg_acc
    adc wg_res
    sta wg_acc
    lda wg_acc+1
    adc wg_res+1
    sta wg_acc+1
@ml2
    asl wg_res
    rol wg_res+1
    dex
    bne @ml
    lda wg_acc                  ; / span
    sta wg_res
    lda wg_acc+1
    sta wg_res+1
    jsr wg_div16
    lda wg_res
    ldy #WG_GRP                 ; clamp to max
    cmp (CX_M_PTR),y
    bcc @store
@max
    ldy #WG_GRP
    lda (CX_M_PTR),y
    bra @store
@slow
    ldy #WG_GRP
    lda (CX_M_PTR),y
@store
    ldy #WG_VAL
    sta (CX_M_PTR),y
    pha
    jsr wg_paint
    pla
    rts

; --- bank 2 state ------------------------------------------------------
wg_list  .word 0
wg_n     .byte 0
wg_svlist .word 0               ; the context wg_setup parks for a panel
wg_svn   .byte 0
wg_svf   .byte 0
wg_i     .byte 0
wg_t     .word 0
wg_t2    .word 0
wg_bx0   .word 0
wg_by0   .word 0
wg_bx1   .word 0
wg_by1   .word 0
wg_grp   .byte 0
wg_win   .byte 0
wg_mul   .byte 0
wg_div   .byte 0
wg_dvh   .byte 0                  ; scroll span's high byte
wg_rem   .byte 0
wg_res   .word 0
wg_acc   .word 0
wg_focus .byte $FF               ; the keyboard-focused widget; $FF none
wg_drag  .byte $FF               ; the scrollbar being dragged; $FF none
wg_dragpx .word 0                ; ...and its thumb's live pixel offset,
                                 ; so the thumb tracks the mouse smoothly
                                 ; while WG_VAL stays quantised
wg_cand  .byte 0                  ; focus_move's candidate walker
wg_step  .byte 0
wg_ch    .byte 0                  ; the character being typed into a field
wg_row   .byte 0                  ; a list's visible row being drawn
wg_idx   .byte 0                  ; ...the item it shows
wg_maxrows .byte 0                ; ...how many rows fit
wg_evt   .byte 0                  ; the press wg_hit saw: DOWN or DBLCLICK

.segment "CODE"
