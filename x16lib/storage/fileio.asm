;ACME
; =====================================================================
; x16lib :: storage/fileio.asm -- generic KERNAL file/channel I/O
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; This module is for streamed file/channel I/O: OPEN/CLOSE, CHKIN/CHKOUT,
; CHRIN/CHROUT, READST, and related setup calls. For one-shot PRG
; LOAD/SAVE, keep using storage/load.asm's fs_* helpers.
;
; Helper calls use:
;       X16_P0/P1 = filename address
;       X16_P2    = filename length
;       X16_P3    = logical file number
;       X16_P4    = device
;       X16_P5    = secondary address
; =====================================================================

; (zone: file scope in ca65)

FIO_DEV_KEYBOARD = 0
FIO_DEV_SCREEN   = 3
FIO_DEV_DISK     = 8
FIO_LFN_COMMAND  = 15
FIO_SA_NONE      = 0
FIO_SA_COMMAND   = 15

; --- raw KERNAL wrappers ---------------------------------------------
fio_set_lfs
    jmp SETLFS                  ; A = logical, X = device, Y = secondary

fio_set_name
    jmp SETNAM                  ; A = length, X/Y = name pointer

fio_open
    jmp OPEN

fio_close
    jmp CLOSE                   ; A = logical file number

fio_chkin
    jmp CHKIN                   ; X = logical file number

fio_chkout
    jmp CHKOUT                  ; X = logical file number

fio_clrchn
    jmp CLRCHN

fio_chrin
    jmp CHRIN

fio_chrout
    jmp CHROUT

fio_readst
    jmp READST

fio_getin
    jmp GETIN

fio_close_all
    jmp CLALL                   ; close every open logical file

fio_close_device
    jmp CLOSE_ALL               ; A = device number

; ---------------------------------------------------------------------
; fio_open_named -- SETNAM + SETLFS + OPEN from X16_P0..P5
;   out: carry follows OPEN
; ---------------------------------------------------------------------
fio_open_named
    jsr fileio_setup
    jmp OPEN

; ---------------------------------------------------------------------
; fio_open_read -- open, then select the logical file for input
;   out: carry set if OPEN or CHKIN failed
; ---------------------------------------------------------------------
fio_open_read
    jsr fio_open_named
    bcs @done
    ldx X16_P3
    jmp CHKIN
@done
    rts

; ---------------------------------------------------------------------
; fio_open_write -- open, then select the logical file for output
;   out: carry set if OPEN or CHKOUT failed
; ---------------------------------------------------------------------
fio_open_write
    jsr fio_open_named
    bcs @done
    ldx X16_P3
    jmp CHKOUT
@done
    rts

; ---------------------------------------------------------------------
; fio_close_named -- CLRCHN + CLOSE for X16_P3
; ---------------------------------------------------------------------
fio_close_named
    jsr CLRCHN
    lda X16_P3
    jmp CLOSE

fileio_setup
    lda X16_P2
    ldx X16_P0
    ldy X16_P1
    jsr SETNAM
    lda X16_P3
    ldx X16_P4
    ldy X16_P5
    jmp SETLFS

; (end zone)
