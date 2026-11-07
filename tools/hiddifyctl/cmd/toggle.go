package cmd

import (
	"fmt"

	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/ctrl"
	"github.com/spf13/cobra"
)

var toggleCmd = &cobra.Command{
	Use:   "toggle",
	Short: "Toggle the connection (connect if disconnected, disconnect if connected)",
	RunE: func(cmd *cobra.Command, args []string) error {
		o := options()
		st, err := ctrl.Status(cmd.Context(), o)
		if err == nil && st.IsConnected() {
			if err := ctrl.Disconnect(cmd.Context(), o); err != nil {
				return err
			}
			fmt.Println("disconnected")
			return nil
		}
		if err := ctrl.Connect(cmd.Context(), o); err != nil {
			return err
		}
		fmt.Println("connected")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(toggleCmd)
}
