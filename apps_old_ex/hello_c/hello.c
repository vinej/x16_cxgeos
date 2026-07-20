/* =====================================================================
 * CXGEOS :: apps/hello_c/hello.c -- the C hello (llvm-mos)
 * =====================================================================
 * The same app as apps/hello_asm, in C, and the smallest example of the
 * csdk: no private helpers, no hand-packed parameter block -- just the
 * named cx_* calls and a cx_event. It leaves through cx_exit, which
 * reloads the shell; main never returns, and must not.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxgeos.h"
#include "csdk/cxsdk.h"

static unsigned char fontbuf[1024];    /* PXL8.CXF is 871 bytes */

int main(void) {
    static char abi_line[] = "the kernel says this is ABI version ?";
    unsigned char frame0;
    cx_event ev;

    cx_print("HELLO C UP");

    cx_clear(2);                 /* its own paper, like the asm hello */
    abi_line[sizeof(abi_line) - 2] = '0' + (cx_version() & 0xFF);

    cx_say("hello from C, through the csdk this time.", 24, 200);
    cx_say(abi_line, 24, 224);
    cx_say("a key -- or three seconds -- returns to the shell.", 24, 260);

    /* the pluggable-font path, end to end: any .CXF on the disk loads
     * with cx_file_load and becomes the face with cx_font. This one
     * reloads the system font, so the proof is that the line below
     * still renders -- swap the name for your own fontconv.py output. */
    if (cx_file_load("PXL8.CXF", fontbuf, sizeof fontbuf) > 0 &&
        cx_font(fontbuf) == 0)
        cx_say("this line is set in a font loaded off the disk.", 24, 296);

    cx_ev_init();
    frame0 = cx_frames();

    for (;;) {
        /* cx_poll hides the "nothing there" carry C cannot see */
        if (cx_poll(&ev) && ev.type == CX_ET_KEY)
            break;
        if ((unsigned char)(cx_frames() - frame0) >= 180)
            break;
    }

    cx_exit(); /* never returns */
    return 0;
}
