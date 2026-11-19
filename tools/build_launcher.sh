#!/bin/sh
# Build releases/TopRamenLauncher.exe (run from the repository root).
set -e
VER=$(cat launcher/VERSION)
python3 tools/make_syso.py launcher/icon.ico launcher/rsrc_windows_amd64.syso
cd launcher
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath \
  -ldflags "-s -w -H windowsgui -X main.Version=$VER" -o ../releases/TopRamenLauncher.exe .
cd ..
ls -la releases/TopRamenLauncher.exe
(cd releases && rm -f TopRamenLauncher.zip && zip -q -X TopRamenLauncher.zip TopRamenLauncher.exe)
