package cmd

import (
	"fmt"

	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/ctrl"
	"github.com/spf13/cobra"
)

var connectCmd = &cobra.Command{
	Use:   "connect",
	Short: "Connect using the active profile or an explicit config",
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := ctrl.Connect(cmd.Context(), options()); err != nil {
			return err
		}
		fmt.Println("connected")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(connectCmd)
}
