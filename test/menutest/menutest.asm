; ca65
; =====================================================================
; CXRF :: test/menutest/menutest.asm -- the menu engine, driven blind
; =====================================================================
; Runs as AUTORUN.CXA in the boot smoke. Synthetic clicks go down the
; same path a mouse's would (ev_post is the point), so the whole
; machine is exercised headless: the bar region routes the click, the
; engine crosses into bank 2, the drop-down saves the pixels it covers,
; a second click picks an item, the pixels come back, and EV_MENU
; arrives at this app's handler like any other event.
;
; The probe pixel is the save-under's witness: painted before the menu
; opens, covered by the box (asserted mid-flight), identical after.
;
; Verdicts through CHROUT: MENUTEST OK, or MENUTEST FAILED and a halt
; the smoke reads as a timeout.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxrf.inc"

EV_MOUSE_MOVE = 1               ; ABI event numbering
EV_MOUSE_DOWN = 2
EV_KEY        = 5
EV_MENU       = 7
EV_WIDGET     = 8
WG_CHECK      = 1
WG_RADIO      = 2
WG_FIELD      = 4
WG_LIST       = 5

PROBE_X = 40                    ; inside menu 0's box-to-be, and OFF
PROBE_Y = 32                    ; its text: the items draw in ink 3,
                                ; the same colour as the witness, and a
                                ; probe under a glyph reads 3 for the
                                ; wrong reason (found the hard way)

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    lda #0
    jsr cx_gfx_clear

    lda #PROBE_X                ; the witness
    sta X16_P0
    stz X16_P1
    lda #PROBE_Y
    sta X16_P2
    stz X16_P3
    lda #3
    jsr cx_gfx_pset

    lda #PROBE_X                ; trust nothing: the witness reads back
    sta X16_P0                  ; before anything else happens
    stz X16_P1
    lda #PROBE_Y
    sta X16_P2
    stz X16_P3
    jsr cx_gfx_read
    cmp #3
    beq @probed
    lda #'P'
    jmp fail
@probed

    jsr cx_ev_init              ; events BEFORE the menu: ev_init resets
    lda #<handlers              ; the region stack the bar lives on
    ldx #>handlers
    jsr cx_ev_handlers

    lda #<bar
    ldx #>bar
    jsr cx_menu_set
    bcc @set
    lda #'A'
    jmp fail
@set
    stz X16_P0                  ; the bar's rule line at (0,11): if the
    stz X16_P1                  ; bar never drew, mn_set never really
    lda #11                     ; ran, and the region walk is moot
    sta X16_P2
    stz X16_P3
    jsr cx_gfx_read
    cmp #3                      ; the bar's rule line: mn_set really ran
    beq @barred
    lda #'Q'
    jmp fail
@barred

    lda #EV_MOUSE_DOWN          ; a click in the bar, over "File"
    ldx #10                     ; x = 10
    ldy #5                      ; y = 5
    jsr click
    jsr drain                   ; dispatch until quiet: the queue also
                                ; holds the hook's first synthetic MOVE,
                                ; and one dispatch would eat that instead

    lda #PROBE_X                ; the witness must be under the box now
    sta X16_P0
    stz X16_P1
    lda #PROBE_Y
    sta X16_P2
    stz X16_P3
    jsr cx_gfx_read
    cmp #0                      ; the box's paper covers the witness
    beq @covered
    lda #'B'
    jmp fail
@covered

    ; the hover highlight, checked by the engine's own state rather than
    ; by pixels: a blind pixel read of a highlighted row is a coin toss
    ; (the row is a few pixels tall and the text sits on it), but mn_hot
    ; -- the highlighted row, pinned at 2:$A027 -- is exact. A MOVE into
    ; row 0 must set it to 0; a MOVE into row 1, to 1.
    lda #EV_MOUSE_MOVE
    ldx #20
    ldy #16                     ; row 0 (rows start at y=13, 10 tall)
    jsr click
    jsr drain
    lda #0
    ldx #0                      ; expect mn_hot = 0
    jsr hot_is
    bcs @hov0
    lda #'H'
    jmp fail
