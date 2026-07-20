; Prog8
; =====================================================================
; CXGEOS :: apps/calc/calc.p8 -- the calculator, in Prog8
; =====================================================================
; A port of apps/calc/calc.c to Prog8. A four-function floating-point calc:
; click the keypad or type; digits, '.', + - * /, RETURN for =, C clears,
; ESC or the exit button leaves. It is the "complete example" for the Prog8
; SDK -- a real interactive app on the two SDK layers:
;   - the friendly p8sdk (p8sdk/cxui.p8, block `ui`): ui.button paints the
;     keypad; ui.poll pulls each event into ui.etype / detail / mx / my
;   - the generated ABI binding (sdk/include_prog8/cxgeos.p8, block `cx`):
;     gfx primitives, cx.say, cx.font_measure, cx.gfx_init/ev_init, and floats
; A headless self-test (2 + 3 = 5) prints "CALC P8 OK" before the loop.
;
;   prog8c -target cx16 -srcdirs sdk\include_prog8 -srcdirs p8sdk calc.p8
; =====================================================================

%import syslib
%import floats
%import cxgeos
%import cxui           ; the p8sdk friendly layer -- ui.button paints the keypad
%zeropage basicsafe
%option no_sysinit      ; REQUIRED: a CXGEOS app is a guest -- the kernel owns
                        ; the machine. Prog8's default init_system does a full
                        ; reset (RESTOR/CINT/IOINIT/mouse_config) that tears out
                        ; the live kernel IRQ + video and crashes a desktop launch.
%zpreserved $02,$5f     ; REQUIRED: the CXGEOS kernel owns zp $02..$5F and
                        ; clobbers it on every API call, so keep Prog8's
                        ; variables in the app-safe $60..$7F (see cxgeos.p8)

