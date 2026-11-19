#!/usr/bin/env python3
"""Write launcher/rsrc_windows_amd64.syso: a COFF object holding the program
icon (RT_GROUP_ICON + RT_ICON) and a manifest, which the Go linker embeds
in the .exe. Usage: python3 tools/make_syso.py launcher/icon.ico out.syso"""
import struct, sys

RT_ICON, RT_GROUP_ICON, RT_MANIFEST = 3, 14, 24
LANG = 0x0409

MANIFEST = b"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity type="win32" name="TopRamen.Launcher" version="1.0.0.0"/>
  <description>Top Ramen Forever Launcher</description>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges>
    <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
  </requestedPrivileges></security></trustInfo>
  <application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings>
    <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware>
  </windowsSettings></application>
</assembly>
"""


def read_ico(path):
    d = open(path, "rb").read()
    _, typ, count = struct.unpack_from("<HHH", d, 0)
    assert typ == 1, "not an .ico"
    imgs = []
    for i in range(count):
        w, h, cc, _, planes, bpp, size, off = struct.unpack_from("<BBBBHHII", d, 6 + 16 * i)
        imgs.append(((w, h, cc, planes, bpp), d[off:off + size]))
    return imgs


def build(ico, out):
    imgs = read_ico(ico)
    # resources: list of (type, id, bytes)
    res = []
    grp = struct.pack("<HHH", 0, 1, len(imgs))
    for i, ((w, h, cc, planes, bpp), data) in enumerate(imgs, start=1):
        res.append((RT_ICON, i, data))
        grp += struct.pack("<BBBBHHIH", w, h, cc, 0, planes, bpp, len(data), i)
    res.append((RT_GROUP_ICON, 1, grp))
    res.append((RT_MANIFEST, 1, MANIFEST))

    types = sorted({t for t, _, _ in res})
    by_type = {t: sorted([(i, b) for tt, i, b in res if tt == t]) for t in types}

    # layout: root dir, type dirs, name dirs (one lang each), data entries, then data
    def dir_size(n):
        return 16 + 8 * n

    off = dir_size(len(types))
    type_dir_off = {}
    for t in types:
        type_dir_off[t] = off
        off += dir_size(len(by_type[t]))
    name_dir_off = {}
    for t in types:
        for i, _ in by_type[t]:
            name_dir_off[(t, i)] = off
            off += dir_size(1)
    entry_off = {}
    for t in types:
        for i, _ in by_type[t]:
            entry_off[(t, i)] = off
            off += 16
    data_off = {}
    for t in types:
        for i, b in by_type[t]:
            off = (off + 7) & ~7
            data_off[(t, i)] = off
            off += len(b)
    total = (off + 7) & ~7

    sec = bytearray(total)

    def put_dir(at, n):
        struct.pack_into("<IIHHHH", sec, at, 0, 0, 0, 0, 0, n)

    put_dir(0, len(types))
    for k, t in enumerate(types):
        struct.pack_into("<II", sec, 16 + 8 * k, t, 0x80000000 | type_dir_off[t])
        put_dir(type_dir_off[t], len(by_type[t]))
        for j, (i, b) in enumerate(by_type[t]):
            struct.pack_into("<II", sec, type_dir_off[t] + 16 + 8 * j, i, 0x80000000 | name_dir_off[(t, i)])
            put_dir(name_dir_off[(t, i)], 1)
            struct.pack_into("<II", sec, name_dir_off[(t, i)] + 16, LANG, entry_off[(t, i)])
            # data entry: RVA (relocated), size, codepage, reserved
            struct.pack_into("<IIII", sec, entry_off[(t, i)], data_off[(t, i)], len(b), 0, 0)
            sec[data_off[(t, i)]:data_off[(t, i)] + len(b)] = b

    relocs = [entry_off[k] for k in sorted(entry_off, key=lambda k: entry_off[k])]

    # COFF file
    hdr_size, sh_size = 20, 40
    raw_ptr = hdr_size + sh_size
    reloc_ptr = raw_ptr + len(sec)
    sym_ptr = reloc_ptr + 10 * len(relocs)
    nsyms = 2  # section symbol + its aux record
    coff = struct.pack("<HHIIIHH", 0x8664, 1, 0, sym_ptr, nsyms, 0, 0)
    shdr = struct.pack("<8sIIIIIIHHI", b".rsrc", 0, 0, len(sec), raw_ptr, reloc_ptr, 0,
                       len(relocs), 0, 0x40000040)  # initialized data, read
    body = bytes(sec)
    rel = b"".join(struct.pack("<IIH", r, 0, 3) for r in relocs)  # IMAGE_REL_AMD64_ADDR32NB vs symbol 0
    sym = struct.pack("<8sIhHBB", b".rsrc", 0, 1, 0, 3, 1)  # static, 1 aux
    aux = struct.pack("<IHHIHBB2s", len(sec), len(relocs), 0, 0, 0, 0, 0, b"\0\0")
    strtab = struct.pack("<I", 4)
    open(out, "wb").write(coff + shdr + body + rel + sym + aux + strtab)
    print("wrote", out, len(imgs), "icon sizes,", len(relocs), "resources")


if __name__ == "__main__":
    build(sys.argv[1], sys.argv[2])
