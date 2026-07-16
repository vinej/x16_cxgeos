/* =====================================================================
 * CXGEOS :: apps/hello_c/hello.c -- the C hello (llvm-mos)
 * =====================================================================
 * The other half of the Phase 4 milestone: the same app as
 * apps/hello_asm, in C, built against sdk/include_llvm/cxgeos.h alone.
 * Everything it does goes through the jump table; the compiler's only
 * jobs are register discipline (llvm-mos puts the first two u8 args in
 * A and X, which is exactly what the slots want) and being pleasant to
 * write in.
 *
 * It leaves through CX_EXIT, which reloads the shell -- main never
 * returns, and must not: the C runtime's exit path would rts into a
 * BASIC that is no longer standing behind this program.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxgeos.h"

#define EV_KEY 5

static void say(const char *s, unsigned int x, unsigned int y) {
    cx_p[0] = x & 0xFF;
    cx_p[1] = x >> 8;
    cx_p[2] = y & 0xFF;
    cx_p[3] = y >> 8;
    cx_call_p(CX_FONT_DRAW, s);
}

static void marker(const char *s) {
    while (*s)
        cbm_k_chrout(*s++);
    cbm_k_chrout('\r');
}

int main(void) {
    static char abi_line[] = "the kernel says this is ABI version ?";
    unsigned char frame0;

    marker("HELLO C UP");

    cx_call_a(CX_GFX_CLEAR, 2);  /* its own paper, like the asm hello */

    abi_line[sizeof(abi_line) - 2] = '0' + (cx_ret16(CX_VERSION) & 0xFF);

    say("hello from C, through the same jump table.", 24, 200);
    say(abi_line, 24, 224);
    say("a key -- or three seconds -- returns to the shell.", 24, 260);

    cx_call(CX_EV_INIT);
    frame0 = cx_ret(CX_EV_FRAMES);

    for (;;) {
        /* CX_EV_GET reports "nothing there" in the carry flag, which C
         * cannot see -- so ask CX_EV_COUNT first and only get what is
         * certainly there. */
        if (cx_ret(CX_EV_COUNT)) {
            cx_call(CX_EV_GET);
            if (cx_p[0] == EV_KEY)
                break;
        }
        if ((unsigned char)(cx_ret(CX_EV_FRAMES) - frame0) >= 180)
            break;
    }

    cx_call(CX_EXIT); /* never returns */
}
