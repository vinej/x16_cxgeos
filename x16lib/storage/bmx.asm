;ACME
; =====================================================================
; x16lib :: storage/bmx.asm -- the X16's native bitmap file format
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; BMX version 1 (the format Prog8 and the community tools write):
;
;   offset  size  field
;   0-2     3     magic "BMX"
;   3       1     version (1)
;   4       1     bits per pixel (1/2/4/8)
;   5       1     VERA colour depth code (0-3; log2 of the bpp)
;   6-7     2     width in pixels, little-endian
;   8-9     2     height
;   10      1     palette entries (0 means 256)
;   11      1     first palette index
;   12-13   2     file offset of the pixel data
;   14      1     compression (0 = none; nothing else is supported)
;   15      1     border colour
;
; The palette follows the header (2 bytes per entry, GB then R --
; VERA's own layout), the pixel data follows the palette.
;
; Rows are written to VRAM bmx_stride bytes apart (default 320, the
; full-screen bitmap stride) -- so a 320-wide image is a plain
; contiguous load, and a narrower one lands as a "stamp" with the
; surrounding pixels untouched. bmx_save reads rows the same way.
;
; CAVEAT for bmx_save: the palette region of VRAM reads back the last
; value the HOST wrote (see const_vera.asm), so the palette saved is
; only meaningful if this program set those entries itself (pal_set /
; pal_load / a previous bmx_load).
; =====================================================================

; (zone: file scope in ca65)

; Filled in by bmx_load's header parse; set by the caller for bmx_save.
bmx_width    .word 0
bmx_height   .word 0
bmx_bpp      .byte 8
bmx_palstart .byte 0
bmx_palcount .word 256          ; 1-256 entries
bmx_border   .byte 0
bmx_stride   .word 320          ; VRAM bytes between row starts

BMX_ERR_IO     = 1              ; open/read/write failed
BMX_ERR_FORMAT = 2              ; not a BMX, or not version 1
BMX_ERR_PACKED = 3              ; compressed data is not supported

; ---------------------------------------------------------------------
; bmx_load -- load a BMX file: palette into the VERA palette, pixels
;             into VRAM
;   in:  X16_P0/P1 = filename address, X16_P2 = length
;        X16_P3    = device (usually 8)
;        X16_P4    = VRAM bank (0/1), X16_P5/P6 = VRAM address
;   out: carry clear on success, set with A = BMX_ERR_* on failure
;        bmx_width/height/bpp/palstart/palcount/border reflect the file
; ---------------------------------------------------------------------
bmx_load
    jsr bmx_open_read
    bcc @hdr
    lda #BMX_ERR_IO
    rts
@hdr
    ldx #0                      ; pull in the 16-byte header
@get_hdr
    jsr CHRIN
    sta bmx_hdr,x
    inx
    cpx #16
    bne @get_hdr

    ; OPEN and CHKIN both succeed for a file that does not exist: CBM DOS
    ; reports "62,FILE NOT FOUND" on the command channel, and the KERNAL
    ; only surfaces it in ST once a read has been attempted. Without this
    ; check the 16 CHRINs above return junk, the magic test below fails,
    ; and a missing file is reported as BMX_ERR_FORMAT -- "this is not a
    ; BMX" rather than "this is not there". ST is likewise nonzero for a
    ; header shorter than 16 bytes, which is an I/O error too. A real BMX
    ; has palette and pixels after byte 16, so EOF cannot legitimately be
    ; set at this point.
    jsr READST
    beq @validate
    lda #BMX_ERR_IO
    bra @close_err

@validate
    lda bmx_hdr                 ; validate
    cmp #'B'
    bne @bad_fmt
    lda bmx_hdr+1
    cmp #'M'
    bne @bad_fmt
    lda bmx_hdr+2
    cmp #'X'
    bne @bad_fmt
    lda bmx_hdr+3
    cmp #1
    bne @bad_fmt
    lda bmx_hdr+14
    beq @fmt_ok
    lda #BMX_ERR_PACKED
    bra @close_err
@bad_fmt
    lda #BMX_ERR_FORMAT
@close_err
    pha
    jsr bmx_close_read
    pla
    sec
    rts

@fmt_ok
    lda bmx_hdr+4               ; publish the header fields
    sta bmx_bpp
    lda bmx_hdr+6
    sta bmx_width
    lda bmx_hdr+7
    sta bmx_width+1
    lda bmx_hdr+8
    sta bmx_height
    lda bmx_hdr+9
    sta bmx_height+1
    lda bmx_hdr+11
    sta bmx_palstart
    lda bmx_hdr+15
    sta bmx_border
    lda bmx_hdr+10
    sta bmx_palcount
    stz bmx_palcount+1
    bne @pal_n
    inc bmx_palcount+1          ; 0 in the file means 256
@pal_n

    ; --- palette -> $1FA00 + palstart*2 -------------------------------
    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL
    lda bmx_palstart
    asl                         ; carry = address bit 8
    sta VERA_ADDR_L
    lda #>VRAM_PALETTE
    adc #0
    sta VERA_ADDR_M
    lda #(VERA_ADDR_H_BANK | (VERA_INC_1 << 4))
    sta VERA_ADDR_H

    lda bmx_palcount            ; byte count = entries * 2
    sta bmx_cnt
    lda bmx_palcount+1
    sta bmx_cnt+1
    asl bmx_cnt
    rol bmx_cnt+1
    jsr bmx_bulk_read              ; MACPTR into DATA0; CHRIN fallback
    bcc @pal_done
    jmp @io_short
@pal_done

    ; --- skip any gap up to the header's data offset -------------------
    ; expected position so far = 16 + palcount*2
    lda bmx_palcount
    sta bmx_cnt
    lda bmx_palcount+1
    sta bmx_cnt+1
    asl bmx_cnt
    rol bmx_cnt+1
    clc
    lda bmx_cnt
    adc #16
    sta bmx_cnt
    lda bmx_cnt+1
    adc #0
    sta bmx_cnt+1
    sec                         ; gap = data offset - position
    lda bmx_hdr+12
    sbc bmx_cnt
    sta bmx_cnt
    lda bmx_hdr+13
    sbc bmx_cnt+1
    sta bmx_cnt+1
    bcc @data                   ; offset before position: trust the data
@skip
    lda bmx_cnt
    ora bmx_cnt+1
    beq @data
    jsr CHRIN
    jsr bmx_dec_cnt
    bra @skip

@data
    ; The header, the palette and any gap all came out of the file, so
    ; every pixel row must still be ahead of us. A nonzero ST here means
    ; the file ended somewhere in the palette or the gap. (EOF cannot be
    ; legitimate at this point unless the image has no rows at all, and a
    ; zero-height BMX describes nothing.)
    jsr READST
    cmp #0
    beq @rows_ahead
    jmp @io_short               ; @io_short is past the row loop: too far
                                ; for a relative branch from here
@rows_ahead

    ; --- pixel rows, bmx_stride apart ----------------------------------
    lda X16_P5                  ; the walking VRAM address
    sta bmx_cur
    lda X16_P6
    sta bmx_cur+1
    lda X16_P4
    and #$01
    sta bmx_cur+2
    jsr bmx_row_bytes              ; bmx_row = width >> (3 - depth)

    lda bmx_height
    sta bmx_rows
    lda bmx_height+1
    sta bmx_rows+1
@row
    lda bmx_rows
    ora bmx_rows+1
    beq @done
    jsr bmx_point_cur              ; port 0 at bmx_cur, INC_1

    lda bmx_row
    sta bmx_cnt
    lda bmx_row+1
    sta bmx_cnt+1
    jsr bmx_bulk_read              ; the whole row in MACPTR-sized gulps
    bcc @row_done
    jmp @io_short
@row_done
    clc                         ; cur += stride (17-bit)
    lda bmx_cur
    adc bmx_stride
    sta bmx_cur
    lda bmx_cur+1
    adc bmx_stride+1
    sta bmx_cur+1
    lda bmx_cur+2
    adc #0
    and #$01
    sta bmx_cur+2
    lda bmx_rows
    bne @dec_rows
    dec bmx_rows+1
@dec_rows
    dec bmx_rows

    ; ST is checked once per row, not once per byte: CHRIN is already the
    ; slow part, but a per-pixel READST would double it. Between rows the
    ; test is exact -- another row is expected, so any status at all (EOF
    ; included) means the file is shorter than its own header claims.
    ; After the LAST row EOF is not merely allowed but expected, since the
    ; final pixel is the final byte of the file.
    lda bmx_rows
    ora bmx_rows+1
    beq @done
    jsr READST
    cmp #0
    beq @row

@io_short
    lda #BMX_ERR_IO
    jmp @close_err

@done
    jsr bmx_close_read
    clc
    rts

; ---------------------------------------------------------------------
; bmx_save -- write a BMX file from VRAM
;   in:  X16_P0/P1 = filename address, X16_P2 = length
;        X16_P3    = device
;        X16_P4    = VRAM bank, X16_P5/P6 = VRAM address of the image
;        bmx_width/height/bpp/palstart/palcount/border/stride describe
;        what to save (bpp 8 and stride 320 are the defaults)
;   out: carry clear on success, set with A = BMX_ERR_IO on failure
; ---------------------------------------------------------------------
bmx_save
    jsr bmx_open_write
    bcc @wr_hdr
    lda #BMX_ERR_IO
    rts
@wr_hdr
    lda #'B'
    sta bmx_hdr
    lda #'M'
    sta bmx_hdr+1
    lda #'X'
    sta bmx_hdr+2
    lda #1
    sta bmx_hdr+3
    lda bmx_bpp
    sta bmx_hdr+4
    jsr bmx_depth_code
    sta bmx_hdr+5
    lda bmx_width
    sta bmx_hdr+6
    lda bmx_width+1
    sta bmx_hdr+7
    lda bmx_height
    sta bmx_hdr+8
    lda bmx_height+1
    sta bmx_hdr+9
    lda bmx_palcount            ; 256 stores as 0
    sta bmx_hdr+10
    lda bmx_palstart
    sta bmx_hdr+11
    lda bmx_palcount            ; data offset = 16 + palcount*2
    sta bmx_cnt
    lda bmx_palcount+1
    sta bmx_cnt+1
    asl bmx_cnt
    rol bmx_cnt+1
    clc
    lda bmx_cnt
    adc #16
    sta bmx_hdr+12
    lda bmx_cnt+1
    adc #0
    sta bmx_hdr+13
    stz bmx_hdr+14              ; uncompressed
    lda bmx_border
    sta bmx_hdr+15

    ldx #0
@hdr_out
    lda bmx_hdr,x
    jsr CHROUT
    inx
    cpx #16
    bne @hdr_out

    ; --- palette from the VRAM shadow ----------------------------------
    lda #VERA_CTRL_ADDRSEL
    tsb VERA_CTRL               ; port 1 reads, so CHROUT stays safe
    lda bmx_palstart
    asl
    sta VERA_ADDR_L
    lda #>VRAM_PALETTE
    adc #0
    sta VERA_ADDR_M
    lda #(VERA_ADDR_H_BANK | (VERA_INC_1 << 4))
    sta VERA_ADDR_H
    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL

    lda bmx_palcount
    sta bmx_cnt
    lda bmx_palcount+1
    sta bmx_cnt+1
    asl bmx_cnt
    rol bmx_cnt+1
@pal_out
    lda bmx_cnt
    ora bmx_cnt+1
    beq @pal_wrote
    lda VERA_DATA1
    jsr CHROUT
    jsr bmx_dec_cnt
    bra @pal_out
@pal_wrote

    ; --- pixel rows -----------------------------------------------------
    lda X16_P5
    sta bmx_cur
    lda X16_P6
    sta bmx_cur+1
    lda X16_P4
    and #$01
    sta bmx_cur+2
    jsr bmx_row_bytes

    lda bmx_height
    sta bmx_rows
    lda bmx_height+1
    sta bmx_rows+1
@wrow
    lda bmx_rows
    ora bmx_rows+1
    beq @wdone
    jsr bmx_point_cur1             ; port 1 at bmx_cur

    lda bmx_row
    sta bmx_cnt
    lda bmx_row+1
    sta bmx_cnt+1
@wpix
    lda bmx_cnt
    ora bmx_cnt+1
    beq @wrow_done
    lda VERA_DATA1
    jsr CHROUT
    jsr bmx_dec_cnt
    bra @wpix
@wrow_done
    clc
    lda bmx_cur
    adc bmx_stride
    sta bmx_cur
    lda bmx_cur+1
    adc bmx_stride+1
    sta bmx_cur+1
    lda bmx_cur+2
    adc #0
    and #$01
    sta bmx_cur+2
    lda bmx_rows
    bne @wdec
    dec bmx_rows+1
@wdec
    dec bmx_rows
    bra @wrow

@wdone
    jsr bmx_close_write
    clc
    rts

; --- plumbing ---------------------------------------------------------

bmx_open_read
    lda X16_P2
    ldx X16_P0
    ldy X16_P1
    jsr SETNAM
    lda #2
    ldx X16_P3
    ldy #0                      ; sequential read, no header games
    jsr SETLFS
    jsr OPEN
    bcs bmx_open_bad
    ldx #2
    jsr CHKIN
    bcs bmx_open_bad
    clc
    rts

bmx_open_write
    lda X16_P2
    ldx X16_P0
    ldy X16_P1
    jsr SETNAM
    lda #2
    ldx X16_P3
    ldy #1                      ; write
    jsr SETLFS
    jsr OPEN
    bcs bmx_open_bad
    ldx #2
    jsr CHKOUT
    bcs bmx_open_bad
    clc
    rts

bmx_open_bad
    jsr CLRCHN
    lda #2
    jsr CLOSE
    sec
    rts

bmx_close_read
bmx_close_write
    jsr CLRCHN
    lda #2
    jsr CLOSE
    rts

; bmx_row = bmx_width >> (3 - depth): the bytes in one row of pixels
bmx_row_bytes
    lda bmx_width
    sta bmx_row
    lda bmx_width+1
    sta bmx_row+1
    jsr bmx_depth_code
    eor #$03                    ; 3 - depth (depth is 0-3)
    tax
    beq bmx_rb_done
bmx_rb_shift
    lsr bmx_row+1
    ror bmx_row
    dex
    bne bmx_rb_shift
bmx_rb_done
    rts

; A = the VERA depth code for bmx_bpp (8->3, 4->2, 2->1, 1->0)
bmx_depth_code
    lda bmx_bpp
    cmp #8
    beq bmx_dc8
    cmp #4
    beq bmx_dc4
    cmp #2
    beq bmx_dc2
    lda #0
    rts
bmx_dc8
    lda #3
    rts
bmx_dc4
    lda #2
    rts
bmx_dc2
    lda #1
    rts

bmx_point_cur
    lda #VERA_CTRL_ADDRSEL
    trb VERA_CTRL
    lda bmx_cur
    sta VERA_ADDR_L
    lda bmx_cur+1
    sta VERA_ADDR_M
    lda bmx_cur+2
    ora #(VERA_INC_1 << 4)
    sta VERA_ADDR_H
    rts

bmx_point_cur1
    lda #VERA_CTRL_ADDRSEL
    tsb VERA_CTRL
    lda bmx_cur
    sta VERA_ADDR_L
    lda bmx_cur+1
    sta VERA_ADDR_M
    lda bmx_cur+2
    ora #(VERA_INC_1 << 4)
    sta VERA_ADDR_H
    lda #VERA_CTRL_ADDRSEL      ; leave ADDRSEL alone for the KERNAL
    trb VERA_CTRL
    rts

bmx_dec_cnt
    lda bmx_cnt
    bne bmx_dc_lo
    dec bmx_cnt+1
bmx_dc_lo
    dec bmx_cnt
    rts

bmx_t .byte 0

; read bmx_cnt bytes from the open channel into VERA_DATA0 (the port
; is already aimed). MACPTR moves them in bulk -- with the input carry
; SET the KERNAL holds the destination address fixed, which is exactly
; the data-port streaming trick mem_copy uses. A device that cannot do
; MACPTR answers carry set, and the byte-by-byte CHRIN path takes over.
;   out: carry clear = done; carry set = the stream died mid-read
bmx_bulk_read
@more
    lda bmx_cnt
    ora bmx_cnt+1
    beq @br_ok
    lda bmx_cnt+1
    beq @small
    lda #255                    ; a big remainder: largest single ask
    bra @ask
@small
    lda bmx_cnt                 ; the exact remainder
@ask
    ldx #<VERA_DATA0
    ldy #>VERA_DATA0
    sec                         ; fixed destination: stream into VERA
    jsr MACPTR
    bcs @fallback               ; the device cannot do block reads
    txa                         ; X/Y = bytes actually delivered
    bne @got
    tya
    beq @br_short               ; zero bytes: the file ran out
@got
    stx bmx_t                   ; bmx_cnt -= bytes read
    sec
    lda bmx_cnt
    sbc bmx_t
    sta bmx_cnt
    sty bmx_t
    lda bmx_cnt+1
    sbc bmx_t
    sta bmx_cnt+1
    bra @more
@br_ok
    clc
    rts
@br_short
    sec
    rts
@fallback
    lda bmx_cnt
    ora bmx_cnt+1
    beq @br_ok
    jsr CHRIN
    sta VERA_DATA0
    jsr bmx_dec_cnt
    bra @fallback

bmx_hdr  .res 16, 0
bmx_cnt  .word 0
bmx_cur  .res 3, 0
bmx_row  .word 0
bmx_rows .word 0

; (end zone)
