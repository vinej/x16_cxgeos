/* =====================================================================
 * CXRF :: apps/gfx4/gfx4.c -- the 320x240 16-colour mode (mode 1, 4bpp)
 * =====================================================================
 * cx_mode(CX_MODE_BMPLOW, 4) selects the 320x240 bitmap at 4bpp -- the same
 * mode-1 personality as the 8bpp demo, one depth down: 16 colours, shown
 * fullscreen (2:1). The framebuffer is on standard VERA, so the palette is
 * the ordinary one at $1FA00 (cx_vram_write, or cx_pal_set). The SAME
 * drawing calls paint it.
 *
 * It loads a 16-entry palette (four 4-level bands: grey/red/green/blue),
 * draws the colour bars, frames them, throws the shapes below, then reads
 * a pixel back to prove the depth took the ink. Self-verifying
 * (GFX4 OK / GFX4 FAIL); cx_exit restores the desktop.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxrf.h"
#include "csdk/cxsdk.h"

static unsigned char pal[32];

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
    unsigned i;
    unsigned char ok;
    cx_screen sc;

    cx_print("GFX4 UP");

    cx_mode(CX_MODE_BMPLOW, 4);               /* 320x240 4bpp, 16 colours */

    /* 16 colours: band (i>>2) grey/red/green/blue, level (i&3) */
    for (i = 0; i < 16; i++) {
        unsigned char v = (unsigned char)((i & 3) * 5);   /* 0,5,10,15 */
        unsigned char r = 0, g = 0, b = 0;
        switch (i >> 2) {
        case 0: r = g = b = v; break;
        case 1: r = v; break;
        case 2: g = v; break;
        case 3: b = v; break;
        }
        pal[i * 2]     = (unsigned char)((g << 4) | b);
        pal[i * 2 + 1] = r;
    }
    cx_vram_write(0x1FA00UL, pal, 32);

    cx_clear(0);
    cx_screen_info(&sc);                    /* 320 x 240, bpp 4 */

    for (i = 0; i < 16; i++)                /* 16 colour bars, 18px each */
        cx_rect(16 + i * 18, 24, 18, 120, (unsigned char)i);
    cx_frame(14, 22, 292, 124, 15);

    cx_disc(80, 195, 28, 9);                /* a red disc + ring        */
    cx_circle(80, 195, 34, 15);
    cx_fellipse(220, 195, 44, 22, 10);      /* a green ellipse + outline */
    cx_ellipse(220, 195, 50, 28, 15);
    cx_line(16, 236, 304, 210, 6);          /* a blue diagonal          */
    cx_rect(276, 6, 30, 12, 5);             /* a red chip (colour 5)    */
    cx_rect(0, sc.h - 4, sc.w, 4, 7);       /* a foot bar               */

    ok = (cx_pget(291, 12) == 5);           /* the chip should read 5   */
    cx_print(ok ? "GFX4 OK" : "GFX4 FAIL");

    exit_button(&sc, 5, 3, 3, 0);
    cx_exit();
    return 0;
}
