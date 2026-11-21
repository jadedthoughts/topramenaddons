// Top Ramen Forever Launcher
//
// Checks the Top Ramen addons in your WoW Forever AddOns folder against the
// latest versions published on GitHub, and installs or updates them.
// The window is a small local web page shown in an Edge (or Chrome) app
// window; the program exits a few seconds after that window is closed.
package main

import (
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"
)

// Version is set at build time from launcher/VERSION.
var Version = "dev"

// The list of latest versions. It's read through GitHub's API first, which
// always returns the current file; raw.githubusercontent.com (the fallback)
// can serve a copy up to 5 minutes old after a change.
var ManifestAPI = "https://api.github.com/repos/jadedthoughts/topramenaddons/contents/manifest.json?ref=main"
var ManifestURL = "https://raw.githubusercontent.com/jadedthoughts/topramenaddons/main/manifest.json"

// First choice: ask GitHub's git endpoint (the one `git clone` uses) for the
// newest commit, then fetch files at that exact commit. Those addresses never
// change, so no cache can serve an old copy, and this endpoint isn't subject
// to the API's 60-requests-an-hour limit.
var RepoGit = "https://github.com/jadedthoughts/topramenaddons.git"
var RawBase = "https://raw.githubusercontent.com/jadedthoughts/topramenaddons/"

// latestCommit returns the commit ID that main points to right now.
func latestCommit() (string, error) {
	client := &http.Client{Timeout: 15 * time.Second}
	req, _ := http.NewRequest("GET", RepoGit+"/info/refs?service=git-upload-pack", nil)
	req.Header.Set("User-Agent", "git/2.43.0 (TopRamenLauncher/"+Version+")")
	req.Header.Set("Cache-Control", "no-cache")
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("git endpoint answered %s", resp.Status)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", err
	}
	for _, line := range strings.Split(string(body), "\n") {
		i := strings.Index(line, " refs/heads/main")
		if i >= 40 {
			sha := line[i-40 : i]
			if isHex(sha) {
				return sha, nil
			}
		}
	}
	return "", errors.New("main branch not found")
}

func isHex(s string) bool {
	for _, c := range s {
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return false
		}
	}
	return len(s) > 0
}

const port = 47321 // fixed, so a second launch just reopens the window

//go:embed web
var webFS embed.FS

type Config struct {
	AddOnsPath string `json:"addonsPath"`
	ShowTest   bool   `json:"showTest"`
}

type ManifestAddon struct {
	Folder  string `json:"folder"`
	Title   string `json:"title"`
	Version string `json:"version"`
	Notes   string `json:"notes"`
	URL     string `json:"url"`
	Size    int64  `json:"size"`
	SHA256  string `json:"sha256"`
}

type Manifest struct {
	Schema     int             `json:"schema"`
	Addons     []ManifestAddon `json:"addons"`
	TestAddons []ManifestAddon `json:"testAddons"`
	Launcher   struct {
		Version string `json:"version"`
		URL     string `json:"url"`    // zip, for downloading by hand
		Exe     string `json:"exe"`    // the .exe itself (raw URL)
		ExeAPI  string `json:"exeApi"` // the .exe through GitHub's API (always current)
		SHA256  string `json:"sha256"` // of the .exe
	} `json:"launcher"`
}

type AddonState struct {
	Folder    string `json:"folder"`
	Title     string `json:"title"`
	Notes     string `json:"notes"`
	Installed string `json:"installed"` // "" when not installed
	Latest    string `json:"latest"`
	Status    string `json:"status"` // missing | update | current | newer
	Test      bool   `json:"test"`
}

type State struct {
	LauncherVersion string       `json:"launcherVersion"`
	AddOnsPath      string       `json:"addonsPath"`
	PathOK          bool         `json:"pathOk"`
	ShowTest        bool         `json:"showTest"`
	TestCount       int          `json:"testCount"`
	ManifestError   string       `json:"manifestError,omitempty"`
	CheckedAt       string       `json:"checkedAt,omitempty"`
	Addons          []AddonState `json:"addons"`
	LauncherUpdate  string       `json:"launcherUpdate,omitempty"`
	LauncherURL     string       `json:"launcherUrl,omitempty"`
	CanSelfUpdate   bool         `json:"canSelfUpdate,omitempty"`
	Stale           bool         `json:"stale,omitempty"`
}

