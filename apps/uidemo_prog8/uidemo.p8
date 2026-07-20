; Prog8
; =====================================================================
; CXGEOS :: apps/uidemo_prog8/uidemo.p8 -- the p8sdk showcase
; =====================================================================
; Drives the friendly Prog8 UI layer (p8sdk/cxui.p8, block `ui`), both
; halves of it:
;   - LEFT: the immediate-mode PAINTERS (button/checkbox/slider/edit) --
;     the app draws them for a custom layout; they are STATIC, the app
;     would hit-test them itself. Here they are just a look.
;   - RIGHT: a live WIDGET LIST built at runtime with the ui.wg_* builders
;     and handed to cx.wg_set -- the kernel toolkit draws it, and ROUTES
;     the mouse, so a click toggles the checkbox, picks a radio, drags the
;     scrollbar, focuses the field. Each surfaces through ui.next() as an
;     ET_WIDGET (ui.detail = the widget index). The Exit button, or ESC,
;     quits. A headless self-test proves the builder laid all six records
;     ("UIDEMO OK") before any drawing.
;   prog8c ... -srcdirs sdk\include_prog8 -srcdirs p8sdk apps\uidemo_prog8\uidemo.p8
; =====================================================================

%import syslib
%import cxgeos
%import cxui
%zeropage basicsafe
%option no_sysinit
%zpreserved $02,$5f

main {
    str s_title  = iso:"p8sdk widgets -- click the live ones on the right; Exit or ESC quits"
    str s_paintl = iso:"painters (static -- the app draws + hit-tests these):"
    str s_livel  = iso:"live toolkit widgets (click them -- they respond):"
    str s_sound  = iso:"enable sound"
    str s_low    = iso:"low"
    str s_high   = iso:"high"
    str s_exit   = iso:"Exit"
    str s_pbtn   = iso:"button"
    str s_sample = iso:"sample text"

    ubyte[24] field                 ; the live text field's edit buffer (NUL-term)
    ; a widget list: a count byte + six 16-byte records
    ; (checkbox, two radios, a scrollbar, a field, the Exit button)
    ubyte[1 + 16*6] wlist

    ubyte[] m_up = [85,73,68,69,77,79,32,85,80,13,0]   ; "UIDEMO UP\r"
    ubyte[] m_ok = [85,73,68,69,77,79,32,79,75,13,0]   ; "UIDEMO OK\r"

    const ubyte W_EXIT = 5          ; the Exit button's index in the list

    sub start() {
        emit(&m_up)
        field[0] = 0                ; start the field empty

        ; --- build the live widget list; self-test the builder headless ---
        ui.wg_begin(&wlist)
        ui.wg_check(330, 110, 240, 1, &s_sound)        ; 0  a checkbox
        ui.wg_radio(330, 150,  90, 1, 1, &s_low)       ; 1  radio, group 1, on
        ui.wg_radio(440, 150,  90, 0, 1, &s_high)      ; 2  radio, group 1
        ui.wg_scroll(330, 190, 250, 4, 10)             ; 3  a 0..10 scrollbar
        ui.wg_field(330, 230, 250, 20, &field)         ; 4  a text field (cap 20)
        ui.wg_button(330, 275, 120, 34, &s_exit)       ; 5  the Exit button
        if wlist[0] == 6                ; all six records were appended
            emit(&m_ok)

        cx.gfx_init()
        cx.ev_init()
        cx.mouse_show(1)
        cx.gfx_clear(cx.PAPER)
        void cx.say(&s_title, 24, 22)

        ; LEFT: the painters, drawn once, static
        void cx.say(&s_paintl, 24, 66)
        ui.button(30, 90, 120, 30, &s_pbtn)
        ui.checkbox(30, 138, &s_sound, 1)
        ui.slider(30, 176, 240, 6, 10)
        ui.edit(30, 212, 240, 26, &s_sample)

        ; RIGHT: the live toolkit widgets -- cx.wg_set draws + routes them
        void cx.say(&s_livel, 330, 88)
        cx.wg_set(&wlist)

        repeat {
            if ui.next() {              ; toolkit poll: mouse routed to the widgets
                when ui.etype {
                    cx.ET_WIDGET -> {
                        if ui.detail == W_EXIT
                            cx.exit()
                        ; the checkbox/radio/scrollbar/field: the toolkit has
                        ; already updated and redrawn them -- nothing to do
                    }
                    cx.ET_KEY -> {
                        if ui.detail == cx.K_ESC
                            cx.exit()
                        void cx.wg_key(ui.detail)   ; TAB moves focus; type into the field
                    }
                }
            }
        }
    }

    ; CHROUT a NUL-terminated ASCII byte string through the KERNAL
    sub emit(uword ptr) {
        ubyte b = @(ptr)
        while b != 0 {
            cbm.CHROUT(b)
            ptr++
            b = @(ptr)
        }
    }
}
