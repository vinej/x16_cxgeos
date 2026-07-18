; ca65
; =====================================================================
; CXGEOS :: kernel/video/shapes.asm -- circle, disc, flood: every mode
; =====================================================================
; x16lib's engine-agnostic shapes module, bound to the graphics PORT:
; SHP_PSET/READ/HLINE point at the overlay's entry vector, and the
; bounds at the port manager's current-canvas words -- so one copy of
; the code draws correct circles, discs and floods in mode 0, mode 1,
; and any mode that ever joins the port. The module rides bank 5
; behind far-call stubs; its calls back into the port land in the
; resident overlay window, which is always mapped.
; =====================================================================

.ifndef CX_NO_OVERLAY

SHP_PSET  = cxov_pset
SHP_READ  = cxov_read
SHP_HLINE = cxov_hline
SHP_W     = cx_cur_w
SHP_H     = cx_cur_h

CX_SHP_BANK = 5

cx_do_gfx_circle
    jsr cxb_call
    .byte CX_SHP_BANK
    .addr shape_circle
cx_do_gfx_disc
    jsr cxb_call
    .byte CX_SHP_BANK
    .addr shape_disc
cx_do_gfx_flood
    jsr cxb_call
    .byte CX_SHP_BANK
    .addr shape_flood
cx_do_gfx_ellipse
    jsr cxb_call
    .byte CX_SHP_BANK
    .addr shape_ellipse
cx_do_gfx_fellipse
    jsr cxb_call
    .byte CX_SHP_BANK
    .addr shape_fellipse

.segment "B5CODE"
.include "gfx/shapes.asm"
.segment "CODE"

.else
; the runner links flat: the port names already alias the 2bpp engine
; (ovl.inc), so the same binds hold and the stubs are the routines.
SHP_PSET  = cxov_pset
SHP_READ  = cxov_read
SHP_HLINE = cxov_hline
SHP_W     = cx_cur_w
SHP_H     = cx_cur_h

cx_do_gfx_circle   = shape_circle
cx_do_gfx_disc     = shape_disc
cx_do_gfx_flood    = shape_flood
cx_do_gfx_ellipse  = shape_ellipse
cx_do_gfx_fellipse = shape_fellipse

.include "gfx/shapes.asm"

.endif
