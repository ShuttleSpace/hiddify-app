package ctrl

import (
	"context"
	"fmt"
	"path/filepath"
	"time"

	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/client"
	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/grpc/hcore"
	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/headless"
	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/locate"
)

// Options holds the resolved control parameters shared by the CLI and the MCP
// server.
type Options struct {
	Addr        string
	AppDir      string
	DBPath      string
	Config      string
	CoreBin     string
	Headless    bool
	Timeout     time.Duration
	Tun         bool
	SystemProxy bool
}

// resolveConfig returns an explicit --config, or falls back to the app's active
// profile config path (read from the drift database).
func resolveConfig(ctx context.Context, o Options) (string, error) {
	if o.Config != "" {
		return o.Config, nil
	}
	paths, err := locate.Detect(o.AppDir, o.DBPath)
	if err != nil {
		return "", err
	}
	id, _, err := locate.ActiveProfile(paths.DBPath)
	if err != nil {
		return "", fmt.Errorf("no --config and %w; pass --config or ensure the app DB is reachable", err)
	}
	return filepath.Join(paths.ConfigsDir, id+".json"), nil
}

// ensureCore connects to the core; if unreachable and Headless is enabled, it
// starts a standalone core with a resolved config and waits until ready.
func ensureCore(ctx context.Context, o Options) (*client.Client, bool, error) {
	c, err := client.Dial(o.Addr, o.Timeout)
	if err == nil {
		return c, false, nil
	}
	if !o.Headless {
		return nil, false, fmt.Errorf("cannot reach %s (is Hiddify running?); pass --headless --config or run `hiddifyctl run -c <config>`", o.Addr)
	}
	cfg, err := resolveConfig(ctx, o)
	if err != nil {
		return nil, false, err
	}
	bin, err := headless.FindCoreBin(o.CoreBin)
	if err != nil {
		return nil, false, err
	}
	if _, err := headless.Start(ctx, cfg, bin, o.Tun, o.SystemProxy, true); err != nil {
		return nil, false, err
	}
	if err := headless.WaitReady(ctx, o.Addr, o.Timeout*3); err != nil {
		return nil, false, err
	}
	c, err = client.Dial(o.Addr, o.Timeout)
	if err != nil {
		return nil, false, err
	}
	return c, true, nil
}

// Connect brings the core up using the active profile (or an explicit config).
// It is idempotent: an already-connected core is left as is.
func Connect(ctx context.Context, o Options) error {
	c, startedHeadless, err := ensureCore(ctx, o)
	if err != nil {
		return err
	}
	defer c.Close()

	state, err := c.CoreState(ctx)
	if err != nil {
		return err
	}
	if state == hcore.CoreStates_STARTED || state == hcore.CoreStates_STARTING || state == hcore.CoreStates_HOT_RELOADING {
		return nil
	}

	cfg, err := resolveConfig(ctx, o)
	if err != nil {
		if startedHeadless {
			// The just-started standalone core is already connected with this config.
			return nil
		}
		return err
	}
	sctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	return c.Start(sctx, cfg, "hiddifyctl", false)
}

// Disconnect stops the core.
func Disconnect(ctx context.Context, o Options) error {
	c, err := client.Dial(o.Addr, o.Timeout)
	if err != nil {
		return fmt.Errorf("cannot reach core at %s (nothing to disconnect)", o.Addr)
	}
	defer c.Close()
	return c.Stop(ctx)
}

// Status reports the current core state and traffic.
func Status(ctx context.Context, o Options) (*client.Status, error) {
	c, err := client.Dial(o.Addr, o.Timeout)
	if err != nil {
		return nil, fmt.Errorf("cannot reach core at %s (is Hiddify running?)", o.Addr)
	}
	defer c.Close()
	return c.Status(ctx)
}
