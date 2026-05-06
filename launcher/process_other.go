//go:build !windows

package main

import "os/exec"

func configureBackendProcess(cmd *exec.Cmd, showConsole bool) {
	// No-op on non-Windows platforms.
}
