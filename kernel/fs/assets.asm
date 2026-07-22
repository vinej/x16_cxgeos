; ca65
; =====================================================================
; CXRF :: kernel/fs/assets.asm -- cx_vload / cx_bload, assets off disk
; =====================================================================
; The two loaders the X16 asset ecosystem is built around, as ABI slots:
;
;   cx_vload (slot 90) -- a file straight into VRAM, the BASIC VLOAD.
;     Sprite images, tile images, tile maps, palettes ($1FA00),
;     charsets ($1F000), bitmaps: every community exporter (Aloevera,
;     X16PngConverter, TilemapEd, tmx2vera, the GIMP plugins) emits
;     exactly this -- raw VERA data behind the standard 2-byte header.
;       in:  A/X = filename, Y = length
;            P0/P1 = VRAM address, P2 = VRAM bank (0/1)
;            P3 bit 0 = the file is RAW (headerless); else the 2-byte
;            header is skipped, the ecosystem default
;       out: carry clear, P4/P5 = one past the last VRAM byte written
;            carry set, A = the KERNAL error code
;
;   cx_bload (slot 91) -- a file into banked RAM, the BASIC BVLOAD.
;     ZSM music for a future player, level data, collision maps -- the
;     KERNAL wraps banks at $BFFF on its own, so a big asset just keeps
;     going. Banks below CX_APP_BANK_FLOOR (20 -- banks.inc, the ledger
;     in docs/memory-map.md) belong to the kernel and are refused.
;       in:  A/X = filename, Y = length
;            P0 = the first RAM bank (20+), P1/P2 = address ($A000+)
;            P3 bit 0 = raw, as above
;       out: carry clear, P4/P5 = one past the last byte, P6 = the bank
;            it ended in
;            carry set, A = the KERNAL error code, or 0 for a refused
;            bank
;
; Interrupts are OFF around the KERNAL LOAD (the event IRQ's GETIN and
; an open channel do not mix -- the dir.asm/loader.asm trap).
;
; The marshalling rides bank 18 -- the fs/system theme bank (banks.inc)
; -- like the rest of the file code. The one thing banked code cannot do
; is flip RAM_BANK out from under itself, so cx_bload's actual LOAD runs
; through a small resident trampoline (as_bload_go, which stays in CODE).
; =====================================================================

cx_do_vload
    jsr cxb_call
    .byte CX_FS_BANK
    .addr as_vload
cx_do_bload
    jsr cxb_call
    .byte CX_FS_BANK
    .addr as_bload

; --- the resident trampoline: LOAD with RAM_BANK elsewhere ------------
;   in:  A = the target bank, X16_T4/T5 = the address, SETNAM/SETLFS done
;   out: LOAD's carry/A/X/Y, X16_P6 = the bank the load ended in;
;        RAM_BANK back where it was (bank 2, mid-cxb_call)
as_bload_go
    ldy RAM_BANK                ; the caller's bank, parked in a temp --
    sty X16_T6                  ; X/Y must come back holding LOAD's end
    sta RAM_BANK                ; address untouched
    lda #0                      ; LOAD: into system RAM
    ldx X16_T4
    ldy X16_T5
    jsr LOAD
    php                         ; LOAD's flags and error code survive
    pha                         ; the bank bookkeeping below
    lda RAM_BANK                ; where the wrap left it
    sta X16_P6
    lda X16_T6
    sta RAM_BANK
    pla
    plp
    rts

.segment "B18CODE"

.include "storage/load.asm"

; the shared marshal: ABI name/len (A/X/Y) into the module's P block.
; The ABI's P0-P3 are read FIRST -- the module wants its own meanings
; in those bytes. Leaves the destination in P5/P6, the flag-derived
; secondary address in P4, name/len in P0-P2, device in P3.
as_marshal
    sta X16_T0                  ; the name, parked
    stx X16_T1
    sty X16_T2

    lda X16_P3                  ; the raw flag decides the secondary
    and #$01                    ; address before P3 becomes the device
    beq @headered
    lda #FS_SA_RAW
    bra @sa
@headered
    lda #FS_SA_ADDR
@sa
    tay                         ; parked in Y across the shuffle

    lda X16_P1                  ; destination address -> P5/P6
    sta X16_P5
    lda X16_P2
    sta X16_P6
    lda X16_P0                  ; the caller's bank byte, returned in A
    pha

    lda X16_T0                  ; name/len -> P0-P2, device -> P3
    sta X16_P0
    lda X16_T1
    sta X16_P1
    lda X16_T2
    sta X16_P2
    lda #8
    sta X16_P3
    sty X16_P4                  ; the secondary address

    pla
    rts

; cx_vload -- ABI: P0/P1 = VRAM address, P2 = VRAM bank. The marshal
; wants the bank in P0 and the address in P1/P2, so rotate first --
; touching only A and a temp, because X/Y still carry the name and
; length the marshal is about to park.
as_vload
    pha                         ; the name low byte, briefly
    lda X16_P2                  ; bank aside...
    sta X16_T4
    lda X16_P1                  ; ...address up one...
    sta X16_P2
    lda X16_P0
    sta X16_P1
    lda X16_T4                  ; ...bank into the marshal's P0
    sta X16_P0
    pla
    jsr as_marshal              ; -> A = the VRAM bank
    and #$01
    clc
    adc #2                      ; LOAD A: VRAM bank 0 -> 2, 1 -> 3
    php
    sei                         ; no IRQ over an open channel
    jsr load_load_common
    bcs @bad
    stx X16_P4                  ; one past the last byte
    sty X16_P5
    plp
    clc
    rts
@bad
    plp
    sec
    rts

; cx_bload -- P0 = RAM bank (CX_APP_BANK_FLOOR+), P1/P2 = address
as_bload
    jsr as_marshal              ; A = the requested bank
    cmp #CX_APP_BANK_FLOOR      ; the kernel's banks are not on offer
    bcc @refused
    pha
    lda X16_P5                  ; the trampoline takes the address in
    sta X16_T4                  ; T4/T5 -- LOAD's A carries the bank
    lda X16_P6
    sta X16_T5
    lda X16_P2                  ; SETNAM/SETLFS here, banked; only the
    jsr fs_setname              ; LOAD itself crosses to the resident
    lda #1                      ; trampoline
    ldx X16_P3
    ldy X16_P4
    jsr SETLFS
    pla
    php
    sei
    jsr as_bload_go
    bcs @bad
    stx X16_P4                  ; one past the last byte (P6 = end bank,
    sty X16_P5                  ; the trampoline filled it)
    plp
    clc
    rts
@bad
    plp
    sec
    rts
@refused
    lda #0
    sec
    rts

.segment "CODE"
