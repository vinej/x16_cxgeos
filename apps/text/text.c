/* =====================================================================
 * CXGEOS :: apps/text/text.c -- the text-mode example (llvm-mos)
 * =====================================================================
 * cx_mode(CX_MODE_TEXT) hands the screen to the KERNAL's 80x60 text
 * grid -- a CHARACTER surface, not pixels. The SAME csdk calls work,
 * reinterpreted as cell operations: coordinates are cells (0-79 x
 * 0-59) and "colour" is a 16-colour attribute. A fill sets the current
 * text colour, so a cx_say after it prints (white) on that background.
 *
 * cx_line / pattern / blit have no grid meaning and refuse (carry).
 * On exit the desktop restores the GUI on its own.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxgeos.h"
#include "csdk/cxsdk.h"

int main(void) {
    cx_event ev;

    cx_print("TEXT UP");

    cx_mode(CX_MODE_TEXT);

    cx_clear(6);                         /* a blue screen (fg white)     */
    cx_say("CXGEOS -- 80x60 text mode", 27, 1);
    cx_say("cx_clear, cx_rect, cx_frame, cx_hline, cx_say", 17, 3);

    cx_rect(20, 8, 40, 8, 2);            /* a red panel                  */
    cx_say("a colour-filled panel", 30, 11);   /* white on red          */

    cx_frame(18, 6, 44, 12, 5);          /* a green border around it     */

    cx_hline(10, 22, 60, 7);             /* a cyan rule                  */
    cx_say("any key exits -- the desktop comes back", 20, 24);

    cx_ev_init();
    for (;;) {
        if (cx_poll(&ev) && ev.type == CX_ET_KEY)
            break;
    }
    cx_exit();
    return 0;
}
