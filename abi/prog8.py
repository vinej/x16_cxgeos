#!/usr/bin/env python3
"""prog8.py -- generate the Prog8 binding for the CXRF ABI.

Prog8 (Irmen de Jong's structured 6502 language) calls a fixed-address routine
with `extsub $ADDR = name(args @reg) -> returns` -- a near-perfect match for the
CXRF jump table ($8010 + slot*3), where args ride A/X/Y and returns come back
in A / A+X / the carry. The one wrinkle is the $22..$29 parameter block: Prog8's
own P8ZP_SCRATCH_PTR lives at $22..$23 and is un-relocatable, so the block is
volatile. Block args are therefore staged ATOMICALLY in raw %asm inside a shim,
right before the jump, from Prog8's virtual registers @R0.. (cx16.r0.. at $02..).

Each slot becomes one of:
    register-only input        -> a direct   extsub $ADDR = name(<reg args>) -> ret
    input via the $22 block    -> a           asmsub name(<@Rn>) { stage; jmp $ADDR }
    a $22-block RETURN value    -> a jsr-capture asmsub (jsr $ADDR; read $22.. -> @AX)
    an irregular slot          -> a hand-written OVERRIDE (packed Y / 24-bit addr)

The argument placement is REUSED from abi/asmsdk.py (its CALLS op-lists), so one
spec drives both the assembler friendly layer and this. Returns come from the
hand-authored RETURNS/PBCAP tables (the .abi "-> out" column is prose).
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asmsdk

TABLE_ADDR = 0x8010


def addr(slot):
    return TABLE_ADDR + slot * 3


# register-return signatures (from the .abi "-> out" column). A missing entry
# means the routine returns nothing the caller reads in a register. Multi-value
# outputs that land in the $22 block (widths, records, byte counts) are noted
# in a comment and read via the cx.pb / cx.pbwN aliases after the call.
RETURNS = {
    "version": "uword @AX",
    "gfx_mode": "bool @Pc", "gfx_read": "ubyte @A", "gfx_flood": "bool @Pc",
    "gfx_info": "ubyte @A",                 # mode; w/h/bpp/stride in the block
    "font_set": "bool @Pc",
    "tile_setup": "bool @Pc",
    "ev_get": "bool @Pc", "ev_next": "bool @Pc",     # the record is in the block
    "ev_count": "ubyte @A", "ev_frames": "ubyte @A",
    "dirty_count": "ubyte @A",
    "menu_set": "bool @Pc", "menu_key": "bool @Pc", "menu_active": "ubyte @A",
    "wg_key": "bool @Pc",
    "dlg_alert": "ubyte @A", "dlg_prompt": "ubyte @A, bool @Pc", "panel": "ubyte @A",
    "pcm_active": "ubyte @A",
    "joy_get": "uword @AX, bool @Pc",
    "spr_collide": "ubyte @A",
    "app_load": "bool @Pc, ubyte @A", "da_open": "bool @Pc",
    "file_load": "bool @Pc, ubyte @A",      # P4/5 = bytes read, in the block
    "vload": "bool @Pc, ubyte @A", "bload": "bool @Pc, ubyte @A",
    "dir_open": "bool @Pc", "dir_next": "ubyte @A, bool @Pc",
    "dos_cmd": "ubyte @A, bool @Pc", "dos_msg": "ubyte @A",
    "clip_put": "bool @Pc", "clip_get": "ubyte @A", "clip_type": "ubyte @A",
}

# slots whose RETURN value is a $22-block word: jsr the slot, then read that
# word into @AX and rts. {name: P-offset of the word}.
PBCAP = {
    "font_measure": 0,          # P0/P1 = the pixel width
    "say": 0,                   # P0/P1 = the pen x past the text
}

# Prog8 keywords / builtin functions a parameter name must not collide with
_RENAME = {"str": "txt", "len": "nlen"}

BLOCK_OPS = ("pw", "pb", "pl", "ph", "pk")
WORD_OPS = ("pw", "al", "pl")   # ops that mean the arg is 16-bit


def _pname(a):
    return _RENAME.get(a, a)


def _is_block(ops):
    return any(op in BLOCK_OPS for op, _, _ in ops)


def _arg_is_word(a, ops):
    return any(oa == a and op in WORD_OPS for op, _, oa in ops)


def _clobbers(ret):
    """The routine trashes A/X/Y except where it returns a value in one. A
    return register must NOT appear in clobbers(), so subtract them out."""
    used = set()
    if re.search(r"@AX\b", ret):
        used |= {"A", "X"}
    if re.search(r"@AY\b", ret):
        used |= {"A", "Y"}
    if re.search(r"@A\b", ret):          # @A alone (not @AX/@AY -- no \b there)
        used.add("A")
    if re.search(r"@X\b", ret):
        used.add("X")
    if re.search(r"@Y\b", ret):
        used.add("Y")
    trashed = [r for r in ("A", "X", "Y") if r not in used]
    return "clobbers(%s)" % ",".join(trashed) if trashed else ""


# =====================================================================
# register-only slots -> extsub
# =====================================================================
def _reg_params(params, ops):
    by = {}
    for op, tgt, a in ops:
        by.setdefault(a, set()).add(op)
    parts = []
    for a in params:
        s = by[a]
        if "al" in s and "xh" in s:
            parts.append("uword %s @AX" % _pname(a))
        elif "al" in s and "yh" in s:
            parts.append("uword %s @AY" % _pname(a))
        elif s == {"a"}:
            parts.append("ubyte %s @A" % _pname(a))
        elif s == {"x"}:
            parts.append("ubyte %s @X" % _pname(a))
        elif s == {"y"}:
            parts.append("ubyte %s @Y" % _pname(a))
        else:
            raise ValueError("unhandled register ops %s for %r" % (s, a))
    return parts


def _extsub(name, params, ops, slot_addr, ret):
    head = "    extsub $%04x = %s(%s)" % (slot_addr, name, ", ".join(_reg_params(params, ops)))
    clob = _clobbers(ret)
    if clob:
        head += " " + clob
    if ret:
        head += " -> " + ret
    return head


# =====================================================================
# block slots -> a normal sub that stages $22.. via the cx.pb aliases (a
# direct store, so Prog8's SCRATCH_PTR at $22 never intervenes) then calls
# a register-only extsub at the slot address. NOT @Rn: those virtual
# registers are also Prog8's own, and a caller holding values there across
# several cx.* calls would see them clobbered.
# =====================================================================
def _reg_op_params(params, ops):
    """The register args (a/x/y/al/xh/yh) as 'type name @reg', friendly order."""
    reg_ops = [(op, t, a) for op, t, a in ops if op not in BLOCK_OPS]
    reg_args = {a for _, _, a in reg_ops}
    ordered = [p for p in params if p in reg_args]
    return _reg_params(ordered, reg_ops), [_pname(p) for p in ordered]


def _stage_lines(ops):
    """`cx.pbwN = arg` / `cx.pb[n] = ...` stores that lay a slot's args into
    the block. Constant indices, so each compiles to a direct $22.. store."""
    L = []
    for op, tgt, a in ops:
        if op not in BLOCK_OPS:
            continue
        off = int(tgt[1:])
        p = _pname(a)
        if op == "pw":
            L.append("        cx.pbw%d = %s" % (off // 2, p))
        elif op == "pb":
            L.append("        cx.pb[%d] = %s" % (off, p))
        elif op == "pl":
            L.append("        cx.pb[%d] = lsb(%s)" % (off, p))
        elif op == "ph":
            L.append("        cx.pb[%d] = msb(%s)" % (off, p))
    return L


def _wrapper_params(params, ops):
    return ["%s %s" % ("uword" if _arg_is_word(a, ops) else "ubyte", _pname(a))
            for a in params]


def _block_binding(name, params, ops, slot_addr, ret, cap_off):
    """The raw register-only extsub + the friendly staging wrapper."""
    reg_parts, reg_call = _reg_op_params(params, ops)
    a_ret = "" if cap_off is not None else ret       # a captured word is read here
    raw = "    extsub $%04x = %s_a(%s)" % (slot_addr, name, ", ".join(reg_parts))
    clob = _clobbers(a_ret)
    if clob:
        raw += " " + clob
    if a_ret:
        raw += " -> " + a_ret

    wret = "uword" if cap_off is not None else _p8_ret_types(ret)
    head = "    sub %s(%s)%s {" % (name, ", ".join(_wrapper_params(params, ops)),
                                   " -> " + wret if wret else "")
    body = _stage_lines(ops)
    call = "%s_a(%s)" % (name, ", ".join(reg_call))
    if cap_off is not None:
        body.append("        %s" % call)
        body.append("        return cx.pbw%d" % (cap_off // 2))
    elif "," in wret:
        # multi-value: Prog8 forbids `return multicall()`, so capture + return
        types = [t.strip() for t in wret.split(",")]
        names = ["r%d" % i for i in range(len(types))]
        for t, n in zip(types, names):
            body.append("        %s %s" % (t, n))
        body.append("        %s = %s" % (", ".join(names), call))
        body.append("        return %s" % ", ".join(names))
    elif wret:
        body.append("        return %s" % call)
    else:
        body.append("        %s" % call)
    return raw + "\n" + head + "\n" + "\n".join(body) + "\n    }"


def _pbcap_binding(name, params, ops, slot_addr, off):
    """A slot whose RESULT is a $22-block word (a width, a pen x). The capture
    must land in registers, not `return cx.pbw0`: Prog8 would alias the result
    to $22 itself, and the next kernel call that stages the block would mutate
    it. So an asmsub does jsr + reads $22.. into A/X (a clean register value);
    any block INPUT is staged first by a normal-sub wrapper (SCRATCH_PTR-safe)."""
    reg_parts, reg_call = _reg_op_params(params, ops)
    block_ops = [t for t in ops if t[0] in BLOCK_OPS]
    raw = name if not block_ops else name + "_raw"
    asm = ["    asmsub %s(%s) clobbers(Y) -> uword @AX {" % (raw, ", ".join(reg_parts)),
           "        %asm {{",
           "            jsr  $%04x" % slot_addr,
           "            lda  $%02x" % (0x22 + off),
           "            ldx  $%02x" % (0x23 + off),
           "            rts",
           "        }}",
           "    }"]
    out = "\n".join(asm)
    if block_ops:
        head = "    sub %s(%s) -> uword {" % (name, ", ".join(_wrapper_params(params, ops)))
        body = _stage_lines(ops)
        body.append("        return %s(%s)" % (raw, ", ".join(reg_call)))
        out += "\n" + head + "\n" + "\n".join(body) + "\n    }"
    return out


# the wrapper's Prog8 return TYPES, from the register-return signature. A
# multi-value slot (e.g. "bool @Pc, ubyte @A") becomes "bool, ubyte" -- a
# normal sub auto-assigns the return registers, so only the types matter.
def _p8_ret_types(ret):
    if not ret:
        return ""
    return ", ".join(p.split()[0] for p in ret.split(","))


# =====================================================================
# hand-written overrides (packed Y, 24-bit VRAM address)
# =====================================================================
def _override_gfx_pattern(a):
    # the fill pattern rides A/X; Y packs both colours: (bg & 3) << 2 | (fg & 3)
    return ("    extsub $%04x = gfx_pattern_a(uword pat @AX, ubyte yv @Y) clobbers(A,X,Y)\n"
            "    sub gfx_pattern(uword pat, ubyte bg, ubyte fg) {\n"
            "        gfx_pattern_a(pat, ((bg & 3) << 2) | (fg & 3))\n"
            "    }") % a["cx_gfx_pattern"]


def _override_sprite_image(a):
    # a 17-bit VRAM image address is split for Prog8: a uword + a bank byte,
    # laid into P0/P1 (addr) and P2 (bank); spr rides X, mode rides A
    return ("    extsub $%04x = sprite_image_a(ubyte spr @X, ubyte mode @A) clobbers(A,X,Y)\n"
            "    sub sprite_image(ubyte spr, uword addr, ubyte bank, ubyte mode) {\n"
            "        cx.pb[0] = lsb(addr)\n"
            "        cx.pb[1] = msb(addr)\n"
            "        cx.pb[2] = bank\n"
            "        sprite_image_a(spr, mode)\n"
            "    }") % a["cx_sprite_image"]


OVERRIDES = {
    "gfx_pattern": _override_gfx_pattern,
    "sprite_image": _override_sprite_image,
}


# =====================================================================
# constants
# =====================================================================
def _const_type(val):
    n = int(val.replace("$", "0x"), 0) if isinstance(val, str) else int(val)
    if n < 0 or n > 0xFFFF:
        return None
    return "ubyte" if n <= 0xFF else "uword"


def gen(version, slots):
    """Return the Prog8 binding sdk/include_prog8/cxrf.p8."""
    a = {s["name"]: addr(s["slot"]) for s in slots}
    L = ["; Prog8 -- GENERATED by abi/gen_bindings.py. Do not edit."]
    L.append("; =====================================================================")
    L.append("; CXRF ABI version %d -- Prog8 binding" % version)
    L.append("; =====================================================================")
    L.append("; Call the kernel through these. A register-only slot is a plain extsub;")
    L.append("; a slot that uses the $22 parameter block is a typed asmsub that stages")
    L.append("; the block in raw asm right before the jump (Prog8's SCRATCH_PTR owns")
    L.append("; $22..$23, so the block is volatile). Slots that RETURN data in the")
    L.append("; block (an event record, a byte count, a width) leave it in cx.pb /")
    L.append("; cx.pbwN -- read those before the next kernel call. Needs syslib (cx16).")
    L.append(";")
    L.append(";     %import cxrf")
    L.append(";     cx.gfx_init()")
    L.append(";     cx.gfx_clear(0)")
    L.append("; =====================================================================")
    L.append("")
    L.append("; !!! YOUR MAIN PROGRAM MUST DECLARE BOTH:")
    L.append(";        %option no_sysinit")
    L.append(";        %zpreserved $02,$5f")
    L.append("; no_sysinit: a CXRF app is a GUEST -- the kernel owns the machine.")
    L.append("; Prog8's default startup (init_system) does a full reset -- RESTOR,")
    L.append("; CINT, IOINIT, mouse_config(0,0,0) -- which tears out the live kernel")
    L.append("; IRQ and video. It looks fine on a boot autorun (nothing live to wreck)")
    L.append("; but crashes the instant the desktop (a running app) launches you.")
    L.append("; no_sysinit skips it; gfx_init/ev_init set up what you actually need.")
    L.append(";")
    L.append("; The CXRF kernel owns zero page $02..$5F and clobbers it across every")
    L.append("; API call (docs: kernel/resident/zp.inc -- $02-$21 KERNAL scratch, $22-$31")
    L.append("; the x16lib block+temps, $32-$5F kernel state). Only $60..$7F is the app's.")
    L.append("; Reserving $02..$5F keeps Prog8's VARIABLES in $60..$7F (+ main RAM), where")
    L.append("; a kernel call can't reach them -- WITHOUT it a variable landing in that")
    L.append("; range is silently corrupted by the next call. Prog8 honours %zpreserved")
    L.append("; only in the program being compiled, so it cannot be inherited from here;")
    L.append("; every app must repeat the line. (basicsafe pins its SCRATCH_PTR at $22 --")
    L.append("; that IS the block; the bindings stage it and read block outputs before any")
    L.append("; indirect op, so it never clashes.)")
    L.append("%zpreserved $02,$5f        ; (also here, though Prog8 applies it per-program)")
    L.append("")
    L.append("cx {")
    L.append("    const ubyte ABI_VERSION = %d" % version)
    L.append("")
    L.append("    ; the parameter block, for reading a slot's $22-block outputs")
    L.append("    &ubyte[8] pb   = $22")
    L.append("    &uword    pbw0 = $22")
    L.append("    &uword    pbw1 = $24")
    L.append("    &uword    pbw2 = $26")
    L.append("    &uword    pbw3 = $28")
    L.append("")

    for group, items in asmsdk.CONSTS:
        L.append("    ; --- " + group + " ---")
        for cname, val, cm in items:
            short = cname[3:] if cname.startswith("CX_") else cname
            t = _const_type(val)
            if t is None:
                L.append("    ; %s = %s   (>16-bit: use a literal)" % (short, val))
                continue
            line = "    const %s %s = %s" % (t, short, val)
            if cm:
                line += "    ; " + cm
            L.append(line)
        L.append("")

    L.append("    ; --- calls ---")
    for spec in asmsdk.CALLS:
        name, params, ops, tail = spec[0], spec[1], spec[3], spec[4]
        call = spec[5] if len(spec) > 5 else "cx_" + name
        slot_addr = a[call]
        ret = RETURNS.get(name, "")
        if name in OVERRIDES:
            L.append(OVERRIDES[name](a))
        elif name in PBCAP:
            L.append(_pbcap_binding(name, params, ops, slot_addr, PBCAP[name]))
        elif _is_block(ops):
            L.append(_block_binding(name, params, ops, slot_addr, ret, None))
        else:
            L.append(_extsub(name, params, ops, slot_addr, ret))
    L.append("}")
    return "\n".join(L) + "\n"


if __name__ == "__main__":
    import gen_bindings
    v, sl = gen_bindings.parse((Path(__file__).resolve().parent / "cxrf.abi").read_text(encoding="ascii"))
    sys.stdout.write(gen(v, sl))
