; ca65
; =====================================================================
; CXGEOS :: kernel/boot/cart.asm -- the cartridge boot stub (ROM bank 32)
; =====================================================================
; The cartridge counterpart to AUTOBOOT.X16 (kernel/boot/auto.asm). After
; the X16 finishes hardware init the KERNAL checks ROM bank 32 for the
; signature "CX16" at $C000 and, finding it, jumps to $C004 with
; interrupts disabled (Programmer's Reference: Booting from Cartridges).
;
; The same kernel runs either way -- it lives at $8000 (resident) and in
; RAM banks 2-5 (banked) whether it arrived off SD or out of ROM. So this
; stub does exactly what stage-0 does, only the source is cartridge ROM
; instead of a disk file: it COPIES the images into RAM and starts them.
; CXKERNEL.PRG, CXBANKS.BIN, the ABI and cxb_call are reused untouched.
;
; Cartridge layout (mkcart / cart.cfg), 3 ROM banks:
;   bank 32  "CX16", this stub, the relocated copier, then the resident
;            image and the font as data
;   bank 33  first 16 KB of CXBANKS.BIN
;   bank 34  second 16 KB of CXBANKS.BIN
;
; The catch: reading banks 33-34 means paging ROM_BANK away from 32 --
; out from under this code. So the part that crosses banks is assembled
; to RUN from low RAM ($0400, free at boot), copied there first, and only
; then does it touch ROM_BANK. Everything the stub reads from bank 32
; (the resident, the font) it copies while still executing in bank 32.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

CX_SYSFONT_BANK = 1             ; the boot half of cx_init's contract

; linker-placed spans (cart.cfg, define = yes)
.import __CONT_LOAD__, __CONT_RUN__, __CONT_SIZE__
.import __RESIMG_LOAD__, __RESIMG_SIZE__
.import __FONTIMG_LOAD__, __FONTIMG_SIZE__

; copy pointers -- KERNAL r0-r2, all scratch at boot
cpsrc = $02
cpdst = $04
cplen = $06

; ---------------------------------------------------------------------
; the signature the KERNAL scans for, at $C000
; ---------------------------------------------------------------------
.segment "SIG"
    .byte "CX16"

; ---------------------------------------------------------------------
; the front: runs from bank 32 at $C004, IRQ off, ROM_BANK = 32 (us).
; Everything here reads bank-32 data only -- no ROM_BANK change yet.
; ---------------------------------------------------------------------
.segment "FRONT"
front
    ldx #$FF                    ; a clean stack -- the KERNAL jmp'd here
    txs

    lda #<__RESIMG_LOAD__       ; 1) the resident image -> $8000
    sta cpsrc
    lda #>__RESIMG_LOAD__
    sta cpsrc+1
    stz cpdst
    lda #$80
    sta cpdst+1
    lda #<__RESIMG_SIZE__
    sta cplen
    lda #>__RESIMG_SIZE__
    sta cplen+1
    jsr fcopy

    lda #CX_SYSFONT_BANK        ; 2) the font -> RAM bank 1, $A000
    sta RAM_BANK
    lda #<__FONTIMG_LOAD__
    sta cpsrc
    lda #>__FONTIMG_LOAD__
    sta cpsrc+1
    stz cpdst
    lda #$A0
    sta cpdst+1
    lda #<__FONTIMG_SIZE__
    sta cplen
    lda #>__FONTIMG_SIZE__
    sta cplen+1
    jsr fcopy

    lda #<__CONT_LOAD__         ; 3) the cross-bank copier -> low RAM
    sta cpsrc
    lda #>__CONT_LOAD__
    sta cpsrc+1
    lda #<__CONT_RUN__
    sta cpdst
    lda #>__CONT_RUN__
    sta cpdst+1
    lda #<__CONT_SIZE__
    sta cplen
    lda #>__CONT_SIZE__
    sta cplen+1
    jsr fcopy

    jmp __CONT_RUN__            ; 4) run it from RAM

; forward memcpy: cplen bytes (cpsrc) -> (cpdst)
fcopy
    ldy #0
    ldx cplen+1
    beq @rem
