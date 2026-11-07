package main

import (
	"os"

	"github.com/hiddify/hiddify-app/tools/hiddifyctl/cmd"
)

func main() {
	if err := cmd.Execute(); err != nil {
		os.Exit(1)
	}
}
