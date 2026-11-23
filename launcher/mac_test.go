package main

import (
	"archive/zip"
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func zipOf(t *testing.T, files map[string]string, modes map[string]os.FileMode) []byte {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for name, body := range files {
		h := &zip.FileHeader{Name: name, Method: zip.Deflate}
		if m, ok := modes[name]; ok {
			h.SetMode(m)
		} else {
			h.SetMode(0o644)
		}
		w, err := zw.CreateHeader(h)
		if err != nil {
			t.Fatal(err)
		}
		w.Write([]byte(body))
	}
	zw.Close()
	return buf.Bytes()
}

func TestMacUpdateUnpackAndSwap(t *testing.T) {
	root := t.TempDir()
	app := filepath.Join(root, "Top Ramen Launcher.app")
	os.MkdirAll(filepath.Join(app, "Contents", "MacOS"), 0o755)
	os.WriteFile(filepath.Join(app, "Contents", "MacOS", "TopRamenLauncher"), []byte("old"), 0o755)
	os.WriteFile(filepath.Join(app, "Contents", "Info.plist"), []byte("old plist"), 0o644)

	if got := appBundle(filepath.Join(app, "Contents", "MacOS", "TopRamenLauncher")); got != app {
		t.Fatalf("appBundle = %q", got)
	}
	if got := appBundle("/usr/local/bin/TopRamenLauncher"); got != "" {
		t.Fatalf("appBundle outside an app = %q", got)
	}

	data := zipOf(t, map[string]string{
		"Top Ramen Launcher.app/Contents/MacOS/TopRamenLauncher":       "new",
		"Top Ramen Launcher.app/Contents/Info.plist":                   "new plist",
		"Top Ramen Launcher.app/Contents/Resources/AppIcon.icns":       "icon",
		"Top Ramen Launcher.app/Contents/_CodeSignature/CodeResources": "sig",
	}, map[string]os.FileMode{"Top Ramen Launcher.app/Contents/MacOS/TopRamenLauncher": 0o755})

	stage := filepath.Join(root, ".TopRamenLauncher-update")
	os.MkdirAll(stage, 0o755)
	newApp, err := unpackApp(data, stage)
	if err != nil {
		t.Fatal(err)
	}
	st, err := os.Stat(filepath.Join(newApp, "Contents", "MacOS", "TopRamenLauncher"))
	if err != nil || st.Mode().Perm()&0o100 == 0 {
		t.Fatalf("program lost its run permission: %v %v", st, err)
	}
	if err := swapApp(app, newApp); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(app, "Contents", "MacOS", "TopRamenLauncher"))
	if string(b) != "new" {
		t.Fatalf("app not replaced: %q", b)
	}
	if _, err := os.Stat(app + ".old"); err != nil {
		t.Fatalf("old app not kept for cleanup: %v", err)
	}

	// tampered zips are refused
	for name, files := range map[string]map[string]string{
		"path escape": {"../evil.app/x": "x"},
		"not an app":  {"payload/x": "x"},
		"two apps":    {"A.app/x": "x", "B.app/y": "y"},
	} {
		d := t.TempDir()
		if _, err := unpackApp(zipOf(t, files, nil), d); err == nil {
			t.Errorf("%s: accepted, want refused", name)
		}
	}
}
