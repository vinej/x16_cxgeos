/* =====================================================================
 * CXGEOS :: apps/paint/paint.c -- a small paint program (llvm-mos)
 * =====================================================================
 * The mouse example: freehand drawing, plus a saved picture. Two tools
 * -- a 1-pixel PENCIL and a chunky ERASER -- both driven by dragging the
 * mouse; a SAVE and a LOAD that stream the canvas to PAINT.DAT; and an
 * EXIT button. Deliberately immediate-mode: it hit-tests its own toolbar
 * and canvas and draws straight to the screen, so it polls raw events
 * with cx_poll (not the toolkit's cx_next). That is exactly when you
 * reach for cx_poll -- you own the pixels and the hit-testing.
 *
 * Drawing: a DOWN in the canvas starts a stroke; each MOVE while the
 * button is held continues it (the pencil joins points with cx_line so a
 * fast drag has no gaps; the eraser stamps a square); UP ends it.
 *
 * Persistence: the canvas is streamed a row at a time to a SEQ file as
 * native framebuffer bytes, copied through VERA's data port rather than a
 * cx_pget/cx_pset per pixel -- those are ABI crossings, and one per pixel
 * made the first save painfully slow. The stream runs with interrupts
 * masked, the same discipline the desktop uses for file I/O: the event
 * IRQ calls GETIN (which would steal file bytes) and moves the mouse
 * sprite (which would disturb VERA), and neither may run mid-transfer.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxgeos.h"
#include "csdk/cxsdk.h"

/* the canvas -- width a multiple of 4 (four pixels a byte at 2bpp) */
#define CV_X   120
#define CV_Y   72
#define CV_W   400
#define CV_H   288
#define CV_R   (CV_X + CV_W)          /* one past the right edge */
#define CV_B   (CV_Y + CV_H)          /* one past the bottom edge */

/* the paint theme's role colours: a white sheet, a black pen */
#define INK    3                      /* CX_FRAME  -- black */
#define PAPER  0                      /* CX_PAPER  -- white */
#define ERASER 12                     /* the eraser square, in pixels */

/* the two tools, and the toolbar/exit button rectangles */
#define T_PENCIL 0
#define T_ERASE  1

static unsigned char tool = T_PENCIL;
static unsigned char pendown = 0;     /* the mouse button is held         */
static unsigned char have_last = 0;   /* lastx/lasty hold a real point    */
static unsigned lastx, lasty;
static const char *msg = "draw with the mouse.";

/* a white sheet, black ink -- the same palette the desktop uses, set
 * explicitly so the canvas looks the same whatever theme we inherit */
static const cx_theme_rec paint_theme = {
    { 0xFF, 0x0F,  0xAA, 0x0A,  0x55, 0x05,  0x00, 0x00 }, 0, 1, 3, 0
};

/* =====================================================================
 * the interface
 * ===================================================================== */
static void status(void) {
    cx_rect(10, 44, 620, 14, PAPER);
    cx_say(tool == T_PENCIL ? "pencil" : "eraser", 10, 46);
    cx_say(msg, 110, 46);
}

static void redraw(void) {
    cx_clear(PAPER);
    cx_button(10,  8, 90, 24, "pencil");
    cx_button(110, 8, 90, 24, "eraser");
    cx_button(220, 8, 90, 24, "save");
    cx_button(320, 8, 90, 24, "load");
    cx_button(430, 8, 90, 24, "clear");
    cx_button(520, 448, 100, 24, "exit");
    cx_frame(CV_X - 2, CV_Y - 2, CV_W + 4, CV_H + 4, INK);   /* the sheet */
    status();
}

/* which button is at (x, y)? -1 = none. y=8..32 is the toolbar row. */
static signed char hit_button(unsigned x, unsigned y) {
    if (y >= 448 && y < 472 && x >= 520 && x < 620) return 4;   /* exit */
    if (y < 8 || y >= 32) return -1;
    if (x >= 10  && x < 100) return 0;                          /* pencil */
    if (x >= 110 && x < 200) return 1;                          /* eraser */
    if (x >= 220 && x < 310) return 2;                          /* save   */
    if (x >= 320 && x < 410) return 3;                          /* load   */
    if (x >= 430 && x < 520) return 5;                          /* clear  */
    return -1;
}