@hov0
    lda #EV_MOUSE_MOVE
    ldx #20
    ldy #26                     ; row 1
    jsr click
    jsr drain
    lda #1                      ; expect mn_hot = 1
    jsr hot_is
    bcs @hov1
    lda #'I'
    jmp fail
@hov1

    lda #EV_MOUSE_DOWN          ; a click on item 1, "Quit": row 1 spans
    ldx #14                     ; y 23-32
    ldy #25
    jsr click
    jsr drain                   ; the close, the EV_MENU it posts, all

    lda got_menu
    cmp #$80                    ; menu 0, marked heard
    beq @heard
    lda #'C'
    jmp fail
@heard
    lda got_item
    cmp #1
    beq @item
    lda #'D'
    jmp fail
@item

    ; ---- keyboard menu navigation --------------------------------
    ; drive menu 0 entirely by key: DOWN opens it (highlight item 0),
    ; DOWN moves to item 1, RETURN picks it. The EV_MENU that lands must
    ; match the mouse path: menu 0, item 1. cx_menu_key consumes each,
    ; so carry comes back set.
    stz got_item
    stz got_menu
    lda #$11                    ; KEY_DOWN: open the bar
    jsr cx_menu_key
    bcs @kopen
    lda #'L'
    jmp fail
@kopen
    lda #$11                    ; KEY_DOWN: highlight item 1
    jsr cx_menu_key
    lda #$0D                    ; KEY_ENTER: pick it
    jsr cx_menu_key
    jsr drain                   ; the EV_MENU it posted
    lda got_menu
    cmp #$80                    ; menu 0
    beq @kheard
    lda #'M'
    jmp fail
@kheard
    lda got_item
    cmp #1                      ; item 1, same as the mouse picked
    beq @kitem
    lda #'N'
    jmp fail
@kitem

    lda #PROBE_X                ; the witness, restored to the pixel
    sta X16_P0
    stz X16_P1
    lda #PROBE_Y
    sta X16_P2
    stz X16_P3
    jsr cx_gfx_read
    cmp #3
    beq @ok
    lda #'E'
    jmp fail
@ok
    ; ---- the dialog engine ---------------------------------------
    lda #<300                   ; a witness under the box-to-be
    sta X16_P0
    lda #>300
    sta X16_P1
    lda #240
    sta X16_P2
    stz X16_P3
    lda #3
    jsr cx_gfx_pset

    lda #EV_MOUSE_DOWN          ; the click, queued BEFORE the call:
    sta X16_P0                  ; the dialog's own loop will find it.
    stz X16_P1                  ; (471, 268) is button 1's middle in a
    lda #<471                   ; two-button box (docs/formats.md) --
    sta X16_P2                  ; both coordinates carry a ninth bit,
    lda #>471                   ; so the click helper is no use here
    sta X16_P3
    lda #<268
    sta X16_P4
    lda #>268
    sta X16_P5
    stz X16_P6
    stz X16_P7
    jsr cx_ev_post

    lda #<dlg2                  ; blocks until the button
    ldx #>dlg2
    jsr cx_dlg_alert
    cmp #1
    beq @btn1
    lda #'F'
    jmp fail
@btn1
    lda #<300                   ; the witness, back to the pixel
    sta X16_P0
    lda #>300
    sta X16_P1
    lda #240
    sta X16_P2
    stz X16_P3
    jsr cx_gfx_read
    cmp #3
    beq @dback
    lda #'G'
    jmp fail
@dback

    lda #EV_KEY                 ; RETURN stands in for button 0. A key
    sta X16_P0                  ; carries its code in detail (P1), not in
    lda #$0D                    ; the x field the click helper fills --
    sta X16_P1                  ; that helper is for mouse events only
    stz X16_P2
    stz X16_P3
    stz X16_P4
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jsr cx_ev_post
    lda #<dlg1
    ldx #>dlg1
    jsr cx_dlg_alert
    cmp #0
    beq @keyed
    lda #'K'
    jmp fail
@keyed

    ; ---- the theme -------------------------------------------------
    lda #<tst_theme             ; palette entry 0 becomes $234
    ldx #>tst_theme
    jsr cx_theme_set
    vera_addr 1, VRAM_PALETTE, VERA_INC_1
    lda VERA_DATA1
    cmp #$34
    beq @themed
    lda #'J'
    jmp fail
