; ca65
; =====================================================================
; CXGEOS :: apps/filer/filer.asm -- the desktop (Phase 6)
; =====================================================================
; The file browser that IS the shell: boot lands here, and cx_exit
; comes back here. The directory arrives through cx_dir_*, lives in a
; list widget, and opening an entry is the whole desktop idea --
; a folder is entered (CD), an app is launched (cx_app_load), and
; anything else politely refuses. The File menu holds the four
; operations -- new folder, rename, copy, delete -- each built as a
; CMDR-DOS command for cx_dos_cmd, named through cx_dlg_prompt, with
; delete behind a confirm alert whose SAFE button is the default.
; The drive's own reply text is shown after every operation.
;
; Mouse or keyboard throughout: click selects, double-click opens;
; UP/DOWN + RETURN do the same; TAB raises the menu bar, ESC leaves.
; =====================================================================

.include "x16.asm"
.include "sdk/include_ca65/cxgeos.inc"

EV_KEY    = 5
EV_MENU   = 7
EV_WIDGET = 8
WG_LIST   = 5
WG_ICON   = 6

; the icon ids cx_icon draws (kernel/ui/icon.asm)
ICON_UP        = 0
ICON_FOLDER    = 1
ICON_APP       = 2
ICON_FONT      = 3
ICON_ACCESSORY = 4
ICON_DATA      = 5
ICON_IMAGE     = 6
ICON_DISK      = 7

MAXFILES  = 96
NAMEMAX   = 20                  ; bytes reserved per name in the pool

; the icon-view grid (mode 0, 640x480). CONTENT_Y0 is the first row below
; the menu bar and title, cleared and redrawn on a view switch.
CONTENT_Y0 = 44
GX0    = 32
GY0    = 52
GCW    = 96                     ; cell width  (icon centred in it)
GCH    = 66                     ; cell height (icon then caption)
GCOLS  = 6
GROWS  = 6
PERPAGE = GCOLS * GROWS         ; 36 icons a page
MAXICON = PERPAGE

; The kernel's cx_hdr_shell header byte ($800A): resident, so unlike the
; desktop's own RAM it survives an app launch and the cx_exit back. The
; view mode lives here, so returning from a program lands in the same view
; it was launched from -- the directory still resets to root (above), but
; list-vs-icons is a preference and should stick.
CX_SHELL_STATE = $800A

