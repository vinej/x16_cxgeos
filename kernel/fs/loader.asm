; ca65
; =====================================================================
; CXGEOS :: kernel/fs/loader.asm -- cx_app_load, the way an app starts
; =====================================================================
; A CXAP is a 32-byte header in front of an ordinary PRG -- see
; docs/formats.md. The header exists so that any of the twelve
; toolchains' stock output becomes an app by prepending 32 bytes
; (tools/mkcxap.py); no linker scripts were harmed.
;
; The header is judged BEFORE the PRG is let anywhere near memory. The
; caller is about to be overwritten by what it asked for, so everything
; that can be refused -- wrong magic, an app that needs a newer kernel,
; a load address that is not $0801, an entry outside app space -- is
; refused while the caller is still intact and can hear the carry.
; After the first payload byte there is no going back: an I/O failure
; past that point lands in cxl_fatal, which puts the text screen up,
; says what happened, and stops, because the machine no longer contains
; a program to return to.
;
; On success the hardware stack is reset and the app ZP ($60-$7F) is
; zeroed -- every app starts in the same machine, whoever launched it.
; =====================================================================

; The header is staged at $0400, below app space, in RAM the KERNAL
; leaves alone -- judging it there costs the resident budget nothing,
; and the entry vector can be jumped through where it lies.
CXL_HDR    = $0400
CXL_MINABI = CXL_HDR+4
CXL_ENTRY  = CXL_HDR+6

CXL_LFN    = 1                  ; the loader's logical file
CXL_DEV    = 8

CX_APP_BASE = $0801
CX_APP_TOP  = $8000             ; exclusive: the kernel's header is here,
                                ; and one byte past it is the jump table
                                ; every app depends on

; The refusal exit sits above the entry so that every validation branch
; below reaches it backward: branches are eight bits, and the
; validations span more than a hundred bytes.
cxl_old
    lda #2                      ; needs a newer kernel
    bra cxl_refuse
cxl_bad
    lda #1                      ; not there, or not an app
cxl_refuse
    pha
    jsr CLRCHN
    lda #CXL_LFN
    jsr CLOSE
    cli                         ; the load masked interrupts (below); a
    pla                         ; refused caller gets its event loop back
    sec
    rts

cxl_load
    ; The ABI passes the name the way every other call passes a string:
    ; A/X = pointer, Y = length. SETNAM wants the length in A.
    sta X16_T0
    stx X16_T1
    tya
    ldx X16_T0
    ldy X16_T1
    jsr SETNAM
    lda #CXL_LFN
    ldx #CXL_DEV
    ldy #2                      ; a raw byte stream: OPEN hands over the
    jsr SETLFS                  ; PRG load address too, LOAD would eat it
    ; INTERRUPTS OFF for the whole load. CHKIN below makes LFN 1 the
    ; current input channel, and the caller's still-live event IRQ drains
    ; the keyboard with GETIN -- which reads the current channel and would
    ; steal bytes out of the app being loaded, corrupting it into a crash
    ; (the same trap as kernel/fs/dir.asm, but here it wrecks code). Every
    ; exit restores them: cxl_refuse, @done via cli, cxl_fatal halts.
    sei
    jsr OPEN
    bcs cxl_bad
    ldx #CXL_LFN
    jsr CHKIN
    bcs cxl_bad

    ldy #0                      ; the 32 header bytes, staged and judged
@hdr
    jsr CHRIN
    sta CXL_HDR,y
    jsr READST                  ; EOF inside the header: whatever this
    bne cxl_bad                 ; is -- missing, empty, tiny -- not an app
    iny
    cpy #32
    bne @hdr

    ldy #3                      ; the magic
@magic
    lda CXL_HDR,y
    cmp cxl_sig,y
    bne cxl_bad
    dey
    bpl @magic

    ; The app's floor, 16-bit: an app that calls slots this kernel does
    ; not have is refused here, with its caller intact -- not started,
    ; to crash on the first call past the table's end.
    lda cx_hdr_version+1
    cmp CXL_MINABI+1
    bcc cxl_old
    bne @okver
    lda cx_hdr_version
    cmp CXL_MINABI
    bcc cxl_old
