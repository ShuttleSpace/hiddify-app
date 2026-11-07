package client

import (
	"context"

	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/grpc/hcommon"
	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/grpc/hcore"
)

// ServiceMode mirrors the app's service mode (ConfigOptions.serviceMode).
type ServiceMode string

const (
	ServiceModeProxy       ServiceMode = "proxy"        // mixed inbound only
	ServiceModeSystemProxy ServiceMode = "system-proxy" // mixed inbound + OS system proxy
	ServiceModeVPN         ServiceMode = "vpn"          // TUN
)

// ParseServiceMode validates a CLI argument, accepting the canonical keys and
// a few common aliases.
func ParseServiceMode(s string) (ServiceMode, bool) {
	switch ServiceMode(s) {
	case ServiceModeProxy, "only-proxy":
		return ServiceModeProxy, true
	case ServiceModeSystemProxy, "systemproxy":
		return ServiceModeSystemProxy, true
	case ServiceModeVPN, "tun":
		return ServiceModeVPN, true
	}
	return "", false
}

// ServiceModeOptions returns the InboundOptions fields for a mode. These are
// the only HiddifyOptions keys we deliberately set; changeHiddifySettings
// resets all other options to defaults on the core side (the desktop app
// re-applies its full option set on its next settings change).
func (m ServiceMode) Options() (enableTun, setSystemProxy bool) {
	switch m {
	case ServiceModeVPN:
		return true, false
	case ServiceModeSystemProxy:
		return false, true
	default:
		return false, false
	}
}

// SetServiceMode switches the core's service mode. It updates HiddifyOptions
// via changeHiddifySettings, then restarts the core with the given config so
// BuildConfig regenerates the config with the new inbound mode.
func (c *Client) SetServiceMode(ctx context.Context, mode ServiceMode, configPath string) error {
	enableTun, setSystemProxy := mode.Options()
	res, err := c.core.ChangeHiddifySettings(ctx, &hcore.ChangeHiddifySettingsRequest{
		HiddifySettingsJson: marshalModeOptions(enableTun, setSystemProxy),
	})
	if err != nil {
		return err
	}
	if res.MessageType != hcore.MessageType_EMPTY {
		return &Error{msg: "change settings failed: " + res.Message}
	}

	res, err = c.core.Restart(ctx, &hcore.StartRequest{
		ConfigPath: configPath,
		ConfigName: "hiddifyctl",
		DelayStart: true,
	})
	if err != nil {
		return err
	}
	if res.MessageType != hcore.MessageType_EMPTY {
		return &Error{msg: "restart failed: " + res.Message}
	}
	return nil
}

// SystemProxyEnabled reports whether the core currently owns the OS system
// proxy, used to display the effective mode in `status`.
func (c *Client) SystemProxyEnabled(ctx context.Context) (bool, error) {
	res, err := c.core.GetSystemProxyStatus(ctx, &hcommon.Empty{})
	if err != nil {
		return false, err
	}
	return res.GetEnabled(), nil
}

func marshalModeOptions(enableTun, setSystemProxy bool) string {
	// Keep the JSON minimal but explicit: changeHiddifySettings resets to
	// defaults first, so omitted keys fall back to core defaults.
	return "{\"enable-tun\":" + boolStr(enableTun) +
		",\"set-system-proxy\":" + boolStr(setSystemProxy) + "}"
}

func boolStr(b bool) string {
	if b {
		return "true"
	}
	return "false"
}
