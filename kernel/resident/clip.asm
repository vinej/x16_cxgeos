; ca65
; =====================================================================
; CXRF :: kernel/resident/clip.asm -- the clipboard
; =====================================================================
; One typed entry, up to ~32KB, in banks 10-13. Put replaces whatever
; was there; get copies out up to the caller's capacity; type answers
; what is waiting without touching it. That is the whole GEOS idea:
; cut/copy/paste is apps agreeing on types, the kernel just carries
; the bytes across the app switch.
;
; SPLIT to keep the resident image lean: the put/get/type ORCHESTRATION
; (arg parsing, size/capacity checks, the type+length bookkeeping) rides
; bank 18 (the fs/system cold half), reached through the far-call stubs
; below. Only the BYTE-MOVER stays resident -- it alone switches RAM_BANK
; to walk the data banks, and bank-18 code that did that would unmap
; ITSELF mid-copy (the vrows_save lesson). The caller's bank is put back.
;
; Types are a convention, not an enum the kernel enforces: 1 = TEXT
; (the only one anything speaks yet), 2 = BMX-rect reserved. 0 means
; empty, and putting a zero-length entry empties it.
; =====================================================================

CX_CLIP_BANK   = 10
CX_CLIP_MAX_HI = $7F            ; length < $7F00: fits the four banks

; --- the ABI stubs: hand the orchestration to bank 18 ----------------
cx_do_clip_put
.ifndef CX_NO_OVERLAY
    jsr cxb_call                ; carry (too big) survives cxb_call
    .byte CX_FS_BANK
    .addr clip_put
.else
    jsr clip_put                ; the flat runner links it in CODE
.endif
    rts
cx_do_clip_get
.ifndef CX_NO_OVERLAY
    jsr cxb_call
    .byte CX_FS_BANK
    .addr clip_get
.else
    jsr clip_get
.endif
    rts
cx_do_clip_type
.ifndef CX_NO_OVERLAY
    jsr cxb_call
    .byte CX_FS_BANK
    .addr clip_type_impl
.else
    jsr clip_type_impl
.endif
    rts

; ---------------------------------------------------------------------
; clip_move -- the resident byte-mover. The orchestration (bank 18) sets
; CX_C_APP (a LOW-RAM pointer -- unaffected by RAM_BANK), clip_cnt, and
; clip_dir, then calls here. This walks banks 10-13 and restores the
; caller's bank; it is the only code allowed to page them, because it
; runs resident and so cannot page its own execution window away.
;   clip_dir: 0 = RAM (CX_C_APP) -> clipboard bank ; 1 = bank -> RAM
; ---------------------------------------------------------------------
clip_move
    jsr clip_rewind             ; the caller's bank saved, bank 10 mapped
@copy
    lda clip_cnt
    ora clip_cnt+1
    beq @done
    lda clip_dir
    bne @get
    lda (CX_C_APP)              ; put: RAM -> the banked window
    sta (CX_C_BNK)
    bra @adv
@get
    lda (CX_C_BNK)              ; get: the banked window -> RAM
    sta (CX_C_APP)
@adv
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

clip_cnt     .word 0            ; the resident mover's working count
clip_oldbank .byte 0
clip_dir     .byte 0

; --- the orchestration: bank 18 (fs/system cold half, banks.inc) -----
.ifndef CX_NO_OVERLAY
.segment "B18CODE"
.endif

; clip_put -- A = type, P0/P1 = source, P2/P3 = length. Carry set = too
; big. Length 0 empties the clipboard.
clip_put
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
    stz clip_dir                ; RAM -> bank
    jsr clip_move               ; resident: it does the bank walk
    clc
    rts
@no
    sec
    rts

; clip_get -- P0/P1 = destination, P2/P3 = its capacity. A = the type
; (0 = empty); P2/P3 become the length actually copied (the smaller of
; what is held and what fits).
clip_get
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
    lda #1
    sta clip_dir                ; bank -> RAM
    jsr clip_move
    lda clip_type
    clc
    rts

; clip_type_impl -- A = the type (0 = empty), P2/P3 = the length.
clip_type_impl
    lda clip_len
    sta X16_P2
    lda clip_len+1
    sta X16_P3
    lda clip_type
    rts

clip_type .byte 0
clip_len  .word 0

.ifndef CX_NO_OVERLAY
.segment "CODE"                 ; back to resident for the next include
.endif
