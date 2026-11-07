package headless

import (
	"context"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// recordPath stores the PID and config of the standalone core started with
// `connect --headless`, so a later `service-mode --headless` can restart it.
func recordPath() string {
	dir, err := os.UserCacheDir()
	if err != nil || dir == "" {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "hiddifyctl", "standalone.pid")
}

func writeRecord(pid int, config string) error {
	p := recordPath()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	return os.WriteFile(p, []byte(strconv.Itoa(pid)+"\n"+config), 0o644)
}

func readRecord() (pid int, config string, ok bool) {
	b, err := os.ReadFile(recordPath())
	if err != nil {
		return 0, "", false
	}
	parts := strings.SplitN(strings.TrimSpace(string(b)), "\n", 2)
	n, err := strconv.Atoi(parts[0])
	if err != nil || n <= 0 {
		return 0, "", false
	}
	cfg := ""
	if len(parts) == 2 {
		cfg = parts[1]
	}
	return n, cfg, true
}

// RestartMode switches the standalone core's service mode by stopping the
// process started earlier with `connect --headless` and relaunching it with
// the matching --tun/--system-proxy startup flags. The standalone core builds
// its config from those flags at startup, so this has no side effect on the
// other Hiddify options (unlike changeHiddifySettings on a running desktop app).
func RestartMode(ctx context.Context, config, bin, addr string, tun, systemProxy bool, timeout time.Duration) error {
	pid, savedConfig, ok := readRecord()
	if !ok && config == "" {
		return fmt.Errorf("no standalone core started by hiddifyctl found; start one with `hiddifyctl connect --headless -c <config>`, or pass --config to launch a fresh one in the new mode")
	}
	if config == "" {
		config = savedConfig
	}

	// Allow the old core time to release the port when we just killed it; with
	// no previous core the port must already be free, otherwise a fresh launch
	// would fail and WaitReady could dial the wrong (old) process.
	wait := 3 * time.Second
	if ok {
		// os.FindProcess + Kill works on every platform; HiddifyCli run is a
		// single process (libbox runs in-process), so killing the leader is enough.
		if p, err := os.FindProcess(pid); err == nil {
			_ = p.Kill() // best effort: the process may already be gone
		}
		_ = os.Remove(recordPath())
	} else {
		wait = 0
	}
	if err := waitPortFree(ctx, addr, wait); err != nil {
		return err
	}

	// Detach the new core from this command's context so it outlives the CLI.
	if _, err := Start(context.Background(), config, bin, tun, systemProxy, true); err != nil {
		return err
	}
	return WaitReady(ctx, addr, timeout*3)
}

// waitPortFree blocks until the gRPC listen address is bindable again (the old
// core released it). net.Listen on the same address is a portable "is it free"
// probe. With max=0 it checks once. It returns an error instead of proceeding,
// so a busy port can never make WaitReady succeed against the wrong core.
func waitPortFree(ctx context.Context, addr string, max time.Duration) error {
	deadline := time.Now().Add(max)
	for {
		ln, err := net.Listen("tcp", addr)
		if err == nil {
			_ = ln.Close()
			return nil
		}
		if !time.Now().Before(deadline) {
			return fmt.Errorf("port %s busy (is Hiddify already running on it?): %w", addr, err)
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(100 * time.Millisecond):
		}
	}
}