@themed
    lda #<def_theme             ; and back, so the shell inherits the
    ldx #>def_theme             ; machine it expects
    jsr cx_theme_set

    ; ---- the widget toolkit --------------------------------------
    ; the menu bar's region is still on the stack under nothing, and a
    ; fresh ev_init would be cleaner, but cx_wg_set just pushes another
    ; region on top -- its widgets are well below the bar, so no click
    ; here reaches both.
    lda #<wg_list
    ldx #>wg_list
    jsr cx_wg_set

    lda #EV_MOUSE_DOWN          ; click the checkbox at (50,100): its
    sta X16_P0                  ; box is 12 wide, so (55,105) is inside
    stz X16_P1
    lda #55
    sta X16_P2
    stz X16_P3
    lda #105
    sta X16_P4
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jsr cx_ev_post
    jsr drain                   ; the widget toggles and posts EV_WIDGET
    lda got_wg                  ; heard, with the new value: 1, marked
    cmp #$81                    ; ($80 | value 1)
    beq @wgtog
    lda #'W'
    jmp fail
@wgtog
    ; the checkbox record's WG_VAL (offset 9) must now read 1
    lda wg_list + 1 + 9         ; count byte, then record 0's val
    cmp #1
    beq @wgval
    lda #'X'
    jmp fail
@wgval
    ; click radio 3 (index 3, at (50,180)); record 2 -- the middle one,
    ; selected at the start -- must clear, proving the group logic
    lda #EV_MOUSE_DOWN
    sta X16_P0
    stz X16_P1
    lda #55
    sta X16_P2
    stz X16_P3
    lda #185
    sta X16_P4
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jsr cx_ev_post
    jsr drain
    lda wg_list + 1 + 3*16 + 9  ; record 3's val = 1 (now selected)
    cmp #1
    beq @wgr3
    lda #'Y'
    jmp fail
@wgr3
    lda wg_list + 1 + 2*16 + 9  ; record 2's val = 0 (was selected)
    beq @wgr2
    lda #'Z'
    jmp fail
@wgr2

    ; ---- keyboard widget focus ------------------------------------
    ; the checkbox (record 0) is checked from the click test. TAB moves
    ; focus onto it (the first widget); SPACE activates it exactly as a
    ; click would -- toggling it off and posting EV_WIDGET value 0.
    stz got_wg
    lda #$09                    ; TAB: focus widget 0
    jsr cx_wg_key
    bcs @wtab
    lda #'T'
    jmp fail
@wtab
    lda #$20                    ; SPACE: activate the focused checkbox
    jsr cx_wg_key
    bcs @wsp
    lda #'U'
    jmp fail
@wsp
    jsr drain                   ; the EV_WIDGET it posted
    lda wg_list + 1 + 9         ; record 0's val toggled 1 -> 0
    beq @wval
    lda #'V'
    jmp fail
@wval
    lda got_wg                  ; heard, value 0 -> $80
    cmp #$80
    beq @wheard
    lda #'0'
    jmp fail
@wheard
    ; ---- text field typing ---------------------------------------
    ; TAB four times to reach record 4 (the field), type "Hi", and the
    ; buffer and length must read it back -- the same wg_key path a real
    ; keystroke takes.
    lda #$09                    ; TAB x4 to reach record 4 (the field).
    jsr cx_wg_key               ; UNROLLED: cx_wg_key clobbers X and Y --
    lda #$09                    ; only A and carry survive it -- so a
    jsr cx_wg_key               ; register loop counter would be corrupt
    lda #$09
    jsr cx_wg_key
    lda #$09
    jsr cx_wg_key
    lda #'H'
    jsr cx_wg_key
    bcs @wty
    lda #'R'
    jmp fail
@wty
    lda #'i'
    jsr cx_wg_key
    lda wl_buf
    cmp #'H'
    beq @wf1
    lda #'S'
    jmp fail
@wf1
    lda wl_buf+1
    cmp #'i'
    beq @wf2
    lda #'2'
    jmp fail
@wf2
    lda wl_buf+2                ; null-terminated after "Hi"
    beq @wf3
    lda #'3'
    jmp fail
