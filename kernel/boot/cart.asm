; ca65
; =====================================================================
; CXRF :: kernel/boot/cart.asm -- the cartridge boot stub (ROM bank 32)
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
; Cartridge layout (mkcart / cart.cfg), 5 ROM banks:
;   bank 32  "CX16", this stub, the relocated copier, then the resident
;            image and the font as data
;   bank 33  first 16 KB of CXBANKS.BIN
;   bank 34  second 16 KB of CXBANKS.BIN
;   bank 35  first 16 KB of CXBANKS2.BIN   (-> RAM banks 16-19)
;   bank 36  second 16 KB of CXBANKS2.BIN
;
; No signature walk here: all five images are .incbin'd from the same
; build, so they cannot be out of step with each other by construction.
; Stage-0's checks guard the SD card, whose files travel separately.
;
; The catch: reading banks 33-34 means paging ROM_BANK away from 32 --
; out from under this code. So the part that crosses banks is assembled
; to RUN from low RAM ($0400, free at boot), copied there first, and only
; then does it touch ROM_BANK. Everything the stub reads from bank 32
; (the resident, the font) it copies while still executing in bank 32.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxrf.inc"

CX_SYSFONT_BANK = 1             ; the boot half of cx_init's contract

; linker-placed spans (cart.cfg, define = yes)
.import __CONT_LOAD__, __CONT_RUN__, __CONT_SIZE__
.import __RESIMG_LOAD__, __RESIMG_SIZE__
.import __FONTIMG_LOAD__, __FONTIMG_SIZE__

; -D CART_APP: a standalone cartridge with one app baked into ROM bank 37
; (cart_app.cfg). The stub runs it straight from ROM -- no SD, no shell.
CX_APP_BASE = $0801             ; where every CXRF app is built and runs
.ifdef CART_APP
.import __APPIMG_LOAD__, __APPIMG_SIZE__
CART_APP_BANK = 37              ; the app's CXA image, at $C000 in this ROM bank
appentry = $08                  ; its CXAP entry vector, read before ROM_BANK 0
.endif

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
    lda #33                     ; CXBANKS.BIN: ROM banks 33-34 -> RAM 2-5
    ldx #2
    jsr bankcopy
    lda #35                     ; CXBANKS2.BIN: ROM banks 35-36 -> RAM 16-19
    ldx #16
    jsr bankcopy

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

.ifdef CART_APP
    jmp launch_cart_app         ; standalone: run the app baked into ROM bank 37
.else
    lda #<s_autorun             ; hand off like auto.asm: AUTORUN if the SD
    ldx #>s_autorun             ; has one, else cx_exit == "go to the shell"
    ldy #s_autorun_len
    jsr cx_app_load
    jmp cx_exit
.endif

doinit
    jmp ($8008)

; bankcopy -- 32 KB out of cartridge ROM into banked RAM.
; A = the first ROM bank ($C000 window, wraps at $FFFF to the next),
; X = the first RAM bank ($A000 window, wraps at $BFFF to the next).
bankcopy
    sta ROM_BANK
    stx RAM_BANK
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
    rts

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
s_nok      .byte $0D, "CXRF CART: BAD KERNEL IMAGE.", $0D, 0
s_nof      .byte $0D, "CXRF CART: FONT REFUSED.", $0D, 0

.ifdef CART_APP
; ---------------------------------------------------------------------
; launch_cart_app -- copy the baked app's payload out of ROM bank 37 to
; $0801 and jump its entry. A fresh cartridge boot has no prior app to
; tear down (no events, mouse or sprites live yet), so the loader's
; finalize is unnecessary here -- a clean app ZP and an empty stack, the
; way cx_app_load leaves them, is all the app is owed. Runs from low RAM
; (CONT), so it may page ROM_BANK; the bank-32 fcopy is gone by now. It
; sits at the end so the front's short branches to badkernel/nofont are
; not pushed out of reach.
; ---------------------------------------------------------------------
launch_cart_app
    lda #CART_APP_BANK
    sta ROM_BANK                ; the app's CXA sits at $C000 in bank 37
    lda __APPIMG_LOAD__+6       ; its CXAP entry vector (header bytes 6-7)
    sta appentry
    lda __APPIMG_LOAD__+7
    sta appentry+1
    lda #<(__APPIMG_LOAD__+34)  ; src: past the 32-byte header + 2-byte PRG addr
    sta cpsrc
    lda #>(__APPIMG_LOAD__+34)
    sta cpsrc+1
    lda #<CX_APP_BASE           ; dst: $0801
    sta cpdst
    lda #>CX_APP_BASE
    sta cpdst+1
    lda #<(__APPIMG_SIZE__-34)  ; len: the CXA minus its header and PRG address
    sta cplen
    lda #>(__APPIMG_SIZE__-34)
    sta cplen+1
    ldy #0                      ; a forward memcpy, inline (fcopy is paged out)
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
    beq @run
@r
    lda (cpsrc),y
    sta (cpdst),y
    iny
    dex
    bne @r
@run
    stz ROM_BANK                ; the KERNAL back at $C000-$FFFF
    ldx #$1F                    ; a clean app ZP ($60-$7F)
@zp
    stz $60,x
    dex
    bpl @zp
    ldx #$FF                    ; an empty stack -- the app owns the machine
    txs
    cli
    jmp (appentry)
.endif

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

.segment "BANKS2_LO"
    .incbin "build/CXBANKS2.BIN", 0, $4000

.segment "BANKS2_HI"
    .incbin "build/CXBANKS2.BIN", $4000, $4000

.ifdef CART_APP
.segment "APPIMG"               ; the baked app (build.ps1 -App staged it here)
    .incbin "build/CARTAPP.CXA"
.endif
