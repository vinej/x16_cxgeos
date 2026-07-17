; ca65
; =====================================================================
; CXGEOS :: kernel/resident/clip.asm -- the clipboard
; =====================================================================
; One typed entry, up to ~32KB, in banks 10-13. Put replaces whatever
; was there; get copies out up to the caller's capacity; type answers
; what is waiting without touching it. That is the whole GEOS idea:
; cut/copy/paste is apps agreeing on types, the kernel just carries
; the bytes across the app switch.
;
; RESIDENT, deliberately: this code switches RAM_BANK to walk the data
; banks, and bank-2 code that did that would unmap itself mid-copy
; (the vrows_save lesson). The caller's bank is put back afterwards.
;
; Types are a convention, not an enum the kernel enforces: 1 = TEXT
; (the only one anything speaks yet), 2 = BMX-rect reserved. 0 means
; empty, and putting a zero-length entry empties it.
; =====================================================================

CX_CLIP_BANK   = 10
CX_CLIP_MAX_HI = $7F            ; length < $7F00: fits the four banks

; ---------------------------------------------------------------------
; cx_do_clip_put -- A = type, P0/P1 = source, P2/P3 = length.
; Carry set = too big. Length 0 empties the clipboard.
; ---------------------------------------------------------------------
cx_do_clip_put
    tax                         ; the type, parked
    lda X16_P3
    cmp #CX_CLIP_MAX_HI
    bcs @no
    lda X16_P2
    ora X16_P3
    bne @some
    stz clip_type               ; nothing IS something: empty
    stz clip_len
    stz clip_len+1
    clc
    rts
@some
    stx clip_type
    lda X16_P2
    sta clip_len
    sta clip_cnt
    lda X16_P3
    sta clip_len+1
    sta clip_cnt+1

    lda X16_P0
    sta CX_C_APP
    lda X16_P1
    sta CX_C_APP+1
    jsr clip_rewind             ; the bank window to the start
@copy
    lda clip_cnt
    ora clip_cnt+1
    beq @done
    lda (CX_C_APP)
    sta (CX_C_BNK)
    jsr clip_step
    lda clip_cnt
    bne @dl
    dec clip_cnt+1
@dl
    dec clip_cnt
    bra @copy
@done
    lda clip_oldbank            ; the caller's bank back
    sta RAM_BANK
    clc
    rts
@no
    sec
    rts

; ---------------------------------------------------------------------
; cx_do_clip_get -- P0/P1 = destination, P2/P3 = its capacity.
; A = the type (0 = empty); P2/P3 become the length actually copied
; (the smaller of what is held and what fits).
; ---------------------------------------------------------------------
cx_do_clip_get
    lda clip_type
    bne @has
    stz X16_P2
    stz X16_P3
    lda #0
    clc
    rts
@has
    lda clip_len+1              ; the smaller length wins
    cmp X16_P3
    bcc @take_len
    bne @take_cap
    lda clip_len
    cmp X16_P2
    bcs @take_cap
@take_len
    lda clip_len
    sta X16_P2
    lda clip_len+1
    sta X16_P3
@take_cap
    lda X16_P2
    sta clip_cnt
    lda X16_P3
    sta clip_cnt+1

    lda X16_P0
    sta CX_C_APP
    lda X16_P1
    sta CX_C_APP+1
    jsr clip_rewind
@copy
    lda clip_cnt
    ora clip_cnt+1
    beq @done
    lda (CX_C_BNK)
    sta (CX_C_APP)
    jsr clip_step
    lda clip_cnt
    bne @dl
    dec clip_cnt+1
@dl
    dec clip_cnt
    bra @copy
@done
    lda clip_oldbank
    sta RAM_BANK
    lda clip_type
    clc
    rts

; ---------------------------------------------------------------------
; cx_do_clip_type -- A = the type (0 = empty), P2/P3 = the length.
; ---------------------------------------------------------------------
cx_do_clip_type
    lda clip_len
    sta X16_P2
    lda clip_len+1
    sta X16_P3
    lda clip_type
    rts

; clip_rewind -- remember the caller's bank, map the first data bank,
; and point the walker at its window.
clip_rewind
    lda RAM_BANK
    sta clip_oldbank
    lda #CX_CLIP_BANK
    sta RAM_BANK
    stz CX_C_BNK
    lda #$A0
    sta CX_C_BNK+1
    rts

; clip_step -- both walkers forward one; the banked one rolls into the
; next bank at the window's end.
clip_step
    inc CX_C_APP
    bne @a
    inc CX_C_APP+1
@a
    inc CX_C_BNK
    bne @b
    inc CX_C_BNK+1
    lda CX_C_BNK+1
    cmp #$C0                    ; off the window: the next bank, rewound
    bne @b
    lda #$A0
    sta CX_C_BNK+1
    inc RAM_BANK
@b
    rts

clip_type .byte 0
clip_len  .word 0
clip_cnt  .word 0
clip_oldbank .byte 0
