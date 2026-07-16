;ACME
; =====================================================================
; x16lib :: storage/mem.asm -- KERNAL block memory operations
; =====================================================================
; This file EMITS CODE. Source it exactly once (x16_code.asm does).
;
; Thin wrappers over the KERNAL's block routines -- MEMORY_FILL,
; MEMORY_COPY, MEMORY_CRC and MEMORY_DECOMPRESS. These live in the
; $FExx jump table, so no bank switching is needed.
;
; ONE PROPERTY MAKES THESE SPECIAL: addresses in $9F00-$9FFF are NOT
; incremented during the operation. Point a VERA data port somewhere
; and pass $9F23 (VERA_DATA0) as the source or target, and these
; routines stream straight into or out of VRAM at the port's own
; increment. mem_decompress with target VERA_DATA0 unpacks assets
; directly into video memory -- no staging buffer.
;
; All four take a 16-bit byte count; the KERNAL's virtual registers
; r0-r2 are used for arguments and are treated as caller-save, exactly
; like everywhere else in this library.
; =====================================================================

; (zone: file scope in ca65)

; ---------------------------------------------------------------------
; mem_fill -- set a block of memory to one value
;   in:  X16_P0/P1 = target address, X16_P2/P3 = byte count, A = value
;
; A target in $9F00-$9FFF is written repeatedly without incrementing:
; to fill VRAM, point port 0 first and pass VERA_DATA0 as the target.
; ---------------------------------------------------------------------
mem_fill
    ldx X16_P2                  ; a zero count fills nothing
    bne @go
    ldx X16_P3
    beq @done
@go
    pha
    lda X16_P0
    sta r0L
    lda X16_P1
    sta r0H
    lda X16_P2
    sta r1L
    lda X16_P3
    sta r1H
    pla
    jmp MEMORY_FILL
@done
    rts

; ---------------------------------------------------------------------
; mem_copy -- copy a block of memory
;   in:  X16_P0/P1 = source, X16_P2/P3 = target, X16_P4/P5 = byte count
;
; The regions may overlap. Source or target in $9F00-$9FFF is not
; incremented, so this uploads to VRAM (target VERA_DATA0), downloads
; from VRAM (source VERA_DATA0), or copies VRAM to VRAM (port to port).
; ---------------------------------------------------------------------
mem_copy
    lda X16_P4                  ; a zero count copies nothing
    ora X16_P5
    beq @done
    lda X16_P0
    sta r0L
    lda X16_P1
    sta r0H
    lda X16_P2
    sta r1L
    lda X16_P3
    sta r1H
    lda X16_P4
    sta r2L
    lda X16_P5
    sta r2H
    jmp MEMORY_COPY
@done
    rts

; ---------------------------------------------------------------------
; mem_crc -- CRC-16/IBM-3740 of a block
;   in:  X16_P0/P1 = address, X16_P2/P3 = byte count
;   out: A = CRC low, X = CRC high
;
; The CRC of an empty block is the algorithm's initial value, $FFFF.
; ---------------------------------------------------------------------
mem_crc
    lda X16_P2
    ora X16_P3
    bne @go
    lda #$FF                    ; empty block: the $FFFF init value
    tax
    rts
@go
    lda X16_P0
    sta r0L
    lda X16_P1
    sta r0H
    lda X16_P2
    sta r1L
    lda X16_P3
    sta r1H
    jsr MEMORY_CRC
    lda r2L
    ldx r2H
    rts

; ---------------------------------------------------------------------
; mem_decompress -- decompress an LZSA2 block
;   in:  X16_P0/P1 = compressed data, X16_P2/P3 = output address
;   out: A/X = address one past the last output byte
;
; Compress with:  lzsa -r -f2 <original> <compressed>
; (raw LZSA2 block -- no frame header).
;
; Cannot decompress in place. The input may sit in banked RAM (map the
; bank yourself; 8 KB limit). A target in $9F00-$9FFF is not
; incremented: point port 0 at VRAM and pass VERA_DATA0 as the target
; to unpack assets straight into video memory.
; ---------------------------------------------------------------------
mem_decompress
    lda X16_P0
    sta r0L
    lda X16_P1
    sta r0H
    lda X16_P2
    sta r1L
    lda X16_P3
    sta r1H
    jsr MEMORY_DECOMPRESS
    lda r1L                     ; the KERNAL leaves r1 one past the end
    ldx r1H
    rts

; (end zone)
