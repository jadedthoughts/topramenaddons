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

// ManifestURL is where the list of latest versions lives.
var ManifestURL = "https://raw.githubusercontent.com/jadedthoughts/topramenaddons/main/manifest.json"

const port = 47321 // fixed, so a second launch just reopens the window

//go:embed web
var webFS embed.FS

type Config struct {
	AddOnsPath string `json:"addonsPath"`
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
	Schema   int             `json:"schema"`
	Addons   []ManifestAddon `json:"addons"`
	Launcher struct {
		Version string `json:"version"`
		URL     string `json:"url"`
	} `json:"launcher"`
}

type AddonState struct {
	Folder    string `json:"folder"`
	Title     string `json:"title"`
	Notes     string `json:"notes"`
	Installed string `json:"installed"` // "" when not installed
	Latest    string `json:"latest"`
	Status    string `json:"status"` // missing | update | current | newer
}

type State struct {
	LauncherVersion string       `json:"launcherVersion"`
	AddOnsPath      string       `json:"addonsPath"`
	PathOK          bool         `json:"pathOk"`
	ManifestError   string       `json:"manifestError,omitempty"`
	CheckedAt       string       `json:"checkedAt,omitempty"`
	Addons          []AddonState `json:"addons"`
	LauncherUpdate  string       `json:"launcherUpdate,omitempty"`
	LauncherURL     string       `json:"launcherUrl,omitempty"`
}

type App struct {
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

func (a *App) fetchManifest() {
	client := &http.Client{Timeout: 20 * time.Second}
	url := fmt.Sprintf("%s?t=%d", ManifestURL, time.Now().Unix())
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Cache-Control", "no-cache")
	req.Header.Set("User-Agent", "TopRamenLauncher/"+Version)
	resp, err := client.Do(req)
	var m Manifest
	if err == nil {
		defer resp.Body.Close()
		if resp.StatusCode != 200 {
			err = fmt.Errorf("the update list answered %s", resp.Status)
		} else {
			err = json.NewDecoder(resp.Body).Decode(&m)
		}
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	a.checkedAt = time.Now()
	if err != nil {
		a.mErr = err
		log.Println("manifest:", err)
		return
	}
	a.manifest, a.mErr = &m, nil
}

func (a *App) state() State {
	a.mu.Lock()
	defer a.mu.Unlock()
	s := State{LauncherVersion: Version, AddOnsPath: a.cfg.AddOnsPath, PathOK: isAddOnsDir(a.cfg.AddOnsPath)}
	if !a.checkedAt.IsZero() {
		s.CheckedAt = a.checkedAt.Format("3:04 PM")
	}
	if a.mErr != nil {
		s.ManifestError = friendlyNetErr(a.mErr)
	}
	if a.manifest == nil {
		s.Addons = []AddonState{}
		return s
	}
	if l := a.manifest.Launcher; l.Version != "" && Version != "dev" && compareVersions(l.Version, Version) > 0 {
		s.LauncherUpdate, s.LauncherURL = l.Version, l.URL
	}
	for _, m := range a.manifest.Addons {
		st := AddonState{Folder: m.Folder, Title: m.Title, Notes: m.Notes, Latest: m.Version}
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
	sort.SliceStable(s.Addons, func(i, j int) bool { return s.Addons[i].Title < s.Addons[j].Title })
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
		for i := range m.Addons {
			if m.Addons[i].Folder == f {
				entry = &m.Addons[i]
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
			cmd := exec.Command(c, "--app="+url, "--window-size=840,860",
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
		ManifestURL = v
	}
	url := fmt.Sprintf("http://127.0.0.1:%d/", port)

	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		// already running: just bring up another window
		log.Println("already running, opening window:", err)
		openWindow(url)
		return
	}
	app := &App{lastPing: time.Now()}
	app.loadConfig()
	go app.fetchManifest()

	srv := &http.Server{Handler: app.routes()}
	go srv.Serve(ln)
	if os.Getenv("TOPRAMEN_NO_WINDOW") == "" {
		openWindow(url)
	}

	// exit once the window has been closed for a while (the page pings every 2s)
	start := time.Now()
	for {
		time.Sleep(2 * time.Second)
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
