/* =====================================================================
 * CXRF :: apps/gfx8hi/gfx8hi.c -- the 640x480 256-colour mode (VERA_2)
 * =====================================================================
 * The top depth of the 640x480 umbrella: cx_mode(CX_MODE_BMPHIGH, 8)
 * swaps the kernel's engine to a 640x480 @ 8bpp bitmap on VERA_2 -- the
 * MiSTer core's second video plane (the emulator wants -bitmap2). The
 * SAME csdk drawing calls -- cx_clear, cx_rect, cx_frame, cx_line, and
 * the shapes (cx_disc/cx_circle/cx_ellipse) -- now paint a 640x480
 * canvas in colours 0-255.
 *
 * VERA_2 keeps its OWN palette, separate from VERA's (so cx_pal_set,
 * which writes the VERA palette, does not reach it). You load it through
 * the three registers at $9F66-$9F68: write the start index once, then
 * LO (G<<4|B) and HI (R) per entry, the index auto-advancing. Here that
 * is the same four-band spectrum the mode-1 demo uses -- grey, red,
 * green, blue ramps.
 *
 * It draws the 256-colour spectrum full width, frames it, throws a few
 * shapes below, then reads one pixel back to prove the plane took the
 * ink -- prints GFX8HI OK / GFX8HI FAIL and exits. cx_exit reloads the
 * desktop, which restores the GUI mode (and turns VERA_2 back off) on
 * its own -- an app cannot strand the machine on the second plane.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxrf.h"
#include "csdk/cxsdk.h"

/* VERA_2's palette port: index, then LO = G<<4|B and HI = R per entry */
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

    cx_print("GFX8HI UP");

    cx_mode(CX_MODE_BMPHIGH, 8);              /* 640x480 8bpp on VERA_2 */

    /* the VERA_2 palette: colour i = band (i>>6) -- grey / red / green /
     * blue -- ramped by the low six bits. Index auto-advances after HI. */
    VERA2_PAL_IDX = 0;
    for (i = 0; i < 256; i++) {
        unsigned char v = (unsigned char)((i & 63) >> 2);   /* 0..15 */
        unsigned char r = 0, g = 0, b = 0;
        switch (i >> 6) {
        case 0: r = g = b = v; break;
        case 1: r = v; break;
        case 2: g = v; break;
        case 3: b = v; break;
        }
        VERA2_PAL_LO = (unsigned char)((g << 4) | b);
        VERA2_PAL_HI = r;
    }

    cx_clear(0);
    cx_screen_info(&sc);                     /* 640 x 480, bpp 8, stride 640 */

    /* the spectrum: 256 columns, two pixels each, centred (512 wide) */
    for (i = 0; i < 256; i++)
        cx_rect(64 + i * 2, 48, 2, 220, (unsigned char)i);
    cx_frame(62, 46, 516, 224, 15);          /* white frame around it */

    /* the shapes ride the port, so they paint here too */
    cx_disc(170, 390, 60, 200);              /* a bright blue disc      */
    cx_circle(170, 390, 72, 15);             /* a pale ring around it   */
    cx_fellipse(430, 390, 96, 48, 175);      /* a filled green ellipse  */
    cx_ellipse(430, 390, 108, 60, 15);       /* ...in a white outline   */
    cx_line(64, 470, 576, 470, 79);          /* a red baseline          */

    cx_rect(556, 8, 60, 28, 207);            /* a blue chip, top right  */
    cx_rect(0, sc.h - 6, sc.w, 6, 63);       /* a width-wide foot bar   */

    /* prove the plane took the ink: the chip's centre should read 207 */
    ok = (cx_pget(586, 22) == 207);
    cx_print(ok ? "GFX8HI OK" : "GFX8HI FAIL");

    exit_button(&sc, 79, 15, 15, 1);   /* red close box; click it or a key to quit */
    cx_exit();  /* never returns; the desktop restores the GUI mode */
    return 0;
}