@wf3
    lda wg_list + 1 + 4*16 + 9  ; the field's length = 2
    cmp #2
    beq @wf4
    lda #'4'
    jmp fail
@wf4
    ; backspace must truncate the buffer, not just drop the length --
    ; the NUL has to land at the new end (the owner's on-screen bug).
    lda #$14                    ; DEL
    jsr cx_wg_key
    lda wg_list + 1 + 4*16 + 9  ; length now 1
    cmp #1
    beq @wf5
    lda #'6'
    jmp fail
@wf5
    lda wl_buf                  ; "H" still there
    cmp #'H'
    bne @wbad
    lda wl_buf+1                ; and the NUL at index 1, so "i" is gone
    beq @wf6
@wbad
    lda #'7'
    jmp fail
@wf6

    ; ---- list view selection --------------------------------------
    ; focus is on the field (record 4); TAB once to the list (record 5),
    ; DOWN twice, and its selected row (WG_VAL) must read 2.
    lda #$09                    ; TAB: field -> list
    jsr cx_wg_key
    lda #$11                    ; DOWN: 0 -> 1
    jsr cx_wg_key
    bcs @l1
    lda #'5'
    jmp fail
@l1
    lda #$11                    ; DOWN: 1 -> 2
    jsr cx_wg_key
    lda wg_list + 1 + 5*16 + 9  ; the list's selected row = 2
    cmp #2
    beq @l2
    lda #'6'
    jmp fail
@l2
    lda #$11                    ; DOWN at the end: stays 2 (clamped)
    jsr cx_wg_key
    lda wg_list + 1 + 5*16 + 9
    cmp #2
    beq @l3
    lda #'7'
    jmp fail
@l3

    ; ---- the DOS command channel -----------------------------------
    ; scratching a file that is not there must come back as the error
    ; class with readable text; making and unmaking a folder must both
    ; succeed. TDOSDIR lives only between the two commands, and only in
    ; the staged sdroot.
    lda #<c_bad
    ldx #>c_bad
    ldy #12
    jsr cx_dos_cmd
    bcc @dosbad                 ; no error? that IS the error
    cmp #20
    bcc @dosbad
    lda #<mbuf                  ; the reply text opens with the code's
    sta X16_P0                  ; first digit
    lda #>mbuf
    sta X16_P1
    jsr cx_dos_msg
    lda mbuf
    cmp #'0'
    bcc @dosbad
    cmp #'9'+1
    bcc @dos1
@dosbad
    lda #'8'
    jmp fail
@dos1
    lda #<c_md
    ldx #>c_md
    ldy #10
    jsr cx_dos_cmd
    bcs @dosbad2
    lda #<c_rd
    ldx #>c_rd
    ldy #10
    jsr cx_dos_cmd
    bcc @dos2
@dosbad2
    lda #'9'
    jmp fail
@dos2

    ; ---- the prompt dialog -----------------------------------------
    ; keys queued before the call, the alert pattern: type "Hi", accept.
    lda #'H'
    jsr pkey
    lda #'i'
    jsr pkey
    lda #$0D
    jsr pkey
    lda #<pbuf
    sta X16_P0
    lda #>pbuf
    sta X16_P1
    lda #16
    sta X16_P2
    lda #<s_pm
    ldx #>s_pm
    jsr cx_dlg_prompt
    bcs @pbad                   ; accepted, length 2, the text in place
    cmp #2
    bne @pbad
    lda pbuf
    cmp #'H'
    bne @pbad
    lda pbuf+1
    cmp #'i'
    bne @pbad
    lda pbuf+2
    beq @p1
@pbad
    lda #'P'
    jmp fail
@p1
    lda #$1B                    ; and ESC must cancel with the carry
    jsr pkey
    lda #<pbuf
    sta X16_P0
    lda #>pbuf
    sta X16_P1
    lda #16
    sta X16_P2
    lda #<s_pm
    ldx #>s_pm
    jsr cx_dlg_prompt
    bcs @p2
    lda #'Q'
    jmp fail
@p2

    ; ---- the desk accessory ----------------------------------------
    ; open the notes DA, type one key through the dispatcher (it lands
    ; in bank 9 via the swapped table), ESC it closed the same way --
    ; then open it AGAIN: the second open only works if the close put
    ; the manager's state back.
    lda #<c_nda
    ldx #>c_nda
    ldy #9
    jsr cx_da_open
    bcs @dabad
    lda #'A'
    jsr pkey
    jsr cx_ev_dispatch
    lda #$1B
    jsr pkey
    jsr cx_ev_dispatch
    lda #<c_nda
    ldx #>c_nda
    ldy #9
    jsr cx_da_open
    bcs @dabad
    lda #$1B
    jsr pkey
    jsr cx_ev_dispatch
    bra @daok
@dabad
    lda #'D'
    jmp fail
@daok

    ; ---- the modal panel -------------------------------------------
    ; cx_panel runs its own dispatch loop over the app's widgets: a click
    ; toggles one INSIDE the box (proving dg_hit forwards to the widgets
    ; while a panel is up), RETURN closes on button 0, and the pixels
    ; under the box come back. Both events queued first, the alert pattern.
    lda #250                    ; a witness on the box paper (box is
    sta X16_P0                  ; 100,100,300,90 -- 90 rows fits the
    stz X16_P1                  ; mode-0 save-under, banks 14-15)
    lda #150
    sta X16_P2
    stz X16_P3
    lda #3
    jsr cx_gfx_pset

    lda #EV_MOUSE_DOWN          ; click the panel's checkbox at (120,125):
    sta X16_P0                  ; 12 wide, so (125,130) is on its marker
    stz X16_P1
    lda #125
    sta X16_P2
    stz X16_P3
    lda #130
    sta X16_P4
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jsr cx_ev_post
    lda #EV_KEY                 ; then RETURN: button 0 closes the panel
    sta X16_P0
    lda #$0D
    sta X16_P1
    stz X16_P2
    stz X16_P3
    stz X16_P4
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jsr cx_ev_post

    lda #<pnl
    ldx #>pnl
    jsr cx_panel
    cmp #0                      ; RETURN picked button 0
    beq @pn0
    lda #'a'
    jmp fail
