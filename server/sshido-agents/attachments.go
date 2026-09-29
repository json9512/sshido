package main

import (
	"errors"
	"fmt"
	"io"
	"log"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const maxAttachmentBytes = 512 << 20

func within(root, path string) bool {
	rel, err := filepath.Rel(root, path)
	return err == nil && rel != "." && rel != ".." && !strings.HasPrefix(rel, "../")
}

func resolveAttachment(workspace, requested string) (Attachment, error) {
	if strings.TrimSpace(requested) == "" {
		return Attachment{}, errors.New("attach needs a file path")
	}
	full := requested
	if !filepath.IsAbs(requested) {
		full = filepath.Join(workspace, requested)
	}
	clean := filepath.Clean(full)
	real, err := realPathInside(workspace, clean)
	if err != nil {
		return Attachment{}, err
	}
	info, err := os.Stat(real)
	if err != nil {
		return Attachment{}, fmt.Errorf("stat %s: %w", clean, err)
	}
	if !info.Mode().IsRegular() {
		return Attachment{}, fmt.Errorf("%s is not a regular file", clean)
	}
	if info.Size() > maxAttachmentBytes {
		return Attachment{}, fmt.Errorf("%s is %d MB; the limit is %d MB", clean, info.Size()>>20, maxAttachmentBytes>>20)
	}
	mimeType, err := mimeOf(real)
	if err != nil {
		return Attachment{}, err
	}
	return Attachment{Name: filepath.Base(clean), Path: clean, Mime: mimeType, Size: info.Size()}, nil
}

func realPathInside(workspace, path string) (string, error) {
	root, err := filepath.EvalSymlinks(workspace)
	if err != nil {
		return "", fmt.Errorf("workspace %s: %w", workspace, err)
	}
	real, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", fmt.Errorf("file not found: %s", path)
	}
	if !within(root, real) {
		return "", fmt.Errorf("%s is outside %s", path, workspace)
	}
	return real, nil
}

func mimeOf(path string) (string, error) {
	if byExt := mime.TypeByExtension(strings.ToLower(filepath.Ext(path))); byExt != "" {
		return strings.SplitN(byExt, ";", 2)[0], nil
	}
	f, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()
	head := make([]byte, 512)
	n, err := io.ReadFull(f, head)
	if err != nil && !errors.Is(err, io.ErrUnexpectedEOF) && !errors.Is(err, io.EOF) {
		return "", fmt.Errorf("read %s: %w", path, err)
	}
	return strings.SplitN(http.DetectContentType(head[:n]), ";", 2)[0], nil
}

func openAttachment(workspace string, att Attachment) (*os.File, error) {
	real, err := realPathInside(workspace, att.Path)
	if err != nil {
		return nil, err
	}
	return os.Open(real)
}

func runFile(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: sshido-agents file <message-id>")
		return 2
	}
	id, err := strconv.ParseInt(args[0], 10, 64)
	if err != nil {
		fmt.Fprintf(os.Stderr, "file: bad message id %q\n", args[0])
		return 2
	}
	store, err := openStore(filepath.Join(env("SSHIDO_DATA_DIR", "/data"), "agents.db"), time.Now)
	if err != nil {
		fmt.Fprintf(os.Stderr, "file: %v\n", err)
		return 1
	}
	defer store.Close()
	msg, err := store.Message(id)
	if err != nil {
		log.Printf("file: denied: message %d: %v", id, err)
		fmt.Fprintf(os.Stderr, "file: message %d: %v\n", id, err)
		return 1
	}
	if msg.Attachment == nil {
		log.Printf("file: denied: message %d has no attachment", id)
		fmt.Fprintf(os.Stderr, "file: message %d has no attachment\n", id)
		return 1
	}
	f, err := openAttachment(env("SSHIDO_WORKSPACE_DIR", "/workspace"), *msg.Attachment)
	if err != nil {
		log.Printf("file: denied: message %d: %v", id, err)
		fmt.Fprintf(os.Stderr, "file: %v\n", err)
		return 1
	}
	defer f.Close()
	if _, err := io.Copy(os.Stdout, f); err != nil {
		fmt.Fprintf(os.Stderr, "file: %v\n", err)
		return 1
	}
	return 0
}
