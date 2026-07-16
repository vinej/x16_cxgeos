; ca65
; =====================================================================
; CXGEOS :: apps/filer/filer.asm -- the file browser (Phase 6)
; =====================================================================
; Reads the SD card's directory into a list widget and launches what
; you pick. Built from sdk/ alone: the directory comes through
; cx_dir_*, the list is a kernel widget, and RETURN on a .CXA hands it
; to cx_app_load -- so choosing a file IS launching it, and cx_exit
; brings the browser back.
;
; Mouse or keyboard: click a row to select it, double-click to open;
; or UP/DOWN walk the focused list and RETURN opens. TAB raises the
; menu bar for the keyboard; the mouse just clicks it. The menu bar's
; Themes recolours the browser live.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

EV_KEY    = 5
EV_MENU   = 7
EV_WIDGET = 8
WG_LIST   = 5

MAXFILES  = 96
NAMEMAX   = 20                  ; bytes reserved per name in the pool

; app zero page ($60-$7F is the app's)
poolp = $60                     ; the next free spot in the name pool

.segment "LOADADDR"
    .word $0801
.segment "CODE"
    basic_stub

main
    ldx #0
@mk
    lda s_marker,x
    beq @go
    jsr CHROUT
    inx
    bne @mk
@go
    jsr cx_gfx_init
    lda #0
    jsr cx_gfx_clear

    lda #<s_title
    ldx #>s_title
    ldy #<20
    jsr say

    jsr readdir                 ; fill the list from the directory

    jsr cx_ev_init
    lda #<bar
    ldx #>bar
    jsr cx_menu_set
    lda #<widgets
    ldx #>widgets
    jsr cx_wg_set
    lda #1                      ; the arrow
    jsr cx_mouse_show

    lda #$09                    ; focus the list so UP/DOWN work at once
    jsr cx_wg_key

    lda #<handlers
    ldx #>handlers
    jsr cx_ev_handlers
    jmp cx_ev_mainloop

; ---------------------------------------------------------------------
say                             ; A/X = string, Y = row; column 20
    sty X16_P2
    stz X16_P3
    ldy #20
    sty X16_P0
    stz X16_P1
    jmp cx_font_draw

; ---------------------------------------------------------------------
; readdir -- walk the directory, copying each name into the pool and
; its pointer into fptrs, and set the list's WG_GRP to the count. The
; volume header (the first entry) is skipped.
; ---------------------------------------------------------------------
readdir
    lda #<pat
    ldx #>pat
    ldy #1
    jsr cx_dir_open
    bcs @none

    lda #<pool                  ; discard the header into the pool head
    sta X16_P0
    lda #>pool
    sta X16_P1
    jsr cx_dir_next

    lda #<pool                  ; the pool grows from the start
    sta poolp
    lda #>pool
    sta poolp+1
    stz fcount
@loop
    lda poolp                   ; next name at the free spot
    sta X16_P0
    lda poolp+1
    sta X16_P1
    jsr cx_dir_next
    bcs @done

    ldx fcount                  ; fptrs[count] = poolp
    txa
    asl
    tay
    lda poolp
    sta fptrs,y
    lda poolp+1
    sta fptrs+1,y

    ldy #0                      ; advance poolp past the name + its null
@len
    lda (poolp),y
    beq @nul
    iny
    cpy #NAMEMAX
    bcc @len
@nul
    iny
    tya
    clc
    adc poolp
    sta poolp
    bcc @nc
    inc poolp+1
@nc
    inc fcount
    lda fcount
    cmp #MAXFILES
    bcc @loop
@done
    jsr cx_dir_close
@none
    lda fcount                  ; the list's item count
    sta wl_rec + 10             ; WG_GRP field of the list record
    rts

; ---------------------------------------------------------------------
; on_widget -- the list was activated (RETURN): P2 = the selected row.
; Load the file it names; cx_app_load refuses anything that is not a
; CXAP (a directory, a data file) with the caller intact, so a bad
; pick just draws a note.
; ---------------------------------------------------------------------
on_widget
    lda X16_P2                  ; row -> fptrs[row] -> the name
    asl
    tay
    lda fptrs,y
    sta poolp
    lda fptrs+1,y
    sta poolp+1

    ldy #0                      ; the name's length, for cx_app_load
@len
    lda (poolp),y
    beq @got
    iny
    bne @len
@got
    tya
    tax                         ; length in X for now
    lda poolp
    ldy poolp+1
    ; cx_app_load wants A/X = ptr, Y = len
    sta X16_T0
    sty X16_T1
    txa
    tay                         ; Y = length
    lda X16_T0
    ldx X16_T1
    jsr cx_app_load             ; returns only if it refused
    lda #<s_bad
    ldx #>s_bad
    ldy #30
    jmp say
on_menu
    lda X16_P2                  ; menu 1 = Themes
    cmp #1
    beq @theme
    lda X16_P1                  ; menu 0: About / Quit
    bne @quit
    lda #<s_about
    ldx #>s_about
    ldy #30
    jmp say
@quit
    jmp cx_exit
@theme
    lda X16_P1
    beq @day
    lda #<theme_night
    ldx #>theme_night
    jsr cx_theme_set
    bra @repaint
@day
    lda #<theme_day
    ldx #>theme_day
    jsr cx_theme_set
@repaint
    jmp cx_wg_draw

; on_key -- modal, because the list and the menu bar both want the arrow
; keys. Browsing: UP/DOWN/RETURN drive the list, TAB opens the menu, ESC
; quits. In the menu: the arrows/RETURN/ESC drive it, and RETURN (pick) or
; ESC (dismiss) drops us back to browsing. Without this the kernel grabs
; DOWN to open the bar and the list can never scroll.
on_key
    lda inmenu
    bne @menu
    lda X16_P1                  ; --- browsing ---
    cmp #$09                    ; TAB: raise the menu bar
    beq @open
    cmp #$1B                    ; ESC: leave the desktop
    beq @quit
    lda X16_P1
    jsr cx_wg_key               ; UP/DOWN select, RETURN launches
    rts
@open
    lda #$11                    ; feed DOWN to drop the first menu
    jsr cx_menu_key
    lda #1
    sta inmenu
    rts
@quit
    jmp cx_exit
@menu
    lda X16_P1                  ; --- a menu is open ---
    jsr cx_menu_key
    lda X16_P1
    cmp #$0D                    ; RETURN picks, ESC dismisses: either way
    beq @close                  ; the bar closes, so back to browsing
    cmp #$1B
    beq @close
    rts
@close
    stz inmenu
    rts

handlers                        ; NULL MOVE DOWN UP DBL KEY TIMER MENU WIDGET
    .addr 0, 0, 0, 0, 0
    .addr on_key
    .addr 0
    .addr on_menu
    .addr on_widget

; ---------------------------------------------------------------------
; the menu tree and the widget list
; ---------------------------------------------------------------------
bar
    .byte 2
    .addr s_m0, m0_items
    .addr s_m1, m1_items
m0_items
    .byte 2
    .addr s_about_i
    .addr s_quit
m1_items
    .byte 2
    .addr s_day
    .addr s_night

widgets
    .byte 1
wl_rec
    .byte WG_LIST, 0
    .word 20, 44, 400
    .byte 240, 0, 0            ; h=240, selected 0, count from readdir
    .addr fptrs
    .byte 0, 0, 0             ; byte 13 = WG_TOP = 0

theme_day
    .byte $FF, $0F,  $AA, $0A,  $55, $05,  $00, $00
    .byte 0, 1, 3, 0
theme_night                     ; 0 near-black paper, 1 medium-blue
    .byte $01, $00,  $48, $02,  $56, $03,  $BC, $0A   ; highlight (was too
    .byte 0, 1, 3, 0                                  ; close to the paper)

s_marker  .byte "CXGEOS SHELL", $0D, 0
s_title   .byte "CXGEOS -- dbl-click opens a file (or UP/DOWN+RETURN), ESC quits", 0
s_m0      .byte "CXGEOS", 0
s_m1      .byte "Themes", 0
s_about_i .byte "about", 0
s_quit    .byte "quit", 0
s_day     .byte "daylight", 0
s_night   .byte "midnight", 0
s_about   .byte "CXGEOS file browser -- the directory is live off the SD card.", 0
s_bad     .byte "that is not a CXGEOS app.                                    ", 0
pat       .byte "$"

fcount    .byte 0
inmenu    .byte 0                 ; 0 = browsing the list, 1 = a menu is open
fptrs     .res MAXFILES * 2, 0
pool      .res MAXFILES * NAMEMAX, 0
