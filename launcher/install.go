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
	"runtime"
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

func download(url string) ([]byte, error) { return downloadWith(url, false) }

// downloadWith fetches url; api asks GitHub's contents API for the raw file.
func downloadWith(url string, api bool) ([]byte, error) {
	client := &http.Client{Timeout: 5 * time.Minute}
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("User-Agent", "TopRamenLauncher/"+Version)
	if api {
		req.Header.Set("Accept", "application/vnd.github.raw")
	}
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

	// carry over the player's own folders (e.g. Sounds) from the installed copy
	for _, k := range m.Keep {
		k = filepath.Clean(k)
		if k == "." || filepath.IsAbs(k) || strings.HasPrefix(k, "..") || strings.ContainsAny(k, `:`) {
			continue
		}
		if err := mergeDir(filepath.Join(final, k), filepath.Join(stage, k)); err != nil {
			return fmt.Errorf("couldn't keep your %s folder, so nothing was changed (%v)", k, err)
		}
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

// mergeDir copies every file under src into dst, except files the new
// version itself ships (those are updated). A missing src is fine.
func mergeDir(src, dst string) error {
	if st, err := os.Stat(src); err != nil || !st.IsDir() {
		return nil
	}
	return filepath.Walk(src, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, p)
		if err != nil {
			return err
		}
		out := filepath.Join(dst, rel)
		if info.IsDir() {
			return os.MkdirAll(out, 0o755)
		}
		if !info.Mode().IsRegular() {
			return nil
		}
		if _, err := os.Stat(out); err == nil {
			return nil // the new version has its own copy of this file
		}
		in, err := os.Open(p)
		if err != nil {
			return err
		}
		defer in.Close()
		w, err := os.OpenFile(out, os.O_CREATE|os.O_EXCL|os.O_WRONLY, info.Mode().Perm())
		if err != nil {
			return err
		}
		if _, err := io.Copy(w, in); err != nil {
			w.Close()
			return err
		}
		return w.Close()
	})
}

func permErr(err error) error {
	if errors.Is(err, os.ErrPermission) {
		if runtime.GOOS == "darwin" {
			return fmt.Errorf("macOS didn't allow writing to the AddOns folder. Close WoW and try again; if it still fails, check the folder's permissions in Finder (Get Info) (%v)", err)
		}
		return fmt.Errorf("Windows didn't allow writing to the AddOns folder. Close WoW, or right-click the launcher and choose Run as administrator (%v)", err)
	}
	return err
}
