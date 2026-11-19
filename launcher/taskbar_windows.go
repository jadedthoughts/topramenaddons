//go:build windows

package main

// Give the launcher's window its own taskbar identity.
//
// The window is drawn by Edge in "app" mode, so Windows groups it with Edge
// and shows Edge's icon. Setting the window's AppUserModelID (plus a relaunch
// command and icon) makes the taskbar treat it as a separate app and show the
// Top Ramen icon from this .exe. We also hand the window our icon directly.

import (
	"log"
	"os"
	"runtime"
	"syscall"
	"time"
	"unsafe"
)

const (
	windowTitle = "Top Ramen Forever Launcher"
	appID       = "TopRamen.ForeverLauncher"
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	shell32  = syscall.NewLazyDLL("shell32.dll")
	ole32    = syscall.NewLazyDLL("ole32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")

	procEnumWindows        = user32.NewProc("EnumWindows")
	procGetWindowTextW     = user32.NewProc("GetWindowTextW")
	procGetClassNameW      = user32.NewProc("GetClassNameW")
	procIsWindowVisible    = user32.NewProc("IsWindowVisible")
	procSendMessageW       = user32.NewProc("SendMessageW")
	procLoadImageW         = user32.NewProc("LoadImageW")
	procGetSystemMetrics   = user32.NewProc("GetSystemMetrics")
	procSHGetPropertyStore = shell32.NewProc("SHGetPropertyStoreForWindow")
	procCoInitializeEx     = ole32.NewProc("CoInitializeEx")
	procGetModuleHandleW   = kernel32.NewProc("GetModuleHandleW")
)

type guid struct {
	Data1 uint32
	Data2 uint16
	Data3 uint16
	Data4 [8]byte
}

type propertyKey struct {
	fmtid guid
	pid   uint32
}

// PROPVARIANT holding a VT_LPWSTR (24 bytes on 64-bit Windows).
type propVariant struct {
	vt       uint16
	r1       uint16
	r2       uint16
	r3       uint16
	val      uintptr
	reserved uintptr
}

var (
	iidIPropertyStore = guid{0x886D8EEB, 0x8CF2, 0x4446, [8]byte{0x8D, 0x02, 0xCD, 0xBA, 0x1D, 0xBD, 0xCF, 0x99}}
	appUserModelFmt   = guid{0x9F4C2855, 0x9F79, 0x4B39, [8]byte{0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3}}
	pkeyID            = propertyKey{appUserModelFmt, 5}
	pkeyRelaunchCmd   = propertyKey{appUserModelFmt, 2}
	pkeyRelaunchIcon  = propertyKey{appUserModelFmt, 3}
	pkeyRelaunchName  = propertyKey{appUserModelFmt, 4}
)

const vtLPWSTR = 31

// findWindows returns the visible Chromium/Edge windows titled like ours.
func findWindows() []uintptr {
	var found []uintptr
	cb := syscall.NewCallback(func(hwnd, _ uintptr) uintptr {
		if v, _, _ := procIsWindowVisible.Call(hwnd); v == 0 {
			return 1
		}
		buf := make([]uint16, 256)
		procGetClassNameW.Call(hwnd, uintptr(unsafe.Pointer(&buf[0])), 256)
		if syscall.UTF16ToString(buf) != "Chrome_WidgetWin_1" {
			return 1
		}
		procGetWindowTextW.Call(hwnd, uintptr(unsafe.Pointer(&buf[0])), 256)
		if syscall.UTF16ToString(buf) == windowTitle {
			found = append(found, hwnd)
		}
		return 1
	})
	procEnumWindows.Call(cb, 0)
	return found
}

func setString(store unsafe.Pointer, key *propertyKey, s string) {
	p, err := syscall.UTF16PtrFromString(s)
	if err != nil {
		return
	}
	pv := propVariant{vt: vtLPWSTR, val: uintptr(unsafe.Pointer(p))}
	vtbl := *(**[8]uintptr)(store)
	syscall.SyscallN(vtbl[6], uintptr(store), uintptr(unsafe.Pointer(key)), uintptr(unsafe.Pointer(&pv))) // SetValue
	runtime.KeepAlive(p)
}

func brandWindow(hwnd uintptr, exe string) {
	var store unsafe.Pointer
	hr, _, _ := procSHGetPropertyStore.Call(hwnd, uintptr(unsafe.Pointer(&iidIPropertyStore)), uintptr(unsafe.Pointer(&store)))
	if hr == 0 && store != nil {
		setString(store, &pkeyID, appID)
		setString(store, &pkeyRelaunchCmd, `"`+exe+`"`)
		setString(store, &pkeyRelaunchIcon, exe+",0")
		setString(store, &pkeyRelaunchName, windowTitle)
		vtbl := *(**[8]uintptr)(store)
		syscall.SyscallN(vtbl[7], uintptr(store)) // Commit
		syscall.SyscallN(vtbl[2], uintptr(store)) // Release
	} else {
		log.Printf("taskbar: no property store for window (hr=%#x)", hr)
	}
	// our icon for the title bar and Alt+Tab
	mod, _, _ := procGetModuleHandleW.Call(0)
	for _, which := range []struct{ kind, cx, cy uintptr }{{1, 11, 12}, {0, 49, 50}} { // ICON_BIG (SM_CXICON), ICON_SMALL (SM_CXSMICON)
		cx, _, _ := procGetSystemMetrics.Call(which.cx)
		cy, _, _ := procGetSystemMetrics.Call(which.cy)
		icon, _, _ := procLoadImageW.Call(mod, 1, 1, cx, cy, 0) // icon group 1, IMAGE_ICON
		if icon != 0 {
			procSendMessageW.Call(hwnd, 0x0080, which.kind, icon) // WM_SETICON
		}
	}
}

// brandTaskbar watches for the launcher's window and brands each new one.
func brandTaskbar() {
	runtime.LockOSThread()
	procCoInitializeEx.Call(0, 2) // COINIT_APARTMENTTHREADED
	exe, err := os.Executable()
	if err != nil {
		return
	}
	done := map[uintptr]bool{}
	for start := time.Now(); ; {
		for _, h := range findWindows() {
			if !done[h] {
				brandWindow(h, exe)
				done[h] = true
				log.Printf("taskbar: gave window %#x the Top Ramen icon", h)
			}
		}
		if time.Since(start) < 20*time.Second {
			time.Sleep(250 * time.Millisecond)
		} else {
			time.Sleep(2 * time.Second)
		}
	}
}