static unsigned char in_canvas(unsigned x, unsigned y) {
    return x >= CV_X && x < CV_R && y >= CV_Y && y < CV_B;
}

/* =====================================================================
 * drawing
 * ===================================================================== */
/* the eraser: a square of paper, clamped to stay inside the sheet */
static void erase_at(unsigned x, unsigned y) {
    unsigned ex = x - ERASER / 2, ey = y - ERASER / 2;
    unsigned ew = ERASER, eh = ERASER;
    if (ex < CV_X) { ew -= (CV_X - ex); ex = CV_X; }
    if (ey < CV_Y) { eh -= (CV_Y - ey); ey = CV_Y; }
    if (ex + ew > CV_R) ew = CV_R - ex;
    if (ey + eh > CV_B) eh = CV_B - ey;
    if (ew && eh) cx_rect(ex, ey, ew, eh, PAPER);
}

/* extend the current stroke to (x, y) */
static void stroke(unsigned x, unsigned y) {
    if (tool == T_PENCIL) {
        if (have_last) cx_line(lastx, lasty, x, y, INK);   /* joined, no gaps */
        else           cx_pset(x, y, INK);                 /* the first dot   */
    } else {
        erase_at(x, y);
    }
    lastx = x; lasty = y; have_last = 1;
}

/* =====================================================================
 * save / load -- the whole canvas is one csdk call
 * =====================================================================
 * cx_pic_save / cx_pic_load stream the framebuffer rectangle to/from a
 * SEQ file through VERA (docs: csdk/README). The old per-pixel version
 * lived here; it now belongs to the csdk, where any app can reach it.
 */
static void do_save(void) {
    msg = "saving..."; status();
    cx_pic_save("PAINT.DAT", CV_X, CV_Y, CV_W, CV_H);
    msg = "saved."; status();
}

static void do_load(void) {
    msg = "loading..."; status();
    msg = cx_pic_load("PAINT.DAT", CV_X, CV_Y, CV_W, CV_H)
              ? "loaded." : "no saved paint yet.";
    status();
}

/* =====================================================================
 * the main loop -- raw events, hit-tested here
 * ===================================================================== */
int main(void) {
    cx_event ev;

    cx_print("PAINT UP");

    cx_gfx_init();
    cx_theme(&paint_theme);
    redraw();
    cx_ev_init();
    cx_mouse_show(1);

    for (;;) {
        if (!cx_poll(&ev))
            continue;
        switch (ev.type) {
        case CX_ET_KEY:
            if (ev.detail == CX_K_ESC)
                goto done;                       /* ESC also leaves */
            break;
        case CX_ET_DOWN: {
            signed char b = hit_button(ev.x, ev.y);
            if (b == 4) goto done;               /* exit */
            else if (b == 0) { tool = T_PENCIL; msg = "pencil."; status(); }
            else if (b == 1) { tool = T_ERASE;  msg = "eraser."; status(); }
            else if (b == 2) do_save();
            else if (b == 3) do_load();
            else if (b == 5) {                   /* clear the sheet */
                cx_rect(CV_X, CV_Y, CV_W, CV_H, PAPER);
                have_last = 0; msg = "cleared."; status();
            }
            else if (in_canvas(ev.x, ev.y)) {
                pendown = 1; have_last = 0;
                stroke(ev.x, ev.y);
            }
            break;
        }
        case CX_ET_MOVE:
            if (pendown) {
                if (in_canvas(ev.x, ev.y)) stroke(ev.x, ev.y);
                else have_last = 0;              /* left the sheet: break the line */
            }
            break;
        case CX_ET_UP:
            pendown = 0; have_last = 0;
            break;
        }
    }
done:
    cx_exit(); /* never returns */
    return 0;
}
