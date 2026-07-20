/* =====================================================================
 * CXGEOS :: apps/sprite/sprite.c -- the hardware-sprite example (llvm-mos)
 * =====================================================================
 * Builds a 16x16 4bpp sprite image in RAM, uploads it to the reserved
 * sprite VRAM (cx_vram_write to CX_SPR_VRAM), points hardware sprite 1 at
 * it, and moves it with the arrow keys or a mouse click. Sprite 0 is the
 * KERNAL mouse pointer, so the diamond and the arrow pointer float over
 * the bitmap independently -- that is the sprite layer at work.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxgeos.h"
#include "csdk/cxsdk.h"

#define SW 16                          /* 16x16, 4bpp: 8 bytes/row, 128 total */
static unsigned char img[(SW / 2) * SW];

/* a white sheet, black ink -- gives the sprite a index-3 (black) colour */
static const cx_theme_rec sheet = {
    { 0xFF, 0x0F,  0xAA, 0x0A,  0x55, 0x05,  0x00, 0x00 }, 0, 1, 3, 0
};

/* set 4bpp pixel (x,y) to colour c; the high nibble is the left pixel */
static void set4(unsigned char x, unsigned char y, unsigned char c) {
    unsigned idx = y * (SW / 2) + (x >> 1);
    if (x & 1) img[idx] = (img[idx] & 0xF0) | c;
    else       img[idx] = (img[idx] & 0x0F) | (unsigned char)(c << 4);
}

int main(void) {
    unsigned char x, y;
    cx_event ev;
    cx_print("SPRITE UP");

    cx_gfx_init();
    cx_theme(&sheet);
    cx_clear(0);
    cx_say("sprite -- the diamond is a hardware sprite following the mouse; a key exits.",
           20, 60);

    /* paint a solid diamond in colour 3, the rest transparent (colour 0) */
    for (y = 0; y < SW; y++)
        for (x = 0; x < SW; x++) {
            unsigned char dx = (x < 8) ? (7 - x) : (x - 8);
            unsigned char dy = (y < 8) ? (7 - y) : (y - 8);
            set4(x, y, (unsigned char)(dx + dy) < 7 ? 3 : 0);
        }
    cx_vram_write(CX_SPR_VRAM, img, sizeof img);

    cx_sprite_image(1, CX_SPR_VRAM, CX_SPR_4BPP);
    cx_sprite_size(1, CX_SPR_16, CX_SPR_16, 0);
    cx_sprite_pos(1, 300, 220);
    cx_sprite_flags(1, CX_SPR_FRONT);      /* full write, shows it in front */

    cx_ev_init();
    cx_mouse_show(1);

    for (;;) {
        if (!cx_poll(&ev))
            continue;
        switch (ev.type) {
        case CX_ET_KEY:
            if (ev.detail == CX_K_ESC) goto done;
            break;
        case CX_ET_MOVE:               /* the diamond tracks the pointer; */
        case CX_ET_DOWN:               /* MOVEs coalesce, so it never lags */
            cx_sprite_pos(1, ev.x, ev.y);
            break;
        }
    }
done:
    cx_exit(); /* never returns */
    return 0;
}
