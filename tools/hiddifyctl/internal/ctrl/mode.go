package ctrl

import (
	"context"
	"fmt"
	"time"

	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/client"
	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/headless"
)

// SetServiceMode switches the core's service mode.
//
// With --headless the standalone core (started by `connect --headless`) is
// stopped and relaunched with the matching --tun/--system-proxy flags. The
// standalone core builds its config from those flags at startup, so this has no
// side effect on the other Hiddify options.
//
// Without --headless the running desktop app is driven over gRPC:
// changeHiddifySettings updates its HiddifyOptions, then Restart regenerates the
// config from the active profile. This mirrors the app's own
// changeOptions -> reconnect path, but resets the other Hiddify options to
// their core defaults (the app restores its full set on its next settings edit).
func SetServiceMode(ctx context.Context, o Options, mode client.ServiceMode) error {
	enableTun, setSystemProxy := mode.Options()

	if o.Headless {
		bin, err := headless.FindCoreBin(o.CoreBin)
		if err != nil {
			return err
		}
		return headless.RestartMode(ctx, o.Config, bin, o.Addr, enableTun, setSystemProxy, o.Timeout)
	}

	c, _, err := ensureCore(ctx, o)
	if err != nil {
		return err
	}
	defer c.Close()

	cfg, err := resolveConfig(ctx, o)
	if err != nil {
		return fmt.Errorf("service-mode needs the active profile config: %w", err)
	}

	rctx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	return c.SetServiceMode(rctx, mode, cfg)
}
