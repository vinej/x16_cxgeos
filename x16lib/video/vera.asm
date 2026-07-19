;ACME
; =====================================================================
; x16lib :: video/vera.asm -- VRAM data-port access
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; Register contract: A, X, Y and flags are clobbered unless a routine
; says otherwise. Scratch is X16_T0..T2.
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; vera_set_addr0 / vera_set_addr1
;   in:  A = ADDR_L, X = ADDR_M, Y = ADDR_H (bank | DECR | incr<<4)
;   out: the chosen port points at that address
;
; The runtime equivalent of +vera_addr, for addresses not known at
; assembly time. Compose Y yourself, or use vera_set_addr0_inc below.
; ---------------------------------------------------------------------
vera_set_addr0
    pha
    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL               ; ADDRSEL = 0
    pla
    sta VERA_ADDR_L
    stx VERA_ADDR_M
    sty VERA_ADDR_H
    rts

vera_set_addr1
    pha
    lda #VERA_CTRL_ADDRSEL
    tsb VERA_CTRL               ; ADDRSEL = 1
    pla
    sta VERA_ADDR_L
    stx VERA_ADDR_M
    sty VERA_ADDR_H
    rts

; ---------------------------------------------------------------------
; vera_fill
;   in:  A = byte value
;        X = count low, Y = count high   (16-bit, 0 means write nothing)
;   pre: caller has pointed port 0 at the destination, with the
;        increment it wants (VERA_INC_1 for a linear run, VERA_INC_320
;        to stripe down a bitmap column, etc.)
;
; The tight `sta VERA_DATA0` loop -- far faster than a per-byte address
; reload. This is GAME.TXT's VFILL.
; ---------------------------------------------------------------------
vera_fill
    sta X16_T0                  ; value
    stx X16_T1                  ; count lo
    sty X16_T2                  ; count hi

    txa
    ora X16_T2
    beq @done                   ; count == 0

    ldx X16_T1
    ldy X16_T2
    txa
    beq @full                   ; low byte 0 -> exactly hi*256 bytes
    iny                         ; otherwise one extra partial page
@full
    lda X16_T0
@loop
    sta VERA_DATA0
    dex
    bne @loop
    dey
    bne @loop
@done
    rts

; ---------------------------------------------------------------------
; vera_copy
;   in:  X = count low, Y = count high
;   pre: port 0 points at the SOURCE (read), port 1 at the DESTINATION
;        (write), each with its own increment.
;
; DATA0 always reads port 0 and DATA1 always writes port 1, whatever
; ADDRSEL says -- so the inner loop never touches CTRL and never
; reloads an address. Two bytes per iteration, both auto-incrementing.
;
;   +vera_addr 0, src, VERA_INC_1
;   +vera_addr 1, dst, VERA_INC_1
;   ldx #<len : ldy #>len : jsr vera_copy
;
; A VERA->VERA blit; a program that only fills does not need it, so it is
; behind X16_USE_VERA_COPY (X16_USE_VERA still pulls it, for compat).
; ---------------------------------------------------------------------
.ifdef X16_USE_VERA_COPY
vera_copy
    stx X16_T1
    sty X16_T2

    txa
    ora X16_T2
    beq @done

    ldx X16_T1
    ldy X16_T2
    txa
    beq @full
    iny
@full
@loop
    lda VERA_DATA0
    sta VERA_DATA1
    dex
    bne @loop
    dey
    bne @loop
@done
    rts
.endif

; ---------------------------------------------------------------------
; vera_has_fx
;   out: carry set if VERA firmware supports the FX register set
;        A = major version (only meaningful when carry is set)
;
; Probes DCSEL=63, where DC_VER0 reads back ASCII 'V' on FX-capable
; VERA. Restores DCSEL to 0 on the way out.
; ---------------------------------------------------------------------
vera_has_fx
    vera_dcsel VERA_DCSEL_FX_VERSION
    lda VERA_DC_VER0
    cmp #VERA_VERSION_MAGIC
    bne @no
    lda VERA_DC_VER1            ; major release
    pha
    vera_dcsel 0
    pla
    sec
    rts
@no
    vera_dcsel 0
    lda #0
    clc
    rts

; (end zone)