type App struct {
	quit      chan func() error // receives the finish step of a self-update
	stale     bool              // the last list came from the cached backup address
	commit    string            // commit the last list was read at ("" if not known)
	mu        sync.Mutex
	cfg       Config
	cfgPath   string
	manifest  *Manifest
	mErr      error
	checkedAt time.Time
	lastPing  time.Time
	busy      bool
}

func dataDir() string {
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		base, _ = os.UserConfigDir()
	}
	if base == "" {
		base = os.TempDir()
	}
	d := filepath.Join(base, "TopRamenLauncher")
	os.MkdirAll(d, 0o755)
	return d
}

func (a *App) loadConfig() {
	a.cfgPath = filepath.Join(dataDir(), "config.json")
	if b, err := os.ReadFile(a.cfgPath); err == nil {
		json.Unmarshal(b, &a.cfg)
	}
	if a.cfg.AddOnsPath == "" || !isAddOnsDir(a.cfg.AddOnsPath) {
		if p := detectAddOns(); p != "" {
			a.cfg.AddOnsPath = p
			a.saveConfig()
		}
	}
}

func (a *App) saveConfig() {
	b, _ := json.MarshalIndent(a.cfg, "", "  ")
	os.WriteFile(a.cfgPath, b, 0o644)
}

// isAddOnsDir accepts an existing folder named AddOns.
func isAddOnsDir(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir() && strings.EqualFold(filepath.Base(p), "AddOns")
}

// normalizeAddOns turns a WoW folder, a _forever_ folder or an Interface
// folder into the AddOns folder inside it.
func normalizeAddOns(p string) string {
	p = strings.Trim(strings.TrimSpace(p), `"`)
	if p == "" {
		return ""
	}
	cands := []string{
		p,
		filepath.Join(p, "AddOns"),
		filepath.Join(p, "Interface", "AddOns"),
		filepath.Join(p, "_forever_", "Interface", "AddOns"),
	}
	for _, c := range cands {
		if isAddOnsDir(c) {
			return filepath.Clean(c)
		}
	}
	// _forever_ exists but Interface\AddOns doesn't yet: create it
	for _, base := range []string{p, filepath.Join(p, "_forever_")} {
		if strings.EqualFold(filepath.Base(base), "_forever_") {
			if st, err := os.Stat(base); err == nil && st.IsDir() {
				c := filepath.Join(base, "Interface", "AddOns")
				if os.MkdirAll(c, 0o755) == nil {
					return c
				}
			}
		}
	}
	return ""
}