main {
    const uword GX      = 200
    const uword GY      = 150
    const uword CW      = 56
    const uword CH      = 28
    const uword STEP    = 64        ; CW + GAP (horizontal cell pitch)
    const uword ROWSTEP = 36        ; CH + GAP (vertical cell pitch)
    const uword CLEARW  = 248       ; 4*CW + 3*GAP, the wide clear button

    ; keypad glyphs as ASCII bytes -- digits and operators are the same in
    ; PETSCII, and the CXGEOS font is ASCII-indexed, so these draw and match
    ; the EV_KEY codes directly.  7 8 9 /  4 5 6 *  1 2 3 -  0 . = +
    ubyte[16] keys = [$37,$38,$39,$2f,  $34,$35,$36,$2a,
                      $31,$32,$33,$2d,  $30,$2e,$3d,$2b]

    float acc                       ; the running total
    float cur                       ; the number being entered
    float frac                      ; 0 = whole part; else the next place value
    ubyte op                        ; the pending operator (0 = none)
    ubyte typing                    ; 1 while cur is being entered
    ubyte err                       ; 1 after divide-by-zero, until cleared
    uword note                      ; a status string address, or 0
    ubyte[2] lab                    ; a one-glyph button-label buffer

    str msg_title = iso:"calc -- type or click; . for decimals, RETURN =, C clears; exit lower-right."
    str msg_clear = iso:"clear"
    str msg_exit  = iso:"exit"
    str msg_clr   = iso:"cleared."
    str msg_dz    = iso:"divide by zero -- C clears."

    sub start() {
        ; markers go out in TEXT mode, BEFORE gfx_init -- KERNAL CHROUT over
        ; the bitmap corrupts the screen, so nothing prints once drawing starts
        emit(&m_up)                 ; load + run worked
        if selftest()               ; 2 + 3 = 5, pure maths (no drawing)
            emit(&m_ok)

        cx.gfx_init()
        cx.ev_init()
        cx.mouse_show(1)
        draw()

        repeat {
            if ui.poll() {          ; p8sdk: pull an event into ui.etype/detail/mx/my
                if ui.etype == cx.ET_KEY {
                    if ui.detail == cx.K_ESC
                        cx.exit()
                    feed(ui.detail)
                } else if ui.etype == cx.ET_DOWN {
                    click(ui.mx, ui.my)
                }
            }
        }
    }

    sub draw() {
        cx.gfx_clear(cx.PAPER)
        cx.say(&msg_title, 90, 60)
        cx.gfx_frame(GX, 110, 248, 28, cx.FRAME)    ; the result display

        ubyte i
        for i in 0 to 15 {
            ; NB: Prog8's `as` cast binds looser than +/*, so a mixed
            ; expression must widen through plain uword locals, not casts,
            ; or `GX + col*STEP` reparses as `(GX+col)*STEP` -- off screen.
            uword col = i & 3
            uword row = i >> 2
            uword bx  = GX + col * STEP
            uword by  = GY + row * ROWSTEP
            lab[0] = keys[i]
            lab[1] = 0
            ui.button(bx, by, CW, CH, &lab)             ; p8sdk painter
        }
        ui.button(GX, GY + 4 * ROWSTEP, CLEARW, CH, &msg_clear)   ; wide clear
        ui.button(520, 448, 100, 24, &msg_exit)                  ; exit
        show()
    }

    sub show() {
        cx.gfx_rect(GX + 2, 112, 244, 24, cx.PAPER)
        if err == 0
            cx.say(floats.tostr(display_value()), GX + 12, 118)
        cx.gfx_rect(40, 88, 420, 14, cx.PAPER)
        if note != 0
            cx.say(note, 40, 90)
        note = 0
    }

    sub display_value() -> float {
        if typing != 0
            return cur
        return acc
    }

    sub apply() {
        when op {
            $2b -> acc += cur                       ; +
            $2d -> acc -= cur                       ; -
            $2a -> acc *= cur                       ; *
            $2f -> {                                ; /
                if cur == 0.0 {
                    err = 1
                    note = &msg_dz
                    return
                }
                acc /= cur
            }
            else -> acc = cur
        }
        cur = 0.0
        frac = 0.0
        typing = 0
    }

    sub feed(ubyte c) {
        if err != 0 and c != $43 and c != $63       ; blocked until 'C'/'c'
            return

        if c >= $30 and c <= $39 {                  ; a digit
            float digit = (c - $30) as float        ; cast alone, then use it
            if frac == 0.0 {
                cur = cur * 10.0 + digit
            } else {
                cur += digit * frac
                frac *= 0.1
            }
            typing = 1
        } else if c == $2e {                        ; '.'
            if frac == 0.0
                frac = 0.1                          ; a second point is ignored
            typing = 1
        } else if c == $2b or c == $2d or c == $2a or c == $2f {   ; an operator
            if typing != 0
                apply()
            if err == 0
                op = c
        } else if c == $3d or c == $0d {            ; '=' or RETURN
            if op != 0 or typing != 0
                apply()
            op = 0
        } else if c == $43 or c == $63 {            ; 'C' / 'c' -- clear
            acc = 0.0
            cur = 0.0
            frac = 0.0
            op = 0
            typing = 0
            err = 0
            note = &msg_clr
        } else {
            return
        }
        show()
    }

    sub click(uword ex, uword ey) {
        if ex >= 520 and ex < 620 and ey >= 448 and ey < 472
            cx.exit()                               ; the exit button
        if ex >= GX and ey >= GY {
            ubyte col = ((ex - GX) / STEP) as ubyte
            ubyte row = ((ey - GY) / ROWSTEP) as ubyte
            if row == 4 {
                if ex < GX + CLEARW and (ey - GY) % ROWSTEP < CH
                    feed($43)                       ; the wide clear button
            } else if col < 4 and row < 4 and (ex - GX) % STEP < CW and (ey - GY) % ROWSTEP < CH {
                feed(keys[row * 4 + col])
            }
        }
    }

    ; a headless proof the float maths work: 2 + 3 = 5, through apply() so it
    ; draws nothing (runs before gfx_init); leaves the state cleared
    sub selftest() -> bool {
        acc = 2.0
        op = $2b
        cur = 3.0
        apply()
        bool ok = acc == 5.0
        acc = 0.0
        cur = 0.0
        frac = 0.0
        op = 0
        typing = 0
        err = 0
        return ok
    }

    ; CHROUT a NUL-terminated byte string through the KERNAL (raw ASCII, so
    ; the headless boot grep matches). "CALC P8 UP\r" / "CALC P8 OK\r"
    ubyte[] m_up = [$43,$41,$4c,$43,$20,$50,$38,$20,$55,$50,$0d,0]
    ubyte[] m_ok = [$43,$41,$4c,$43,$20,$50,$38,$20,$4f,$4b,$0d,0]

    sub emit(uword ptr) {
        ubyte b = @(ptr)
        while b != 0 {
            cbm.CHROUT(b)
            ptr++
            b = @(ptr)
        }
    }
}