; app zero page ($60-$7F is the app's)
poolp = $60                     ; the pool write head / a name walker
iwp   = $62                     ; the icon record write head, (zp),y

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

    ; The disk work goes FIRST, before the screen is cleared. gfx2_init
    ; leaves the framebuffer alone, so the outgoing app's picture stays up
    ; through the directory read; then the clear and the whole desktop are
    ; painted in one burst instead of a bare screen sitting through the I/O
    ; -- the jarring part when an app closes.
    lda #<s_home                ; home is the root: an app launched from
    ldx #>s_home                ; a folder leaves us there on reload, so
    ldy #s_home_len             ; the desktop always resets. depth stays 0
    jsr cx_dos_cmd
    jsr seed_clock              ; start the RTC if at the emulator default
    jsr readdir                 ; fill the list from the directory

    lda #0                      ; now clear and paint the desktop at once
    jsr cx_gfx_clear
    lda #<s_title
    ldx #>s_title
    ldy #20
    jsr say

    jsr cx_ev_init
    lda #<bar
    ldx #>bar
    jsr cx_menu_set
    lda CX_SHELL_STATE          ; the view the last desktop left (0 at cold
    and #1                      ; boot); an app launch does not clear it
    sta viewmode
    beq @vlist
    jsr build_icons             ; icons: lay the grid, then install it
    lda #<iwbuf
    ldx #>iwbuf
    bra @vset
@vlist
    lda #<widgets
    ldx #>widgets
@vset
    jsr cx_wg_set
    lda #1                      ; the arrow
    jsr cx_mouse_show

    lda #$09                    ; focus the list so UP/DOWN work at once
    jsr cx_wg_key

    lda #60                     ; a tick a second, for the clock
    jsr cx_ev_timer
    jsr on_timer                ; and the clock NOW, not in a second

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

note                            ; A/X = string onto a cleared note row
    pha
    phx
    ldy #20                     ; the row back to paper first
    sty X16_P0
    stz X16_P1
    ldy #30
    sty X16_P2
    stz X16_P3
    lda #<600
    sta X16_P4
    lda #>600
    sta X16_P5
    lda #12
    sta X16_P6
    stz X16_P7
    lda #0
    jsr cx_gfx_rect
    plx
    pla
    ldy #30
    jmp say

; ---------------------------------------------------------------------
; readdir -- walk the directory into the pool. Inside a folder (depth >
; 0) row 0 is "../", the way up; at the root there is nowhere up, so no
; such row -- CD:.. above the root is a DOS "file not found", which is
; the loop the owner hit. The listing's own "." and ".." are skipped:
; the one go-back row is ours. Directories wear a trailing '/'.
; ---------------------------------------------------------------------
readdir
    stz fcount
    lda #<pool                  ; the pool grows from the start...
    sta poolp
    lda #>pool
    sta poolp+1

    lda depth                   ; ...after a "../" go-back row, but only
    beq @open                   ; when we are down inside a folder
    lda #<pool
    sta fptrs
    lda #>pool
    sta fptrs+1
    lda #'.'
    sta pool
    sta pool+1
    lda #'/'
    sta pool+2
    stz pool+3
    lda #1
    sta fcount
    lda #ICON_UP                ; the go-back row wears the up arrow
    sta ficon
    lda #<(pool+4)
    sta poolp
    lda #>(pool+4)
    sta poolp+1
@open
    lda #<pat
    ldx #>pat
    ldy #1
    jsr cx_dir_open
    bcc @opened                 ; the loop body outgrew a short branch to @none
    jmp @none
@opened
    lda poolp                   ; discard the volume header
    sta X16_P0
    lda poolp+1
    sta X16_P1
    jsr cx_dir_next
@loop
    lda poolp                   ; next name at the free spot
    sta X16_P0
    lda poolp+1
    sta X16_P1
    jsr cx_dir_next
    bcs @done
    sta ftype                   ; 0 file / 1 dir

    ldy #0                      ; skip the listing's own "." and ".." --
    lda (poolp),y               ; our "../" row is the only go-back
    cmp #'.'
    bne @keep
    iny
    lda (poolp),y
    beq @loop                   ; "." alone
    cmp #'.'
    bne @keep
    iny
    lda (poolp),y
    beq @loop                   ; ".."
@keep
    lda ftype                   ; folders always show; a system artifact
    bne @store                  ; (.X16 .BIN .PRG .CXF) is hidden, so the
    jsr hidden_ext              ; list is the programs and folders only
    bcs @loop
@store
    ldx fcount                  ; fptrs[count] = poolp
    txa
    asl
    tay
    lda poolp
    sta fptrs,y
    lda poolp+1
    sta fptrs+1,y

    jsr entry_icon              ; ficon[count] = its type icon
    ldx fcount
    sta ficon,x

    ldy #0                      ; the name's end
@len
    lda (poolp),y
    beq @nul
    iny
    cpy #NAMEMAX-2
    bcc @len
@nul
    lda ftype                   ; a directory wears its slash
    beq @plain
    lda #'/'
    sta (poolp),y
    iny
    lda #0
    sta (poolp),y
@plain
    iny                         ; past the NUL
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
    lda fcount                  ; the record: count, selection 0, top 0
    sta wl_rec + 10
    stz wl_rec + 9
    stz wl_rec + 13
    rts

refresh                         ; the directory again, repainted
    jsr readdir
    lda viewmode
    beq @list
    stz iconpage                ; a fresh listing lands on the first page
    jmp set_view                ; re-grid the icons and repaint
@list
    jmp cx_wg_draw

; ---------------------------------------------------------------------
; entry_icon -- A = the type icon for the entry at (poolp), given ftype
; (0 file / 1 dir). A folder gets the folder; a file is classed by its
; extension -- .CXA an app, .CXD a desk accessory, anything else data.
; The name is NUL-terminated here (the slash a directory wears is added
; after this runs), so the suffix test is on the bare name.
; ---------------------------------------------------------------------
entry_icon
    lda ftype
    beq @file
    lda #ICON_FOLDER
    rts
@file
    ldy #0                      ; Y = strlen
@sl
    lda (poolp),y
    beq @got
    iny
    cpy #NAMEMAX
    bcc @sl
@got
    cpy #4                      ; shorter than ".CX?": data
    bcc @data
    tya
    sec
    sbc #4
    tay                         ; Y -> the four-char suffix
    lda (poolp),y
    cmp #'.'
    bne @data
    iny
    lda (poolp),y
    cmp #'C'
    bne @data
    iny
    lda (poolp),y
    cmp #'X'
    bne @data
    iny
    lda (poolp),y
    cmp #'A'
    beq @app
    cmp #'D'
    beq @acc
@data
    lda #ICON_DATA
    rts
@app
    lda #ICON_APP
    rts
@acc
    lda #ICON_ACCESSORY
    rts

; ---------------------------------------------------------------------
; the icon view: a page of the directory as a grid of icon widgets
; ---------------------------------------------------------------------
; set_view -- clear the content area and draw whichever view is current.
; The menu bar and title above CONTENT_Y0 stay standing; cx_wg_set is
; idempotent (it replaces its click region), so toggling never leaks the
; region stack.
set_view
    jsr clear_content
    lda viewmode
    beq @list
    jsr build_icons
    lda #<iwbuf
    ldx #>iwbuf
    jmp cx_wg_set
@list
    lda #<widgets
    ldx #>widgets
    jmp cx_wg_set

; clear_content -- the desktop below the bar back to paper (index 0).
clear_content
    stz X16_P0
    stz X16_P1
    lda #CONTENT_Y0
    sta X16_P2
    stz X16_P3
    lda #<640
    sta X16_P4
    lda #>640
    sta X16_P5
    lda #<(480 - CONTENT_Y0)
    sta X16_P6
    lda #>(480 - CONTENT_Y0)
    sta X16_P7
    lda #0
    jmp cx_gfx_rect

; build_icons -- lay this page's files into iwbuf as WG_ICON records.
; A page is PERPAGE cells on a GCOLS x GROWS grid; it stops early at the
; last file. pagebase = iconpage * PERPAGE is the first file shown.
build_icons
    lda #0                      ; pagebase = iconpage * PERPAGE
    sta pagebase
    ldx iconpage
    beq @pbok
@pbmul
    clc
    lda pagebase
    adc #PERPAGE
    sta pagebase
    dex
    bne @pbmul
@pbok
    stz iw_n
    lda #<(iwbuf+1)
    sta iwp
    lda #>(iwbuf+1)
    sta iwp+1
    lda #GY0
    sta cy
    stz cy+1
    stz grow
@rows
    lda grow
    cmp #GROWS
    bcs @finish
    lda #GX0
    sta cxw
    stz cxw+1
    stz gcol
@cols
    lda gcol
    cmp #GCOLS
    bcs @nextrow
    lda pagebase                ; fidx = pagebase + iw_n, until fcount
    clc
    adc iw_n
    cmp fcount
    bcs @finish
    sta fidx
    jsr emit_icon_rec
    clc                         ; the record head forward one widget
    lda iwp
    adc #16
    sta iwp
    bcc @iwok
    inc iwp+1
@iwok
    inc iw_n
    clc                         ; the next column
    lda cxw
    adc #GCW
    sta cxw
    bcc @cxok
    inc cxw+1
@cxok
    inc gcol
    bra @cols
@nextrow
    clc                         ; the next row
    lda cy
    adc #GCH
    sta cy
    bcc @cyok
    inc cy+1
@cyok
    inc grow
    bra @rows
@finish
    lda iw_n
    sta iwbuf                   ; the count byte the toolkit reads
    rts

; emit_icon_rec -- one 16-byte WG_ICON record at (iwp) for file fidx at
; cell (cxw, cy). WG_VAL is its icon, WG_LBL its name pointer.
emit_icon_rec
    ldy #0                      ; WG_TYPE
    lda #WG_ICON
    sta (iwp),y
    ldy #1                      ; WG_FLAGS
    lda #0
    sta (iwp),y
    ldy #2                      ; WG_X
    lda cxw
    sta (iwp),y
    ldy #3
    lda cxw+1
    sta (iwp),y
    ldy #4                      ; WG_Y
    lda cy
    sta (iwp),y
    ldy #5
    lda cy+1
    sta (iwp),y
    ldy #6                      ; WG_W
    lda #GCW
    sta (iwp),y
    ldy #7
    lda #0
    sta (iwp),y
    ldy #8                      ; WG_H
    lda #GCH
    sta (iwp),y
    ldy #9                      ; WG_VAL = the icon id
    ldx fidx
    lda ficon,x
    sta (iwp),y
    ldy #10                     ; WG_GRP
    lda #0
    sta (iwp),y
    lda fidx                    ; WG_LBL = fptrs[fidx]
    asl
    tax
    ldy #11
    lda fptrs,x
    sta (iwp),y
    ldy #12
    lda fptrs+1,x
    sta (iwp),y
    ldy #13                     ; WG_TOP + the two pad bytes
    lda #0
    sta (iwp),y
    ldy #14
    sta (iwp),y
    ldy #15
    sta (iwp),y
    rts

; ---------------------------------------------------------------------
; hidden_ext -- carry set if the name at (poolp) ends in a system-file
; extension the desktop hides (.X16 .BIN .PRG .CXF), so the list reads
; as the programs available (.CXA apps, .CXD accessories) and folders,
; not the boot artifacts beside them.
; ---------------------------------------------------------------------
HIDDEN_N = 4
hidden_ext
    ldy #0                      ; Y = strlen(name)
@fn
    lda (poolp),y
    beq @got
    iny
    cpy #NAMEMAX
    bcc @fn
@got
    cpy #4                      ; shorter than a ".EXT": keep it
    bcc @no
    tya                         ; copy the last four bytes into ext4
    sec
    sbc #4
    tay
    ldx #0
@cp
    lda (poolp),y
    sta ext4,x
    iny
    inx
    cpx #4
    bne @cp
    stz he_i                    ; ext4 against each hidden suffix
@try
    lda he_i
    cmp #HIDDEN_N
    bcs @no
    asl                         ; entry base = he_i * 4
    asl
    tax
    ldy #0
@cmp
    lda hidden_tab,x
    cmp ext4,y
    bne @miss
    inx
    iny
    cpy #4
    bne @cmp
    sec                         ; all four matched: hide it
    rts
@miss
    inc he_i
    bra @try
@no
    clc
    rts

; ---------------------------------------------------------------------
; selname -- obuf = the selected entry's name with any trailing slash
; stripped; oblen = its length; A = 1 if it was a directory. The pool
; entry itself is left alone.
; ---------------------------------------------------------------------
selname
    lda wl_rec + 9              ; WG_VAL -> fptrs[2v]
    asl
    tay
    lda fptrs,y
    sta poolp
    lda fptrs+1,y
    sta poolp+1
    ldy #0
@cp
    lda (poolp),y
    sta obuf,y
    beq @end
    iny
    cpy #NAMEMAX
    bcc @cp
@end
    sty oblen
    ldy oblen                   ; strip the slash, remember it
    beq @plain
    dey
    lda obuf,y
    cmp #'/'
    bne @plain
    lda #0
    sta obuf,y
    sty oblen
    lda #1
    rts
@plain
    lda #0
    rts

; ---------------------------------------------------------------------
; dop -- send cbuf (Y = length) to the drive, show its reply, refresh.
; ---------------------------------------------------------------------
dop
    lda #<cbuf
    ldx #>cbuf
    jsr cx_dos_cmd
    lda #<mbuf                  ; the drive's words, whatever they were
    sta X16_P0
    lda #>mbuf
    sta X16_P1
    jsr cx_dos_msg
    lda #<mbuf
    ldx #>mbuf
    jsr note
    jmp refresh

; ---------------------------------------------------------------------
; the handlers
; ---------------------------------------------------------------------
on_widget                       ; an entry was activated: open it
    lda viewmode
    beq @open                   ; list view: wl_rec+9 is the selected row
    lda X16_P2                  ; icon view: only a double-click (value 1)
    bne @doopen                 ; opens; a single click (value 0) just selects
    rts
@doopen
    lda pagebase                ; the file = this page's base + the widget's
    clc                         ; index; put it where selname looks
    adc X16_P1
    sta wl_rec + 9
@open
    jsr selname
    bne @dir
    ldy oblen                   ; a ".CXD" opens OVER the desktop
    cpy #5
    bcc @app
    lda obuf-4,y
    cmp #'.'
    bne @app
    lda obuf-3,y
    cmp #'C'
    bne @app
    lda obuf-2,y
    cmp #'X'
    bne @app
    lda obuf-1,y
    cmp #'D'
    bne @app
    lda #<obuf                  ; a desk accessory: the desktop stays
    ldx #>obuf
    ldy oblen
    jsr cx_da_open
    bcc @ok
    lda #<s_noda
    ldx #>s_noda
    jmp note
@ok
    rts
@app
    lda oblen                   ; SHELL.CXA is this desktop itself --
    cmp #9                      ; launching it just reloads the same
    bne @load                   ; screen, so say what it is instead
    ldy #8
@shcmp
    lda obuf,y
    cmp s_shname,y
    bne @load
    dey
    bpl @shcmp
    lda #<s_isdesk
    ldx #>s_isdesk
    jmp note
@load
    ; a file: only a CXAP comes back from this
    lda #<obuf
    ldx #>obuf
    ldy oblen
    jsr cx_app_load             ; returns only if it refused
    lda #<s_bad
    ldx #>s_bad
    jmp note
@dir                            ; a folder: go there and re-read
    lda #1                      ; the depth step: a name goes down, ".."
    sta ddelta                  ; comes back up
    lda oblen
    cmp #2
    bne @cd
    lda obuf
    cmp #'.'
    bne @cd
    lda obuf+1
    cmp #'.'
    bne @cd
    lda #$FF
    sta ddelta
@cd
    ldy #0                      ; "CD:" + name
@cdc
    lda s_cd,y
    beq @cdn
    sta cbuf,y
    iny
    bne @cdc
@cdn
    ldx #0
@cd2
    lda obuf,x
    sta cbuf,y
    beq @go
    iny
    inx
    bne @cd2
@go
    lda #<cbuf                  ; send it, and only on success does the
    ldx #>cbuf                  ; depth move -- a refused CD leaves us put
    jsr cx_dos_cmd
    php
    lda #<mbuf
    sta X16_P0
    lda #>mbuf
    sta X16_P1
    jsr cx_dos_msg
    lda #<mbuf
    ldx #>mbuf
    jsr note
    plp
    bcs @refresh
    lda depth
    clc
    adc ddelta
    sta depth
@refresh
    jmp refresh

on_menu
    lda X16_P2
    cmp #1
    beq @file
    cmp #2
    beq @theme
    cmp #3
    beq @view
    lda X16_P1                  ; menu 0: about / quit
    bne @quit
    lda #<dlg_about             ; a real box with an ok button, not a
    ldx #>dlg_about             ; line that is easy to miss
    jsr cx_dlg_alert
    rts
@quit
    jmp cx_exit
@view
    lda X16_P1                  ; 0 = list, 1 = icons
    sta viewmode
    sta CX_SHELL_STATE          ; remember it across the next app launch
    stz iconpage                ; a view change starts at the first page
    jmp set_view
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
@file
    lda X16_P1                  ; the ops live pages away: jmp, not branch
    beq @fmk
    cmp #1
    beq @fnf
    cmp #2
    beq @frn
    cmp #3
    beq @fcp
    cmp #4
    beq @fdl
    rts
@fmk
    jmp do_mkdir
@fnf
    jmp do_newfile
@frn
    jmp do_rename
@fcp
    jmp do_copy
@fdl
    jmp do_delete

; ---- new folder ------------------------------------------------------
do_mkdir
    stz pbuf                    ; an empty seed
    lda #<s_mkq
    ldx #>s_mkq
    jsr ask
    bcs @out                    ; cancelled or empty
    ldy #0                      ; "MD:" + the name
@c
    lda s_md,y
    beq @n
    sta cbuf,y
    iny
    bne @c
@n
    ldx #0
@c2
    lda pbuf,x
    sta cbuf,y
    beq @send
    iny
    inx
    bne @c2
@send
    jmp dop
@out
    rts

; ---- new file --------------------------------------------------------
; An empty sequential file, created by opening "NAME,S,W" and closing
; it. Interrupts masked around the OPEN/CLOSE, the same reason the loader
; masks them -- the event IRQ must not re-enter the KERNAL mid-I/O. The
; drive's status is shown after, then the list re-reads.
do_newfile
    stz pbuf
    lda #<s_nfq
    ldx #>s_nfq
    jsr ask
    bcs @out
    ldx #0                      ; "NAME" into cbuf
@c
    lda pbuf,x
    beq @suf
    sta cbuf,x
    inx
    bne @c
@suf
    ldy #0                      ; ...then ",S,W"
@s
    lda s_sw,y
    sta cbuf,x
    beq @open
    inx
    iny
    bne @s
@open
    txa                         ; A = length (up to the NUL)
    ldx #<cbuf
    ldy #>cbuf
    jsr SETNAM
    lda #3
    ldx #8
    ldy #3                      ; secondary 3: a write channel
    jsr SETLFS
    sei                         ; do not let the IRQ re-enter the KERNAL
    jsr OPEN                    ; creates (and truncates) the file
    jsr CLRCHN
    lda #3
    jsr CLOSE
    cli
    lda #0                      ; the drive's verdict, then the list again
    tax
    tay
    jsr cx_dos_cmd
    lda #<mbuf
    sta X16_P0
    lda #>mbuf
    sta X16_P1
    jsr cx_dos_msg
    lda #<mbuf
    ldx #>mbuf
    jsr note
    jmp refresh
@out
    rts

; ---- rename ----------------------------------------------------------
do_rename
    jsr selname                 ; seed the prompt with the old name
    jsr no_dots
    bcs @out                    ; ".." is not a thing to rename
    ldy #0
@seed
    lda obuf,y
    sta pbuf,y
    beq @sn
    iny
    bne @seed
@sn
    lda #<s_rnq
    ldx #>s_rnq
    jsr ask
    bcs @out
    ldy #0                      ; "R:" + new + "=" + old
@c
    lda s_r,y
    beq @n
    sta cbuf,y
    iny
    bne @c
@n
    ldx #0
@c2
    lda pbuf,x
    beq @eq
    sta cbuf,y
    iny
    inx
    bne @c2
@eq
    lda #'='
    sta cbuf,y
    iny
    ldx #0
@c3
    lda obuf,x
    sta cbuf,y
    beq @send
    iny
    inx
    bne @c3
@send
    jmp dop
@out
    rts

; ---- copy ------------------------------------------------------------
; CMDR-DOS "C:new=old" is a syntax error on hostfs, so the copy is done
; by hand: open the source for read and the new name for write and
; stream the bytes across. Interrupts are masked around the transfer
; (the event IRQ must not re-enter the KERNAL mid-I/O, the loader
; lesson).
do_copy
    jsr selname
    jsr no_dots
    bcs @out
    ldy #0                      ; the source name is safe in obuf; ask
@save                           ; overwrites nothing of it, but keep a copy
    lda obuf,y                  ; in srcn so a later selname cannot disturb
    sta srcn,y
    beq @asked
    iny
    bne @save
@asked
    stz pbuf                    ; a fresh name for the copy
    lda #<s_cpq
    ldx #>s_cpq
    jsr ask
    bcs @out

    lda #<srcn                  ; open the source, ",S,R"
    ldx #>srcn
    jsr name_open_r
    bcs @noread

    lda #<pbuf                  ; open the destination, ",S,W"
    ldx #>pbuf
    jsr name_open_w
    bcs @nowrite

    sei                         ; stream source -> dest
@loop
    ldx #2
    jsr CHKIN
    jsr CHRIN
    sta ftype                   ; the byte (ftype is free here)
    jsr READST
    sta deldir                  ; the status
    ldx #3
    jsr CHKOUT
    lda ftype
    jsr CHROUT
    lda deldir
    and #$40                    ; EOF on the read?
    beq @loop
    jsr CLRCHN
    lda #2
    jsr CLOSE
    lda #3
    jsr CLOSE
    cli
    lda #<s_copied
    ldx #>s_copied
    jsr note
    jmp refresh
@nowrite
    lda #2                      ; the source is still open
    jsr CLOSE
@noread
    lda #<s_cpbad
    ldx #>s_cpbad
    jmp note
@out
    rts

; name_open_r -- A/X = a bare name; build "name,S,R" in cbuf and OPEN it
; as LFN 2. Carry set if OPEN refused.
name_open_r
    jsr build_name
    lda #<s_sr
    ldx #>s_sr
    jsr append_suffix           ; X = the full length
    txa
    ldx #<cbuf
    ldy #>cbuf
    jsr SETNAM
    lda #2
    ldx #8
    ldy #2
    jsr SETLFS
    jmp OPEN

; name_open_w -- A/X = a bare name; build "name,S,W" and OPEN it as LFN 3.
name_open_w
    jsr build_name
    lda #<s_sw
    ldx #>s_sw
    jsr append_suffix
    txa
    ldx #<cbuf
    ldy #>cbuf
    jsr SETNAM
    lda #3
    ldx #8
    ldy #3
    jsr SETLFS
    jmp OPEN

; build_name -- A/X = a NUL name; copy it into cbuf, cbuf_i = its length.
build_name
    sta poolp
    stx poolp+1
    ldy #0
@c
    lda (poolp),y
    beq @d
    sta cbuf,y
    iny
    bne @c
@d
    sty cbuf_i
    rts

; append_suffix -- A/X = a NUL suffix; append it (and its NUL) at cbuf_i.
; Returns X = the total length (the NUL's position).
append_suffix
    sta poolp
    stx poolp+1
    ldy #0
    ldx cbuf_i
@c
    lda (poolp),y
    sta cbuf,x
    beq @d
    inx
    iny
    bne @c
@d
    stx cbuf_i
    rts

; ---- delete ----------------------------------------------------------
; The alert's button 0 is what RETURN picks, so button 0 is "keep":
; destroying a file must be the deliberate answer, never the default.
do_delete
    jsr selname
    sta deldir                  ; 1 = a directory (RD:), 0 = a file (S:)
    jsr no_dots
    bcs @out
    ldy #0                      ; "delete " + name + "?"
@m
    lda s_delp,y
    beq @mn
    sta qbuf,y
    iny
    bne @m
@mn
    ldx #0
@m2
    lda obuf,x
    beq @mq
    sta qbuf,y
    iny
    inx
    bne @m2
@mq
    lda #'?'
    sta qbuf,y
    iny
    lda #0
    sta qbuf,y

    lda #<dlg_del
    ldx #>dlg_del
    jsr cx_dlg_alert
    cmp #1                      ; only the second button destroys
    bne @out
    ldy #0                      ; "S:" or "RD:" + name
    lda deldir
    beq @scr
    lda #'R'
    sta cbuf
    lda #'D'
    sta cbuf+1
    ldy #2
    bra @colon
@scr
    lda #'S'
    sta cbuf
    ldy #1
@colon
    lda #':'
    sta cbuf,y
    iny
    ldx #0
@c
    lda obuf,x
    sta cbuf,y
    beq @send
    iny
    inx
    bne @c
@send
    jmp dop
@out
    rts

; ask -- prompt with message A/X into pbuf; carry set if cancelled or
; left empty
ask
    pha
    lda #<pbuf
    sta X16_P0
    lda #>pbuf
    sta X16_P1
    lda #17                     ; a DOS name: 16 chars and the NUL
    sta X16_P2
    pla
    jsr cx_dlg_prompt
    bcs @no
    cmp #0
    beq @no
    clc
    rts
@no
    sec
    rts

; no_dots -- carry set if the selection is the "../" row (obuf = "..")
no_dots
    lda obuf
    cmp #'.'
    bne @ok
    lda obuf+1
    cmp #'.'
    bne @ok
    sec
    rts
@ok
    clc
    rts

; on_timer -- the live clock, top right of the menu bar. The KERNAL
; keeps the RTC; this draws HH:MM over a paper patch once a second.
; The bar's rule line (row 13) is left alone.
; on_timer -- "YYYY-MM-DD HH:MM" top right, once a second. The emulator
; RTC starts stopped at 2000-01-01 and only ticks once set, so the boot
; seeds it (see main); on real hardware it is already right and the seed
; is skipped.
on_timer
    jsr CLOCK_GET_DATE_TIME
    lda $02                     ; year: r0L is (year - 1900), so 100+ is
    cmp #100                    ; a 20xx date, below it a 19xx one
    bcc @c19
    sec
    sbc #100
    ldx #'2'
    ldy #'0'
    bra @yy
@c19
    ldx #'1'
    ldy #'9'
@yy
    stx tbuf
    sty tbuf+1
    jsr two_digits              ; the last two digits of the year
    stx tbuf+2
    sta tbuf+3
    lda #'-'
    sta tbuf+4
    lda $03                     ; month
    jsr two_digits
    stx tbuf+5
    sta tbuf+6
    lda #'-'
    sta tbuf+7
    lda $04                     ; day
    jsr two_digits
    stx tbuf+8
    sta tbuf+9
    lda #' '
    sta tbuf+10
    lda $05                     ; hours
    jsr two_digits
    stx tbuf+11
    sta tbuf+12
    lda #':'
    sta tbuf+13
    lda $06                     ; minutes
    jsr two_digits
    stx tbuf+14
    sta tbuf+15
    stz tbuf+16

    lda #<tbuf                  ; measure the date first, to right-align it
    ldx #>tbuf                  ; with an 8px margin (632 = 640-8), the same
    jsr cx_font_measure         ; margin the menu titles get on the left
    sec                         ; clkx = 632 - width
    lda #<632
    sbc X16_P0
    sta clkx
    lda #>632
    sbc X16_P1
    sta clkx+1

    lda #<470                   ; the patch, inside the bar. Height 10, not
    sta X16_P0                  ; 11: row 11 is the bar's rule line. Wide
    lda #>470                   ; enough to cover any right-aligned date
    sta X16_P1
    lda #1
    sta X16_P2
    stz X16_P3
    lda #<164
    sta X16_P4
    stz X16_P5
    lda #10
    sta X16_P6
    stz X16_P7
    lda #0
    jsr cx_gfx_rect

    lda clkx                    ; the date, right-aligned, row 2
    sta X16_P0
    lda clkx+1
    sta X16_P1
    lda #2
    sta X16_P2
    stz X16_P3
    lda #<tbuf
    ldx #>tbuf
    jmp cx_font_draw

two_digits                      ; A = 0-99 -> X = tens char, A = units
    ldx #'0'
@tens
    cmp #10
    bcc @units
    sbc #10
    inx
    bra @tens
@units
    adc #'0'
    rts

; seed_clock -- the emulator's RTC sits stopped at 2000-01-01 00:00:00
; until it is set, then it ticks. If it reads exactly that frozen state,
; start it at a sane date so the desktop clock moves; the control panel
; sets the real time. A hardware RTC holds a real date, fails this test,
; and is left alone.
seed_clock
    jsr CLOCK_GET_DATE_TIME
    lda $02                     ; year 2000?
    cmp #100
    bne @out
    lda $03                     ; month 1, day 1, 00:00:00?
    cmp #1
    bne @out
    lda $04
    cmp #1
    bne @out
    lda $05
    ora $06
    ora $07
    bne @out
    lda #126                    ; 2026-01-01 12:00:00 -- moving, not 00:00
    sta $02
    lda #1
    sta $03
    sta $04
    lda #12
    sta $05
    stz $06
    stz $07
    stz $08
    lda #4
    sta $09
    jmp CLOCK_SET_DATE_TIME
@out
    rts

on_key
    lda inmenu
    bne @menu
    lda X16_P1                  ; --- browsing ---
    cmp #$09                    ; TAB: raise the menu bar
    beq @open
    cmp #$1B                    ; ESC: leave the desktop
    beq @quit
    ldx viewmode                ; icon view turns pages with LEFT/RIGHT
    beq @tolist
    cmp #$9D                    ; LEFT
    beq @pgprev
    cmp #$1D                    ; RIGHT
    beq @pgnext
@tolist
    jsr cx_wg_key               ; UP/DOWN select, RETURN opens (list view)
    rts
@pgprev
    lda iconpage
    beq @pgnone                 ; already the first page
    dec iconpage
    jmp set_view
@pgnext
    clc                         ; a next page only if files remain past this one
    lda pagebase
    adc iw_n
    cmp fcount
    bcs @pgnone
    inc iconpage
    jmp set_view
@pgnone
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

handlers                        ; NULL MOVE DOWN UP DBL KEY TIMER MENU WIDGET JOY
    .addr 0, 0, 0, 0, 0
    .addr on_key
    .addr on_timer
    .addr on_menu
    .addr on_widget
    .addr 0                     ; JOY: the table is EV_COUNT (10) vectors --
                                ; one short and a dispatched type reads a
                                ; garbage vector from whatever data follows

; ---------------------------------------------------------------------
; the menu tree and the widget list
; ---------------------------------------------------------------------
bar
    .byte 4
    .addr s_m0, m0_items
    .addr s_m1, m1_items
    .addr s_m2, m2_items
    .addr s_m3, m3_items
m0_items
    .byte 2
    .addr s_about_i
    .addr s_quit
m1_items
    .byte 5
    .addr s_newf
    .addr s_newfl
    .addr s_ren
    .addr s_cpy
    .addr s_del
m2_items
    .byte 2
    .addr s_day
    .addr s_night
m3_items
    .byte 2
    .addr s_list
    .addr s_icons

widgets
    .byte 1
wl_rec
    .byte WG_LIST, 0
    .word 20, 44, 400
    .byte 240, 0, 0            ; h=240, selected 0, count from readdir
    .addr fptrs
    .byte 0, 0, 0             ; byte 13 = WG_TOP = 0

dlg_del                         ; keep | delete -- keep is the default
    .byte 2
    .addr qbuf
    .addr s_keep, s_dodel

dlg_about                       ; one ok button
    .byte 1
    .addr s_about
    .addr s_ok

theme_day
    .byte $FF, $0F,  $AA, $0A,  $55, $05,  $00, $00
    .byte 0, 1, 3, 0
theme_night                     ; 0 near-black paper, 1 medium-blue
    .byte $01, $00,  $48, $02,  $56, $03,  $BC, $0A   ; highlight
    .byte 0, 1, 3, 0

s_marker  .byte "CXGEOS SHELL", $0D, 0
s_title   .byte "CXGEOS -- dbl-click opens (or UP/DOWN+RETURN), TAB menu, ESC quits", 0
s_m0      .byte "CXGEOS", 0
s_m1      .byte "File", 0
s_m2      .byte "Themes", 0
s_m3      .byte "View", 0
s_list    .byte "list", 0
s_icons   .byte "icons", 0
s_about_i .byte "about", 0
s_quit    .byte "quit", 0
s_newf    .byte "new folder", 0
s_newfl   .byte "new file", 0
s_ren     .byte "rename", 0
s_cpy     .byte "copy", 0
s_del     .byte "delete", 0
s_day     .byte "daylight", 0
s_night   .byte "midnight", 0
s_about   .byte "CXGEOS -- a GEOS-inspired desktop for the X16.", 0
s_ok      .byte "ok", 0
s_bad     .byte "that is not a CXGEOS app.", 0
s_noda    .byte "that desk accessory would not open.", 0
s_shname  .byte "SHELL.CXA"
s_isdesk  .byte "this is the desktop -- you are already in it.", 0
s_mkq     .byte "name the new folder:", 0
s_nfq     .byte "name the new file:", 0
s_rnq     .byte "rename to:", 0
s_cpq     .byte "copy to:", 0
s_delp    .byte "delete "
          .byte 0
s_keep    .byte "keep", 0
s_dodel   .byte "delete", 0
s_cd      .byte "CD:", 0
s_home    .byte "CD://"
s_home_len = * - s_home
s_md      .byte "MD:", 0
s_r       .byte "R:", 0
s_sw      .byte ",S,W", 0
s_sr      .byte ",S,R", 0
s_copied  .byte "copied.                       ", 0
s_cpbad   .byte "copy failed.                  ", 0
pat       .byte "$"
hidden_tab .byte ".X16", ".BIN", ".PRG", ".CXF"
ext4       .res 4, 0
he_i       .byte 0

fcount    .byte 0
ftype     .byte 0
deldir    .byte 0
depth     .byte 0               ; folders deep from the root; 0 = home
ddelta    .byte 0               ; a pending CD's step: +1 down, -1 up
inmenu    .byte 0               ; 0 = browsing, 1 = a menu is open
viewmode  .byte 0               ; 0 = list, 1 = icons
iconpage  .byte 0               ; the icon page on screen
pagebase  .byte 0               ; the first file index of that page
iw_n      .byte 0               ; icons built on it
fidx      .byte 0               ; the file build_icons is placing
grow      .byte 0               ; the grid row/column being laid
gcol      .byte 0
cxw       .word 0               ; the running cell x / y
cy        .word 0
oblen     .byte 0
cbuf_i    .byte 0               ; build_name/append_suffix write index
tbuf      .res 17, 0            ; "YYYY-MM-DD HH:MM"
clkx      .word 0               ; the date's right-aligned x, recomputed each tick
srcn      .res NAMEMAX, 0       ; the copy's source name, kept across ask
obuf      .res NAMEMAX, 0       ; the selected name, slash stripped
pbuf      .res 20, 0            ; what the prompt collects
qbuf      .res 32, 0            ; the delete question
cbuf      .res 48, 0            ; the DOS command being built
mbuf      .res 64, 0            ; the drive's reply
fptrs     .res MAXFILES * 2, 0
ficon     .res MAXFILES, 0        ; the type icon for each listed entry
iwbuf     .res 1 + MAXICON * 16, 0 ; the icon view's widget list (count + records)
pool      .res MAXFILES * NAMEMAX, 0
