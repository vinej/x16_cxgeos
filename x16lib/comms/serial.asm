;ACME
; =====================================================================
; x16lib :: comms/serial.asm -- the serial / WiFi card UARTs
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; The Commander X16 serial / WiFi card carries up to two 16C550-style
; UARTs in the expansion I/O window. They live on 8-byte boundaries
; between $9F60 and $9FF8; the standard card populates $9F60 (UART 0)
; and $9F68 (UART 1). The WiFi half is an ESP32 running ZiModem, driven
; as an AT-command modem over UART 0 -- but that is a protocol on top of
; these bytes, not something this module knows about.
;
; The register file (offset from the UART's base address):
;   0  RHR/THR   receive / transmit holding    (DLL when DLAB=1)
;   1  IER       interrupt enable              (DLM when DLAB=1)
;   2  IIR/FCR   read: interrupt id / write: FIFO control
;   3  LCR       line control (word size, parity, stop, DLAB)
;   4  MCR       modem control (DTR/RTS/loop/auto-flow)
;   5  LSR       line status (DR, THRE, errors)
;   6  MSR       modem status
;   7  SCR       scratch (no hardware effect -- used to fingerprint)
;
; Typical use, 9600 baud on the standard card:
;       jsr ser_detect              ; A = count, ser_u0 = first UART
;       lda ser_u0 : ldx ser_u0+1
;       ldy #<SER_BAUD_9600 : sty X16_P0
;       ldy #>SER_BAUD_9600 : sty X16_P1
;       jsr ser_init                ; 8N1, FIFOs, auto-flow, no IRQ
;       lda #<msg : ldx #>msg : jsr ser_puts
;   poll:
;       jsr ser_get                 ; carry set = nothing waiting
;       bcs poll
;       ; A = the received byte
;
; ser_init remembers the UART it was handed; ser_put/ser_get/... all
; talk to that one. Point them elsewhere by calling ser_init again.
;
; Reads have side effects on real UARTs -- reading RHR pops the RX FIFO,
; reading LSR clears the sticky error bits -- so this module never lets
; an indexed store's dummy read fall on RHR: byte writes to THR go out
; through `sta (ptr)` (no index, no dummy read on the 65C02).
; =====================================================================

; (zone: file scope in ca65)

; --- register offsets ------------------------------------------------
SER_RHR = 0                     ; = THR on write, = DLL when DLAB set
SER_IER = 1                     ; = DLM when DLAB set
SER_FCR = 2                     ; write: FIFO control (reads IIR)
SER_LCR = 3
SER_MCR = 4
SER_LSR = 5
SER_MSR = 6
SER_SCR = 7

; --- LSR bits --------------------------------------------------------
SER_LSR_DR   = %00000001        ; a received byte is ready
SER_LSR_THRE = %00100000        ; the transmit holding register is empty

; --- baud-rate divisors (14.7456 MHz clock: 14745600 / (16 * baud)) --
; Hand these to ser_init in X16_P0 (low) / X16_P1 (high).
SER_BAUD_921600 = $0001
SER_BAUD_460800 = $0002
SER_BAUD_230400 = $0004
SER_BAUD_115200 = $0008
SER_BAUD_57600  = $0010
SER_BAUD_38400  = $0018
SER_BAUD_28800  = $0020
SER_BAUD_19200  = $0030
SER_BAUD_14400  = $0040
SER_BAUD_9600   = $0060
SER_BAUD_4800   = $00C0
SER_BAUD_2400   = $0180
SER_BAUD_1200   = $0300
SER_BAUD_600    = $0600
SER_BAUD_300    = $0C00

SER_SCAN_FIRST = $9F60          ; first candidate UART base
SER_SCAN_LAST  = $9FF8          ; last candidate UART base
SER_SCAN_STEP  = 8              ; UARTs sit on 8-byte boundaries

; ---------------------------------------------------------------------
; ser_detect -- scan the expansion window for UART chips.
;   out: A = number found (0, 1 or 2)
;        carry clear if at least one was found, set if none
;        ser_u0 = first UART base (0 if none)
;        ser_u1 = second UART base (0 if none)
;
; The probe writes and reads back three registers whose behaviour a UART
; is required to have and bare bus is not: the top nibble of IER always
; reads 0, the top two bits of MCR always read 0, and the scratch
; register holds whatever you put in it. Two different scratch patterns
; make a floating bus very unlikely to answer by accident. Interrupts
; are held off across the probe so an IRQ handler never sees the UART
; mid-fingerprint.
; ---------------------------------------------------------------------
ser_detect
    stz ser_u0
    stz ser_u0+1
    stz ser_u1
    stz ser_u1+1
    lda #<SER_SCAN_FIRST        ; X16_TPTR1 walks the candidate bases
    sta X16_T2
    lda #>SER_SCAN_FIRST
    sta X16_T3
    php
    sei
@scan
    jsr serial_probe
    bcc @next                   ; carry set from serial_probe = a UART is here
    lda ser_u0+1                ; first slot still empty?
    ora ser_u0
    bne @have_first
    lda X16_T2                  ; store as UART 0
    sta ser_u0
    lda X16_T3
    sta ser_u0+1
    bra @next
@have_first
    lda X16_T2                  ; store as UART 1 and stop
    sta ser_u1
    lda X16_T3
    sta ser_u1+1
    bra @done
@next
    clc                         ; advance the base by SER_SCAN_STEP
    lda X16_T2
    adc #SER_SCAN_STEP
    sta X16_T2
    bcc @nohi
    inc X16_T3
@nohi
    lda X16_T3                  ; past SER_SCAN_LAST?
    cmp #>SER_SCAN_LAST
    bcc @scan
    bne @done
    lda X16_T2
    cmp #<SER_SCAN_LAST
    bcc @scan
    beq @scan                   ; include SER_SCAN_LAST itself
@done
    plp
    ldx #0                      ; count the non-zero slots
    lda ser_u0
    ora ser_u0+1
    beq @c0
    inx
@c0
    lda ser_u1
    ora ser_u1+1
    beq @c1
    inx
@c1
    txa
    beq @none                   ; count 0: nothing found
    clc                         ; carry clear = at least one UART
    rts
@none
    sec
    rts

; probe the UART whose base is in X16_TPTR1 (X16_T2/T3).
;   out: carry set = a UART answered, carry clear = nothing there
; Leaves IER and MCR at 0 either way.
serial_probe
    ldy #SER_IER
    lda #$F0
    sta (X16_T2),y
    lda (X16_T2),y
    and #$F0                    ; the high nibble must read back as 0
    bne serial_no
    lda #0
    sta (X16_T2),y
    ldy #SER_MCR
    lda #$FF
    sta (X16_T2),y
    lda (X16_T2),y
    cmp #$3F                    ; bits 7,6 of MCR always read 0
    bne serial_no_mcr
    lda #0
    sta (X16_T2),y
    ldy #SER_SCR                ; scratch holds two distinct patterns
    lda #$A5
    sta (X16_T2),y
    lda (X16_T2),y
    cmp #$A5
    bne serial_no
    lda #$5A
    sta (X16_T2),y
    lda (X16_T2),y
    cmp #$5A
    bne serial_no
    sec
    rts
serial_no_mcr
    lda #0                      ; leave MCR clean before bailing
    sta (X16_T2),y
serial_no
    clc
    rts

; ---------------------------------------------------------------------
; ser_init -- program a UART for 8N1, FIFOs on, auto-flow, no interrupts.
;   in:  A = UART base low, X = UART base high
;        X16_P0/P1 = baud divisor (SER_BAUD_* constant)
; The UART becomes "the current one" for ser_put/ser_get/etc.
; ---------------------------------------------------------------------
ser_init
    sta ser_base
    stx ser_base+1
    jsr serial_load_ptr

    ldy #SER_LCR                ; DLAB = 1 to reach the divisor latch
    lda #$80
    sta (X16_T0),y
    ldy #SER_RHR               ; DLL
    lda X16_P0
    sta (X16_T0),y
    ldy #SER_IER               ; DLM
    lda X16_P1
    sta (X16_T0),y
    ldy #SER_LCR                ; 8 bits, no parity, 1 stop, DLAB = 0
    lda #$03
    sta (X16_T0),y
    ldy #SER_FCR                ; FIFO enable + reset both, RX trigger 8
    lda #$87
    sta (X16_T0),y
    ldy #SER_MCR                ; DTR+RTS, auto-flow, OUT2 (ZiModem stream)
    lda #$27
    sta (X16_T0),y
    ldy #SER_IER                ; no interrupts: this module polls
    lda #$00
    sta (X16_T0),y
    rts

; ---------------------------------------------------------------------
; ser_avail -- is a received byte waiting?
;   out: carry set = yes (LSR data-ready), carry clear = no
; ---------------------------------------------------------------------
ser_avail
    jsr serial_load_ptr
    ldy #SER_LSR
    lda (X16_T0),y
    and #SER_LSR_DR
    beq @none
    sec
    rts
@none
    clc
    rts

; ---------------------------------------------------------------------
; ser_get -- read one byte without blocking.
;   out: carry clear + A = byte if one was waiting;
;        carry set if the RX FIFO was empty (A undefined)
; ---------------------------------------------------------------------
ser_get
    jsr serial_load_ptr
    ldy #SER_LSR
    lda (X16_T0),y
    and #SER_LSR_DR
    beq @empty
    ldy #SER_RHR
    lda (X16_T0),y             ; this read pops the RX FIFO
    clc
    rts
@empty
    sec
    rts

; ---------------------------------------------------------------------
; ser_get_wait -- read one byte, blocking until one arrives.
;   out: A = byte
; Spins on the UART: only sane once something is actually connected.
; ---------------------------------------------------------------------
ser_get_wait
    jsr serial_load_ptr
@wait
    ldy #SER_LSR
    lda (X16_T0),y
    and #SER_LSR_DR
    beq @wait
    ldy #SER_RHR
    lda (X16_T0),y
    rts

; ---------------------------------------------------------------------
; ser_put -- send one byte, waiting for room in the transmit FIFO.
;   in:  A = byte
; Preserves nothing but is safe to call in a tight loop.
; ---------------------------------------------------------------------
ser_put
    pha
    jsr serial_load_ptr
@wait
    ldy #SER_LSR
    lda (X16_T0),y
    and #SER_LSR_THRE
    beq @wait                   ; hold until the holding register is empty
    pla
    sta (X16_T0)                ; THR write: no index, so no dummy read
    rts

; ---------------------------------------------------------------------
; ser_puts -- send a NUL-terminated string.
;   in:  A = string low, X = string high
; ---------------------------------------------------------------------
ser_puts
    sta X16_P2
    stx X16_P3
    ldy #0
@loop
    lda (X16_P2),y
    beq @done
    phy
    jsr ser_put
    ply
    iny
    bne @loop
@done
    rts

; ---------------------------------------------------------------------
; ser_write -- send a counted (binary-safe) run of bytes.
;   in:  A = data low, X = data high, Y = length (1..255; 0 = 256)
; ---------------------------------------------------------------------
ser_write
    sta X16_P2
    stx X16_P3
    sty X16_P4                  ; remaining count
    ldy #0
@loop
    phy
    lda (X16_P2),y
    jsr ser_put
    ply
    iny
    dec X16_P4
    bne @loop
    rts

; ---------------------------------------------------------------------
; ser_read_until -- read into a buffer until a match string is seen.
;   in:  A = match low, X = match high (NUL-terminated needle)
;        X16_P0/P1 = buffer address
;        X16_P2/P3 = max bytes to store
;   out: X16_P4/P5 = bytes actually stored
; The matched needle is included in the buffer. Stops at the match or at
; max bytes. Blocks on the UART between bytes -- for real hardware.
; ---------------------------------------------------------------------
ser_read_until
    sta X16_T4                  ; X16_TPTR2 = match base (needle start)
    stx X16_T5
    lda X16_T4                  ; X16_P6/P7 = the moving needle cursor
    sta X16_P6
    lda X16_T5
    sta X16_P7
    stz X16_P4                  ; stored count = 0
    stz X16_P5
@loop
    lda X16_P5                  ; stored >= max ?  (16-bit compare)
    cmp X16_P3
    bcc @room
    lda X16_P4
    cmp X16_P2
    bcs @done
@room
    jsr ser_get_wait            ; A = next byte
    ldy #0
    sta (X16_P0),y              ; store it
    inc X16_P0
    bne @nostorehi
    inc X16_P1
@nostorehi
    inc X16_P4                  ; ++stored (16-bit)
    bne @cmp
    inc X16_P5
@cmp
    cmp (X16_P6)                ; does it continue the needle?
    bne @reset
    inc X16_P6                  ; advance the needle cursor
    bne @noneedlehi
    inc X16_P7
@noneedlehi
    lda (X16_P6)                ; needle fully matched (next char NUL)?
    beq @done
    bra @loop
@reset
    lda X16_T4                  ; mismatch: rewind the needle cursor
    sta X16_P6
    lda X16_T5
    sta X16_P7
    bra @loop
@done
    rts

; ---------------------------------------------------------------------
; ser_discard_until -- read and throw away bytes until a match is seen.
;   in:  A = match low, X = match high (NUL-terminated needle)
; The matched needle is discarded too. Blocks on the UART -- hardware.
; ---------------------------------------------------------------------
ser_discard_until
    sta X16_T4                  ; needle base
    stx X16_T5
    lda X16_T4                  ; moving cursor in X16_P6/P7
    sta X16_P6
    lda X16_T5
    sta X16_P7
@loop
    jsr ser_get_wait
    cmp (X16_P6)
    bne @reset
    inc X16_P6
    bne @nohi
    inc X16_P7
@nohi
    lda (X16_P6)
    beq @done                   ; hit the NUL: whole needle matched
    bra @loop
@reset
    lda X16_T4
    sta X16_P6
    lda X16_T5
    sta X16_P7
    bra @loop
@done
    rts

; copy the current UART base into X16_TPTR0 for (zp),y register access
serial_load_ptr
    lda ser_base
    sta X16_T0
    lda ser_base+1
    sta X16_T0+1
    rts

ser_base .byte 0, 0             ; the UART ser_init last selected
ser_u0   .byte 0, 0             ; ser_detect results
ser_u1   .byte 0, 0

; (end zone)
