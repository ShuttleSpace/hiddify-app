package headless

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"syscall"
	"time"

	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/client"
)

// FindCoreBin resolves the HiddifyCli binary used to launch a standalone core.
func FindCoreBin(explicit string) (string, error) {
	if explicit != "" {
		return explicit, nil
	}
	candidates := []string{
		"HiddifyCli",
		filepath.Join("..", "..", "hiddify-core", "bin", "HiddifyCli"),
	}
	for _, c := range candidates {
		if p, err := exec.LookPath(c); err == nil {
			return p, nil
		}
	}
	return "", fmt.Errorf("HiddifyCli binary not found (looked for 'HiddifyCli' and hiddify-core/bin/HiddifyCli); pass --core-bin")
}

// Start launches `HiddifyCli run -c <config>` in the background. When detach is
// true the child is placed in its own process group so it survives the parent
// exiting (used by the connect fallback).
func Start(ctx context.Context, config, bin string, tun, systemProxy, detach bool) (*exec.Cmd, error) {
	args := []string{"run", "-c", config}
	if tun {
		args = append(args, "--tun")
	}
	if systemProxy {
		args = append(args, "--system-proxy")
	}
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if detach && runtime.GOOS != "windows" {
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	}
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("start core: %w", err)
	}
	return cmd, nil
}

// WaitReady polls the gRPC address until a dial succeeds or the timeout elapses.
func WaitReady(ctx context.Context, addr string, timeout time.Duration) error {
	dl, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	ticker := time.NewTicker(300 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-dl.Done():
			return fmt.Errorf("core not ready at %s: %w", addr, dl.Err())
		case <-ticker.C:
			c, err := client.Dial(addr, 500*time.Millisecond)
			if err == nil {
				_ = c.Close()
				return nil
			}
		}
	}
}
