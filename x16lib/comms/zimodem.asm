;ACME
; =====================================================================
; x16lib :: comms/zimodem.asm -- ZiModem (ESP32 WiFi) over the serial card
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; The WiFi half of the serial card is an ESP32 running ZiModem firmware.
; You drive it as a Hayes-style modem: send "AT..." command lines over
; UART 0 and read the replies back, "OK\r\n" on success. This layer is a
; thin skin over comms/serial.asm's ser_* primitives -- it frames the AT
; commands and matches the replies; it is not the ESP32 firmware.
;
;       lda #<uart : ldx #>uart          ; a base from ser_detect
;       lda #<SER_BAUD_115200 : sta X16_P0
;       lda #>SER_BAUD_115200 : sta X16_P1
;       jsr zi_init                      ; reset the modem to a known state
;       lda #<atcmd : ldx #>atcmd
;       jsr zi_cmd                       ; e.g. "atd..." to dial a host
;       jsr zi_wait_ok
;
; zi_init leaves the same UART selected that ser_init did, so every ser_*
; call keeps working alongside these.
;
; A NOTE ON TESTING. Unlike the base UART module, ZiModem is an
; interactive protocol: nearly every routine here blocks reading the
; ESP32's reply (through ser_discard_until / ser_read_until / ser_get_wait).
; The bundled emulator has no ESP32 and never fills the receive FIFO, so
; those flows cannot run headless -- they are verified on real hardware.
; What the test suite DOES pin on-target is the one piece of real logic:
; zi_hexdecode (the hex-mode payload decoder), plus zi_cmd's transmit
; path, plus 7-way byte parity. The rest is documented, not emulator-run.
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; zi_init -- put the ESP32 into a known command state.
;   in:  A = UART base low, X = UART base high
;        X16_P0/P1 = baud divisor (SER_BAUD_* constant)
; Programs the UART (ser_init), lets the board settle, aborts any stream
; left running with CTRL-C, then applies the standard ZiModem config
; (echo off, verbose result codes, stream mode) and waits for "OK".
; ---------------------------------------------------------------------
zi_init
    jsr ser_init                ; program + select the UART
    lda #4                      ; the ESP32 may still be booting
    jsr zi_delay
    lda #$03                    ; CTRL-C: abort any prior file stream
    jsr ser_put
    lda #2
    jsr zi_delay
    lda #<zi_cfg                ; ate0q0v1x1f0r1s45=3&p0&k3
    ldx #>zi_cfg
    jsr zi_cmd
    jmp zi_wait_ok

; ---------------------------------------------------------------------
; zi_reset -- issue ATZ, returning the modem to its saved profile.
; ---------------------------------------------------------------------
zi_reset
    lda #$03
    jsr ser_put
    lda #2
    jsr zi_delay
    lda #<zi_atz
    ldx #>zi_atz
    jsr zi_cmd
    jmp zi_wait_ok

; ---------------------------------------------------------------------
; zi_cmd -- send an AT command line.
;   in:  A = command low, X = command high (NUL-terminated, no CR)
; Appends the CR/LF the firmware expects. Pure transmit -- it does NOT
; read the reply; follow with zi_wait_ok (or your own read) when the
; command answers with "OK".
; ---------------------------------------------------------------------
zi_cmd
    jsr ser_puts                ; the command text
    lda #<zi_crlf
    ldx #>zi_crlf
    jmp ser_puts                ; the line ending

; ---------------------------------------------------------------------
; zi_wait_ok -- read and discard the reply up to and including "OK\r\n".
; Blocks on the UART -- for a connected board.
; ---------------------------------------------------------------------
zi_wait_ok
    lda #<zi_ok
    ldx #>zi_ok
    jmp ser_discard_until

; ---------------------------------------------------------------------
; zi_get_ip -- fetch the current IPv4 address as a NUL-terminated string.
;   in:  A = buffer low, X = buffer high (>= 25 bytes)
; Sends ATI2, reads the reply, and trims it at the first whitespace so
; the buffer holds just the dotted-quad. Blocks -- hardware.
; ---------------------------------------------------------------------
zi_get_ip
    sta zi_dest
    stx zi_dest+1
    lda #<zi_ati2
    ldx #>zi_ati2
    jsr zi_cmd                  ; ATI2 -> the board prints its IP then OK
    lda zi_dest                 ; read the reply into the caller's buffer
    sta X16_P0
    lda zi_dest+1
    sta X16_P1
    lda #24
    sta X16_P2
    stz X16_P3
    lda #<zi_ok
    ldx #>zi_ok
    jsr ser_read_until          ; up to and including "OK\r\n"
    lda zi_dest                 ; a zero-page cursor to walk the reply
    sta X16_T0
    lda zi_dest+1
    sta X16_T0+1
    ldy #0                      ; trim at the first control/space char
@scan
    lda (X16_T0),y
    cmp #' '+1                  ; anything <= space ends the address
    bcc @cut
    iny
    bne @scan
@cut
    lda #0
    sta (X16_T0),y
    rts

