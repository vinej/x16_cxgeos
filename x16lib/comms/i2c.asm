;ACME
; =====================================================================
; x16lib :: comms/i2c.asm -- KERNAL I2C helper wrappers
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; These are thin wrappers over the Commander X16 KERNAL I2C jump table.
; The carry flag follows the ROM convention: carry set means NAK/error.
;
; Byte calls:
;       ldx #device                 ; 7-bit I2C device address
;       ldy #offset                 ; device register/offset
;       jsr i2c_read_byte           ; A = value, C = error
;
;       lda #value
;       ldx #device
;       ldy #offset
;       jsr i2c_write_byte          ; C = error
;
; Batch calls use the KERNAL virtual registers:
;       X  = 7-bit I2C device address
;       r0 = RAM buffer pointer
;       r1 = byte count
;       C  = 0 to advance r0 after each read, 1 to keep r0 fixed
;       r2 = bytes written by i2c_batch_write
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; i2c_read_byte -- read one byte from an I2C device offset
;   in:  X = 7-bit device address, Y = offset
;   out: A = value, X/Y preserved, carry set on error
; ---------------------------------------------------------------------
i2c_read_byte
    jmp I2C_READ_BYTE

; ---------------------------------------------------------------------
; i2c_write_byte -- write one byte to an I2C device offset
;   in:  A = value, X = 7-bit device address, Y = offset
;   out: X/Y preserved, carry set on error
; ---------------------------------------------------------------------
i2c_write_byte
    jmp I2C_WRITE_BYTE

; ---------------------------------------------------------------------
; i2c_batch_read -- read bytes into RAM through r0
;   in:  X = 7-bit device address, r0 = buffer, r1 = byte count
;        C = 0 advance buffer pointer, C = 1 keep pointer fixed
;   out: X/r0/r1 preserved, carry set on error
; ---------------------------------------------------------------------
i2c_batch_read
    jmp I2C_BATCH_READ

; ---------------------------------------------------------------------
; i2c_batch_write -- write bytes from RAM through r0
;   in:  X = 7-bit device address, r0 = buffer, r1 = byte count
;   out: X/r0/r1 preserved, r2 = byte count written, carry set on error
; ---------------------------------------------------------------------
i2c_batch_write
    jmp I2C_BATCH_WRITE

; (end zone)
