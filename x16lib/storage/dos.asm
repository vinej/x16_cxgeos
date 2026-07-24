;ACME
; =====================================================================
; x16lib :: storage/dos.asm -- the DOS command channel
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; fs_load/fs_save report failure with the carry, but never WHY. The
; answer lives on channel 15: every command sent there is answered
; with a status line like "62,FILE NOT FOUND,00,00". These routines
; send commands, read that line, and hand back the numeric code --
; codes below 20 are success, 20 and up are errors, exactly CBM DOS's
; convention.
;
;       jsr dos_status            ; A = code, dos_msg = the text
;       lda #<name : ldx #>name : ldy #len
;       jsr dos_delete            ; carry set if the drive said no
;
; The device defaults to 8; store to dos_device to change it.
; =====================================================================

; (zone: file scope in ca65)

dos_device .byte 8

; ---------------------------------------------------------------------
; dos_cmd -- send a raw DOS command and fetch the reply
;   in:  A = command low, X = command high, Y = length (0 = none: just
;        read the pending status)
;   out: A = status code (0-99; 255 if the channel would not open)
;        carry set when the code is an error (>= 20)
;        dos_msg = the full reply, NUL-terminated; Y = its length
; ---------------------------------------------------------------------
dos_cmd
    sta X16_T0
    stx X16_T1
    tya                         ; SETNAM wants A = length, X/Y = address
    ldx X16_T0
    ldy X16_T1
    jsr SETNAM

    lda #15
    ldx dos_device
    ldy #15                     ; secondary 15: the command channel
    jsr SETLFS
    jsr OPEN
    bcs @no_channel

    ldx #15
    jsr CHKIN
    bcs @no_channel

    ldy #0
@read
    jsr CHRIN
    cmp #$0D                    ; the status line ends with a CR
    beq @got
    cpy #(DOS_MSG_MAX - 1)
    bcs @skip                   ; overlong: keep draining, stop storing
    sta dos_msg,y
    iny
@skip
    jsr READST
    beq @read                   ; keep going while the stream is alive
@got
    lda #0
    sta dos_msg,y
    phy
    jsr CLRCHN
    lda #15
    jsr CLOSE
    ply

    ; the code is the first two digits: "62,FILE NOT FOUND,..."
    lda dos_msg
    sec
    sbc #'0'
    sta X16_T0
    asl                         ; *10 = *8 + *2
    asl
    adc X16_T0
    asl
    sta X16_T0
    lda dos_msg+1
    sec
    sbc #'0'
    clc
    adc X16_T0
    cmp #20                     ; carry set = error class
    rts

@no_channel
    jsr CLRCHN
    lda #15
    jsr CLOSE
    stz dos_msg
    ldy #0
    lda #$FF
    sec
    rts

; ---------------------------------------------------------------------
; dos_status -- read the drive's pending status line
;   out: as dos_cmd. Note the first read after power-on returns code
;        73 (the DOS version banner) by design.
; ---------------------------------------------------------------------
dos_status
    lda #0
    tax
    tay
    jmp dos_cmd

; ---------------------------------------------------------------------
; One-call wrappers. Each takes A = name low, X = name high,
; Y = name length, and returns like dos_cmd.
;
;   dos_delete   S:name       scratch a file
;   dos_mkdir    MD:name      make a directory
;   dos_rmdir    RD:name      remove a directory
;   dos_chdir    CD:name      change directory ("//" is the root)
;
; dos_rename additionally takes the OLD name in X16_P0/P1 with its
; length in X16_P2, and renames it to the A/X/Y name:  R:new=old
; ---------------------------------------------------------------------
dos_delete
    jsr dos_stash_name
    lda #'S'
    sta dos_cmdbuf
    lda #':'
    sta dos_cmdbuf+1
    ldx #2
    bra dos_append_send

dos_mkdir
    jsr dos_stash_name
    lda #'M'
    bra dos_dir_cmd
dos_rmdir
    jsr dos_stash_name
    lda #'R'
    bra dos_dir_cmd
dos_chdir
    jsr dos_stash_name
    lda #'C'
dos_dir_cmd
    sta dos_cmdbuf
    lda #'D'
    sta dos_cmdbuf+1
    lda #':'
    sta dos_cmdbuf+2
    ldx #3
    bra dos_append_send

dos_rename
    jsr dos_stash_name             ; the NEW name
    lda #'R'
    sta dos_cmdbuf
    lda #':'
    sta dos_cmdbuf+1
    ldx #2
    jsr dos_append                 ; R:new
    bcs dos_too_long
    cpx #DOS_CMD_MAX
    bcs dos_too_long
    lda #'='
    sta dos_cmdbuf,x
    inx
    ldy #0                      ; append the OLD name from X16_P0..P2
@old
    cpy X16_P2
    beq @send
    cpx #DOS_CMD_MAX
    bcs dos_too_long
    lda (X16_P0),y
    sta dos_cmdbuf,x
    inx
    iny
    bra @old
@send
    bra dos_send

; park A/X/Y (name pointer + length) in T0/T1/T2
dos_stash_name
    sta X16_T0
    stx X16_T1
    sty X16_T2
    rts

; copy the stashed name into dos_cmdbuf at X, then send; X advances
dos_append_send
    jsr dos_append
    bcs dos_too_long
dos_send
    txa
    tay                         ; Y = total command length
    lda #<dos_cmdbuf
    ldx #>dos_cmdbuf
    jmp dos_cmd

dos_append
    ldy #0
@cp
    cpy X16_T2
    beq @done
    cpx #DOS_CMD_MAX
    bcs @too_long
    lda (X16_T0),y
    sta dos_cmdbuf,x
    inx
    iny
    bra @cp
@done
    clc
    rts
@too_long
    sec
    rts

; local construction failure: no command was sent
dos_too_long
    stz dos_msg
    ldy #0
    lda #$FF
    sec
    rts

DOS_MSG_MAX = 64
DOS_CMD_MAX = 80
dos_msg    .res DOS_MSG_MAX, 0
dos_cmdbuf .res DOS_CMD_MAX, 0

; (end zone)