; ---------------------------------------------------------------------
; zi_hex_open -- begin a hex-mode file download.
;   in:  A = filename/URL low, X = filename/URL high (NUL-terminated)
;   out: carry clear = transfer started, carry set = file not found
; Switches the board to hex transfer, requests the file, and eats the
; "[..header..]" line. Then pull the payload with zi_hex_chunk until it
; returns 0, and finish with zi_hex_close. Blocks -- hardware.
; ---------------------------------------------------------------------
zi_hex_open
    sta zi_fname
    stx zi_fname+1
    lda #<zi_ats45              ; ats45=1 : enable hex-mode transfer
    ldx #>zi_ats45
    jsr zi_cmd
    jsr zi_wait_ok
    lda #<zi_atg                ; at&g"
    ldx #>zi_atg
    jsr ser_puts
    lda zi_fname
    ldx zi_fname+1
    jsr ser_puts                ; the filename
    lda #<zi_qcrlf              ; " CR LF
    ldx #>zi_qcrlf
    jsr ser_puts
    jsr ser_get_wait            ; '[' opens the header, anything else errs
    cmp #'['
    bne @err
    lda #<zi_crlf               ; skip the rest of the header line
    ldx #>zi_crlf
    jsr ser_discard_until
    clc
    rts
@err
    lda #<zi_rrerr              ; drain to the end of the "ERROR" line
    ldx #>zi_rrerr
    jsr ser_discard_until
    sec
    rts

; ---------------------------------------------------------------------
; zi_hex_chunk -- read the next payload chunk of a hex-mode download.
;   in:  A = buffer low, X = buffer high (must hold >= 44 bytes)
;   out: A = bytes decoded into the buffer, 0 when the file is done
; One hex line -> up to 44 raw bytes. Blocks on the UART -- hardware.
; ---------------------------------------------------------------------
zi_hex_chunk
    sta zi_dest
    stx zi_dest+1
    lda #<zi_linebuf            ; read one CR/LF-terminated line
    sta X16_P0
    lda #>zi_linebuf
    sta X16_P1
    lda #90
    sta X16_P2
    stz X16_P3
    lda #<zi_crlf
    ldx #>zi_crlf
    jsr ser_read_until          ; P4/P5 = bytes stored (incl. the CR/LF)
    lda X16_P5
    bne @data
    lda X16_P4                  ; "OK\r\n" (4 bytes, starts 'O') ends it
    cmp #4
    bne @data
    lda zi_linebuf
    cmp #'O'
    bne @data
    lda #0
    rts
@data
    lda X16_P4                  ; digits = line length minus the CR/LF
    sec
    sbc #2
    tay
    lda zi_dest                 ; decode into the caller's buffer
    sta X16_P0
    lda zi_dest+1
    sta X16_P1
    lda #<zi_linebuf
    ldx #>zi_linebuf
    jmp zi_hexdecode            ; returns A = bytes produced

; ---------------------------------------------------------------------
; zi_hex_close -- swallow the trailing "OK" after the payload.
; ---------------------------------------------------------------------
zi_hex_close
    jmp zi_wait_ok

; ---------------------------------------------------------------------
; zi_hexdecode -- turn a run of ASCII hex digits into packed bytes.
;   in:  A = source low, X = source high (uppercase hex text)
;        Y = number of digits (even)
;        X16_P0/P1 = destination pointer
;   out: A = bytes written (Y / 2); X16_P0/P1 advanced past them
; The one piece of ZiModem logic with an independent oracle, so it is a
; standalone routine the test suite drives directly.
; ---------------------------------------------------------------------
zi_hexdecode
    sta X16_T4                  ; T4/T5 = source cursor
    stx X16_T5
    sty X16_T6                  ; T6 = digits left
    stz X16_T7                  ; T7 = bytes produced
@loop
    lda X16_T6
    beq @done
    ldy #0
    lda (X16_T4),y              ; high nibble digit
    jsr zimodem_nib
    asl
    asl
    asl
    asl
    sta X16_T3
    ldy #1
    lda (X16_T4),y              ; low nibble digit
    jsr zimodem_nib
    ora X16_T3
    sta (X16_P0)                ; store the packed byte
    inc X16_P0
    bne @dst
    inc X16_P1
@dst
    lda X16_T4                  ; source += 2
    clc
    adc #2
    sta X16_T4
    bcc @src
    inc X16_T5
@src
    inc X16_T7
    dec X16_T6
    dec X16_T6
    bra @loop
@done
    lda X16_T7
    rts

; one ASCII hex digit in A -> its 0..15 value (uppercase A-F)
zimodem_nib
    sec
    sbc #'0'
    cmp #10
    bcc zimodem_nib_lo
    sbc #('A' - '0' - 10)       ; = 7: fold 'A'..'F' onto 10..15
zimodem_nib_lo
    rts

; ---------------------------------------------------------------------
; zi_delay -- a coarse busy-wait so the ESP32 can keep up.
;   in:  A = ticks (~40 ms each at 8 MHz; timing is approximate)
; Self-contained (no jiffy IRQ, no KERNAL), so it works in any context.
; ---------------------------------------------------------------------
zi_delay
    tax
    beq @done
@tick
    lda #0                      ; A: 256-step middle counter
@mid
    ldy #0
@inner
    iny
    bne @inner                  ; 256 inner steps
    inc a
    bne @mid                    ; 256 middle steps -> 65536 inner
    dex
    bne @tick
@done
    rts

; --- data ------------------------------------------------------------
zi_cfg   .byte "ate0q0v1x1f0r1s45=3&p0&k3", $00
zi_atz   .byte "atz", $00
zi_ati2  .byte "ati2", $00
zi_ats45 .byte "ats45=1", $00
zi_atg   .byte "at&g", $22, $00     ; at&g"
zi_qcrlf .byte $22, $0D, $0A, $00   ; " CR LF
zi_crlf  .byte $0D, $0A, $00
zi_ok    .byte "OK", $0D, $0A, $00
zi_rrerr .byte "RROR", $0D, $0A, $00

zi_dest  .byte 0, 0                 ; caller's current destination buffer
zi_fname .byte 0, 0
zi_linebuf .res 90, 0              ; one hex line, read before decoding

; (end zone)
