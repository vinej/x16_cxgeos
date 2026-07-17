/* =====================================================================
 * CXGEOS :: apps/calc/calc.c -- the calculator (llvm-mos)
 * =====================================================================
 * The first real C application: a four-function 32-bit integer
 * calculator, built against sdk/include_llvm/cxgeos.h alone. Click the
 * buttons or type -- digits, + - * /, RETURN for =, C to clear, ESC
 * back to the desktop.
 *
 * It polls CX_EV_GET (the hello_c pattern) instead of running the
 * kernel dispatcher: a C handler cannot take a kernel callback -- the
 * event data arrives in $22-$29, which is also where llvm-mos keeps
 * its soft stack pointer -- and polling through cx_run() is exactly
 * the safe crossing the SDK provides. The buttons are its own grid,
 * hit-tested here in C; the widget engine stays out of it.
 * ===================================================================== */

#include <cbm.h>
#include "sdk/include_llvm/cxgeos.h"

#define EV_MOUSE_DOWN 2
#define EV_KEY 5

/* the grid: 4x4 cells at (200,160), 56 wide, 28 tall, 8 apart */
#define GX 200
#define GY 160
#define CW 56
#define CH 28
#define GAP 8

static const char keys[16] = {
    '7', '8', '9', '/',
    '4', '5', '6', '*',
    '1', '2', '3', '-',
    'C', '0', '=', '+',
};

static unsigned long acc, cur;
static char op;            /* the pending operator, 0 = none        */
static char typing;        /* 1 while cur is being entered          */
static char digits;       /* how many, to keep the u32 exact       */
static const char *note = "";

static void rect(unsigned x, unsigned y, unsigned w, unsigned h,
                 unsigned char colour) {
    cx_p[0] = x & 0xFF; cx_p[1] = x >> 8;
    cx_p[2] = y & 0xFF; cx_p[3] = y >> 8;
    cx_p[4] = w & 0xFF; cx_p[5] = w >> 8;
    cx_p[6] = h & 0xFF; cx_p[7] = h >> 8;
    cx_call_a(CX_GFX_RECT, colour);
}

static void frame(unsigned x, unsigned y, unsigned w, unsigned h,
                  unsigned char colour) {
    cx_p[0] = x & 0xFF; cx_p[1] = x >> 8;
    cx_p[2] = y & 0xFF; cx_p[3] = y >> 8;
    cx_p[4] = w & 0xFF; cx_p[5] = w >> 8;
    cx_p[6] = h & 0xFF; cx_p[7] = h >> 8;
    cx_call_a(CX_GFX_FRAME, colour);
}

static void say(const char *s, unsigned x, unsigned y) {
    cx_p[0] = x & 0xFF; cx_p[1] = x >> 8;
    cx_p[2] = y & 0xFF; cx_p[3] = y >> 8;
    cx_call_p(CX_FONT_DRAW, s);
}

static void marker(const char *s) {
    while (*s)
        cbm_k_chrout(*s++);
    cbm_k_chrout('\r');
}

/* the display: the number right-ish in its frame, notes underneath */
static void show(void) {
    static char buf[12];
    unsigned long v = typing ? cur : acc;
    char *p = buf + sizeof(buf) - 1;

    *p = 0;
    do {
        *--p = '0' + (unsigned char)(v % 10);
        v /= 10;
    } while (v);

    rect(GX + 2, 122, 244, 24, 0);
    say(p, GX + 12, 128);
    rect(GX, 300, 320, 14, 0);
    say(note, GX, 300);
    note = "";
}

static void apply(void) {
    switch (op) {
    case '+': acc += cur; break;
    case '-': acc -= cur; break;
    case '*': acc *= cur; break;
    case '/':
        if (cur == 0) {
            note = "divide by zero -- cleared.";
            acc = 0;
        } else {
            acc /= cur;
        }
        break;
    default:  acc = cur; break;
    }
    cur = 0;
    digits = 0;
    typing = 0;
}

static void feed(char c) {
    if (c >= '0' && c <= '9') {
        if (digits < 9) {
            cur = cur * 10 + (c - '0');
            digits++;
        }
        typing = 1;
    } else if (c == '+' || c == '-' || c == '*' || c == '/') {
        if (typing || op == 0)
            apply();
        op = c;
    } else if (c == '=' || c == '\r') {
        apply();
        op = 0;
    } else if (c == 'C' || c == 'c') {
        acc = cur = 0;
        op = 0;
        digits = 0;
        typing = 0;
        note = "cleared.";
    } else {
        return;
    }
    show();
}

static void draw(void) {
    unsigned char i;
    static char lab[2];

    cx_call_a(CX_GFX_CLEAR, 0);
    say("calc -- type or click; RETURN is =, C clears, ESC leaves.",
        140, 60);

    frame(GX, 120, 248, 28, 3);
    for (i = 0; i < 16; i++) {
        unsigned x = GX + (i & 3) * (CW + GAP);
        unsigned y = GY + (i >> 2) * (CH + GAP);
        frame(x, y, CW, CH, 3);
        lab[0] = keys[i];
        say(lab, x + 24, y + 8);
    }
    show();
}

int main(void) {
    marker("CALC UP");

    cx_call(CX_GFX_INIT);
    draw();
    cx_call(CX_EV_INIT);
    cx_call_a(CX_MOUSE_SHOW, 1);

    for (;;) {
        if (!cx_ret(CX_EV_COUNT))
            continue;
        cx_call(CX_EV_GET);
        if (cx_p[0] == EV_KEY) {
            char k = (char)cx_p[1];
            if (k == 0x1B)
                break;
            feed(k);
        } else if (cx_p[0] == EV_MOUSE_DOWN) {
            unsigned x = cx_p[2] | ((unsigned)cx_p[3] << 8);
            unsigned y = cx_p[4] | ((unsigned)cx_p[5] << 8);
            if (x >= GX && y >= GY) {
                unsigned char col = (x - GX) / (CW + GAP);
                unsigned char row = (y - GY) / (CH + GAP);
                if (col < 4 && row < 4 &&
                    (x - GX) % (CW + GAP) < CW &&
                    (y - GY) % (CH + GAP) < CH)
                    feed(keys[row * 4 + col]);
            }
        }
    }

    cx_call(CX_EXIT); /* never returns */
}
