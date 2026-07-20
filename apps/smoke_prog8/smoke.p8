; Prog8
; =====================================================================
; CXGEOS :: apps/smoke_prog8/smoke.p8 -- the Prog8 SDK smoke test
; =====================================================================
; Proves the GENERATED Prog8 binding (sdk/include_prog8/cxgeos.p8) drives
; the kernel through the jump table. Prints a start marker, makes a spread
; of calls through the binding -- register-only extsubs and the block
; asmsub shims -- prints an OK marker, and exits to the shell. Headless:
; the boot smoke greps stdout for "SMOKE PROG8 OK".
;   java -jar prog8c.jar -target cx16 -srcdirs sdk\include_prog8 -out build smoke.p8
; =====================================================================

%import syslib
%import cxgeos
%zeropage basicsafe
%option no_sysinit      ; REQUIRED: a CXGEOS app is a guest; don't reset the machine (see cxgeos.p8)
%zpreserved $02,$5f     ; REQUIRED: keep Prog8 vars out of the kernel's zp (see cxgeos.p8)

main {
    ; the headless markers as explicit ASCII bytes (a number is not
    ; PETSCII-translated the way a "string"/'char' literal is), so the
    ; boot smoke's ASCII grep matches. "SMOKE PROG8 UP\r" / "...OK\r"
    ubyte[] m_up = [83,77,79,75,69,32,80,82,79,71,56,32,85,80,13,0]
    ubyte[] m_ok = [83,77,79,75,69,32,80,82,79,71,56,32,79,75,13,0]
    str hello = iso:"hi from prog8, through the jump table"

    sub start() {
        emit(&m_up)                     ; load + run worked

        cx.gfx_init()                   ; a no-arg extsub
        cx.gfx_clear(0)                 ; a byte arg (A)
        cx.say(&hello, 24, 200)         ; a shim: pointer + two block words
        cx.gfx_frame(20, 20, 300, 160, 3)   ; a shim: four block words + a byte
        cx.gfx_circle(160, 120, 40, 3)  ; a shim: words + a P-block byte
        cx.gfx_disc(260, 120, 20, 2)

        ; a RETURNING extsub: only print the pass line if the kernel reports
        ; the ABI version we were built against (proves the -> uword @AX path)
        if lsb(cx.version()) == cx.ABI_VERSION
            emit(&m_ok)                 ; survived every call -> the pass line
        cx.exit()                       ; back to the shell (never returns)
    }

    ; CHROUT a NUL-terminated byte string through the KERNAL
    sub emit(uword ptr) {
        ubyte b = @(ptr)
        while b != 0 {
            cbm.CHROUT(b)
            ptr++
            b = @(ptr)
        }
    }
}
