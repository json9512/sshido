package main

import (
	"fmt"
	"path/filepath"
	"strings"
)

const agentClaudeDir = "/home/agent/.claude"

type WritableBind struct {
	Source string
	Target string
}

func parseHostClaudeHome(raw string) (string, error) {
	home := strings.TrimSpace(raw)
	if home == "" {
		return "", nil
	}
	clean := filepath.Clean(home)
	if !filepath.IsAbs(clean) || clean == "/" {
		return "", fmt.Errorf("SSHIDO_HOST_CLAUDE_HOME must be an absolute path below /, got %q", raw)
	}
	return clean, nil
}

func sharesHostClaude(home string, spec harnessSpec) bool {
	return home != "" && spec.stateDir == ".claude"
}

func claudeConfigDir(home string, spec harnessSpec) string {
	if !sharesHostClaude(home, spec) {
		return agentClaudeDir
	}
	return home + "/.claude"
}

func hostClaudeBinds(home string, spec harnessSpec) []WritableBind {
	if !sharesHostClaude(home, spec) {
		return nil
	}
	return []WritableBind{
		{Source: home + "/.claude", Target: home + "/.claude"},
		{Source: home + "/.claude.json", Target: home + "/.claude/.claude.json"},
	}
}

func ownershipCommand(spec ContainerSpec) []string {
	if !spec.KeepID {
		return append([]string{"chown", "agent:agent"}, spec.Owned...)
	}
	return append(append([]string{"find"}, spec.Owned...), "!", "-user", "agent", "-exec", "chown", "-h", "agent:agent", "{}", "+")
}
