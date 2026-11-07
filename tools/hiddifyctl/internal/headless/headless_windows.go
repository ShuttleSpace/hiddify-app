//go:build windows

package headless

import "os/exec"

// setDetachAttrs is a no-op on Windows: process-group detach is Unix-only, and
// detach there falls back to the default child lifetime behavior.
func setDetachAttrs(cmd *exec.Cmd) {}
