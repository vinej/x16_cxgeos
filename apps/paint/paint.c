/* =====================================================================
 * CXRF :: apps/paint/paint.c -- a small paint program (llvm-mos)
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
 * Click feedback: a DOWN on a toolbar button redraws it "pressed" (the
 * highlight fill of cx_button_down) and the matching UP redraws it normal
 * -- so a click flashes, the way the toolkit's own WG_BUTTON does. An
 * immediate-mode app owns WHEN to flash; the SDK just gives it the two
 * painters (cx_button / cx_button_down) so the look matches the toolkit.
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
#include "sdk/include_llvm/cxrf.h"
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

/* the toolbar + exit buttons: geometry and label. The index IS the action
 * (see the CX_ET_DOWN switch). Kept in a table so one can be redrawn
 * pressed without repeating its rectangle. */
typedef struct { unsigned x, y, w, h; const char *label; } paint_btn;
static const paint_btn BTN[] = {
    {  10,   8,  90, 24, "pencil" },  /* 0 */
    { 110,   8,  90, 24, "eraser" },  /* 1 */
    { 220,   8,  90, 24, "save"   },  /* 2 */
    { 320,   8,  90, 24, "load"   },  /* 3 */
    { 430,   8,  90, 24, "clear"  },  /* 4 */
    { 520, 448, 100, 24, "exit"   },  /* 5 */
};
#define NBTN 6
static signed char held = -1;         /* the button drawn pressed, or -1  */

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

/* draw button i normal, or pressed (the highlight-fill click feedback) */
static void draw_button(unsigned char i, unsigned char pressed) {
    const paint_btn *b = &BTN[i];
    if (pressed) cx_button_down(b->x, b->y, b->w, b->h, b->label);
    else         cx_button(b->x, b->y, b->w, b->h, b->label);
}

static void redraw(void) {
    unsigned char i;
    cx_clear(PAPER);
    for (i = 0; i < NBTN; i++) draw_button(i, i == held);
    cx_frame(CV_X - 2, CV_Y - 2, CV_W + 4, CV_H + 4, INK);   /* the sheet */
    status();
}

/* which button INDEX is at (x, y)? -1 = none. */
static signed char hit_button(unsigned x, unsigned y) {
    unsigned char i;
    for (i = 0; i < NBTN; i++) {
        const paint_btn *b = &BTN[i];
        if (x >= b->x && x < b->x + b->w && y >= b->y && y < b->y + b->h)
            return (signed char)i;
    }
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
            if (b >= 0) {
                draw_button(b, 1);               /* press feedback (held) */
                held = b;
                if (b == 0)      { tool = T_PENCIL; msg = "pencil."; status(); }
                else if (b == 1) { tool = T_ERASE;  msg = "eraser."; status(); }
                else if (b == 2) do_save();
                else if (b == 3) do_load();
                else if (b == 4) {               /* clear the sheet */
                    cx_rect(CV_X, CV_Y, CV_W, CV_H, PAPER);
                    have_last = 0; msg = "cleared."; status();
                }
                else if (b == 5) goto done;      /* exit */
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
            if (held >= 0) { draw_button(held, 0); held = -1; }  /* release */
            pendown = 0; have_last = 0;
            break;
        }
    }
done:
    cx_exit(); /* never returns */
    return 0;
}