@okver

    lda CXL_ENTRY+1             ; the entry must be inside app space
    cmp #>CX_APP_BASE
    bcc cxl_bad
    cmp #>CX_APP_TOP
    bcs cxl_bad

    jsr CHRIN                   ; the PRG's own load address: apps are
    cmp #<CX_APP_BASE           ; built at $0801, and a file that says
    bne cxl_bad                 ; anything else is refused, not relocated
    jsr CHRIN
    cmp #>CX_APP_BASE
    bne cxl_bad
    jsr READST
    bne cxl_bad

    ; ---- the point of no return: the caller is overwritten from here --
    lda #<CX_APP_BASE
    sta X16_T0
    lda #>CX_APP_TOP            ; T2 = first page the payload must not
    sta X16_T2                  ; reach; the page compares against it
    lda #>CX_APP_BASE
    sta X16_T1

@chunk
    sec                         ; how much room is left below $8000
    lda #<CX_APP_TOP
    sbc X16_T0
    tay
    lda #>CX_APP_TOP
    sbc X16_T1
    bne @page                   ; 256 or more: ask for a full 255
    cpy #0
    beq @toobig                 ; no room, and the file has more
    bra @take
@page
    ldy #$FF
@take
    tya
    ldx X16_T0
    ldy X16_T1
    clc                         ; MACPTR: a block at once, pointer
    jsr MACPTR                  ; advanced the normal way
    bcs @slow                   ; the device cannot: byte at a time
    txa                         ; X/Y = how many arrived
    clc
    adc X16_T0
    sta X16_T0
    tya
    adc X16_T1
    sta X16_T1
    jsr READST
    beq @chunk                  ; clean and more to come
    and #$40
    bne @done                   ; EOF: the whole app is in
    jmp cxl_fatal               ; a read error mid-file

; No MACPTR on this device, so CHRIN. The last byte of a CBM stream
; arrives together with the EOF bit, so store first, judge after.
@slow
    jsr CHRIN
    sta (X16_T0)
    jsr READST
    bne @sdone
    inc X16_T0
    bne @slow
    inc X16_T1
    lda X16_T1
    cmp X16_T2
    bne @slow
    bra @toobig
@sdone
    and #$40
    beq @fatal                  ; a read error mid-file
@done
    jsr CLRCHN
    lda #CXL_LFN
    jsr CLOSE
    jsr ev_stop                 ; every app starts in the same machine:
    jsr mouse_hide              ; events off, mouse hidden, app sprites
    jsr sprites_reset           ; cleared (so none linger under the next),
    cli                         ; a clean ZP; interrupts back (load masked
    ldx #$FF                    ; an empty stack. The old program is
    txs                         ; gone, and so is every return address
    ldx #$1F                    ; it ever pushed.
@zp
    stz $60,x
    dex
    bpl @zp
    jmp (CXL_ENTRY)

@fatal
    jmp cxl_fatal

@toobig
    ; The file runs into the kernel at $8000. The caller is already
    ; gone, so this is not an error return -- it is a dead machine with
    ; a polite sign, and the kernel it nearly ate is intact.
    jmp cxl_fatal

; ---------------------------------------------------------------------
; cxl_fatal -- a load died after the point of no return. Text mode, a
; message the KERNAL can print without our font, and a stop. Reached
; from mid-stream I/O errors and from a payload that overran app space.
; ---------------------------------------------------------------------
cxl_fatal
    jsr CLRCHN
    lda #CXL_LFN
    jsr CLOSE
    vera_addrsel 0
    lda #$80
    clc
    jsr SCREEN_MODE
    ldx #0
@msg
    lda cxl_dead,x
    beq @halt
    jsr CHROUT
    inx
    bra @msg
@halt
    bra @halt

cxl_sig   .byte "CXAP"
cxl_dead  .byte $0D, "CXGEOS: A LOAD DIED MID-STREAM.", $0D
          .byte "RESET THE MACHINE.", $0D, 0

; The shell's name lives with the loader because cx_exit is a load: an
; app that is done is replaced by the shell, from disk, every time.
; Root-anchored ("//" is CMDR-DOS for the root), because the desktop
; can CD into a folder -- an app quit down there must still find home.
cxl_shell     .byte "//:SHELL.CXA"
CXL_SHELL_LEN = * - cxl_shell
cxl_noshell   .byte $0D, "CXGEOS: NO SHELL.CXA ON THIS DISK.", $0D, 0
