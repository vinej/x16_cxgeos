;ACME
; =====================================================================
; x16lib :: storage/load.asm -- load and save
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; Device 8 is the SD card. Filenames are (address, length), not
; NUL-terminated.
;
; Two different registers steer a load, and they are easy to conflate:
;
;   SETLFS's secondary address says how to TREAT the file:
;     0  skip the 2-byte PRG header, load at the address you pass in X/Y
;     1  skip it, load at the address the header itself names
;     2  raw: no header to skip, load everything at your X/Y address
;
;   LOAD's own A register says WHERE memory-wise:
;     0  system RAM        1  verify only
;     2  VRAM bank 0       3  VRAM bank 1
;
; (Putting 2/3 into the secondary address does NOT reach VRAM -- it
; requests a raw header-included load into system RAM.)
; =====================================================================

; (zone: file scope in ca65)

FS_SA_ADDR   = 0                ; skip the header, load at the caller's address
FS_SA_HEADER = 1                ; skip it, load at the header's own address
FS_SA_RAW    = 2                ; no header: load the whole file at the address

; ---------------------------------------------------------------------
; fs_setname -- in: X16_P0/P1 = filename address, A = length
; ---------------------------------------------------------------------
fs_setname
    ldx X16_P0
    ldy X16_P1
    jmp SETNAM

; ---------------------------------------------------------------------
; fs_load -- load a file
;   in:  X16_P0/P1 = filename address
;        X16_P2    = filename length
;        X16_P3    = device (usually 8)
;        X16_P4    = secondary address (FS_SA_*)
;        X16_P5/P6 = destination address (ignored when SA = 1)
;   out: carry clear on success; carry set with A = KERNAL error code
;        X/Y = address one past the last byte loaded
; ---------------------------------------------------------------------
fs_load
    lda #0                      ; LOAD A = 0: into system RAM
    ; fall through
; in: A = LOAD's destination code (0 RAM, 2/3 VRAM); rest as fs_load
load_load_common
    sta X16_T3
    lda X16_P2
    jsr fs_setname

    lda #1                      ; logical file number
    ldx X16_P3                  ; device
    ldy X16_P4                  ; secondary address
    jsr SETLFS

    lda X16_T3
    ldx X16_P5
    ldy X16_P6
    jmp LOAD

; ---------------------------------------------------------------------
; fs_save -- save a block of memory as a PRG
;   in:  X16_P0/P1 = filename address
;        X16_P2    = filename length
;        X16_P3    = device
;        X16_P5/P6 = start address
;        X16_T6/T7 = end address, one past the last byte
;   out: carry clear on success; carry set with A = KERNAL error code
;
;   X16_T4/T5 is borrowed as the zero-page pointer KERNAL SAVE requires.
; ---------------------------------------------------------------------
; fs_save wants five 16-bit-ish things and the parameter block is eight
; bytes, so the end address goes in T6/T7 rather than squeezing P7.
;   X16_P5/P6 = start, X16_T6/T7 = end (exclusive)
fs_save
    lda X16_P2
    jsr fs_setname

    lda #1
    ldx X16_P3
    ldy #0                      ; secondary 0: no PRG-header relocation
    jsr SETLFS

    lda X16_P5                  ; SAVE takes the start address through a
    sta X16_T4                  ; zero-page pointer, given by its address
    lda X16_P6
    sta X16_T5

    lda #X16_T4                 ; A = zero-page offset of the pointer
    ldx X16_T6                  ; X/Y = end address, exclusive
    ldy X16_T7
    jmp SAVE

; ---------------------------------------------------------------------
; fs_vload -- load straight into VRAM
;   in:  X16_P0/P1 = filename address
;        X16_P2    = filename length
;        X16_P3    = device
;        X16_P4    = VRAM bank (0 or 1)
;        X16_P5/P6 = VRAM address within that bank
;   out: as fs_load
;
; The bank turns into LOAD's A register (2 or 3); the secondary address
; is forced to 0 so the PRG header is skipped and X/Y is honoured.
; ---------------------------------------------------------------------
fs_vload
    lda X16_P4
    and #$01
    clc
    adc #2                      ; LOAD A: bank 0 -> 2, bank 1 -> 3
    stz X16_P4                  ; SETLFS SA = 0 (does not disturb A)
    bra load_load_common

; (end zone)
