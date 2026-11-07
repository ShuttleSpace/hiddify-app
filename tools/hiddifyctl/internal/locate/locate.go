package locate

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
)

// AppPaths describes where the Hiddify desktop app stores its data.
type AppPaths struct {
	WorkingDir string // directory that contains the `configs/` folder
	ConfigsDir string // directory holding <profileId>.json
	DBPath     string // drift sqlite database (db.sqlite)
}

func home() string {
	h, _ := os.UserHomeDir()
	return h
}

// candidateDirs returns, per platform, candidate roots for the working
// directory (which holds configs/) and for the database file.
func candidateDirs() (working, db []string) {
	h := home()
	switch runtime.GOOS {
	case "darwin":
		working = []string{
			filepath.Join(h, "Library/Application Support/app.hiddify.com"),
			filepath.Join(h, "Library/Application Support/com.hiddify.app"),
		}
		db = []string{
			filepath.Join(h, "Library"),
			filepath.Join(h, "Library/Application Support/app.hiddify.com"),
			filepath.Join(h, "Library/Application Support/com.hiddify.app"),
		}
	case "windows":
		appdata := os.Getenv("APPDATA")
		localappdata := os.Getenv("LOCALAPPDATA")
		working = []string{
			filepath.Join(appdata, "app.hiddify.com"),
			filepath.Join(appdata, "com.hiddify.app"),
			filepath.Join(localappdata, "app.hiddify.com"),
		}
		db = append([]string{appdata, localappdata}, working...)
	default: // linux and anything else
		data := os.Getenv("XDG_DATA_HOME")
		if data == "" {
			data = filepath.Join(h, ".local/share")
		}
		cfg := os.Getenv("XDG_CONFIG_HOME")
		if cfg == "" {
			cfg = filepath.Join(h, ".config")
		}
		flatpak := filepath.Join(h, ".var/app/app.hiddify.com")
		working = []string{
			filepath.Join(data, "app.hiddify.com"),
			filepath.Join(data, "com.hiddify.app"),
			filepath.Join(cfg, "app.hiddify.com"),
			filepath.Join(flatpak, "data/app.hiddify.com"),
			filepath.Join(flatpak, "config/app.hiddify.com"),
			filepath.Join(h, ".local/share/app.hiddify.com"),
		}
		db = append([]string{data, cfg, flatpak}, working...)
	}
	return working, db
}

func firstWith(cond func(dir string) bool, dirs []string) string {
	for _, d := range dirs {
		if d != "" && cond(d) {
			return d
		}
	}
	return ""
}

func hasConfigs(dir string) bool {
	entries, err := os.ReadDir(filepath.Join(dir, "configs"))
	if err != nil {
		return false
	}
	for _, e := range entries {
		if !e.IsDir() {
			return true
		}
	}
	return false
}

// Detect resolves the app's data directories. Explicit overrides take priority;
// otherwise well-known per-platform locations are probed.
func Detect(overrideAppDir, overrideDB string) (*AppPaths, error) {
	working, db := candidateDirs()

	var wd string
	if overrideAppDir != "" {
		wd = overrideAppDir
	} else {
		wd = firstWith(hasConfigs, working)
	}
	if wd == "" {
		return nil, fmt.Errorf("could not locate Hiddify app directory; pass --app-dir")
	}

	dbPath := overrideDB
	if dbPath == "" {
		if dir := firstWith(func(d string) bool {
			_, err := os.Stat(filepath.Join(d, "db.sqlite"))
			return err == nil
		}, db); dir != "" {
			dbPath = filepath.Join(dir, "db.sqlite")
		}
	}

	return &AppPaths{
		WorkingDir: wd,
		ConfigsDir: filepath.Join(wd, "configs"),
		DBPath:     dbPath,
	}, nil
}
