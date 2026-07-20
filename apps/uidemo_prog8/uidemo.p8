; Prog8
; =====================================================================
; CXGEOS :: apps/uidemo_prog8/uidemo.p8 -- the p8sdk showcase
; =====================================================================
; Drives the friendly Prog8 UI layer (p8sdk/cxui.p8, block `ui`):
;   - the immediate-mode PAINTERS on the left (button, checkbox, slider,
;     edit), drawn by the app for a custom layout;
;   - a kernel-managed WIDGET LIST on the right, built at runtime with the
;     ui.wg_* builders and handed to cx.wg_set -- the toolkit draws it and
;     routes clicks, surfacing them through ui.next() as ET_WIDGET.
; Click either live button, or press ESC, to quit. A headless self-test
; proves the builder laid down two records ("UIDEMO OK") before any drawing.
;   prog8c ... -srcdirs sdk\include_prog8 -srcdirs p8sdk apps\uidemo_prog8\uidemo.p8
; =====================================================================

%import syslib
%import cxgeos
%import cxui
%zeropage basicsafe
%option no_sysinit
%zpreserved $02,$5f

main {
    str s_title = iso:"p8sdk ui demo -- painters (left) + a live widget list (right); click OK or ESC"
    str s_paint = iso:"painted"
    str s_sound = iso:"enable sound"
    str s_edit  = iso:"edit me"
    str s_ok    = iso:"OK"
    str s_cancel = iso:"Cancel"
    str s_hint  = iso:"the two boxes on the right are real toolkit widgets"

    ubyte[1 + 16*2] wlist       ; a widget list: a count byte + two 16-byte records

    ubyte[] m_up = [85,73,68,69,77,79,32,85,80,13,0]   ; "UIDEMO UP\r"
    ubyte[] m_ok = [85,73,68,69,77,79,32,79,75,13,0]   ; "UIDEMO OK\r"

    sub start() {
        emit(&m_up)

        ; --- headless self-test of the builder (no graphics needed) ---
        ui.wg_begin(&wlist)
        ui.wg_button(420, 110, 150, 34, &s_ok)
        ui.wg_button(420, 160, 150, 34, &s_cancel)
        if wlist[0] == 2                ; two records were appended
            emit(&m_ok)

        cx.gfx_init()
        cx.ev_init()
        cx.mouse_show(1)

        cx.gfx_clear(cx.PAPER)
        void cx.say(&s_title, 30, 24)

        ; the painters -- custom layout, the app draws them
        ui.button(30, 70, 150, 30, &s_paint)
        ui.checkbox(30, 120, &s_sound, 1)
        ui.slider(30, 160, 220, 6, 10)
        ui.edit(30, 195, 220, 26, &s_edit)

        ; the interactive widgets -- the toolkit draws + routes them
        void cx.say(&s_hint, 300, 80)
        cx.wg_set(&wlist)

        repeat {
            if ui.next() {
                when ui.etype {
                    cx.ET_WIDGET -> cx.exit()       ; either live button quits
                    cx.ET_KEY -> {
                        if ui.detail == cx.K_ESC
                            cx.exit()
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
