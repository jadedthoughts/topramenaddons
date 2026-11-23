package main

// Mac support: the launcher ships as "Top Ramen Launcher.app". This file has
// the Mac-only behaviour; it builds on every platform so it can be tested.

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"
)

// appBundle returns the .app folder the program runs from, or "" if it isn't
// inside one (exe is <app>/Contents/MacOS/<name>).
func appBundle(exe string) string {
	app := filepath.Dir(filepath.Dir(filepath.Dir(exe)))
	if strings.HasSuffix(strings.ToLower(app), ".app") &&
		filepath.Base(filepath.Dir(exe)) == "MacOS" && filepath.Base(filepath.Dir(filepath.Dir(exe))) == "Contents" {
		return app
	}
	return ""
}

// openWindowMac shows the page in Chrome, Edge or Brave as its own app window
// (with its own profile, so the browser process lives as long as the window),
// or in the default browser (usually Safari) if none of those is installed.
func openWindowMac(url string) *os.Process {
	profile := filepath.Join(dataDir(), "window")
	home, _ := os.UserHomeDir()
	browsers := []string{
		"Google Chrome.app/Contents/MacOS/Google Chrome",
		"Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
		"Brave Browser.app/Contents/MacOS/Brave Browser",
		"Chromium.app/Contents/MacOS/Chromium",
	}
	for _, dir := range []string{"/Applications", filepath.Join(home, "Applications")} {
		for _, b := range browsers {
			p := filepath.Join(dir, b)
			if _, err := os.Stat(p); err != nil {
				continue
			}
			cmd := exec.Command(p, "--app="+url, "--window-size=860,940",
				"--user-data-dir="+profile, "--no-first-run", "--no-default-browser-check")
			if cmd.Start() == nil {
				return cmd.Process
			}
		}
	}
	exec.Command("open", url).Start()
	return nil
}

// unpackApp extracts the single .app bundle in a zip into dir and returns its
// path. File modes (the executable bit) and symlinks are kept.
func unpackApp(data []byte, dir string) (string, error) {
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return "", fmt.Errorf("the download isn't a valid zip: %w", err)
	}
	app := ""
	for _, f := range zr.File {
		name := path.Clean(strings.ReplaceAll(f.Name, `\`, "/"))
		if strings.HasPrefix(name, "__MACOSX") || name == "." {
			continue
		}
		if strings.HasPrefix(name, "../") || path.IsAbs(name) || strings.Contains(name, "/../") {
			return "", fmt.Errorf("unsafe path in zip: %s", f.Name)
		}
		top := strings.SplitN(name, "/", 2)[0]
		if !strings.HasSuffix(strings.ToLower(top), ".app") {
			return "", fmt.Errorf("unexpected file in zip: %s", f.Name)
		}
		if app == "" {
			app = top
		} else if app != top {
			return "", errors.New("the zip holds more than one app")
		}
		out := filepath.Join(dir, filepath.FromSlash(name))
		mode := f.Mode()
		switch {
		case mode.IsDir():
			if err := os.MkdirAll(out, 0o755); err != nil {
				return "", err
			}
			continue
		case mode&os.ModeSymlink != 0:
			rc, err := f.Open()
			if err != nil {
				return "", err
			}
			target, _ := io.ReadAll(io.LimitReader(rc, 4096))
			rc.Close()
			t := string(target)
			if path.IsAbs(t) || strings.HasPrefix(path.Clean(path.Join(path.Dir(name), t)), "../") {
				return "", fmt.Errorf("unsafe link in zip: %s", f.Name)
			}
			os.MkdirAll(filepath.Dir(out), 0o755)
			if err := os.Symlink(t, out); err != nil {
				return "", err
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
			return "", err
		}
		rc, err := f.Open()
		if err != nil {
			return "", err
		}
		perm := mode.Perm()
		if perm == 0 {
			perm = 0o644
		}
		w, err := os.OpenFile(out, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, perm)
		if err != nil {
			rc.Close()
			return "", err
		}
		_, err = io.Copy(w, io.LimitReader(rc, maxZip))
		rc.Close()
		if cerr := w.Close(); err == nil {
			err = cerr
		}
		if err != nil {
			return "", err
		}
	}
	if app == "" {
		return "", errors.New("the zip has no app in it")
	}
	return filepath.Join(dir, app), nil
}

// swapApp puts newApp where app is, keeping the old one at app+".old" until
// the new one is in place.
func swapApp(app, newApp string) error {
	old := app + ".old"
	os.RemoveAll(old)
	if err := os.Rename(app, old); err != nil {
		return err
	}
	if err := os.Rename(newApp, app); err != nil {
		os.Rename(old, app) // put this copy back
		return err
	}
	return nil
}

func (a *App) selfUpdateMac() (func() error, error) {
	a.mu.Lock()
	m, commit := a.manifest, a.commit
	a.mu.Unlock()
	if m == nil || m.LauncherMac.Version == "" || m.LauncherMac.SHA256 == "" || m.LauncherMac.Path == "" {
		return nil, errors.New("the update list doesn't have a Mac launcher update yet; try Check for updates")
	}
	if compareVersions(m.LauncherMac.Version, Version) <= 0 {
		return nil, errors.New("you already have the newest launcher")
	}
	self, err := exePath()
	if err != nil {
		return nil, err
	}
	app := appBundle(self)
	if app == "" {
		return nil, errors.New("this launcher isn't running as a Mac app, so it can't replace itself. Use the Download link instead")
	}
	if strings.Contains(app, "/AppTranslocation/") {
		return nil, errors.New("macOS is running the launcher from a temporary copy, so it can't update itself. Quit it, drag Top Ramen Launcher into your Applications folder, and open it from there")
	}
	var urls []string
	if commit != "" && RawBase != "" {
		urls = append(urls, RawBase+commit+"/"+m.LauncherMac.Path)
	}
	if RawBase != "" {
		urls = append(urls, RawBase+"main/"+m.LauncherMac.Path)
	}
	data, err := downloadLauncher(urls...)
	if err != nil {
		return nil, err
	}
	sum := sha256.Sum256(data)
	if !strings.EqualFold(hex.EncodeToString(sum[:]), m.LauncherMac.SHA256) {
		return nil, errors.New("the new launcher didn't download correctly (checksum mismatch). GitHub may still be updating; try again in a few minutes")
	}
	stage := filepath.Join(filepath.Dir(app), ".TopRamenLauncher-update")
	os.RemoveAll(stage)
	if err := os.MkdirAll(stage, 0o755); err != nil {
		return nil, fmt.Errorf("couldn't save the new launcher next to this one (%v). Use the Download link instead", err)
	}
	newApp, err := unpackApp(data, stage)
	if err != nil {
		os.RemoveAll(stage)
		return nil, err
	}
	finish := func() error {
		defer os.RemoveAll(stage)
		if err := swapApp(app, newApp); err != nil {
			return err
		}
		log.Println("swapped in the new Mac launcher; opening it")
		return exec.Command("open", "-n", app, "--args", updatedFlag).Start()
	}
	return finish, nil
}
