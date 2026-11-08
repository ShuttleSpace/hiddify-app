//go:build !windows

package headless

import (
	"os/exec"
	"syscall"
)

// setDetachAttrs places the child in its own process group so it survives the
// parent exiting (used by the connect fallback on Unix).
func setDetachAttrs(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
}