func detectAddOns() string {
	if runtime.GOOS != "windows" {
		return ""
	}
	var roots []string
	for _, env := range []string{"ProgramFiles(x86)", "ProgramFiles", "ProgramW6432"} {
		if v := os.Getenv(env); v != "" {
			roots = append(roots, v)
		}
	}
	for _, d := range "CDEFGH" {
		drive := string(d) + `:\`
		roots = append(roots, drive, drive+`Games`, drive+`Program Files (x86)`, drive+`Program Files`, drive+`Battle.net`)
	}
	for _, r := range roots {
		if p := normalizeAddOns(filepath.Join(r, "World of Warcraft", "_forever_")); p != "" {
			return p
		}
	}
	return ""
}

func getManifest(url string, api bool) (*Manifest, error) {
	client := &http.Client{Timeout: 20 * time.Second}
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Cache-Control", "no-cache")
	req.Header.Set("User-Agent", "TopRamenLauncher/"+Version)
	if api {
		req.Header.Set("Accept", "application/vnd.github.raw")
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("the update list answered %s", resp.Status)
	}
	var m Manifest
	if err := json.NewDecoder(resp.Body).Decode(&m); err != nil {
		return nil, err
	}
	return &m, nil
}

func (a *App) fetchManifest() {
	var m *Manifest
	var err error
	stale, source, commit := false, "", ""
	if RepoGit != "" {
		if commit, err = latestCommit(); err == nil {
			if m, err = getManifest(RawBase+commit+"/manifest.json", false); err == nil {
				source = "commit " + commit[:7]
			}
		}
		if err != nil {
			log.Println("manifest via commit:", err, "- trying API")
			commit = ""
		}
	}
	if m == nil && ManifestAPI != "" {
		// a unique address each time, so no cache along the way can answer with an old copy
		if m, err = getManifest(fmt.Sprintf("%s&t=%d", ManifestAPI, time.Now().UnixNano()), true); err != nil {
			log.Println("manifest via API:", err, "- trying raw")
		} else {
			source = "API"
		}
	}
	if m == nil {
		m, err = getManifest(fmt.Sprintf("%s?t=%d", ManifestURL, time.Now().UnixNano()), false)
		stale = err == nil && ManifestAPI != ""
		source = "raw (may be a few minutes old)"
	}
	if err == nil {
		log.Printf("update list: %d addons, %d test, launcher %s, from %s", len(m.Addons), len(m.TestAddons), m.Launcher.Version, source)
	}
	a.mu.Lock()
	a.stale = stale
	if err == nil {
		a.commit = commit
	}
	defer a.mu.Unlock()
	a.checkedAt = time.Now()
	if err != nil {
		a.mErr = err
		log.Println("manifest:", err)
		return
	}
	a.manifest, a.mErr = m, nil
}

func (a *App) state() State {
	a.mu.Lock()
	defer a.mu.Unlock()
	s := State{LauncherVersion: Version, AddOnsPath: a.cfg.AddOnsPath, PathOK: isAddOnsDir(a.cfg.AddOnsPath), ShowTest: a.cfg.ShowTest}
	if !a.checkedAt.IsZero() {
		s.CheckedAt = a.checkedAt.Format("3:04 PM")
	}
	if a.mErr != nil {
		s.ManifestError = friendlyNetErr(a.mErr)
	}
	s.Stale = a.stale
	if a.manifest == nil {
		s.Addons = []AddonState{}
		return s
	}
	if l := a.manifest.Launcher; l.Version != "" && Version != "dev" && compareVersions(l.Version, Version) > 0 {
		s.LauncherUpdate, s.LauncherURL = l.Version, l.URL
		s.CanSelfUpdate = l.SHA256 != "" && (l.Exe != "" || l.ExeAPI != "")
	}
	s.TestCount = len(a.manifest.TestAddons)
	list := a.manifest.Addons
	if a.cfg.ShowTest {
		list = append(append([]ManifestAddon{}, list...), a.manifest.TestAddons...)
	}
	for k, m := range list {
		st := AddonState{Folder: m.Folder, Title: m.Title, Notes: m.Notes, Latest: m.Version, Test: k >= len(a.manifest.Addons)}
		if s.PathOK {
			st.Installed = installedVersion(filepath.Join(a.cfg.AddOnsPath, m.Folder))
		}
		switch {
		case st.Installed == "":
			st.Status = "missing"
		case compareVersions(m.Version, st.Installed) > 0:
			st.Status = "update"
		case compareVersions(m.Version, st.Installed) < 0:
			st.Status = "newer"
		default:
			st.Status = "current"
		}
		s.Addons = append(s.Addons, st)
	}
	sort.SliceStable(s.Addons, func(i, j int) bool {
		if s.Addons[i].Test != s.Addons[j].Test {
			return !s.Addons[i].Test // test addons go last
		}
		return s.Addons[i].Title < s.Addons[j].Title
	})
	return s
}

func friendlyNetErr(err error) string {
	var ne net.Error
	if errors.As(err, &ne) {
		return "Couldn't reach GitHub to check for updates. Check your internet connection and click Check again."
	}
	return "Couldn't read the update list: " + err.Error()
}

// ---------- web server ----------

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	json.NewEncoder(w).Encode(v)
}

func (a *App) routes() http.Handler {
	mux := http.NewServeMux()
	sub, _ := fs.Sub(webFS, "web")
	mux.Handle("/", http.FileServer(http.FS(sub)))

	mux.HandleFunc("/api/ping", func(w http.ResponseWriter, r *http.Request) {
		a.mu.Lock()
		a.lastPing = time.Now()
		a.mu.Unlock()
		writeJSON(w, map[string]string{"app": "TopRamenLauncher", "version": Version})
	})
	mux.HandleFunc("/api/state", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, a.state())
	})
	mux.HandleFunc("/api/check", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			http.Error(w, "POST only", 405)
			return
		}
		a.fetchManifest()
		writeJSON(w, a.state())
	})
	mux.HandleFunc("/api/path", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			http.Error(w, "POST only", 405)
			return
		}
		var body struct {
			Path   string `json:"path"`
			Browse bool   `json:"browse"`
		}
		json.NewDecoder(r.Body).Decode(&body)
		p := body.Path
		if body.Browse {
			p = browseFolder()
			if p == "" {
				writeJSON(w, map[string]any{"ok": false, "cancelled": true})
				return
			}
		}
		n := normalizeAddOns(p)
		if n == "" {
			writeJSON(w, map[string]any{"ok": false, "error": "That isn't a WoW Forever AddOns folder. Pick the folder ending in _forever_\\Interface\\AddOns."})
			return
		}
		a.mu.Lock()
		a.cfg.AddOnsPath = n
		a.saveConfig()
		a.mu.Unlock()
		writeJSON(w, map[string]any{"ok": true, "state": a.state()})
	})
	mux.HandleFunc("/api/settings", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			http.Error(w, "POST only", 405)
			return
		}
		var body struct {
			ShowTest bool `json:"showTest"`
		}
		json.NewDecoder(r.Body).Decode(&body)
		a.mu.Lock()
		a.cfg.ShowTest = body.ShowTest
		a.saveConfig()
		a.mu.Unlock()
		writeJSON(w, a.state())
	})
	mux.HandleFunc("/api/install", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			http.Error(w, "POST only", 405)
			return
		}
		var body struct {
			Folders []string `json:"folders"`
		}
		json.NewDecoder(r.Body).Decode(&body)
		writeJSON(w, a.install(body.Folders))
	})
	mux.HandleFunc("/api/selfUpdate", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			http.Error(w, "POST only", 405)
			return
		}
		a.mu.Lock()
		if a.busy {
			a.mu.Unlock()
			writeJSON(w, map[string]any{"error": "Already busy, one moment."})
			return
		}
		a.busy = true
		a.mu.Unlock()
		finish, err := a.selfUpdate()
		if err != nil {
			a.mu.Lock()
			a.busy = false
			a.mu.Unlock()
			log.Println("self-update:", err)
			writeJSON(w, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, map[string]any{"ok": true})
		go func() { a.quit <- finish }()
	})
	mux.HandleFunc("/api/openFolder", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "POST" && runtime.GOOS == "windows" && isAddOnsDir(a.cfg.AddOnsPath) {
			exec.Command("explorer.exe", a.cfg.AddOnsPath).Start()
		}
		writeJSON(w, map[string]bool{"ok": true})
	})
	mux.HandleFunc("/api/openURL", func(w http.ResponseWriter, r *http.Request) {
		var body struct{ URL string }
		json.NewDecoder(r.Body).Decode(&body)
		if r.Method == "POST" && strings.HasPrefix(body.URL, "https://") {
			openDefaultBrowser(body.URL)
		}
		writeJSON(w, map[string]bool{"ok": true})
	})
	// only answer requests addressed to our own loopback origin
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host := r.Host
		if host != fmt.Sprintf("127.0.0.1:%d", port) && host != fmt.Sprintf("localhost:%d", port) {
			http.Error(w, "forbidden", 403)
			return
		}
		if r.Method == "POST" {
			if o := r.Header.Get("Origin"); o != "" && o != "http://"+host {
				http.Error(w, "forbidden", 403)
				return
			}
		}
		mux.ServeHTTP(w, r)
	})
}

type InstallResult struct {
	Folder  string `json:"folder"`
	OK      bool   `json:"ok"`
	Version string `json:"version,omitempty"`
	Error   string `json:"error,omitempty"`
}

func (a *App) install(folders []string) map[string]any {
	a.mu.Lock()
	if a.busy {
		a.mu.Unlock()
		return map[string]any{"error": "Already installing, one moment."}
	}
	a.busy = true
	m, dest := a.manifest, a.cfg.AddOnsPath
	a.mu.Unlock()
	defer func() { a.mu.Lock(); a.busy = false; a.mu.Unlock() }()

	if m == nil {
		return map[string]any{"error": "The update list hasn't loaded yet. Click Check for updates."}
	}
	if !isAddOnsDir(dest) {
		return map[string]any{"error": "Choose your AddOns folder first."}
	}
	var results []InstallResult
	for _, f := range folders {
		var entry *ManifestAddon
		for _, list := range [][]ManifestAddon{m.Addons, m.TestAddons} {
			for i := range list {
				if list[i].Folder == f {
					entry = &list[i]
				}
			}
		}
		if entry == nil {
			results = append(results, InstallResult{Folder: f, Error: "not in the update list"})
			continue
		}
		err := installAddon(*entry, dest)
		if err != nil {
			log.Printf("install %s: %v", f, err)
			results = append(results, InstallResult{Folder: f, Error: err.Error()})
		} else {
			log.Printf("installed %s %s", f, entry.Version)
			results = append(results, InstallResult{Folder: f, OK: true, Version: entry.Version})
		}
	}
	return map[string]any{"results": results, "state": a.state()}
}

// ---------- window ----------

func openWindow(url string) {
	if runtime.GOOS != "windows" {
		fmt.Println("Open", url)
		return
	}
	profile := filepath.Join(dataDir(), "window")
	var cands []string
	for _, env := range []string{"ProgramFiles(x86)", "ProgramFiles", "LOCALAPPDATA"} {
		if v := os.Getenv(env); v != "" {
			cands = append(cands,
				filepath.Join(v, `Microsoft\Edge\Application\msedge.exe`),
				filepath.Join(v, `Google\Chrome\Application\chrome.exe`))
		}
	}
	for _, c := range cands {
		if _, err := os.Stat(c); err == nil {
			cmd := exec.Command(c, "--app="+url, "--window-size=860,940",
				"--user-data-dir="+profile, "--no-first-run", "--no-default-browser-check")
			if cmd.Start() == nil {
				return
			}
		}
	}
	openDefaultBrowser(url)
}

func openDefaultBrowser(url string) {
	switch runtime.GOOS {
	case "windows":
		exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
	case "darwin":
		exec.Command("open", url).Start()
	default:
		exec.Command("xdg-open", url).Start()
	}
}

// browseFolder shows the Windows folder picker through PowerShell.
func browseFolder() string {
	if runtime.GOOS != "windows" {
		return ""
	}
	script := `Add-Type -AssemblyName System.Windows.Forms;` +
		`$f = New-Object System.Windows.Forms.FolderBrowserDialog;` +
		`$f.Description = 'Pick your WoW Forever AddOns folder (World of Warcraft\_forever_\Interface\AddOns)';` +
		`$f.ShowNewFolderButton = $false;` +
		`$t = New-Object System.Windows.Forms.Form -Property @{TopMost=$true};` +
		`if ($f.ShowDialog($t) -eq 'OK') { [Console]::Out.Write($f.SelectedPath) }`
	cmd := exec.Command("powershell.exe", "-NoProfile", "-STA", "-NonInteractive", "-Command", script)
	hideWindow(cmd)
	out, err := cmd.Output()
	if err != nil {
		log.Println("browse:", err)
		return ""
	}
	return strings.TrimSpace(string(out))
}

func main() {
	logf, err := os.OpenFile(filepath.Join(dataDir(), "launcher.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err == nil {
		log.SetOutput(logf)
	}
	log.Printf("Top Ramen Launcher %s starting", Version)
	if v := os.Getenv("TOPRAMEN_MANIFEST_URL"); v != "" { // for testing
		ManifestURL, ManifestAPI, RepoGit = v, "", ""
	}
	url := fmt.Sprintf("http://127.0.0.1:%d/", port)

	justUpdated := len(os.Args) > 1 && os.Args[1] == updatedFlag
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	for i := 0; err != nil && justUpdated && i < 20; i++ {
		time.Sleep(250 * time.Millisecond) // the old copy is still letting go of the port
		ln, err = net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	}
	if justUpdated {
		go cleanupOld()
	}
	if err != nil {
		// already running: just bring up another window
		log.Println("already running, opening window:", err)
		openWindow(url)
		return
	}
	app := &App{lastPing: time.Now(), quit: make(chan func() error, 1)}
	app.loadConfig()
	go app.fetchManifest()

	srv := &http.Server{Handler: app.routes()}
	go srv.Serve(ln)
	if os.Getenv("TOPRAMEN_NO_WINDOW") == "" {
		openWindow(url)
		go brandTaskbar() // our own taskbar button and icon instead of Edge's
	}

	// exit once the window has been closed for a while (the page pings every 2s),
	// or hand over to a freshly downloaded launcher
	start := time.Now()
	for {
		select {
		case finish := <-app.quit:
			time.Sleep(700 * time.Millisecond) // let the page get its answer
			srv.Close()
			if err := finish(); err != nil {
				log.Println("self-update swap failed:", err)
				// couldn't swap; carry on as before
				ln, lerr := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
				if lerr != nil {
					return
				}
				srv = &http.Server{Handler: app.routes()}
				go srv.Serve(ln)
				app.mu.Lock()
				app.busy = false
				app.mu.Unlock()
				continue
			}
			log.Println("updated launcher started, exiting")
			return
		case <-time.After(2 * time.Second):
		}
		app.mu.Lock()
		idle := time.Since(app.lastPing)
		busy := app.busy
		app.mu.Unlock()
		limit := 12 * time.Second
		if time.Since(start) < 60*time.Second {
			limit = 60 * time.Second // give the window time to start
		}
		if os.Getenv("TOPRAMEN_NO_WINDOW") != "" {
			continue
		}
		if !busy && idle > limit {
			log.Println("window closed, exiting")
			return
		}
	}
}
