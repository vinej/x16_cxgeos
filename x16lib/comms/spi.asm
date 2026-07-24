;ACME
; =====================================================================
; x16lib :: comms/spi.asm -- VERA SPI controller helpers
; =====================================================================
; Gate: X16_USE_VERA_SPI
;
; VERA's SPI controller is exposed at VERA_SPI_DATA/CTRL. Writing DATA
; starts one full-duplex transfer; BUSY stays set until the received byte
; can be read back from DATA. SELECT asserts chip-select when set.
;
; Buffer routines use r0 = RAM pointer and r1 = byte count. They advance
; r0 to one byte past the buffer and leave r1 = 0.
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; spi_get_ctrl -- read SPI_CTRL
;   out: A = VERA_SPI_* control/status bits
; ---------------------------------------------------------------------
spi_get_ctrl
    lda VERA_SPI_CTRL
    rts

; ---------------------------------------------------------------------
; spi_set_ctrl -- write SPI_CTRL
;   in: A = VERA_SPI_SELECT/SLOWCLK/AUTOTX bits
; ---------------------------------------------------------------------
spi_set_ctrl
    sta VERA_SPI_CTRL
    rts

; ---------------------------------------------------------------------
; spi_wait -- wait for the active transfer to finish
; ---------------------------------------------------------------------
spi_wait
    bit VERA_SPI_CTRL
    bmi spi_wait
    rts

; ---------------------------------------------------------------------
; spi_select / spi_deselect -- assert or release chip-select
; ---------------------------------------------------------------------
spi_select
    lda VERA_SPI_CTRL
    ora #VERA_SPI_SELECT
    sta VERA_SPI_CTRL
    rts

spi_deselect
    lda VERA_SPI_CTRL
    and #%11111110
    sta VERA_SPI_CTRL
    rts

; ---------------------------------------------------------------------
; spi_slow / spi_fast -- select ~390 kHz or ~12.5 MHz SPI clock
; ---------------------------------------------------------------------
spi_slow
    lda VERA_SPI_CTRL
    ora #VERA_SPI_SLOWCLK
    sta VERA_SPI_CTRL
    rts

spi_fast
    lda VERA_SPI_CTRL
    and #%11111101
    sta VERA_SPI_CTRL
    rts

; ---------------------------------------------------------------------
; spi_autotx_on / spi_autotx_off
;   Auto-TX makes each SPI_DATA read start a new $FF transfer.
; ---------------------------------------------------------------------
spi_autotx_on
    lda VERA_SPI_CTRL
    ora #VERA_SPI_AUTOTX
    sta VERA_SPI_CTRL
    rts

spi_autotx_off
    lda VERA_SPI_CTRL
    and #%11111011
    sta VERA_SPI_CTRL
    rts

; ---------------------------------------------------------------------
; spi_transfer -- transmit A, wait, then return the received byte
;   in:  A = byte to transmit
;   out: A = received byte
; ---------------------------------------------------------------------
spi_transfer
    sta VERA_SPI_DATA
    jsr spi_wait
    lda VERA_SPI_DATA
    rts

; ---------------------------------------------------------------------
; spi_write -- transmit A and wait; received byte is discarded
; ---------------------------------------------------------------------
spi_write
    sta VERA_SPI_DATA
    jmp spi_wait

; ---------------------------------------------------------------------
; spi_read -- transmit $FF, wait, then return the received byte
;   out: A = received byte
; ---------------------------------------------------------------------
spi_read
    lda #$ff
    jmp spi_transfer

; ---------------------------------------------------------------------
; spi_autotx_read -- wait, then read DATA in Auto-TX mode
;   out: A = received byte; the read starts the next $FF transfer
; ---------------------------------------------------------------------
spi_autotx_read
    jsr spi_wait
    lda VERA_SPI_DATA
    rts

; ---------------------------------------------------------------------
; spi_read_bytes -- read bytes into RAM
;   in:  r0 = destination pointer, r1 = byte count
;   out: r0 advanced, r1 = 0
; ---------------------------------------------------------------------
spi_read_bytes
    lda r1L
    ora r1H
    beq @done
@loop
    jsr spi_read
    ldy #0
    sta (r0),y
    inc r0L
    bne @dec
    inc r0H
@dec
    lda r1L
    bne @dec_lo
    dec r1H
@dec_lo
    dec r1L
    lda r1L
    ora r1H
    bne @loop
@done
    rts

; ---------------------------------------------------------------------
; spi_write_bytes -- write bytes from RAM
;   in:  r0 = source pointer, r1 = byte count
;   out: r0 advanced, r1 = 0
; ---------------------------------------------------------------------
spi_write_bytes
    lda r1L
    ora r1H
    beq @done
@loop
    ldy #0
    lda (r0),y
    jsr spi_write
    inc r0L
    bne @dec
    inc r0H
@dec
    lda r1L
    bne @dec_lo
    dec r1H
@dec_lo
    dec r1L
    lda r1L
    ora r1H
    bne @loop
@done
    rts

; (end zone)
