/* =====================================================================
 * CXRF :: apps/cdemo/cdemo.c -- the csdk descriptor demo (llvm-mos)
 * =====================================================================
 * The C answer to the asm gallery: a menu bar, the full widget set
 * (button, checkboxes, radios, two sliders, a text field, a list), a
 * modal dialog and two themes -- all declared as C data with the csdk's
 * descriptor macros (CX_WIDGETS / CX_MENU_BAR / CX_MENU_ITEMS /
 * CX_DIALOG / cx_theme_rec). The point is the layout: each packed struct
 * must disassemble byte-for-byte to what the kernel reads, so if a field
 * is misaligned the widgets visibly break. A working demo IS the test.
 *
 * Events come through cx_next: it routes each mouse click into the
 * widget/menu regions for us (so a click surfaces as the EV_WIDGET /
 * EV_MENU the toolkit posts) and hands back the keys, which we pass to
 * the menu bar and then the widget list, exactly as the gallery's asm
 * handler does. (cx_poll, calc's raw poll, would never route the mouse
 * to the toolkit.) It leaves through cx_exit, which reloads the shell.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxrf.h"
#include "csdk/cxsdk.h"

/* the widget list, in declaration order -- these are its indices, the
 * value that arrives in an EV_WIDGET's detail */
enum { W_EXIT, W_CHK1, W_CHK2, W_RAD0, W_RAD1, W_RAD2,
       W_SLA, W_SLB, W_FIELD, W_LIST };

static char field[32];      /* the text field's mutable buffer (cap 24) */
static const char *rows[] = { "apple", "banana", "cherry", "date", "fig" };

/* one count byte, then ten 16-byte records -- the kernel reads it in
 * place, so it is `static` (mutable): the toolkit writes state back */
CX_WIDGETS(panel,
    CX_BUTTON(520, 448, 100, 24, "exit"),
    CX_CHECK (40, 100, 160, 1, "wrap long lines"),
    CX_CHECK (40, 122, 160, 0, "show the ruler"),
    CX_RADIO (40, 160, 120, 0, 1, "left"),
    CX_RADIO (40, 182, 120, 1, 1, "centre"),
    CX_RADIO (40, 204, 120, 0, 1, "right"),
    CX_SCROLL(360, 116, 200, 2, 9),      /* value 2 (=3), max 9 (=10) */
    CX_SCROLL(360, 176, 200, 0, 4),      /* value 0 (=1), max 4 (=5)  */
    CX_FIELD (40, 290, 300, 24, field),
    CX_LIST  (360, 250, 200, 120, 5, rows));

/* the menu bar: Demo (about / quit) and Themes (day / night) */
CX_MENU_ITEMS(demo_items, "about", "quit");
CX_MENU_ITEMS(theme_items, "day", "night");
CX_MENU_BAR(bar,
    CX_MENU("Demo",   &demo_items),
    CX_MENU("Themes", &theme_items));

/* the modal about box: a message and one button */
CX_DIALOG(about, "cdemo -- the csdk descriptor builders.", "ok");

/* two 12-byte themes: four palette colours then the paper/hi/frame roles
 * (the same records the asm gallery uses) */
static const cx_theme_rec theme_day = {
    { 0xFF, 0x0F,  0xAA, 0x0A,  0x55, 0x05,  0x00, 0x00 }, 0, 1, 3, 0
};
static const cx_theme_rec theme_night = {
    { 0x01, 0x00,  0x23, 0x01,  0x56, 0x03,  0xBC, 0x0A }, 0, 1, 3, 0
};

/* the static captions -- drawn once; a palette swap recolours them, so a
 * theme change needs no repaint of this text */
static void labels(void) {
    cx_say("cdemo -- checkboxes, radios, sliders, a field, a list.", 40, 56);
    cx_say("Demo>about opens a dialog; Themes recolours; exit lower-right.",
           40, 72);
    cx_say("slider 1-10:", 360, 100);
    cx_say("slider 1-5:", 360, 160);
    cx_say("pick one:", 360, 234);
    cx_say("type here:", 40, 274);
}

int main(void) {
    cx_event ev;

    cx_print("CDEMO UP");

    cx_gfx_init();
    cx_clear(0);

    cx_ev_init();            /* resets the region stack -- before menu_set */
    cx_menu_set(&bar);
    labels();
    cx_wg_set(&panel);       /* parks the list, draws it, pushes its region */
    cx_mouse_show(1);

    for (;;) {
        if (!cx_next(&ev))            /* routes the mouse into the toolkit */
            continue;
        switch (ev.type) {
        case CX_ET_KEY:
            if (ev.detail == CX_K_ESC)
                goto done;
            cx_menu_key(ev.detail);   /* the bar first: DOWN opens it */
            cx_wg_key(ev.detail);     /* then the widgets: TAB, arrows */
            break;
        case CX_ET_MENU:
            if (ev.x == 0) {                 /* the Demo menu */
                if (ev.detail == 0)          /* about */
                    cx_alert(&about);
                else                         /* quit */
                    goto done;
            } else {                         /* the Themes menu */
                cx_theme(ev.detail == 0 ? &theme_day : &theme_night);
                cx_wg_draw();                /* recolour the widgets in place */
            }
            break;
        case CX_ET_WIDGET:
            if (ev.detail == W_EXIT)
                goto done;
            break;
        }
    }
done:
    cx_exit(); /* never returns */
    return 0;
}