@full
    lda (cpsrc),y
    sta (cpdst),y
    iny
    bne @full
    inc cpsrc+1
    inc cpdst+1
    dex
    bne @full
@rem
    ldx cplen
    beq @done
@r
    lda (cpsrc),y
    sta (cpdst),y
    iny
    dex
    bne @r
@done
    rts

; ---------------------------------------------------------------------
; the continuation: RUNS from $0400 (low RAM), so it can page ROM_BANK
; freely. Copies the 32 KB banked kernel out of ROM banks 33-34, brings
; the machine up the way BASIC's cold start would, and hands off exactly
; like auto.asm.
; ---------------------------------------------------------------------
.segment "CONT"
cont
    lda #33                     ; source: ROM bank 33, $C000 (16 KB window)
    sta ROM_BANK
    lda #2                      ; dest: RAM bank 2, $A000 (8 KB window)
    sta RAM_BANK
    stz cpsrc
    lda #$C0
    sta cpsrc+1
    stz cpdst
    lda #$A0
    sta cpdst+1
    ldx #128                    ; 32 KB = 128 pages
@page
    ldy #0
@byte
    lda (cpsrc),y
    sta (cpdst),y
    iny
    bne @byte
    inc cpsrc+1                 ; ROM window wraps at $FFFF -> next ROM bank
    bne @dst
    lda #$C0
    sta cpsrc+1
    inc ROM_BANK
@dst
    inc cpdst+1                 ; RAM window wraps at $BFFF -> next RAM bank
    lda cpdst+1
    cmp #$C0
    bne @next
    lda #$A0
    sta cpdst+1
    inc RAM_BANK
@next
    dex
    bne @page

    stz ROM_BANK                ; the KERNAL back at $C000-$FFFF
    lda #1                      ; the default user RAM bank
    sta RAM_BANK

    jsr IOINIT                  ; the state BASIC's cold start would leave:
    jsr RESTOR                  ; default vectors (CINV, for the event chain)
    jsr CINT                    ; default screen/editor
    cli                         ; interrupts on -- CINV is valid now

    ldy #3                      ; believe nothing without the magic
@magic
    lda $8000,y
    cmp cxos,y
    bne badkernel
    dey
    bpl @magic

    jsr doinit                  ; cx_init, the vector at $8008
    bcs nofont                  ; carry: it would not accept the font

    lda #<s_autorun             ; hand off like auto.asm: AUTORUN if the SD
    ldx #>s_autorun             ; has one, else cx_exit == "go to the shell"
    ldy #s_autorun_len
    jsr cx_app_load
    jmp cx_exit

doinit
    jmp ($8008)

badkernel
    lda #<s_nok
    ldx #>s_nok
    jmp cpmsg
nofont
    lda #<s_nof
    ldx #>s_nof
    ; fall through

cpmsg                           ; A/X = a NUL string, then stop
    sta cpsrc
    stx cpsrc+1
    ldy #0
@l
    lda (cpsrc),y
    beq @halt
    jsr CHROUT
    iny
    bne @l
@halt
    bra @halt

cxos       .byte "CXOS"
s_autorun  .byte "AUTORUN.CXA"
s_autorun_len = * - s_autorun
s_nok      .byte $0D, "CXGEOS CART: BAD KERNEL IMAGE.", $0D, 0
s_nof      .byte $0D, "CXGEOS CART: FONT REFUSED.", $0D, 0

; ---------------------------------------------------------------------
; the payload, laid into ROM by cart.cfg. The resident carries its own
; 2-byte PRG load-address header, which we skip; the others are raw.
; ---------------------------------------------------------------------
.segment "RESIMG"
    .incbin "build/CXKERNEL.PRG", 2

.segment "FONTIMG"
    .incbin "fonts/pxl8.cxf"

.segment "BANKS_LO"
    .incbin "build/CXBANKS.BIN", 0, $4000

.segment "BANKS_HI"
    .incbin "build/CXBANKS.BIN", $4000, $4000
