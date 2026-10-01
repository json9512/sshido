package main

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
)

const hostDirRoot = "/host"

type HostDir struct {
	Name   string
	Source string
}

func (h HostDir) Target() string { return hostDirRoot + "/" + h.Name }

var unsafeName = regexp.MustCompile(`[^A-Za-z0-9._-]+`)

func parseHostDirs(raw string) ([]HostDir, error) {
	if strings.TrimSpace(raw) == "" {
		return nil, nil
	}
	var paths []string
	if err := json.Unmarshal([]byte(raw), &paths); err != nil {
		return nil, fmt.Errorf("SSHIDO_HOST_DIRS must be a JSON array of absolute paths: %w", err)
	}
	dirs := []HostDir{}
	for _, p := range paths {
		dir, err := hostDir(p, dirs)
		if err != nil {
			return nil, err
		}
		dirs = append(dirs, dir)
	}
	return dirs, nil
}

func hostDir(path string, taken []HostDir) (HostDir, error) {
	clean := filepath.Clean(strings.TrimSpace(path))
	if !filepath.IsAbs(clean) || clean == "/" {
		return HostDir{}, fmt.Errorf("host directory %q must be an absolute path below /", path)
	}
	base := strings.Trim(unsafeName.ReplaceAllString(filepath.Base(clean), "-"), "-.")
	if base == "" {
		base = "dir"
	}
	return HostDir{Name: uniqueName(base, taken, 1), Source: clean}, nil
}

func uniqueName(base string, taken []HostDir, n int) string {
	name := base
	if n > 1 {
		name = fmt.Sprintf("%s-%d", base, n)
	}
	for _, t := range taken {
		if t.Name == name {
			return uniqueName(base, taken, n+1)
		}
	}
	return name
}

func setupFingerprint(dirs []HostDir) string {
	parts := make([]string, 0, len(dirs)+1)
	for _, d := range dirs {
		parts = append(parts, d.Target()+"="+d.Source)
	}
	return strings.Join(append(parts, fmt.Sprintf("desktop=%d", desktopPort), "logins="+loginsVolume), "\n")
}
