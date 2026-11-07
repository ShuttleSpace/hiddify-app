package cmd

import (
	"fmt"

	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/client"
	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/ctrl"
	"github.com/spf13/cobra"
)

var serviceModeCmd = &cobra.Command{
	Use:   "service-mode <proxy|system-proxy|vpn>",
	Short: "Switch the service mode: proxy, system-proxy or vpn",
	Long: "Switch how the core accepts traffic:\n" +
		"  proxy         only the local mixed/socks proxy (no OS proxy, no TUN)\n" +
		"  system-proxy  local proxy + set the OS system proxy\n" +
		"  vpn           TUN interface (VPN mode)\n\n" +
		"Default (app mode): drives the running desktop app over gRPC\n" +
		"(changeHiddifySettings + Restart), mirroring its own mode switch. The\n" +
		"connection is briefly interrupted, and the other Hiddify options are\n" +
		"reset to core defaults (the app restores them on its next settings edit).\n\n" +
		"--headless: restarts the standalone core started by `connect --headless`\n" +
		"with the matching --tun/--system-proxy startup flags. No option reset,\n" +
		"but the standalone core is restarted. Pass --config (-c) to launch a\n" +
		"fresh standalone core in the new mode when none is running.",
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		mode, ok := client.ParseServiceMode(args[0])
		if !ok {
			return fmt.Errorf("unknown service mode %q (use proxy, system-proxy or vpn)", args[0])
		}
		if err := ctrl.SetServiceMode(cmd.Context(), options(), mode); err != nil {
			return err
		}
		fmt.Printf("service mode set to %s\n", mode)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(serviceModeCmd)
}
