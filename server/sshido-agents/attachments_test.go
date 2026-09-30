package main

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

var pngHeader = []byte("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR")

func workspaceWith(t *testing.T, files map[string][]byte) string {
	t.Helper()
	dir := t.TempDir()
	for name, data := range files {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, data, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func TestResolveAttachment(t *testing.T) {
	ws := workspaceWith(t, map[string][]byte{"shots/hn.png": pngHeader, "notes": []byte("plain text notes")})
	abs, err := resolveAttachment(ws, filepath.Join(ws, "shots/hn.png"))
	if err != nil {
		t.Fatal(err)
	}
	if abs.Name != "hn.png" || abs.Mime != "image/png" || abs.Size != int64(len(pngHeader)) {
		t.Fatalf("got %+v", abs)
	}
	rel, err := resolveAttachment(ws, "shots/hn.png")
	if err != nil || rel.Path != abs.Path {
		t.Fatalf("relative path: %+v %v", rel, err)
	}
	sniffed, err := resolveAttachment(ws, "notes")
	if err != nil || sniffed.Mime != "text/plain" {
		t.Fatalf("sniffed: %+v %v", sniffed, err)
	}
}

func TestResolveAttachmentDenies(t *testing.T) {
	outside := workspaceWith(t, map[string][]byte{"secret": []byte("x")})
	ws := workspaceWith(t, map[string][]byte{"ok.txt": []byte("x")})
	if err := os.Symlink(filepath.Join(outside, "secret"), filepath.Join(ws, "link")); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(ws, "dir"), 0o755); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"", "../secret", filepath.Join(outside, "secret"), "link", "dir", "missing.png", "/etc/passwd"} {
		if _, err := resolveAttachment(ws, path); err == nil {
			t.Fatalf("path %q must be refused", path)
		}
	}
}

func TestOpenAttachmentRechecksSymlinks(t *testing.T) {
	outside := workspaceWith(t, map[string][]byte{"secret": []byte("x")})
	ws := workspaceWith(t, map[string][]byte{"a.txt": []byte("hello")})
	att, err := resolveAttachment(ws, "a.txt")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(ws, "a.txt")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(outside, "secret"), filepath.Join(ws, "a.txt")); err != nil {
		t.Fatal(err)
	}
	if f, err := openAttachment(ws, att); err == nil {
		f.Close()
		t.Fatal("a file swapped for an escaping symlink must not open")
	}
}

func TestParseCtlAttach(t *testing.T) {
	for _, args := range [][]string{
		{"attach", "hn.png", "--caption", "front page"},
		{"attach", "--caption", "front page", "hn.png"},
	} {
		req, err := parseCtl(args)
		if err != nil {
			t.Fatal(err)
		}
		if req.Op != BusAttach || req.Path != "hn.png" || req.Text != "front page" {
			t.Fatalf("%v -> %+v", args, req)
		}
	}
	if _, err := parseCtl([]string{"attach", "--caption", "x"}); err == nil {
		t.Fatal("attach without a path must fail")
	}
	send, err := parseCtl([]string{"send", "fix", "--to", "a1", "the tests"})
	if err != nil || send.To != "a1" || send.Text != "fix the tests" {
		t.Fatalf("interleaved send: %+v %v", send, err)
	}
}

func TestBusAttachPostsAttachment(t *testing.T) {
	d, pods, _ := testDaemon(t)
	d.cfg.WorkspaceDir = workspaceWith(t, map[string][]byte{"hn.png": pngHeader})
	if _, err := d.orchestrator(context.Background(), firstChat(t, d)); err != nil {
		t.Fatal(err)
	}
	token, _ := tokenOf(t, pods, RoleOrchestrator)
	resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: token, Op: BusAttach, Path: "hn.png", Text: "front page"}))
	if !resp.OK {
		t.Fatalf("attach failed: %+v", resp)
	}
	files := messagesOfKind(t, d, KindFile)
	if len(files) != 1 || files[0].Attachment == nil || files[0].Attachment.Mime != "image/png" || files[0].Text != "front page" {
		t.Fatalf("attachment message: %+v", files)
	}
	stored, err := d.store.Message(files[0].ID)
	if err != nil || stored.Attachment == nil || !strings.HasSuffix(stored.Attachment.Path, "hn.png") {
		t.Fatalf("stored attachment: %+v %v", stored, err)
	}
	out := string(mustJSON(t, files[0]))
	if strings.Contains(out, d.cfg.WorkspaceDir) {
		t.Fatalf("the path must not reach the app: %s", out)
	}
	if denied := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: token, Op: BusAttach, Path: "../x"})); denied.OK {
		t.Fatal("attach outside the workspace must be denied")
	}
}
