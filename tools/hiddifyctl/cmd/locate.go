package cmd

import (
	"fmt"
	"path/filepath"

	"github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/locate"
	"github.com/spf13/cobra"
)

var locateCmd = &cobra.Command{
	Use:   "locate",
	Short: "Print detected app directories (debug helper)",
	RunE: func(cmd *cobra.Command, args []string) error {
		p, err := locate.Detect(appDir, dbPath)
		if err != nil {
			return err
		}
		fmt.Printf("WorkingDir: %s\n", p.WorkingDir)
		fmt.Printf("ConfigsDir: %s\n", p.ConfigsDir)
		fmt.Printf("DBPath:     %s\n", orNA(p.DBPath))
		id, name, err := locate.ActiveProfile(p.DBPath)
		if err != nil {
			fmt.Printf("ActiveProfile: <not found: %v>\n", err)
			return nil
		}
		fmt.Printf("ActiveProfile: id=%s name=%q config=%s\n", id, name, filepath.Join(p.ConfigsDir, id+".json"))
		return nil
	},
}

func orNA(s string) string {
	if s == "" {
		return "n/a"
	}
	return s
}

func init() {
	rootCmd.AddCommand(locateCmd)
}
