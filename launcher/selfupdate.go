package main

// Self-update: download the new launcher .exe, check its SHA-256 against the
// version list, swap it in for the running file and start it.
//
// Windows won't let a running .exe be overwritten, but it will let it be
// renamed. So: write TopRamenLauncher.exe.new, rename the running file to
// TopRamenLauncher.exe.old, rename .new into its place, start it, and exit.
// The new copy deletes the .old file when it starts.

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const updatedFlag = "--updated"

func exePath() (string, error) {
	p, err := os.Executable()
	if err != nil {
		return "", err
	}
	if r, err := filepath.EvalSymlinks(p); err == nil {
		p = r
	}
	return p, nil
}

// downloadLauncher tries GitHub's API first (always current), then the raw URL.
func downloadLauncher(urls ...string) ([]byte, error) {
	var lastErr error
	for _, u := range urls {
		if u == "" {
			continue
		}
		data, err := downloadWith(u, strings.Contains(u, "api.github.com"))
		if err == nil {
			return data, nil
		}
		log.Println("launcher download:", u, err)
		lastErr = err
	}
	if lastErr == nil {
		lastErr = errors.New("the update list has no download for the launcher")
	}
	return nil, lastErr
}

// selfUpdate prepares the new launcher next to the running one. It returns
// a function that finishes the swap and starts the new copy; the caller runs
// it after shutting down the web server, then exits.
func (a *App) selfUpdate() (func() error, error) {
	a.mu.Lock()
	m, commit := a.manifest, a.commit
	a.mu.Unlock()
	if m == nil || m.Launcher.Version == "" || m.Launcher.SHA256 == "" {
		return nil, errors.New("the update list doesn't have a launcher update yet; try Check for updates")
	}
	if compareVersions(m.Launcher.Version, Version) <= 0 {
		return nil, errors.New("you already have the newest launcher")
	}
	self, err := exePath()
	if err != nil {
		return nil, err
	}
	// the .exe at the same commit as the version list matches its checksum exactly
	exeAtCommit := ""
	if commit != "" && RawBase != "" {
		exeAtCommit = RawBase + commit + "/releases/TopRamenLauncher.exe"
	}
	data, err := downloadLauncher(exeAtCommit, m.Launcher.ExeAPI, m.Launcher.Exe)
	if err != nil {
		return nil, err
	}
	sum := sha256.Sum256(data)
	if !strings.EqualFold(hex.EncodeToString(sum[:]), m.Launcher.SHA256) {
		return nil, errors.New("the new launcher didn't download correctly (checksum mismatch). GitHub may still be updating; try again in a few minutes")
	}
	newPath, oldPath := self+".new", self+".old"
	os.Remove(newPath)
	if err := os.WriteFile(newPath, data, 0o755); err != nil {
		return nil, fmt.Errorf("couldn't save the new launcher next to this one (%v). Use the Download link instead", err)
	}
	finish := func() error {
		os.Remove(oldPath)
		if err := os.Rename(self, oldPath); err != nil {
			os.Remove(newPath)
			return err
		}
		if err := os.Rename(newPath, self); err != nil {
			os.Rename(oldPath, self) // put this copy back
			return err
		}
		cmd := exec.Command(self, updatedFlag)
		cmd.Dir = filepath.Dir(self)
		return cmd.Start()
	}
	return finish, nil
}

// cleanupOld removes the previous launcher left behind by an update. The old
// process may take a moment to exit, so keep trying for a little while.
func cleanupOld() {
	self, err := exePath()
	if err != nil {
		return
	}
	old := self + ".old"
	for i := 0; i < 20; i++ {
		if _, err := os.Stat(old); os.IsNotExist(err) {
			return
		}
		if os.Remove(old) == nil {
			log.Println("removed", old)
			return
		}
		time.Sleep(500 * time.Millisecond)
	}
}
