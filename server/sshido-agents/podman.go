package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
)

type ContainerSpec struct {
	Name    string
	Image   string
	Env     map[string]string
	Labels  map[string]string
	Volumes map[string]string
	User    string
	WorkDir string
}

type ExecSpec struct {
	Cmd     []string
	User    string
	WorkDir string
}

type ExecResult struct {
	Stdout   []byte
	Stderr   []byte
	ExitCode int
}

type Containers interface {
	Create(ctx context.Context, spec ContainerSpec) error
	Start(ctx context.Context, name string) error
	Exec(ctx context.Context, name string, spec ExecSpec) (ExecResult, error)
	Stop(ctx context.Context, name string) error
	Remove(ctx context.Context, name string) error
	Exists(ctx context.Context, name string) (bool, error)
}

type podmanAPI struct {
	client *http.Client
	base   string
}

func newPodmanAPI(socketPath string) *podmanAPI {
	dial := func(ctx context.Context, _, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "unix", socketPath)
	}
	return &podmanAPI{
		client: &http.Client{Transport: &http.Transport{DialContext: dial}},
		base:   "http://podman/v5.0.0/libpod",
	}
}

func (p *podmanAPI) do(ctx context.Context, method, path string, body any) (*http.Response, error) {
	payload, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("encode %s %s: %w", method, path, err)
	}
	req, err := http.NewRequestWithContext(ctx, method, p.base+path, bytes.NewReader(payload))
	if err != nil {
		return nil, fmt.Errorf("request %s %s: %w", method, path, err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := p.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("podman %s %s: %w", method, path, err)
	}
	return resp, nil
}

func (p *podmanAPI) expect(ctx context.Context, method, path string, body any, ok ...int) ([]byte, error) {
	resp, err := p.do(ctx, method, path, body)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read podman %s %s: %w", method, path, err)
	}
	for _, code := range ok {
		if resp.StatusCode == code {
			return data, nil
		}
	}
	return nil, fmt.Errorf("podman %s %s: http %d: %s", method, path, resp.StatusCode, truncate(strings.TrimSpace(string(data)), 300))
}

type namedVolume struct {
	Name string `json:"Name"`
	Dest string `json:"Dest"`
}

func (p *podmanAPI) Create(ctx context.Context, spec ContainerSpec) error {
	volumes := make([]namedVolume, 0, len(spec.Volumes))
	for name, dest := range spec.Volumes {
		volumes = append(volumes, namedVolume{Name: name, Dest: dest})
	}
	body := map[string]any{
		"name":     spec.Name,
		"image":    spec.Image,
		"command":  []string{"sleep", "infinity"},
		"env":      spec.Env,
		"labels":   spec.Labels,
		"volumes":  volumes,
		"user":     spec.User,
		"work_dir": spec.WorkDir,
		"init":     true,
	}
	_, err := p.expect(ctx, http.MethodPost, "/containers/create", body, http.StatusCreated)
	return err
}

func (p *podmanAPI) Start(ctx context.Context, name string) error {
	_, err := p.expect(ctx, http.MethodPost, "/containers/"+url.PathEscape(name)+"/start", nil,
		http.StatusNoContent, http.StatusNotModified)
	return err
}

func (p *podmanAPI) Stop(ctx context.Context, name string) error {
	_, err := p.expect(ctx, http.MethodPost, "/containers/"+url.PathEscape(name)+"/stop?timeout=10", nil,
		http.StatusNoContent, http.StatusNotModified)
	return err
}

func (p *podmanAPI) Remove(ctx context.Context, name string) error {
	_, err := p.expect(ctx, http.MethodDelete, "/containers/"+url.PathEscape(name)+"?force=true", nil,
		http.StatusOK, http.StatusNoContent, http.StatusNotFound)
	return err
}

func (p *podmanAPI) Exists(ctx context.Context, name string) (bool, error) {
	resp, err := p.do(ctx, http.MethodGet, "/containers/"+url.PathEscape(name)+"/exists", nil)
	if err != nil {
		return false, err
	}
	resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusNoContent:
		return true, nil
	case http.StatusNotFound:
		return false, nil
	}
	return false, fmt.Errorf("podman exists %s: http %d", name, resp.StatusCode)
}

func (p *podmanAPI) Exec(ctx context.Context, name string, spec ExecSpec) (ExecResult, error) {
	create := map[string]any{
		"Cmd": spec.Cmd, "AttachStdout": true, "AttachStderr": true,
		"User": spec.User, "WorkingDir": spec.WorkDir,
	}
	data, err := p.expect(ctx, http.MethodPost, "/containers/"+url.PathEscape(name)+"/exec", create, http.StatusCreated)
	if err != nil {
		return ExecResult{}, err
	}
	var created struct{ Id string }
	if err := json.Unmarshal(data, &created); err != nil || created.Id == "" {
		return ExecResult{}, fmt.Errorf("podman exec create %s: bad response %q", name, truncate(string(data), 200))
	}
	stdout, stderr, err := p.startExec(ctx, created.Id)
	if err != nil {
		return ExecResult{}, err
	}
	code, err := p.execExitCode(ctx, created.Id)
	if err != nil {
		return ExecResult{}, err
	}
	return ExecResult{Stdout: stdout, Stderr: stderr, ExitCode: code}, nil
}

func (p *podmanAPI) startExec(ctx context.Context, id string) ([]byte, []byte, error) {
	resp, err := p.do(ctx, http.MethodPost, "/exec/"+id+"/start", map[string]any{"Detach": false, "Tty": false})
	if err != nil {
		return nil, nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		data, _ := io.ReadAll(resp.Body)
		return nil, nil, fmt.Errorf("podman exec start: http %d: %s", resp.StatusCode, truncate(string(data), 300))
	}
	return demux(resp.Body)
}

func (p *podmanAPI) execExitCode(ctx context.Context, id string) (int, error) {
	data, err := p.expect(ctx, http.MethodGet, "/exec/"+id+"/json", nil, http.StatusOK)
	if err != nil {
		return 0, err
	}
	var info struct{ ExitCode int }
	if err := json.Unmarshal(data, &info); err != nil {
		return 0, fmt.Errorf("podman exec inspect: %w", err)
	}
	return info.ExitCode, nil
}

func demux(r io.Reader) ([]byte, []byte, error) {
	var stdout, stderr bytes.Buffer
	header := make([]byte, 8)
	for {
		if _, err := io.ReadFull(r, header); err != nil {
			if errors.Is(err, io.EOF) {
				return stdout.Bytes(), stderr.Bytes(), nil
			}
			return nil, nil, fmt.Errorf("read exec stream header: %w", err)
		}
		size := int64(binary.BigEndian.Uint32(header[4:]))
		target := &stdout
		if header[0] == 2 {
			target = &stderr
		}
		if _, err := io.CopyN(target, r, size); err != nil {
			return nil, nil, fmt.Errorf("read exec stream frame: %w", err)
		}
	}
}