@pn0
    lda pnl_wg + 1 + 9          ; the checkbox toggled 0 -> 1 (record 0 val)
    cmp #1
    beq @pn1
    lda #'b'
    jmp fail
@pn1
    lda #250                    ; the witness is back: the save-under put
    sta X16_P0                  ; the box's rows back exactly
    stz X16_P1
    lda #150
    sta X16_P2
    stz X16_P3
    jsr cx_gfx_read
    cmp #3
    beq @pn2
    lda #'c'
    jmp fail
@pn2
    ; the panel handed the widget slot back: the app's OWN checkbox (at
    ; 50,100, in wg_list) must answer a click again. This is the bug where
    ; the panel, running in bank 5, left the bank-2 wg_list on its own list.
    lda wg_list + 1 + 9         ; note its value now, to prove the click flips it
    sta got_wg                  ; (a spent byte, reused as scratch)
    lda #EV_MOUSE_DOWN
    sta X16_P0
    stz X16_P1
    lda #55
    sta X16_P2
    stz X16_P3
    lda #105
    sta X16_P4
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jsr cx_ev_post
    jsr drain
    lda wg_list + 1 + 9         ; toggled -> different from before the click
    cmp got_wg
    bne @pn3
    lda #'d'
    jmp fail
@pn3
    ; a MOUSE click selects a list row too, via the mode-aware hit-test:
    ; click row 0 of the list (record 5) and WG_VAL returns to 0 from 2.
    lda #EV_MOUSE_DOWN
    sta X16_P0
    stz X16_P1
    lda #60
    sta X16_P2
    stz X16_P3
    lda #243                    ; box_y (240) + into row 0
    sta X16_P4
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jsr cx_ev_post
    jsr drain
    lda wg_list + 1 + 5*16 + 9  ; the list's selected row = 0 (clicked)
    beq @pn4
    lda #'e'
    jmp fail
