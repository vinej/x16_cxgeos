; ca65
; =====================================================================
; CXGEOS :: kernel/fs/dosglue.asm -- the DOS command channel (bank 18)
; =====================================================================
; The library's storage/dos.asm does all the work: send any CMDR-DOS
; command on channel 15, read the "62,FILE NOT FOUND,00,00" reply, hand
; back the numeric code with the carry flagging the error class. It is
; included HERE, into bank 18 -- the fs/system theme bank (banks.inc)
; -- not through the X16_USE_DOS gate: the module is ~400 bytes with
; its buffers and the resident budget has no room -- and no caller is
; latency-sensitive, so a far call costs nothing that matters.
;
; The reply text lands in dos_msg, which travels with the code into
; bank 18 where an app cannot see it; cx_dos_msg copies it into a
; caller buffer.
; =====================================================================

; the slots' resident stubs. dos_cmd and b2_dos_msg are far-called by
; label now (they used bank 2's local table while dos shared that bank;
; the b2_table rows 7 and 13 are retired to mn_off).
;
; cx_do_dos_cmd masks interrupts across the whole command: dos_cmd does
; CHKIN #15 and reads the reply with CHRIN, and the event IRQ's GETIN
; reads the current channel -- a firing IRQ would steal reply bytes the
; way it stole directory bytes (kernel/fs/dir.asm). cli preserves A and
; the carry, which are dos_cmd's return, so the result survives. The
; sei/cli wrapper is resident and bank-independent, so the move is just
; the callee's bank byte.
cx_do_dos_cmd
    sei
    jsr @go
    cli
    rts
@go
    jsr cxb_call
    .byte CX_FS_BANK
    .addr dos_cmd
cx_do_dos_msg
    jsr cxb_call
    .byte CX_FS_BANK
    .addr b2_dos_msg

.segment "B18CODE"

.include "storage/dos.asm"

; ---------------------------------------------------------------------
; b2_dos_msg -- P0/P1 = a >=64-byte buffer: the last reply, copied out
; NUL-terminated. A = its length.
; ---------------------------------------------------------------------
b2_dos_msg
    ldy #0
@cp
    lda dos_msg,y
    sta (X16_P0),y
    beq @done
    iny
    cpy #DOS_MSG_MAX-1
    bcc @cp
    lda #0                      ; overlong: cut it, terminated
    sta (X16_P0),y
@done
    tya
    rts

.segment "CODE"
