; ca65
; =====================================================================
; CXGEOS :: kernel/resident/zp.inc -- the kernel's zero page
; =====================================================================
; The ONLY place kernel zero page is allocated. docs/memory-map.md is
; the ledger; this file is the enforcement.
;
;   $02-$21  KERNAL r0-r15      caller-save scratch, never live across
;                               a CXGEOS API call
;   $22-$31  x16lib             X16_P0..P7 + X16_T0..T7, fixed
;   $32-$5F  CXGEOS kernel      here
;   $60-$7F  application        the kernel and its IRQ never touch it
;   $80-$FF  KERNAL/BASIC/DOS   never touch
;
; Anything an app can see lives in $60-$7F; anything the kernel needs
; across a call lives here. A module that wants a byte adds it here with
; its owner named, so the next module can see what is free.
; =====================================================================

.ifndef CX_ZP_INC
CX_ZP_INC = 1

CX_ZP      = $32
CX_ZP_END  = $60                ; one past the last byte we may use

; --- font engine (kernel/font/font.asm) ------------------------------
CX_F_CXF   = CX_ZP + 0          ; $32/$33  the live CXF image
CX_F_ROWP  = CX_ZP + 2          ; $34/$35  the glyph rows being cached
CX_F_STR   = CX_ZP + 4          ; $36/$37  the string being drawn
CX_F_SRC   = CX_ZP + 6          ; $38/$39  a cache slot, for blitm
CX_F_PEN   = CX_ZP + 8          ; $3A/$3B  pen x, walked across a string
CX_F_Y     = CX_ZP + 10         ; $3C/$3D  the row being drawn on
CX_F_T0    = CX_ZP + 12         ; $3E      scratch
CX_F_T1    = CX_ZP + 13         ; $3F

CX_F_ZP_TOP = CX_ZP + 14        ; = $40

; --- event system (kernel/event/event.asm) ---------------------------
CX_E_HND   = CX_ZP + 14         ; $40/$41  the app's handler table

CX_E_ZP_TOP = CX_ZP + 16        ; = $42

; --- far-call trampoline (kernel/resident/farcall.asm) ---------------
CX_B_PTR   = CX_ZP + 16         ; $42/$43  the stub's inline data, read
                                ;          with (zp),y; dead by the time
                                ;          the banked routine runs

CX_B_ZP_TOP = CX_ZP + 18        ; = $44

; --- menu engine (kernel/ui/menu.asm, bank 2) -------------------------
CX_M_PTR   = CX_ZP + 18         ; $44/$45  walking the app's menu tree

CX_M_ZP_TOP = CX_ZP + 20        ; = $46

; --- free: $46-$5F ---------------------------------------------------

.if CX_ZP < $32
    .error "CX_ZP must be >= $32: below that is x16lib's block"
.endif
.if CX_M_ZP_TOP > CX_ZP_END
    .error "kernel zero page overflows into the application's $60-$7F"
.endif

.endif
