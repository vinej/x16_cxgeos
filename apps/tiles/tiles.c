/* =====================================================================
 * CXRF :: apps/tiles/tiles.c -- the tile-mode example (llvm-mos)
 * =====================================================================
 * The game personality: cx_mode(CX_MODE_TILE) hands the screen to two
 * VERA tile layers. This uploads two 8x8 4bpp tiles (a dim checker and
 * a bright brick), carpets layer 0 with the checker, writes a brick
 * window in the middle of the map, and scrolls the layer with the
 * arrow keys, a joystick -- or by itself, drifting. The scroll is a
 * register write: nothing is redrawn, which is the whole point of
 * tiles. SPACE pauses the game with a modal dialog drawn over the still-
 * visible world (cx_tile_text flips layer 1 to a text overlay); dismiss
 * it and the scroll picks up where it left off. Any other key exits; the
 * desktop restores the GUI on its own.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxrf.h"
#include "csdk/cxsdk.h"

static unsigned char tiles[64];        /* two 4bpp 8x8 tiles, 32 B each */

/* the pause dialog -- one button, dismissed with RETURN or ESC */
CX_DIALOG(paused, "Paused. Resume the game?", "OK");

int main(void) {
    unsigned char x, y;
    unsigned h = 0, v = 0;
    cx_event ev;

    cx_print("TILES UP");

    cx_mode(CX_MODE_TILE, 0);

    /* tile 0: a checker of colours 11 (dark grey) and 0; tile 1: a
     * brick of colour 8 (orange) with a colour-2 (red) mortar line */
    for (y = 0; y < 8; y++)
        for (x = 0; x < 4; x++) {
            unsigned char lt = ((x >> 1) ^ (y >> 2)) & 1 ? 0xBB : 0x00;
            unsigned char br = (y == 7 || x == 3) ? 0x22 : 0x88;
            tiles[y * 4 + x]      = lt;
            tiles[32 + y * 4 + x] = br;
        }
    cx_vram_write(CX_TILE_IMG, tiles, sizeof tiles);

    cx_tile_setup(0, 4);
    cx_tile_fill(0, CX_CELL(0, 0));    /* the checker carpet */
    for (y = 10; y < 22; y++)          /* a brick window mid-map */
        for (x = 24; x < 40; x++)
            cx_tile_cell(0, x, y, CX_CELL(1, 0));

    cx_ev_init();
    cx_ev_mask(CX_EVS_KEYS);           /* no mouse here: skip its SMC
                                        * round-trip every frame */
    cx_joy_enable(1);                  /* pad 0: the keyboard joystick */

    for (;;) {
        if (cx_poll(&ev)) {
            if (ev.type == CX_ET_KEY) {
                if (ev.detail == CX_K_LEFT)       h -= 8;
                else if (ev.detail == CX_K_RIGHT) h += 8;
                else if (ev.detail == CX_K_UP)    v -= 8;
                else if (ev.detail == CX_K_DOWN)  v += 8;
                else if (ev.detail == CX_K_SPACE) {
                    /* pause: a text overlay on layer 1, a modal dialog on
                     * it over the frozen-but-visible world, then back --
                     * layer 0's scroll is untouched, so play resumes here.
                     * The mouse is switched on just for the dialog (the game
                     * itself is keyboard/joystick), so the button is
                     * clickable as well as RETURN/ESC. */
                    cx_tile_text(1, 1);
                    cx_tile_fill(1, 0x20);   /* clear transparent: world shows around it */
                    cx_mouse_show(1);
                    cx_ev_mask(CX_EVS_KEYS | CX_EVS_MOUSE);
                    cx_alert(&paused);
                    cx_ev_mask(CX_EVS_KEYS);
                    cx_mouse_hide();
                    cx_tile_text(1, 0);
                }
                else break;            /* any other key exits */
            } else if (ev.type == CX_ET_JOY) {
                if (ev.x & CX_J_LEFT)  h -= 8;
                if (ev.x & CX_J_RIGHT) h += 8;
                if (ev.x & CX_J_UP)    v -= 8;
                if (ev.x & CX_J_DOWN)  v += 8;
            } else {
                continue;
            }
        } else {
            unsigned char t = cx_frames();     /* idle drift, ~30/s */
            while ((unsigned char)(cx_frames() - t) < 2)
                ;
            h++;
        }
        cx_tile_scroll(0, h & 0x0FFF, v & 0x0FFF);
    }
    cx_exit(); /* never returns */
    return 0;
}
