; Prog8
; =====================================================================
; CXGEOS :: p8sdk/cxui.p8 -- the friendly Prog8 UI layer (block `ui`)
; =====================================================================
; The Prog8 parallel of csdk/cxsdk.h's widget helpers, one level above the
; generated ABI binding (sdk/include_prog8/cxgeos.p8, block `cx`). It adds:
;
;   - immediate-mode PAINTERS (ui.button / checkbox / slider / edit): draw a
;     widget by name for custom layouts (a keypad, a status bar). They only
;     paint -- the app hit-tests the pixels itself -- and match the kernel
;     toolkit's look, so a hand-painted button sits beside a real one.
;   - a one-call EVENT poll (ui.poll / ui.next): pull the next event and read
;     it out of the $22 block into ui.etype / detail / mx / my BEFORE any
;     indirect op reuses Prog8's SCRATCH_PTR there.
;   - runtime DESCRIPTOR builders for the kernel-managed toolkit: fill an app
;     buffer with a widget list (ui.wg_*), a menu bar (ui.menu*), a dialog
;     (ui.dlg*) or a theme, then hand it to cx.wg_set / cx.menu_set / cx.panel.
;     C/asm lay these down as static data; Prog8 builds them into RAM at
;     startup, which sidesteps embedding pointers in a byte-array literal.
;
; Uses only the public `cx` binding, so it inherits its rules -- your MAIN
; program still needs `%option no_sysinit` and `%zpreserved $02,$5f`. Build
; with BOTH source dirs on the path:
;   prog8c ... -srcdirs sdk\include_prog8 -srcdirs p8sdk  app.p8
; =====================================================================

%import cxgeos

