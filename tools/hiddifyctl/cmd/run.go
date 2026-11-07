package cmd

import (
	"fmt"

	headlesscore "github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/headless"
	"github.com/spf13/cobra"
)

var runCmd = &cobra.Command{
	Use:   "run",
	Short: "Headless: start an independent hiddify-core with a config (blocking)",
	RunE: func(cmd *cobra.Command, args []string) error {
		if config == "" {
			return fmt.Errorf("--config <path|url> is required for run")
		}
		bin, err := headlesscore.FindCoreBin(coreBin)
		if err != nil {
			return err
		}
		child, err := headlesscore.Start(cmd.Context(), config, bin, tun, systemProxy, false)
		if err != nil {
			return err
		}
		fmt.Printf("started hiddify-core (%s); press Ctrl+C to stop\n", bin)
		return child.Wait()
	},
}

func init() {
	rootCmd.AddCommand(runCmd)
}
