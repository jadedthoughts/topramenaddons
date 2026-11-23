#!/usr/bin/env python3
"""Build release zips and manifest.json for the Top Ramen launcher.

Run from the repository root:  python3 tools/build_release.py

Addons named under "test" in channels.json go in a separate testAddons list,
shown only when the player ticks "Show test addons" in the launcher.

For every folder in addons/ it reads "## Version:" from the .toc, writes
releases/<Addon>-<version>.zip (with the addon folder at the top of the zip,
like any WoW addon download) and lists it in manifest.json. Zips that already
exist for a version are left alone, so old versions keep working.
"""
import hashlib, json, os, re, sys, zipfile

REPO = "jadedthoughts/topramenaddons"
BRANCH = "main"
RAW = f"https://raw.githubusercontent.com/{REPO}/{BRANCH}/"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def toc_fields(folder):
    name = os.path.basename(folder)
    toc = os.path.join(folder, name + ".toc")
    fields = {}
    with open(toc, encoding="utf-8-sig") as f:
        for line in f:
            m = re.match(r"##\s*([\w-]+)\s*:\s*(.*?)\s*$", line)
            if m:
                fields[m.group(1)] = m.group(2)
    return fields


def build_zip(folder, out):
    name = os.path.basename(folder)
    tmp = out + ".tmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for base, dirs, files in os.walk(folder):
            dirs.sort()
            for fn in sorted(files):
                full = os.path.join(base, fn)
                rel = os.path.relpath(full, os.path.dirname(folder)).replace(os.sep, "/")
                info = zipfile.ZipInfo(rel, date_time=(2026, 1, 1, 0, 0, 0))  # stable bytes
                info.compress_type = zipfile.ZIP_DEFLATED
                with open(full, "rb") as fh:
                    z.writestr(info, fh.read())
    os.replace(tmp, out)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    addons_dir = os.path.join(ROOT, "addons")
    rel_dir = os.path.join(ROOT, "releases")
    os.makedirs(rel_dir, exist_ok=True)
    old = {}
    mpath = os.path.join(ROOT, "manifest.json")
    if os.path.exists(mpath):
        old = json.load(open(mpath))
    chan_path = os.path.join(ROOT, "channels.json")
    test = set(json.load(open(chan_path)).get("test", [])) if os.path.exists(chan_path) else set()
    entries, test_entries = [], []
    for name in sorted(os.listdir(addons_dir)):
        folder = os.path.join(addons_dir, name)
        if not os.path.isdir(folder):
            continue
        t = toc_fields(folder)
        ver = t.get("Version")
        if not ver:
            sys.exit(f"{name}: no '## Version:' line in its .toc")
        zname = f"{name}-{ver}.zip"
        zpath = os.path.join(rel_dir, zname)
        if not os.path.exists(zpath):
            build_zip(folder, zpath)
            print("built", zname)
        else:
            print("exists", zname)
        notes = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t.get("Notes", ""))
        (test_entries if name in test else entries).append({
            "folder": name,
            "title": t.get("Title", name),
            "version": ver,
            "notes": notes,
            "url": RAW + "releases/" + zname,
            "size": os.path.getsize(zpath),
            "sha256": sha256(zpath),
        })
    launcher = old.get("launcher", {})
    lver_file = os.path.join(ROOT, "launcher", "VERSION")
    if os.path.exists(lver_file):
        launcher = {
            "version": open(lver_file).read().strip(),
            "url": f"https://github.com/{REPO}/raw/{BRANCH}/releases/TopRamenLauncher.zip",
            # for the launcher's own "Update launcher" button (1.4.0 and later)
            "exe": RAW + "releases/TopRamenLauncher.exe",
            "exeApi": f"https://api.github.com/repos/{REPO}/contents/releases/TopRamenLauncher.exe?ref={BRANCH}",
        }
        exe = os.path.join(rel_dir, "TopRamenLauncher.exe")
        if os.path.exists(exe):
            launcher["sha256"] = sha256(exe)
    # test addons get their own list, so launchers older than 1.1.0 never see them
    # the Mac launcher (a zipped .app), built by the GitHub workflow on a Mac
    launcher_mac = old.get("launcherMac", {})
    mac_zip = os.path.join(rel_dir, "TopRamenLauncher-mac.zip")
    mac_ver = os.path.join(rel_dir, "TopRamenLauncher-mac.version")
    if os.path.exists(mac_zip) and os.path.exists(mac_ver):
        launcher_mac = {
            "version": open(mac_ver).read().strip(),
            "url": f"https://github.com/{REPO}/raw/{BRANCH}/releases/TopRamenLauncher-mac.zip",
            "path": "releases/TopRamenLauncher-mac.zip",
            "sha256": sha256(mac_zip),
        }
    manifest = {"schema": 1, "addons": entries, "testAddons": test_entries,
                "launcher": launcher, "launcherMac": launcher_mac}
    with open(mpath, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print("wrote manifest.json with", len(entries), "addons and", len(test_entries), "test addons")


if __name__ == "__main__":
    main()