ui {
    ; --- painter geometry (matches the kernel toolkit) ---
    const uword FONT_H   = 8        ; the system font's glyph height
    const uword BOX      = 12       ; the checkbox marker square (= cx.BOX)
    const uword THUMB    = 16       ; the slider thumb width (= cx.THUMB)
    const uword SLIDER_H = 16       ; the slider's height

    ; =================================================================
    ; immediate-mode painters -- draw one widget, no kernel state
    ; =================================================================

    ; a push button: a framed box with its label centred both ways
    sub button(uword x, uword y, uword w, uword h, uword label) {
        uword tw = cx.font_measure(label)
        cx.gfx_rect(x, y, w, h, cx.PAPER)
        cx.gfx_frame(x, y, w, h, cx.FRAME)
        void cx.say(label, x + (w - tw) / 2, y + (h - FONT_H) / 2)
    }

    ; a checkbox: a marker box (filled when checked) and a label to its right
    sub checkbox(uword x, uword y, uword label, ubyte checked) {
        cx.gfx_rect(x, y, BOX, BOX, cx.PAPER)
        cx.gfx_frame(x, y, BOX, BOX, cx.FRAME)
        if checked != 0
            cx.gfx_rect(x + 3, y + 3, BOX - 6, BOX - 6, cx.FRAME)
        void cx.say(label, x + BOX + 6, y + 2)
    }

    ; a horizontal slider: a framed trough with a thumb at value/max
    ; (0..max inclusive, so a 1..10 slider passes value 0..9, max 9)
    sub slider(uword x, uword y, uword w, ubyte value, ubyte maxv) {
        cx.gfx_rect(x, y, w, SLIDER_H, cx.PAPER)
        cx.gfx_frame(x, y, w, SLIDER_H, cx.FRAME)
        uword tx = x + 2
        if maxv != 0 {
            uword travel = w - 4 - THUMB    ; inner width less the thumb
            long off = travel as long       ; 32-bit so value*travel can't wrap
            off *= value
            off /= maxv
            tx += off as uword
        }
        cx.gfx_rect(tx, y + 2, THUMB, SLIDER_H - 4, cx.HI)
    }

    ; an edit box: a framed field with its text, left-aligned, centred down.
    ; No caret -- the app owns the text; repaint to update it.
    sub edit(uword x, uword y, uword w, uword h, uword text) {
        cx.gfx_rect(x, y, w, h, cx.PAPER)
        cx.gfx_frame(x, y, w, h, cx.FRAME)
        void cx.say(text, x + 4, y + (h - FONT_H) / 2)
    }

    ; =================================================================
    ; events -- pull one, read it out of the block at once
    ; =================================================================
    ubyte etype                     ; cx.ET_*
    ubyte detail                    ; key code / widget index / menu item
    uword mx                        ; mouse x  (a widget event: its value)
    uword my                        ; mouse y  (a menu event: the menu index)
    ubyte frame                     ; the frame stamp

    ; copy the current $22-block event record into the ui.* fields
    sub grab() {
        etype  = cx.pb[0]
        detail = cx.pb[1]
        mx     = cx.pbw1
        my     = cx.pbw2
        frame  = cx.pb[6]
    }

    ; RAW poll: next event into ui.*, true if one was waiting. Mouse events
    ; arrive as ET_DOWN/MOVE/UP for an app that hit-tests its own pixels.
    sub poll() -> bool {
        if cx.ev_get()              ; carry set = the queue was empty
            return false
        grab()
        return true
    }

    ; TOOLKIT poll: like poll(), but pending mouse events are first routed
    ; through the widget/menu regions, so a click on a cx.wg_set widget or a
    ; cx.menu_set bar surfaces as the ET_WIDGET / ET_MENU the toolkit posts.
    sub next() -> bool {
        if cx.ev_next()
            return false
        grab()
        return true
    }

    ; =================================================================
    ; descriptor builders -- fill an app buffer with the kernel's byte
    ; layout (docs/formats.md). Build at startup, then hand to the kernel.
    ; The builders are stateful: finish one list before starting another.
    ; =================================================================

    ; --- a widget list: a count byte, then 16-byte records (cx.wg_set) ---
    uword wtop
    uword wcur

    sub wg_begin(uword buffer) {
        wtop = buffer
        wcur = buffer + 1
        @(buffer) = 0
    }
    sub wput(ubyte t, uword x, uword y, uword w, ubyte h, ubyte val, ubyte grp, uword label) {
        uword p = wcur
        @(p)    = t
        @(p+1)  = 0
        @(p+2)  = lsb(x)
        @(p+3)  = msb(x)
        @(p+4)  = lsb(y)
        @(p+5)  = msb(y)
        @(p+6)  = lsb(w)
        @(p+7)  = msb(w)
        @(p+8)  = h
        @(p+9)  = val
        @(p+10) = grp
        @(p+11) = lsb(label)
        @(p+12) = msb(label)
        @(p+13) = 0
        @(p+14) = 0
        @(p+15) = 0
        wcur = p + 16
        @(wtop) = @(wtop) + 1
    }
    sub wg_button(uword x, uword y, uword w, uword h, uword label) {
        wput(cx.WG_BUTTON, x, y, w, lsb(h), 0, 0, label)
    }
    sub wg_check(uword x, uword y, uword w, ubyte on, uword label) {
        wput(cx.WG_CHECK, x, y, w, 14, on, 0, label)
    }
    sub wg_radio(uword x, uword y, uword w, ubyte on, ubyte group, uword label) {
        wput(cx.WG_RADIO, x, y, w, 14, on, group, label)
    }
    sub wg_scroll(uword x, uword y, uword w, ubyte val, ubyte maxv) {
        wput(cx.WG_SCROLL, x, y, w, 16, val, maxv, 0)
    }
    sub wg_field(uword x, uword y, uword w, ubyte cap, uword buf) {
        wput(cx.WG_FIELD, x, y, w, 16, 0, cap, buf)
    }
    sub wg_icon(uword x, uword y, ubyte id, uword label) {
        wput(cx.WG_ICON, x, y, 24, 24, id, 0, label)
    }
    sub wg_hit(uword x, uword y, uword w, uword h, ubyte shape, ubyte trig) {
        wput(cx.WG_HIT, x, y, w, lsb(h), shape, trig, 0)
    }

    ; --- a menu bar: a count, then (title, items) per menu (cx.menu_set) ---
    uword mtop
    uword mcur

    sub menu_begin(uword buffer) {
        mtop = buffer
        mcur = buffer + 1
        @(buffer) = 0
    }
    sub menu(uword title, uword items) {
        uword p = mcur
        @(p)   = lsb(title)
        @(p+1) = msb(title)
        @(p+2) = lsb(items)
        @(p+3) = msb(items)
        mcur = p + 4
        @(mtop) = @(mtop) + 1
    }

    ; --- one menu's drop-down: a count, then a label pointer per item ---
    uword itop
    uword icur

    sub items_begin(uword buffer) {
        itop = buffer
        icur = buffer + 1
        @(buffer) = 0
    }
    sub item(uword label) {
        @(icur)   = lsb(label)
        @(icur+1) = msb(label)
        icur += 2
        @(itop) = @(itop) + 1
    }

    ; --- an alert/panel dialog: a button count, the message, then labels
    ; (cx.dlg_alert / cx.panel-style descriptors) ---
    uword dtop
    uword dcur

    sub dlg_begin(uword buffer, uword message) {
        dtop = buffer
        @(buffer)   = 0
        @(buffer+1) = lsb(message)
        @(buffer+2) = msb(message)
        dcur = buffer + 3
    }
    sub dlg_button(uword label) {
        @(dcur)   = lsb(label)
        @(dcur+1) = msb(label)
        dcur += 2
        @(dtop) = @(dtop) + 1
    }

    ; --- a 12-byte theme record: four $0RGB palette colours, then the
    ; paper / highlight / frame role indices (cx.theme_set) ---
    sub theme(uword buffer, uword c0, uword c1, uword c2, uword c3,
              ubyte paper, ubyte hi, ubyte frame) {
        @(buffer)    = lsb(c0)
        @(buffer+1)  = msb(c0)
        @(buffer+2)  = lsb(c1)
        @(buffer+3)  = msb(c1)
        @(buffer+4)  = lsb(c2)
        @(buffer+5)  = msb(c2)
        @(buffer+6)  = lsb(c3)
        @(buffer+7)  = msb(c3)
        @(buffer+8)  = paper
        @(buffer+9)  = hi
        @(buffer+10) = frame
        @(buffer+11) = 0
    }
}
