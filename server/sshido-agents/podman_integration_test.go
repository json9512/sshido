package main

import (
	"context"
	"os"
	"path/filepath"
	"strings"
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

func TestLivePickerTakesTurns(t *testing.T) {
	url, model := os.Getenv("SSHIDO_TEST_PICKER_URL"), os.Getenv("SSHIDO_TEST_PICKER_MODEL")
	if url == "" || model == "" {
		t.Skip("set SSHIDO_TEST_PICKER_URL and SSHIDO_TEST_PICKER_MODEL to run against a real model")
	}
	picker := newPicker(url, model)
	chat := Chat{Title: "haiku"}
	members := []Agent{{Name: "poet", Harness: "claude"}, {Name: "critic", Harness: "codex"}}
	user := Message{Kind: KindUser, Author: "you", Text: "Poet, write a haiku about rain. Critic, then review it in one line."}
	poem := Message{Kind: KindReply, Author: "poet", Text: "Rain taps the tin roof / puddles gather the gray sky / a sparrow shakes dry"}
	review := Message{Kind: KindReply, Author: "critic", Text: "Clean imagery; the last line lands. No changes needed."}
	steps := []struct {
		history []Message
		want    int
	}{
		{[]Message{user}, 0},
		{[]Message{user, poem}, 1},
		{[]Message{user, poem, review}, 2},
	}
	for i, step := range steps {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		pick, err := picker.Pick(ctx, pickerState(chat, members, step.history), pickerQuestion(i > 0), pickerOptions(members, i > 0))
		cancel()
		if err != nil {
			t.Fatalf("step %d: %v", i, err)
		}
		t.Logf("step %d: picked %d, probabilities %.3f", i, pick.Index, pick.Probs)
		if pick.Index != step.want {
			t.Fatalf("step %d: picked %d, want %d", i, pick.Index, step.want)
		}
	}
}
