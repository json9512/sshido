package main

import (
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

const (
	recordRoot     = ".sshido/records"
	logFile        = "log.md"
	logTailBytes   = 6000
	maxRecordField = 8000
)

func agentRecordPath(id string) string { return "/workspace/" + recordRoot + "/" + id }

func recordDir(workspace, id string) (string, error) {
	dir := filepath.Join(workspace, recordRoot, id)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("record dir for %s: %w", id, err)
	}
	if _, err := realPathInside(workspace, dir); err != nil {
		return "", fmt.Errorf("record dir for %s: %w", id, err)
	}
	return dir, nil
}

func writeNoFollow(path string, flags int, body string) error {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|syscall.O_NOFOLLOW|flags, 0o644)
	if err != nil {
		return err
	}
	if _, err := io.WriteString(f, body); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}

func recordFiles(a Agent) map[string]string {
	return map[string]string{
		"goal.md":         a.Goal,
		"status.md":       a.WorkStatus,
		"verification.md": a.Verification,
		"verdict.md":      strings.TrimSuffix(verdictLine(a), ": "),
	}
}

func writeRecordFiles(workspace string, a Agent) error {
	dir, err := recordDir(workspace, a.ID)
	if err != nil {
		return err
	}
	for name, body := range recordFiles(a) {
		if err := writeNoFollow(filepath.Join(dir, name), os.O_TRUNC, strings.TrimSpace(body)+"\n"); err != nil {
			return fmt.Errorf("write %s for %s: %w", name, a.ID, err)
		}
	}
	return nil
}

func appendLogEntry(workspace, id string, at time.Time, entry string) error {
	dir, err := recordDir(workspace, id)
	if err != nil {
		return err
	}
	body := fmt.Sprintf("## %s\n\n%s\n\n", at.UTC().Format(time.RFC3339), strings.TrimSpace(entry))
	if err := writeNoFollow(filepath.Join(dir, logFile), os.O_APPEND, body); err != nil {
		return fmt.Errorf("append to the track record of %s: %w", id, err)
	}
	return nil
}

func readLog(workspace, id string) (string, error) {
	data, err := os.ReadFile(filepath.Join(workspace, recordRoot, id, logFile))
	if errors.Is(err, os.ErrNotExist) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("read the track record of %s: %w", id, err)
	}
	return string(data), nil
}

func logTail(full string, max int) string {
	if len(full) <= max {
		return strings.TrimSpace(full)
	}
	cut := full[len(full)-max:]
	next := strings.Index(cut, "\n## ")
	if next < 0 {
		return "[earlier entries are in " + logFile + "]\n" + strings.TrimSpace(strings.ToValidUTF8(cut, ""))
	}
	return "[earlier entries are in " + logFile + "]\n" + strings.TrimSpace(cut[next+1:])
}

func runLog(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: sshido-agents log <agent-id>")
		return 2
	}
	store, err := openStore(filepath.Join(env("SSHIDO_DATA_DIR", "/data"), "agents.db"), time.Now)
	if err != nil {
		fmt.Fprintf(os.Stderr, "log: %v\n", err)
		return 1
	}
	defer store.Close()
	a, err := store.Agent(args[0])
	if err != nil {
		log.Printf("log: denied: agent %q: %v", args[0], err)
		fmt.Fprintf(os.Stderr, "log: agent %q: %v\n", args[0], err)
		return 1
	}
	full, err := readLog(env("SSHIDO_WORKSPACE_DIR", "/workspace"), a.ID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "log: %v\n", err)
		return 1
	}
	fmt.Print(full)
	return 0
}
