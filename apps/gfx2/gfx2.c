/* =====================================================================
 * CXRF :: apps/gfx2/gfx2.c -- the 320x240 4-colour mode (mode 1, 2bpp)
 * =====================================================================
 * cx_mode(CX_MODE_BMPLOW, 2) selects the 320x240 bitmap at 2bpp -- four
 * colours, shown fullscreen (2:1), on standard VERA. The palette is the
 * ordinary one at $1FA00. The same drawing calls paint it, with colours
 * 0-3.
 *
 * It loads a 4-entry palette (black / red / green / blue), draws the four
 * bars, frames them, adds lines and shapes, then reads a pixel back.
 * Self-verifying (GFX2 OK / GFX2 FAIL); cx_exit restores the desktop.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxrf.h"
#include "csdk/cxsdk.h"

/* four VERA entries: LO = G<<4|B, HI = R -- black, red, green, blue */
static const unsigned char pal[8] = {
    0x00, 0x00,   /* 0 black */
    0x00, 0x0F,   /* 1 red   */
    0xF0, 0x00,   /* 2 green */
    0x0F, 0x00,   /* 3 blue  */
};

/* Draw a close box at the bottom-right, then wait -- a click on it (or any
 * key) exits. `passthru` != 0 is a mode-4 (VERA_2) demo: set CTRL bit 3 so
 * VERA's hardware sprites -- sprite 0 is the KERNAL mouse -- composite OVER
 * the bitmap (the engine already turned the VERA layers off). Does NOT
 * auto-exit, so the picture stays up. */
static void exit_button(cx_screen *sc, unsigned char fill, unsigned char edge,
                        unsigned char xcol, unsigned char passthru) {
    unsigned bw = sc->w / 6, bh = sc->h / 12;
    unsigned bx = (unsigned)(sc->w - bw - 4), by = (unsigned)(sc->h - bh - 4);
    cx_event ev;
    cx_rect(bx, by, bw, bh, fill);
    cx_frame(bx, by, bw, bh, edge);
    cx_line(bx + 4, by + 4, bx + bw - 5, by + bh - 5, xcol);
    cx_line(bx + 4, by + bh - 5, bx + bw - 5, by + 4, xcol);
    if (passthru)
        *(volatile unsigned char *)0x9F60U |= 0x08;
    cx_mouse_show(1);
    cx_ev_init();
    cx_ev_mask(CX_EVS_MOUSE | CX_EVS_KEYS);
    for (;;) {
        if (cx_poll(&ev)) {
            if (ev.type == CX_ET_KEY)
                return;
            if (ev.type == CX_ET_DOWN &&
                ev.x >= bx && ev.x < bx + bw && ev.y >= by && ev.y < by + bh)
                return;
        }
    }
}

int main(void) {
    unsigned char i, ok;
    cx_screen sc;

    cx_print("GFX2 UP");

    cx_mode(CX_MODE_BMPLOW, 2);               /* 320x240 2bpp, 4 colours */
    cx_vram_write(0x1FA00UL, (void *)pal, 8);

    cx_clear(0);
    cx_screen_info(&sc);                    /* 320 x 240, bpp 2 */

    for (i = 0; i < 4; i++)                 /* four wide colour bars */
        cx_rect(20 + i * 70, 24, 70, 110, i);
    cx_frame(18, 22, 284, 114, 1);

    cx_disc(90, 190, 30, 1);                /* a red disc, green ring   */
    cx_circle(90, 190, 36, 2);
    cx_fellipse(220, 190, 46, 22, 3);       /* a blue ellipse, red edge */
    cx_ellipse(220, 190, 52, 28, 1);
    cx_line(20, 236, 300, 210, 2);          /* a green diagonal         */
    cx_hline(20, 12, 280, 3);               /* a blue rule at the top   */
    cx_rect(276, 4, 26, 12, 2);             /* a green chip (colour 2)  */

    ok = (cx_pget(289, 10) == 2);           /* the chip should read 2   */
    cx_print(ok ? "GFX2 OK" : "GFX2 FAIL");

    exit_button(&sc, 1, 3, 3, 0);
    cx_exit();
    return 0;
}
