package main

import (
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

// Updating an addon keeps the player's own files in its "keep" folders, and
// still removes files the old version had that the new one doesn't.
func TestInstallKeepsPlayerFolders(t *testing.T) {
	addons := filepath.Join(t.TempDir(), "AddOns")
	old := filepath.Join(addons, "TopRamenThunderCats")
	os.MkdirAll(filepath.Join(old, "Sounds", "extra"), 0o755)
	os.WriteFile(filepath.Join(old, "TopRamenThunderCats.toc"), []byte("## Version: 1.1.0\n"), 0o644)
	os.WriteFile(filepath.Join(old, "Stale.lua"), []byte("old"), 0o644)
	os.WriteFile(filepath.Join(old, "Sounds", "ThunderCats1.mp3"), []byte("clip one"), 0o644)
	os.WriteFile(filepath.Join(old, "Sounds", "extra", "Mine.mp3"), []byte("my clip"), 0o644)

	zipData := zipOf(t, map[string]string{
		"TopRamenThunderCats/TopRamenThunderCats.toc": "## Version: 1.1.1\n",
		"TopRamenThunderCats/TopRamenThunderCats.lua": "-- new",
	}, nil)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write(zipData) }))
	defer srv.Close()
	sum := sha256.Sum256(zipData)
	m := ManifestAddon{Folder: "TopRamenThunderCats", Version: "1.1.1", URL: srv.URL, SHA256: hex.EncodeToString(sum[:]), Keep: []string{"Sounds"}}

	if err := installAddon(m, addons); err != nil {
		t.Fatal(err)
	}
	if v := installedVersion(old); v != "1.1.1" {
		t.Fatalf("version = %q", v)
	}
	for _, f := range []string{"Sounds/ThunderCats1.mp3", "Sounds/extra/Mine.mp3"} {
		if _, err := os.Stat(filepath.Join(old, f)); err != nil {
			t.Errorf("%s was lost: %v", f, err)
		}
	}
	if _, err := os.Stat(filepath.Join(old, "Stale.lua")); err == nil {
		t.Error("Stale.lua from the old version should be gone")
	}

	// without a keep list (older behaviour), Sounds would be lost: guard the test itself
	m.Keep, m.Version = nil, "1.1.1"
	if err := installAddon(m, addons); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(old, "Sounds")); err == nil {
		t.Error("expected Sounds to be replaced when nothing asks to keep it")
	}
}
