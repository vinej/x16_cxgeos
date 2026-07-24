;ACME
; =====================================================================
; x16lib :: storage/iec.asm -- low-level IEC / serial bus wrappers
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; These are direct helpers for the classic Commodore serial bus / IEC
; KERNAL calls. Most programs should use FILEIO, LOAD, DOS, or BMX
; instead; this gate is for protocols that need explicit bus control.
;
; MACPTR and MCIOUT are X16 block transfers for the current channel:
;       A   = byte count, 0 lets the implementation choose
;       X/Y = destination/source pointer
;       X/Y = bytes transferred on return
;       C   = set when unsupported/error
; =====================================================================

; (zone: file scope in ca65)

IEC_CMD_DATA  = $60             ; secondary data channel command base
IEC_CMD_CLOSE = $E0             ; close channel command base
IEC_CMD_OPEN  = $F0             ; open channel command base

; --- raw KERNAL wrappers ---------------------------------------------
iec_listen
    jmp LISTEN                  ; A = device number

iec_talk
    jmp TALK                    ; A = device number

iec_second
    jmp SECOND                  ; A = secondary/listen command byte

iec_tksa
    jmp TKSA                    ; A = secondary/talk command byte

iec_ciout
    jmp CIOUT                   ; A = byte to send

iec_acptr
    jmp ACPTR                   ; out: A = byte received

iec_unlisten
    jmp UNLSN

iec_untalk
    jmp UNTLK

iec_set_timeout
    jmp SETTMO                  ; A = timeout control (ROM r49 is a no-op)

iec_readst
    jmp READST                  ; out: A = serial/KERNAL status

iec_macptr
    jmp MACPTR                  ; block read: A=count, X/Y=dest

iec_mciout
    jmp MCIOUT                  ; block write: A=count, X/Y=source

; ---------------------------------------------------------------------
; iec_open_channel -- LISTEN device, send OPEN secondary command
;   in: A = device number, Y = secondary channel
; ---------------------------------------------------------------------
iec_open_channel
    jsr LISTEN
    tya
    ora #IEC_CMD_OPEN
    jmp SECOND

; ---------------------------------------------------------------------
; iec_data_channel -- LISTEN device, send DATA secondary command
;   in: A = device number, Y = secondary channel
; ---------------------------------------------------------------------
iec_data_channel
    jsr LISTEN
    tya
    ora #IEC_CMD_DATA
    jmp SECOND

; ---------------------------------------------------------------------
; iec_talk_channel -- TALK device, send DATA secondary command
;   in: A = device number, Y = secondary channel
; ---------------------------------------------------------------------
iec_talk_channel
    jsr TALK
    tya
    ora #IEC_CMD_DATA
    jmp TKSA

; ---------------------------------------------------------------------
; iec_close_channel -- LISTEN device, send CLOSE secondary command
;   in: A = device number, Y = secondary channel
; ---------------------------------------------------------------------
iec_close_channel
    jsr LISTEN
    tya
    ora #IEC_CMD_CLOSE
    jmp SECOND

; (end zone)