@pn4
    ; ---- a mode-3 dialog must not stomp the mode-0 font cache --------
    ; The text engine's save-under once borrowed bank 6 -- the glyph
    ; cache, idle in text mode -- but the desktop returned to on exit
    ; reads it, so a dialog raised inside the TUI corrupted the desktop
    ; font. Plant a sentinel in the cache, raise a dialog in mode 3, and
    ; it must survive.
    lda RAM_BANK
    pha
    lda #6
    sta RAM_BANK
    lda $A000
    sta got_menu                ; keep the real cache byte
    lda #$5A
    sta $A000                   ; the sentinel
    pla
    sta RAM_BANK

    lda #3                      ; into text mode
    jsr cx_gfx_mode
    lda #EV_KEY                 ; RETURN closes the alert on button 0
    sta X16_P0
    lda #$0D
    sta X16_P1
    stz X16_P2
    stz X16_P3
    stz X16_P4
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jsr cx_ev_post
    lda #<dlg1
    ldx #>dlg1
    jsr cx_dlg_alert
    lda #0                      ; back to the desktop mode
    jsr cx_gfx_mode

    lda RAM_BANK
    pha
    lda #6
    sta RAM_BANK
    ldx $A000                   ; the cache byte after the excursion
    lda got_menu
    sta $A000                   ; the real byte back, before any branch
    pla
    sta RAM_BANK
    cpx #$5A
    beq @f3ok
    lda #'f'
    jmp fail
@f3ok

menu_ok
    lda #<s_ok
    ldx #>s_ok
    jsr pmsg
    jmp cx_exit                 ; and the shell must come back

fail
    sta s_which                 ; the stage letter, into the verdict
    lda #<s_bad
    ldx #>s_bad
    jsr pmsg
@halt
    bra @halt

; drain -- dispatch a bounded number of events. NOT until-empty: the
; raster hook posts a mouse MOVE every frame, and under warp a redraw
; triggered by one can be slower than the next arriving, so an
; until-empty loop can never see the queue reach zero. Our synthetic
; event is at most a few slots deep behind coalesced MOVEs, so eight
; dispatches always reach it; an empty queue dispatches a harmless
; EV_NULL. (A real app's mainloop dispatches one per iteration and has
; never had this problem -- only a test that waits for quiet does.)
drain
    ldx #8
@d
    phx
    jsr cx_ev_dispatch
    plx
    dex
    bne @d
    rts

; hot_is -- A = the row mn_hot should hold. Carry set if it matches.
; mn_hot lives in bank 2 at $A027 (the menu engine's state block, right
; behind its eight-entry jump table).
hot_is
    sta @want+1
    lda RAM_BANK
    pha
    lda #2
    sta RAM_BANK
    lda $A03F                   ; mn_hot (state block behind the
                                ; 48-byte, 16-slot bank-2 table)
    tay                         ; hold it across the bank restore, which
    pla                         ; the compare's flags would not survive
    sta RAM_BANK
    tya
@want
    cmp #$00
    beq @yes
    clc
    rts
@yes
    sec
    rts

; click -- A = type, X = x low, Y = y low; the rest zero. Down the real
; path via cx_ev_post.
click
    sta X16_P0
    stx X16_P2
    sty X16_P4
    stz X16_P1
    stz X16_P3
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jmp cx_ev_post

; pkey -- A = a key: queue it as an EV_KEY for a synchronous dialog to
; find, the way the RETURN-for-button-0 test posts its key.
pkey
    sta X16_P1
    lda #EV_KEY
    sta X16_P0
    stz X16_P2
    stz X16_P3
    stz X16_P4
    stz X16_P5
    stz X16_P6
    stz X16_P7
    jmp cx_ev_post

on_menu
    lda X16_P1
    sta got_item
    lda X16_P2
    ora #$80                    ; heard, even if menu 0
    sta got_menu
    rts

pmsg
    sta $02
    stx $03
    ldy #0
@loop
    lda ($02),y
    beq @done
    jsr CHROUT
    iny
    bne @loop
@done
    rts

on_widget
    lda X16_P2                  ; the value, marked heard
    ora #$80
    sta got_wg
    rts

handlers                        ; NULL MOVE DOWN UP DBL KEY TIMER
    .addr 0, 0, 0, 0, 0, 0, 0
    .addr on_menu               ; MENU
    .addr on_widget             ; WIDGET
    .addr 0                     ; JOY: EV_COUNT (10) vectors, always

