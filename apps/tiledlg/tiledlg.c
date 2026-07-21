/* =====================================================================
 * CXGEOS :: apps/tiledlg/tiledlg.c -- a modal PANEL of widgets on a tile game
 * =====================================================================
 * The payoff of cx_tile_text: a game in tile mode can raise the SAME
 * modal toolkit a desktop app uses. Here it is cx_panel -- a full box of
 * widgets (a checkbox, two radios, a slider, a text field, OK / Cancel) --
 * drawn on a text layer over the still-visible world:
 *
 *   cx_tile_text(1, 1)   layer 1 -> a 1bpp text layer; the port -> OV3T
 *   cx_panel(&form)      the kernel's modal panel, on those cells
 *   cx_tile_text(1, 0)   layer 1 -> the game's 4bpp map again, instant
 *
 * Coordinates are CELLS (a 40x30 grid) and every widget is ONE cell tall
 * -- the same convention the mode-3 TUI uses (the C CX_CHECK/... macros
 * hard-code PIXEL heights, so a cell panel lays the records down itself).
 * Every text-drawable widget renders here; the two that can't are WG_ICON
 * (a bitmap icon) and WG_HIT (you draw its own pixels).
 *
 * The world scrolls while you play and FREEZES under the panel (it owns
 * the loop). SPACE opens it; TAB moves focus, SPACE toggles, arrows drive
 * a slider, RETURN = OK, ESC = Cancel -- or drive it with the MOUSE, which
 * the app switches on just for the panel and off again after (the game
 * itself is keyboard-only). It also auto-opens once for a headless capture.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxgeos.h"
#include "csdk/cxsdk.h"

static const char t_opts[]   = "Options";
static const char t_sound[]  = "Sound effects";
static const char t_easy[]   = "Easy";
static const char t_hard[]   = "Hard";
static const char t_ok[]     = "OK";
static const char t_cancel[] = "Cancel";
static char       fieldbuf[13] = "player";

/* the widget list in CELL units -- every widget one cell tall (h = 1).
 * Fields are {type, flags, x, y, w, h, val, grp, label, pad}. */
static struct CX_PACKED {
    unsigned char n;
    cx_widget     w[5];
} opts = { 5, {
    { CX_WG_CHECK,  0,  8,  8, 22, 1, 1,  0, t_sound,  {0,0,0} },  /* on */
    { CX_WG_RADIO,  0,  8, 10, 20, 1, 1,  1, t_easy,   {0,0,0} },  /* group 1, on */
    { CX_WG_RADIO,  0,  8, 12, 20, 1, 0,  1, t_hard,   {0,0,0} },  /* group 1 */
    { CX_WG_SCROLL, 0,  8, 14, 20, 1, 3,  9, 0,        {0,0,0} },  /* 0..9, at 3 */
    { CX_WG_FIELD,  0,  8, 16, 22, 1, 0, 12, fieldbuf, {0,0,0} },  /* cap 12 */
} };

/* the panel descriptor: box (cells), title, the widget list, buttons */
static const struct CX_PACKED {
    unsigned      x, y, w;
    unsigned char h;
    const void   *title;
    const void   *widgets;
    unsigned char nbtn;
    const void   *btn[2];
} form = { 4, 4, 32, 21, t_opts, &opts, 2, { t_ok, t_cancel } };

static unsigned char tile[32];

int main(void) {
    unsigned char i, opened = 0;
    unsigned h = 0;
    cx_event ev;

    cx_print("TILEDLG UP");
    cx_mode(CX_MODE_TILE);

    /* a 4x4 blue/white checker world on layer 0 */
    for (i = 0; i < 32; i++) {
        unsigned char row = i >> 2, col = i & 3;
        tile[i] = (((row >> 2) ^ (col >> 1)) & 1) ? 0x66 : 0x11;
    }
    cx_vram_write(CX_TILE_IMG, tile, 32);
    cx_tile_setup(0);
    cx_tile_fill(0, CX_CELL(0, 0));


    cx_ev_init();
    cx_ev_mask(CX_EVS_KEYS);

    for (;;) {
        unsigned char open_now = 0;

        if (cx_poll(&ev)) {
            if (ev.type == CX_ET_KEY) {
                if (ev.detail == CX_K_SPACE) open_now = 1;
                else if (ev.detail == CX_K_ESC) break;
            }
        } else {
            unsigned char t = cx_frames();          /* ~30/s idle drift */
            while ((unsigned char)(cx_frames() - t) < 2)
                ;
            h = (h + 2) & 0x0FFF;
            cx_tile_scroll(0, h, 0);
            if (!opened && h > 40) open_now = 1;     /* auto-open once */
        }

        if (open_now) {
            opened = 1;
            cx_tile_text(1, 1);                 /* text overlay + OV3T port */
            cx_tile_fill(1, 0x20);              /* clear: the world shows through */
            cx_mouse_show(1);                   /* the default arrow, to click the widgets */
            cx_ev_mask(CX_EVS_KEYS | CX_EVS_MOUSE);
            cx_panel(&form);                    /* the modal widget panel, on tiles */
            cx_ev_mask(CX_EVS_KEYS);            /* the game is keyboard-only again */
            cx_mouse_hide();
            cx_tile_text(1, 0);                 /* the game map back, untouched */
        }
    }

    cx_exit();
    return 0;
}
