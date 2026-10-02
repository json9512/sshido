package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestPodmanMountsHostDirReadOnly(t *testing.T) {
	socket, image := os.Getenv("SSHIDO_TEST_PODMAN_SOCKET"), os.Getenv("SSHIDO_TEST_AGENT_IMAGE")
	if socket == "" || image == "" {
		t.Skip("set SSHIDO_TEST_PODMAN_SOCKET and SSHIDO_TEST_AGENT_IMAGE to run against a real Podman")
	}
	src, err := os.MkdirTemp(os.Getenv("HOME"), "sshido-hostdir-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(src)
	if err := os.WriteFile(filepath.Join(src, "note.txt"), []byte("from the host"), 0o644); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	pods := newPodmanAPI(socket)
	name := "sshido-hostdir-test-" + randomHex(4)
	defer pods.Remove(context.Background(), name)
	spec := ContainerSpec{Name: name, Image: image, Binds: []HostDir{{Name: "notes", Source: src}}, User: "agent", WorkDir: "/tmp"}
	if err := pods.Create(ctx, spec); err != nil {
		t.Fatal(err)
	}
	if err := pods.Start(ctx, name); err != nil {
		t.Fatal(err)
	}
	read, err := pods.Exec(ctx, name, ExecSpec{Cmd: []string{"cat", "/host/notes/note.txt"}, User: "agent"})
	if err != nil || read.ExitCode != 0 || string(read.Stdout) != "from the host" {
		t.Fatalf("read: %v exit %d out %q err %q", err, read.ExitCode, read.Stdout, read.Stderr)
	}
	write, err := pods.Exec(ctx, name, ExecSpec{Cmd: []string{"touch", "/host/notes/new.txt"}, User: "agent"})
	if err != nil || write.ExitCode == 0 || !strings.Contains(string(write.Stderr), "Read-only file system") {
		t.Fatalf("write must fail read-only: %v exit %d err %q", err, write.ExitCode, write.Stderr)
	}
}

func TestPodmanDesktopOnLoopbackPort(t *testing.T) {
	socket, image := os.Getenv("SSHIDO_TEST_PODMAN_SOCKET"), os.Getenv("SSHIDO_TEST_AGENT_IMAGE")
	if socket == "" || image == "" {
		t.Skip("set SSHIDO_TEST_PODMAN_SOCKET and SSHIDO_TEST_AGENT_IMAGE to run against a real Podman")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	pods := newPodmanAPI(socket)
	name := "sshido-desktop-test-" + randomHex(4)
	defer pods.Remove(context.Background(), name)
	spec := ContainerSpec{Name: name, Image: image, Ports: []int{desktopPort}, User: "agent", WorkDir: "/tmp"}
	if err := pods.Create(ctx, spec); err != nil {
		t.Fatal(err)
	}
	if err := pods.Start(ctx, name); err != nil {
		t.Fatal(err)
	}
	serve, err := pods.Exec(ctx, name, ExecSpec{Cmd: []string{"desktop", "serve"}, User: "agent"})
	if err != nil || serve.ExitCode != 0 || len(strings.TrimSpace(string(serve.Stdout))) != 8 {
		t.Fatalf("serve: %v exit %d out %q err %q", err, serve.ExitCode, serve.Stdout, serve.Stderr)
	}
	shot, err := pods.Exec(ctx, name, ExecSpec{Cmd: []string{"sh", "-c", "desktop screenshot /tmp/s.png && test -s /tmp/s.png"}, User: "agent"})
	if err != nil || shot.ExitCode != 0 {
		t.Fatalf("screenshot: %v exit %d err %q", err, shot.ExitCode, shot.Stderr)
	}
	data, err := pods.expect(ctx, "GET", "/containers/"+name+"/json", nil, 200)
	if err != nil {
		t.Fatal(err)
	}
	var inspect struct {
		NetworkSettings struct {
			Ports map[string][]struct{ HostIp, HostPort string }
		}
	}
	if err := json.Unmarshal(data, &inspect); err != nil {
		t.Fatal(err)
	}
	bound := inspect.NetworkSettings.Ports["6080/tcp"]
	if len(bound) != 1 || bound[0].HostIp != "127.0.0.1" || bound[0].HostPort == "" || bound[0].HostPort == "0" {
		t.Fatalf("desktop port must be published on a random loopback port, got %+v", bound)
	}
}

func TestPodmanAgentWritesSharedHostConfigAsTheHostUser(t *testing.T) {
	socket, image := os.Getenv("SSHIDO_TEST_PODMAN_SOCKET"), os.Getenv("SSHIDO_TEST_AGENT_IMAGE")
	if socket == "" || image == "" {
		t.Skip("set SSHIDO_TEST_PODMAN_SOCKET and SSHIDO_TEST_AGENT_IMAGE to run against a real Podman")
	}
	home, err := os.MkdirTemp(os.Getenv("HOME"), "sshido-claudehome-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(home)
	if err := os.Mkdir(filepath.Join(home, ".claude"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, ".claude.json"), []byte(`{"mcpServers":{}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	pods := newPodmanAPI(socket)
	name := "sshido-claudehome-test-" + randomHex(4)
	defer pods.Remove(context.Background(), name)
	claude := harnessSpec{stateDir: ".claude"}
	spec := ContainerSpec{Name: name, Image: image, Writable: hostClaudeBinds(home, claude), KeepID: true, User: "agent", WorkDir: "/tmp"}
	if err := pods.Create(ctx, spec); err != nil {
		t.Fatal(err)
	}
	if err := pods.Start(ctx, name); err != nil {
		t.Fatal(err)
	}
	script := "cat " + home + "/.claude/.claude.json && echo '{\"written\":true}' > " + home + "/.claude/.claude.json && touch " + home + "/.claude/fromagent"
	run, err := pods.Exec(ctx, name, ExecSpec{Cmd: []string{"sh", "-c", script}, User: "agent"})
	if err != nil || run.ExitCode != 0 || !strings.Contains(string(run.Stdout), "mcpServers") {
		t.Fatalf("agent read/write: %v exit %d out %q err %q", err, run.ExitCode, run.Stdout, run.Stderr)
	}
	written, err := os.ReadFile(filepath.Join(home, ".claude.json"))
	if err != nil || strings.TrimSpace(string(written)) != `{"written":true}` {
		t.Fatalf("host .claude.json after the agent wrote it: %q %v", written, err)
	}
	info, err := os.Stat(filepath.Join(home, ".claude", "fromagent"))
	if err != nil {
		t.Fatal(err)
	}
	if owner := info.Sys().(*syscall.Stat_t).Uid; int(owner) != os.Getuid() {
		t.Fatalf("file the agent created is owned by uid %d, want the host user %d", owner, os.Getuid())
	}
}
