/* =====================================================================
 * CXRF :: apps/text/text.c -- the text-mode example (llvm-mos)
 * =====================================================================
 * cx_mode(CX_MODE_TEXT) hands the screen to the KERNAL's 80x60 text
 * grid -- a CHARACTER surface, not pixels. The SAME csdk calls work,
 * reinterpreted as cell operations: coordinates are cells (0-79 x
 * 0-59) and "colour" is a 16-colour attribute.
 *
 * cx_clear / cx_rect fill cells with a colour (and set the "paper" that
 * later drawing sits on). cx_frame draws a real box in the PETSCII
 * frame glyphs; cx_hline / cx_vline are ruled lines; cx_line works for
 * horizontal and vertical runs and refuses diagonals (carry). pattern /
 * blit have no grid meaning and refuse. On exit the desktop restores
 * the GUI on its own.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxrf.h"
#include "csdk/cxsdk.h"

int main(void) {
    cx_event ev;

    cx_print("TEXT UP");

    cx_mode(CX_MODE_TEXT, 0);

    cx_clear(6);                         /* a blue screen (white ink)    */
    cx_say("CXRF -- 80x60 text mode", 27, 1);
    cx_say("boxes, rules and panels, in text cells", 20, 3);

    cx_frame(18, 6, 44, 12, 5);          /* a green box on the blue      */
    cx_rect(20, 8, 40, 8, 2);            /* a red panel inside it        */
    cx_say("a colour-filled panel", 30, 11);   /* white on red          */

    cx_rect(0, 20, 80, 1, 6);            /* paper back to blue for...    */
    cx_hline(10, 21, 60, 7);             /* ...a yellow rule             */
    cx_line(5, 24, 5, 34, 13);           /* a vertical cx_line           */
    cx_line(8, 29, 40, 29, 13);          /* a horizontal one             */

    cx_say("cx_line draws rules too -- diagonals refuse", 12, 26);

    cx_ink(7);                           /* 0.4.0: say in a colour       */
    cx_say("and cx_ink colours the text", 12, 31);
    cx_ink(1);

    cx_say("any key exits -- the desktop comes back", 20, 36);

    cx_ev_init();
    for (;;) {
        if (cx_poll(&ev) && ev.type == CX_ET_KEY)
            break;
    }
    cx_exit();
    return 0;
}
