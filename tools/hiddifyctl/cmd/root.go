package cmd

import (
	"time"

	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/ctrl"
	"github.com/spf13/cobra"
)

var (
	addr        string
	appDir      string
	dbPath      string
	coreBin     string
	headless    bool
	timeout     time.Duration
	config      string
	tun         bool
	systemProxy bool
)

var rootCmd = &cobra.Command{
	Use:   "hiddifyctl",
	Short: "Control the Hiddify network from the CLI or an MCP server",
	Long: "hiddifyctl talks to the local hiddify-core gRPC endpoint (127.0.0.1:17078)\n" +
		"to connect, disconnect and report status. It drives the desktop app that is\n" +
		"already running, or can start an independent core in headless mode.",
}

func init() {
	rootCmd.PersistentFlags().StringVar(&addr, "addr", "127.0.0.1:17078", "hiddify-core gRPC address")
	rootCmd.PersistentFlags().StringVar(&appDir, "app-dir", "", "override Hiddify app working dir (contains configs/)")
	rootCmd.PersistentFlags().StringVar(&dbPath, "db-path", "", "override Hiddify drift db.sqlite path")
	rootCmd.PersistentFlags().StringVar(&coreBin, "core-bin", "", "path to HiddifyCli binary for headless mode")
	rootCmd.PersistentFlags().BoolVar(&headless, "headless", false, "start an independent hiddify-core if the endpoint is unreachable")
	rootCmd.PersistentFlags().DurationVar(&timeout, "timeout", 5*time.Second, "gRPC dial timeout")
	rootCmd.PersistentFlags().StringVar(&config, "config", "", "explicit config path or subscription URL")
	rootCmd.PersistentFlags().BoolVar(&tun, "tun", false, "headless: enable TUN")
	rootCmd.PersistentFlags().BoolVar(&systemProxy, "system-proxy", false, "headless: enable system proxy")
}

func options() ctrl.Options {
	return ctrl.Options{
		Addr:        addr,
		AppDir:      appDir,
		DBPath:      dbPath,
		Config:      config,
		CoreBin:     coreBin,
		Headless:    headless,
		Timeout:     timeout,
		Tun:         tun,
		SystemProxy: systemProxy,
	}
}

// Execute runs the root command.
func Execute() error {
	return rootCmd.Execute()
}
