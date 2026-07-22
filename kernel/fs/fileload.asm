; ca65
; =====================================================================
; CXRF :: kernel/fs/fileload.asm -- cx_file_load, any file into RAM
; =====================================================================
; The generic asset loader (slot 88): a bounded read of any file on the
; SD card into a caller buffer. This is how fonts and charsets become
; disk assets -- cx_file_load a .CXF then cx_font_set it; cx_file_load
; a 2KB charset then cx_vram_write it to $1F000 -- and how any future
; asset (an image, a level, a sample) gets off the disk without every
; app hand-rolling the KERNAL.
;
;   in:  A/X = filename, Y = length
;        P0/P1 = destination, P2/P3 = capacity in bytes
;   out: carry clear: P4/P5 = bytes read (the whole file)
;        carry set:   A = 1 not there / would not open
;                         2 a read error mid-file
;                         3 the file is BIGGER than the capacity -- the
;                           buffer holds its first P4/P5 (= cap) bytes
;
; The bytes are the FILE's bytes, exactly (secondary 2: a raw stream,
; nothing eaten) -- a PRG's two-byte load address, if it has one, is
; data here.
;
; Interrupts are OFF for the whole read: CHKIN makes the channel the
; current input, and the event IRQ's GETIN reads the current channel --
; it would steal file bytes (the dir.asm/loader.asm trap). Every exit
; restores them.
;
; Cold code with no claim to the resident budget: bank 18 behind a
; far-call stub, beside the directory walk in the fs/system bank.
; =====================================================================

CX_FL_LFN = 3

cx_do_file_load
    jsr cxb_call
    .byte CX_FS_BANK
    .addr fl_load

.segment "B18CODE"

fl_load
    sta X16_T0                  ; SETNAM wants length in A, name in X/Y
    stx X16_T1
    tya
    ldx X16_T0
    ldy X16_T1
    jsr SETNAM
    lda #CX_FL_LFN
    ldx #8                      ; device 8, the SD card
    ldy #2                      ; secondary 2: the raw byte stream
    jsr SETLFS

    sei                         ; before OPEN, like the app loader: no
    jsr OPEN                    ; window where the IRQ can see the channel
    bcs @nofile
    ldx #CX_FL_LFN
    jsr CHKIN
    bcs @nofile

    lda X16_P0                  ; T0/T1 walk the destination,
    sta X16_T0                  ; T2/T3 count the capacity down,
    lda X16_P1                  ; P4/P5 count the bytes up
    sta X16_T1
    lda X16_P2
    sta X16_T2
    lda X16_P3
    sta X16_T3
    stz X16_P4
    stz X16_P5

@byte
    jsr CHRIN
    pha
    jsr READST
    beq @store                  ; clean: store and continue
    and #$FF-$40                ; any bit BESIDES EOF is trouble
    bne @sick
    pla                         ; pure EOF arrives WITH the final byte:
    jsr @put                    ; store it, then the file is in
    bcs @toobig
    jsr @cleanup
    clc
    rts

@store
    pla
    jsr @put
    bcs @toobig
    bra @byte

@sick                           ; CMDR-DOS opens a missing name CLEANLY
    pla                         ; and errors the first read instead -- so
    jsr @cleanup                ; trouble before any byte means "not
    lda X16_P4                  ; there", and trouble mid-file is a real
    ora X16_P5                  ; read error
    bne @mid
    lda #1
    sec
    rts
@mid
    lda #2
    sec
    rts

@put                            ; A -> (dest++), capacity--; carry set
    ldy X16_T2                  ; when the capacity is already gone
    bne @room
    ldy X16_T3
    beq @full
@room
    sta (X16_T0)
    inc X16_T0
    bne @nc1
    inc X16_T1
@nc1
    lda X16_T2
    bne @nc2
    dec X16_T3
@nc2
    dec X16_T2
    inc X16_P4
    bne @nc3
    inc X16_P5
@nc3
    clc
    rts
@full
    sec
    rts

@nofile
    jsr @cleanup
    lda #1
    sec
    rts
@toobig
    jsr @cleanup
    lda #3
    sec
    rts

@cleanup
    jsr CLRCHN
    lda #CX_FL_LFN
    jsr CLOSE
    cli                         ; the event IRQ may read the keyboard again
    rts

.segment "CODE"
