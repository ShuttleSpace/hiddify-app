package cmd

import (
	"encoding/json"
	"fmt"

	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/ctrl"
	"github.com/spf13/cobra"
)

var statusJSON bool

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show connection status, current profile/node and traffic",
	RunE: func(cmd *cobra.Command, args []string) error {
		st, err := ctrl.Status(cmd.Context(), options())
		if err != nil {
			return err
		}
		if statusJSON {
			b, err := json.MarshalIndent(st, "", "  ")
			if err != nil {
				return err
			}
			fmt.Println(string(b))
			return nil
		}
		fmt.Print(st.String())
		return nil
	},
}

func init() {
	statusCmd.Flags().BoolVar(&statusJSON, "json", false, "output JSON")
	rootCmd.AddCommand(statusCmd)
}
