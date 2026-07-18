/* =====================================================================
 * CXGEOS :: apps/gfx8/gfx8.c -- the 256-colour mode example (llvm-mos)
 * =====================================================================
 * The graphics port's second personality: cx_mode(CX_MODE_BMP8) swaps
 * the kernel's engine to 320x240 @ 8bpp, and the SAME csdk drawing
 * calls -- cx_clear, cx_vline, cx_rect, cx_frame, cx_line -- now take
 * colours 0-255. The palette is yours: 256 VERA entries at $1FA00,
 * two bytes each, uploaded with cx_vram_write.
 *
 * This draws a 256-colour spectrum (four bands: grey, red, green,
 * blue ramps), frames it, crosses it with diagonals, and waits for a
 * key. cx_exit reloads the desktop, which lands back in the GUI mode
 * on its own -- an app cannot strand the machine in 8bpp.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxgeos.h"
#include "csdk/cxsdk.h"

static unsigned char pal[512];

int main(void) {
    unsigned i;
    cx_event ev;
    cx_screen sc;

    cx_print("GFX8 UP");

    cx_mode(CX_MODE_BMP8);

    /* the palette: colour i = band (i>>6): grey / red / green / blue,
     * ramped by the low six bits. VERA entries are GB then 0R. */
    for (i = 0; i < 256; i++) {
        unsigned char v = (unsigned char)((i & 63) >> 2);   /* 0..15 */
        unsigned char r = 0, g = 0, b = 0;
        switch (i >> 6) {
        case 0: r = g = b = v; break;
        case 1: r = v; break;
        case 2: g = v; break;
        case 3: b = v; break;
        }
        pal[i * 2]     = (unsigned char)((g << 4) | b);
        pal[i * 2 + 1] = r;
    }
    cx_vram_write(0x1FA00UL, pal, 512);

    cx_clear(0);

    /* the spectrum: 256 one-pixel columns, one per colour */
    for (i = 0; i < 256; i++)
        cx_vline(32 + i, 40, 160, (unsigned char)i);

    cx_frame(30, 38, 260, 164, 15);        /* white frame around it   */
    cx_line(0, 239, 319, 210, 79);         /* a red diagonal          */
    cx_line(0, 210, 319, 239, 143);        /* ...and a green one      */
    cx_rect(8, 8, 40, 20, 207);            /* a blue chip, top left   */

    cx_screen_info(&sc);                   /* prove the info call: put a
                                            * width-wide bar at the foot */
    cx_rect(0, sc.h - 4, sc.w, 4, 63);

    /* the shapes ride the port, so they work here too: a disc, a ring
     * around it, and a flood seeded in the moat between them -- fenced
     * by the ring, the disc, and the diagonals that cross it */
    cx_disc(250, 222, 7, 220);             /* a bright blue disc        */
    cx_circle(250, 222, 13, 15);           /* a pale ring around it     */
    cx_flood(250, 212, 110);               /* the moat's top arc, red   */

    cx_ev_init();
    for (;;) {
        if (cx_poll(&ev) && ev.type == CX_ET_KEY)
            break;
    }
    cx_exit(); /* never returns; the desktop restores the GUI mode */
    return 0;
}
