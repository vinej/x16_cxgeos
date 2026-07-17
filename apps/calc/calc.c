/* =====================================================================
 * CXGEOS :: apps/calc/calc.c -- the calculator (llvm-mos)
 * =====================================================================
 * The first real C application: a four-function FLOATING-POINT
 * calculator, built against sdk/include_llvm/cxgeos.h alone. Click the
 * buttons or type -- digits, a decimal point, + - * /, RETURN for =,
 * C to clear, ESC back to the desktop. The math is C float (llvm-mos
 * soft-float); the result is formatted to four decimals, trailing
 * zeros trimmed, so 10 / 3 reads 3.3333 and 1.5 + 2.5 reads 4.
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

/* the grid: 4 columns x 5 rows at (200,150), 56 wide, 28 tall, 8 apart */
#define GX 200
#define GY 150
#define CW 56
#define CH 28
#define GAP 8
#define CLEARW (4 * CW + 3 * GAP)  /* the wide clear button spans the row */

static const char keys[16] = {
    '7', '8', '9', '/',
    '4', '5', '6', '*',
    '1', '2', '3', '-',
    '0', '.', '=', '+',
};

static float acc, cur;
static float frac;         /* 0 = whole-number entry; else the next   */
                           /* fractional digit's place value          */
static char op;            /* the pending operator, 0 = none          */
static char typing;        /* 1 while cur is being entered            */
static char err;           /* 1 after divide-by-zero, until cleared   */
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

/* fmt -- v into out, seven decimals (a 32-bit float's worth, so 1/3
 * reads 0.3333333), trailing zeros (and a bare point) trimmed. Handles
 * the sign and guards the range where a u32 integer part would
 * overflow. */
static void fmt(float v, char *out) {
    char tmp[12];
    char *p = out;
    unsigned long ip;
    unsigned long f;
    signed char nd;

    if (v < 0) {
        *p++ = '-';
        v = -v;
    }
    if (v >= 1000000000.0f) {      /* past nine digits: not a display */
        *p++ = 'o'; *p++ = 'v'; *p++ = 'f'; *p++ = 0;
        return;
    }

    ip = (unsigned long)v;
    f = (unsigned long)((v - (float)ip) * 10000000.0f + 0.5f);
    if (f >= 10000000UL) {         /* the round carried into the ones */
        f -= 10000000UL;
        ip++;
    }

    nd = 0;                        /* integer part, emitted big-end first */
    do {
        tmp[nd++] = '0' + (char)(ip % 10);
        ip /= 10;
    } while (ip);
    while (nd)
        *p++ = tmp[--nd];

    if (f) {                       /* seven decimals, trailing zeros gone */
        char dg[7];
        char len;
        unsigned long d = 1000000UL;
        char i;
        for (i = 0; i < 7; i++) {
            dg[i] = '0' + (char)(f / d % 10);
            d /= 10;
        }
        len = 7;
        while (len > 0 && dg[len - 1] == '0')
            len--;
        if (len) {
            *p++ = '.';
            for (i = 0; i < len; i++)
                *p++ = dg[i];
        }
    }
    *p = 0;
}

static void show(void) {
    static char buf[24];

    if (err)
        buf[0] = 0;
    else
        fmt(typing ? cur : acc, buf);

    rect(GX + 2, 112, 244, 24, 0);
    say(err ? "" : buf, GX + 12, 118);
    /* the note goes ABOVE the display -- at y=300 it sat on the bottom
     * button row and wiped out the C labels */
    rect(40, 88, 420, 14, 0);
    say(note, 40, 90);
    note = "";
}

static void apply(void) {
    switch (op) {
    case '+': acc += cur; break;
    case '-': acc -= cur; break;
    case '*': acc *= cur; break;
    case '/':
        if (cur == 0.0f) {
            err = 1;
            note = "divide by zero -- C clears.";
            return;
        }
        acc /= cur;
        break;
    default:  acc = cur; break;
    }
    cur = 0.0f;
    frac = 0.0f;
    typing = 0;
}

static void feed(char c) {
    if (err && c != 'C' && c != 'c')
        return;

    if (c >= '0' && c <= '9') {
        if (frac == 0.0f) {
            cur = cur * 10.0f + (float)(c - '0');
        } else {
            cur += (float)(c - '0') * frac;
            frac *= 0.1f;
        }
        typing = 1;
    } else if (c == '.') {
        if (frac == 0.0f)
            frac = 0.1f;           /* a second point is ignored */
        typing = 1;
    } else if (c == '+' || c == '-' || c == '*' || c == '/') {
        /* fold a just-typed number into acc; after '=', acc IS the
         * running total, so leave it there and only set the new op */
        if (typing)
            apply();
        if (!err)
            op = c;
    } else if (c == '=' || c == '\r') {
        /* nothing pending: keep the result, so pressing '=' twice or
         * an operator after it does not zero the running total */
        if (op || typing)
            apply();
        op = 0;
    } else if (c == 'C' || c == 'c') {
        acc = cur = 0.0f;
        frac = 0.0f;
        op = 0;
        typing = 0;
        err = 0;
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
    say("calc -- type or click; . for decimals, RETURN =, C clears, ESC out.",
        120, 60);

    frame(GX, 110, 248, 28, 3);
    for (i = 0; i < 16; i++) {
        unsigned x = GX + (i & 3) * (CW + GAP);
        unsigned y = GY + (i >> 2) * (CH + GAP);
        frame(x, y, CW, CH, 3);
        lab[0] = keys[i];
        say(lab, x + 24, y + 8);
    }
    /* one wide clear button under the grid, not four "C"s */
    frame(GX, GY + 4 * (CH + GAP), CLEARW, CH, 3);
    say("clear", GX + 100, GY + 4 * (CH + GAP) + 8);
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
                if (row == 4) {           /* the wide clear button */
                    if (x < GX + CLEARW &&
                        (y - GY) % (CH + GAP) < CH)
                        feed('C');
                } else if (col < 4 && row < 4 &&
                           (x - GX) % (CW + GAP) < CW &&
                           (y - GY) % (CH + GAP) < CH) {
                    feed(keys[row * 4 + col]);
                }
            }
        }
    }

    cx_call(CX_EXIT); /* never returns */
}
