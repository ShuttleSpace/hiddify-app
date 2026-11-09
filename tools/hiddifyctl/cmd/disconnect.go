package cmd

import (
	"fmt"

	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/ctrl"
	"github.com/spf13/cobra"
)

var disconnectCmd = &cobra.Command{
	Use:   "disconnect",
	Short: "Disconnect the core",
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := ctrl.Disconnect(cmd.Context(), options()); err != nil {
			return err
		}
		fmt.Println("disconnected")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(disconnectCmd)
}
