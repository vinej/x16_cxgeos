; ca65
; =====================================================================
; CXRF :: kernel/fs/dir.asm -- reading a directory
; =====================================================================
; CMDR-DOS hands a directory back as a BASIC-program listing when you
; OPEN "$": a load address, then one "line" per entry -- a next-line
; pointer, a line number that is really the block count, and the text
; `  "NAME"   TYPE`, ended by a zero. The last line's next pointer is
; zero. This walks that stream one entry at a time so the file browser
; can build its own list without a giant fixed buffer.
;
;   cx_dir_open   A/X = the pattern (e.g. "$"), Y = length. Carry set
;                 on a DOS error.
;   cx_dir_next   P0/P1 = a >=17-byte buffer. Fills it with the entry's
;                 name and returns A = 0 file / 1 directory. Carry set
;                 means the listing is done. The FIRST entry is the
;                 volume header, not a file -- the browser shows it as
;                 the drive's name.
;   cx_dir_close  let the channel go.
;
; One logical file (2). Not re-entrant: one directory walk at a time.
;
; INTERRUPTS OFF for the whole walk. CHKIN makes LFN 2 the current input
; channel, and the event IRQ drains the keyboard with GETIN, which reads
; the CURRENT channel -- so a firing IRQ steals bytes straight out of the
; directory stream and desyncs the parse (it drew ghost "PRG" lines in
; the file browser). cx_dir_open masks interrupts once CHKIN has taken,
; cx_dir_close restores them. Directory reads are short, so the masked
; window is brief.
; =====================================================================

CX_DIR_LFN = 2

; The walk is cold code with no claim to the resident budget: it rides
; bank 18 -- the fs/system theme bank (banks.inc) -- behind far-call
; stubs. cxb_call restores the flags exactly as the banked routine left
; them, so dir_open's sei and dir_close's cli still reach the caller.
cx_do_dir_open
    jsr cxb_call
    .byte CX_FS_BANK
    .addr dir_open
cx_do_dir_next
    jsr cxb_call
    .byte CX_FS_BANK
    .addr dir_next
cx_do_dir_close
    jsr cxb_call
    .byte CX_FS_BANK
    .addr dir_close

.segment "B18CODE"

dir_open
    sta X16_T0                  ; SETNAM wants length in A, name in X/Y
    stx X16_T1
    tya
    ldx X16_T0
    ldy X16_T1
    jsr SETNAM
    lda #CX_DIR_LFN
    ldx #8                      ; device 8, the SD card
    ldy #0                      ; secondary 0: read
    jsr SETLFS
    jsr OPEN
    bcs @err
    ldx #CX_DIR_LFN
    jsr CHKIN
    bcs @err
    sei                         ; ours now -- the IRQ's GETIN must not
    jsr CHRIN                   ; touch this channel (see the header)
    jsr CHRIN                   ; the two-byte load address, discarded
    clc
    rts
@err
    rts                         ; carry from OPEN/CHKIN

dir_close
    jsr CLRCHN                  ; default input back...
    cli                         ; ...then the IRQ may read the keyboard
    lda #CX_DIR_LFN
    jmp CLOSE

; ---------------------------------------------------------------------
; cx_dir_next -- P0/P1 = the name buffer. One entry, or carry set at
; the end. A = 1 for a directory, 0 for a file.
; ---------------------------------------------------------------------
dir_next
    lda X16_P0
    sta CX_D_BUF
    lda X16_P1
    sta CX_D_BUF+1
    stz cx_d_eof

    jsr dgetc                   ; next-line pointer, low
    sta cx_d_t
    bit cx_d_eof
    bmi @end                    ; EOF: nothing more
    jsr dgetc                   ; ...high
    ora cx_d_t
    beq @end                    ; a zero pointer ends the listing

    jsr dgetc                   ; the line number = block count, ignored
    jsr dgetc

    ldy #0                      ; copy the quoted name into the buffer
@findq
    jsr dgetc
    bit cx_d_eof
    bmi @end                    ; ran off the end looking for a name
    cmp #'"'
    bne @findq
@name
    jsr dgetc
    bit cx_d_eof
    bmi @named
    cmp #'"'
    beq @named
    sta (CX_D_BUF),y
    iny
    cpy #16
    bcc @name
@named
    lda #0
    sta (CX_D_BUF),y            ; null-terminate

    lda #0                      ; the type: first non-space after the
    sta cx_d_type               ; name. 'D' (DIR) marks a directory.
@skipsp
    jsr dgetc
    bit cx_d_eof
    bmi @done
    cmp #0
    beq @done                   ; the line's end came early
    cmp #' '
    beq @skipsp
    cmp #'D'
    bne @drain
    lda #1
    sta cx_d_type
@drain
    jsr dgetc                   ; consume the rest of the line
    bit cx_d_eof
    bmi @done
    cmp #0
    bne @drain
@done
    lda cx_d_type
    clc
    rts
@end
    sec
    rts

; dgetc -- one byte from the channel in A; sets cx_d_eof (bit 7) when
; the read hit EOF or an error, so a malformed listing cannot spin a
; parse loop forever.
dgetc
    jsr CHRIN
    pha
    jsr READST
    beq @ok
    lda #$80
    sta cx_d_eof
@ok
    pla
    rts

cx_d_t    .byte 0
cx_d_type .byte 0
cx_d_eof  .byte 0

.segment "CODE"
