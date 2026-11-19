package main

import (
	"archive/zip"
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var versionLine = regexp.MustCompile(`^##\s*Version\s*:\s*(.+?)\s*$`)

// installedVersion reads "## Version:" from <folder>\<folder>.toc.
func installedVersion(dir string) string {
	return tocVersion(dir, filepath.Base(dir))
}

// tocVersion reads "## Version:" from dir\<name>.toc ("" if there's no .toc).
func tocVersion(dir, name string) string {
	f, err := os.Open(filepath.Join(dir, name+".toc"))
	if err != nil {
		return ""
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimPrefix(sc.Text(), string(rune(0xFEFF)))
		if m := versionLine.FindStringSubmatch(line); m != nil {
			return m[1]
		}
	}
	return "?" // installed, but no version line
}

// compareVersions compares dotted versions like 1.14.1 numerically.
// Returns 1 if a > b, -1 if a < b, 0 if equal. "?" counts as oldest.
func compareVersions(a, b string) int {
	pa, pb := strings.Split(a, "."), strings.Split(b, ".")
	for i := 0; i < len(pa) || i < len(pb); i++ {
		var x, y int
		if i < len(pa) {
			x, _ = strconv.Atoi(strings.TrimFunc(pa[i], func(r rune) bool { return r < '0' || r > '9' }))
		}
		if i < len(pb) {
			y, _ = strconv.Atoi(strings.TrimFunc(pb[i], func(r rune) bool { return r < '0' || r > '9' }))
		}
		if x != y {
			if x > y {
				return 1
			}
			return -1
		}
	}
	return 0
}

const maxZip = 200 << 20

func download(url string) ([]byte, error) {
	client := &http.Client{Timeout: 5 * time.Minute}
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("User-Agent", "TopRamenLauncher/"+Version)
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("download failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("download failed: %s", resp.Status)
	}
	return io.ReadAll(io.LimitReader(resp.Body, maxZip))
}

// installAddon downloads the addon zip, checks it, unpacks it next to the
// AddOns folder's copy and swaps it in. The old copy is kept until the new
// one is in place, so a failure leaves the addon as it was.
func installAddon(m ManifestAddon, addonsDir string) error {
	if m.Folder == "" || strings.ContainsAny(m.Folder, `/\:.`) {
		return errors.New("bad addon name in update list")
	}
	data, err := download(m.URL)
	if err != nil {
		return err
	}
	if m.SHA256 != "" {
		sum := sha256.Sum256(data)
		if !strings.EqualFold(hex.EncodeToString(sum[:]), m.SHA256) {
			return errors.New("the download was damaged (checksum mismatch); try again")
		}
	}
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return fmt.Errorf("the download isn't a valid zip: %w", err)
	}

	stage := filepath.Join(addonsDir, "."+m.Folder+".new")
	old := filepath.Join(addonsDir, "."+m.Folder+".old")
	final := filepath.Join(addonsDir, m.Folder)
	os.RemoveAll(stage)
	os.RemoveAll(old)
	if err := os.MkdirAll(stage, 0o755); err != nil {
		return permErr(err)
	}
	cleanup := true
	defer func() {
		if cleanup {
			os.RemoveAll(stage)
		}
	}()

	prefix := m.Folder + "/"
	files := 0
	for _, f := range zr.File {
		name := strings.ReplaceAll(f.Name, `\`, "/")
		if !strings.HasPrefix(name, prefix) {
			return fmt.Errorf("unexpected file in zip: %s", f.Name)
		}
		rel := path.Clean(strings.TrimPrefix(name, prefix))
		if rel == "." || strings.HasSuffix(name, "/") {
			continue
		}
		if strings.HasPrefix(rel, "../") || path.IsAbs(rel) || strings.Contains(rel, ":") {
			return fmt.Errorf("unsafe path in zip: %s", f.Name)
		}
		out := filepath.Join(stage, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
			return permErr(err)
		}
		rc, err := f.Open()
		if err != nil {
			return err
		}
		w, err := os.Create(out)
		if err != nil {
			rc.Close()
			return permErr(err)
		}
		_, err = io.Copy(w, io.LimitReader(rc, maxZip))
		rc.Close()
		if cerr := w.Close(); err == nil {
			err = cerr
		}
		if err != nil {
			return err
		}
		files++
	}
	if tocVersion(stage, m.Folder) == "" {
		return fmt.Errorf("the zip has no %s.toc", m.Folder)
	}

	hadOld := false
	if _, err := os.Stat(final); err == nil {
		if err := os.Rename(final, old); err != nil {
			return fmt.Errorf("couldn't replace %s. If WoW is running, close it and try again (%v)", m.Folder, err)
		}
		hadOld = true
	}
	if err := os.Rename(stage, final); err != nil {
		if hadOld {
			os.Rename(old, final) // put the old copy back
		}
		return permErr(err)
	}
	cleanup = false
	if hadOld {
		os.RemoveAll(old)
	}
	return nil
}

func permErr(err error) error {
	if errors.Is(err, os.ErrPermission) {
		return fmt.Errorf("Windows didn't allow writing to the AddOns folder. Close WoW, or right-click the launcher and choose Run as administrator (%v)", err)
	}
	return err
}
