/* =====================================================================
 * CXRF :: apps/gfx4hi/gfx4hi.c -- the 640x480 16-colour mode (VERA_2)
 * =====================================================================
 * cx_mode(CX_MODE_BMPHIGH, 4) selects the 640x480 bitmap at 4bpp on VERA_2
 * -- the second video plane (the emulator wants -bitmap2), the same mode-4
 * personality as the 8bpp demo, one depth down: 16 colours. VERA_2 keeps
 * its own palette (cx_pal_set writes VERA's, not this one), loaded through
 * the registers at $9F66-$9F68.
 *
 * It loads a 16-entry palette (four 4-level bands), draws the colour bars
 * full width, frames them, throws the shapes below, then reads a pixel
 * back. Self-verifying (GFX4HI OK / GFX4HI FAIL); cx_exit restores the
 * desktop and turns VERA_2 back off.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxrf.h"
#include "csdk/cxsdk.h"

#define VERA2_PAL_IDX (*(volatile unsigned char *)0x9F66U)
#define VERA2_PAL_LO  (*(volatile unsigned char *)0x9F67U)
#define VERA2_PAL_HI  (*(volatile unsigned char *)0x9F68U)

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

    cx_print("GFX4HI UP");

    cx_mode(CX_MODE_BMPHIGH, 4);              /* 640x480 4bpp on VERA_2 */

    VERA2_PAL_IDX = 0;                      /* 16 colours: grey/red/green/blue */
    for (i = 0; i < 16; i++) {
        unsigned char v = (unsigned char)((i & 3) * 5);   /* 0,5,10,15 */
        unsigned char r = 0, g = 0, b = 0;
        switch (i >> 2) {
        case 0: r = g = b = v; break;
        case 1: r = v; break;
        case 2: g = v; break;
        case 3: b = v; break;
        }
        VERA2_PAL_LO = (unsigned char)((g << 4) | b);
        VERA2_PAL_HI = r;
    }

    cx_clear(0);
    cx_screen_info(&sc);                    /* 640 x 480, bpp 4 */

    for (i = 0; i < 16; i++)                /* 16 colour bars, 32px each */
        cx_rect(64 + i * 32, 48, 32, 220, (unsigned char)i);
    cx_frame(62, 46, 516, 224, 15);

    cx_disc(170, 390, 60, 9);               /* a red disc + ring        */
    cx_circle(170, 390, 72, 15);
    cx_fellipse(430, 390, 96, 48, 10);      /* a green ellipse + outline */
    cx_ellipse(430, 390, 108, 60, 15);
    cx_line(64, 470, 576, 470, 6);          /* a blue baseline          */
    cx_rect(556, 8, 60, 28, 5);             /* a red chip (colour 5)    */
    cx_rect(0, sc.h - 6, sc.w, 6, 7);       /* a foot bar               */

    ok = (cx_pget(586, 22) == 5);           /* the chip should read 5   */
    cx_print(ok ? "GFX4HI OK" : "GFX4HI FAIL");

    exit_button(&sc, 5, 3, 3, 1);
    cx_exit();
    return 0;
}