got_item .byte $FF
got_menu .byte 0
got_wg   .byte 0

; a checkbox at (50,100) and a three-radio group (group 1), the middle
; one selected -- enough for toggle and the group's clear-the-others.
wg_list
    .byte 6
    .byte WG_CHECK, 0
    .word 50, 100, 140
    .byte 12, 0, 0
    .addr wl_c
    .byte 0, 0, 0
    .byte WG_RADIO, 0
    .word 50, 140, 100
    .byte 12, 0, 1
    .addr wl_a
    .byte 0, 0, 0
    .byte WG_RADIO, 0
    .word 50, 160, 100
    .byte 12, 1, 1
    .addr wl_b
    .byte 0, 0, 0
    .byte WG_RADIO, 0
    .word 50, 180, 100
    .byte 12, 0, 1
    .addr wl_c2
    .byte 0, 0, 0
    .byte WG_FIELD, 0            ; record 4: a text field
    .word 50, 210, 200
    .byte 16, 0, 8              ; length 0, capacity 8
    .addr wl_buf
    .byte 0, 0, 0
    .byte WG_LIST, 0            ; record 5: a three-item list
    .word 50, 240, 200
    .byte 40, 0, 3             ; h=40, selected 0, count 3
    .addr wl_ptrs
    .byte 0, 0, 0             ; byte 13 = WG_TOP = 0
wl_ptrs .addr wl_i0, wl_i1, wl_i2
wl_i0 .byte "alpha", 0
wl_i1 .byte "bravo", 0
wl_i2 .byte "charlie", 0
wl_c  .byte "check", 0
wl_a  .byte "a", 0
wl_b  .byte "b", 0
wl_c2 .byte "c", 0
wl_buf .res 9, 0

; the modal panel: a box with one checkbox and OK/Cancel. 90 rows tall so
; its save-under fits banks 14-15 (the mode-0 dialog strip is 96).
pnl
    .word 100, 100, 300         ; box x, y, w
    .byte 90                    ; box h
    .addr s_pnl
    .addr pnl_wg
    .byte 2
    .addr s_pok, s_pcancel
pnl_wg
    .byte 1
    .byte WG_CHECK, 0
    .word 120, 125, 160
    .byte 12, 0, 0
    .addr s_pcb
    .byte 0, 0, 0
s_pnl     .byte "Form", 0
s_pcb     .byte "option", 0
s_pok     .byte "OK", 0
s_pcancel .byte "Cancel", 0

; the menu tree (docs/formats.md)
bar
    .byte 2
    .addr s_file, file_items
    .addr s_edit, edit_items
file_items
    .byte 2
    .addr s_open, s_quit
edit_items
    .byte 1
    .addr s_one

s_file .byte "File", 0
s_edit .byte "Edit", 0
s_open .byte "Open", 0
s_quit .byte "Quit", 0
s_one  .byte "One", 0

dlg2                            ; two buttons: 356-427 and 436-507
    .byte 2
    .addr s_dmsg
    .addr s_dno, s_dyes
dlg1
    .byte 1
    .addr s_dmsg
    .addr s_dok
tst_theme
    .byte $34, $02,  $AA, $0A,  $55, $05,  $00, $00
    .byte 0, 1, 3, 0
def_theme
    .byte $FF, $0F,  $AA, $0A,  $55, $05,  $00, $00
    .byte 0, 1, 3, 0
s_dmsg .byte "a question with two answers", 0
s_dno  .byte "no", 0
s_dyes .byte "yes", 0
s_dok  .byte "ok", 0

c_bad .byte "S:NOSUCH.XYZ"       ; 12
c_md  .byte "MD:TDOSDIR"         ; 10
c_rd  .byte "RD:TDOSDIR"         ; 10
c_nda .byte "NOTES.CXD"          ; 9
s_pm  .byte "type Hi and RETURN (a robot is doing this)", 0
mbuf  .res 64, 0
pbuf  .res 16, 0

s_ok  .byte "MENUTEST OK", $0D, 0
s_bad   .byte "MENUTEST FAILED "
s_which .byte "?", $0D, 0
