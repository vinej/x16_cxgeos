; =====================================================================
; CXGEOS :: kernel/resident/impl.inc -- ABI name -> kernel routine
; =====================================================================
; abi/cxgeos.abi names what an app may call. This names the code behind
; each one. They are kept apart on purpose: the left column is a promise
; to every app ever built, the right is the kernel's business. A routine
; can be renamed, rewritten or moved to another module by editing this
; file alone, and no app notices.
;
; Read by abi/gen_bindings.py, which builds the jump table from it and
; refuses to run if the two columns disagree -- an ABI slot with no
; routine, or a routine claiming a slot that does not exist.
;
;   <abi name> = <kernel label>
; =====================================================================

cx_version      = cx_do_version
cx_exit         = cx_do_exit

cx_gfx_init     = gfx2_init
cx_gfx_clear    = gfx2_clear
cx_gfx_pset     = gfx2_pset
cx_gfx_read     = gfx2_read
cx_gfx_hline    = gfx2_hline
cx_gfx_vline    = gfx2_vline
cx_gfx_rect     = gfx2_rect
cx_gfx_frame    = gfx2_frame
cx_gfx_line     = gfx2_line
cx_gfx_pattern  = gfx2_pattern_set
cx_gfx_patrect  = gfx2_pattern_rect
cx_gfx_blit     = gfx2_blit
cx_gfx_blitm    = gfx2_blitm

cx_font_set     = font_set
cx_font_style   = font_style
cx_font_measure = font_measure
cx_font_draw    = font_draw

cx_ev_handlers  = ev_handlers
cx_ev_mainloop  = ev_mainloop
cx_ev_dispatch  = ev_dispatch
cx_ev_get       = ev_get
cx_ev_post      = ev_post
cx_ev_count     = ev_count
cx_ev_timer     = ev_timer
cx_ev_frames    = ev_frames

cx_dirty_reset  = dr_reset
cx_dirty_add    = dr_add
cx_dirty_count  = dr_count
cx_dirty_get    = dr_get

cx_app_load     = cxl_load
cx_ev_init      = ev_init
cx_menu_set     = cx_do_menu_set
cx_menu_off     = cx_do_menu_off
cx_mouse_show   = cx_do_mouse_show
cx_mouse_hide   = mouse_hide
cx_theme_set    = cx_do_theme_set
cx_dlg_alert    = cx_do_dlg_alert
cx_wg_set       = cx_do_wg_set
cx_wg_draw      = cx_do_wg_draw
cx_menu_key     = cx_do_menu_key
cx_wg_key       = cx_do_wg_key
cx_dir_open     = cx_dir_open
cx_dir_next     = cx_dir_next
cx_dir_close    = cx_dir_close
cx_dos_cmd      = cx_do_dos_cmd
cx_dos_msg      = cx_do_dos_msg
cx_dlg_prompt   = cx_do_dlg_prompt
cx_clip_put     = cx_do_clip_put
cx_clip_get     = cx_do_clip_get
cx_clip_type    = cx_do_clip_type
