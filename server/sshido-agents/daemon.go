package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

type Config struct {
	DataDir             string
	BusDir              string
	PodmanSocket        string
	AgentImage          string
	OrchestratorHarness string
	OrchestratorModel   string
	WorkerHarness       string
	WorkerModel         string
	LocalURL            string
	NotifyURL           string
	WorkspaceVolume     string
	WorkspaceDir        string
	BusVolume           string
	HostName            string
	TurnTimeout         time.Duration
}

func env(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func loadConfig() (Config, error) {
	minutes, err := strconv.Atoi(env("SSHIDO_TURN_TIMEOUT_MINUTES", "60"))
	if err != nil || minutes <= 0 {
		return Config{}, fmt.Errorf("SSHIDO_TURN_TIMEOUT_MINUTES must be a positive integer")
	}
	orchestrator := env("SSHIDO_ORCHESTRATOR", HarnessClaude)
	cfg := Config{
		DataDir:             env("SSHIDO_DATA_DIR", "/data"),
		BusDir:              env("SSHIDO_BUS_DIR", "/bus"),
		PodmanSocket:        env("SSHIDO_PODMAN_SOCKET", "/run/podman.sock"),
		AgentImage:          env("SSHIDO_AGENT_IMAGE", "localhost/sshido-agent:dev"),
		OrchestratorHarness: orchestrator,
		OrchestratorModel:   env("SSHIDO_ORCHESTRATOR_MODEL", ""),
		WorkerHarness:       env("SSHIDO_WORKER_HARNESS", orchestrator),
		WorkerModel:         env("SSHIDO_WORKER_MODEL", ""),
		LocalURL:            env("SSHIDO_LOCAL_URL", ""),
		NotifyURL:           env("SSHIDO_NOTIFY_URL", ""),
		WorkspaceVolume:     env("SSHIDO_WORKSPACE_VOLUME", "sshido-agents-workspace"),
		WorkspaceDir:        env("SSHIDO_WORKSPACE_DIR", "/workspace"),
		BusVolume:           env("SSHIDO_BUS_VOLUME", "sshido-agents-bus"),
		HostName:            env("SSHIDO_HOST_NAME", "agents"),
		TurnTimeout:         time.Duration(minutes) * time.Minute,
	}
	for _, name := range []string{cfg.OrchestratorHarness, cfg.WorkerHarness} {
		if _, err := lookupHarness(name); err != nil {
			return Config{}, err
		}
	}
	return cfg, nil
}

type Daemon struct {
	cfg    Config
	store  *Store
	pods   Containers
	hub    *Hub
	push   Pusher
	queues sync.Map
	mu     sync.Mutex
}

func newDaemon(cfg Config, store *Store, pods Containers, push Pusher) *Daemon {
	return &Daemon{cfg: cfg, store: store, pods: pods, hub: newHub(), push: push}
}

func randomHex(n int) string {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		panic(fmt.Sprintf("crypto/rand failed: %v", err))
	}
	return hex.EncodeToString(buf)
}

func (d *Daemon) publishAgent(a Agent) { d.hub.Publish(AppEvent{Type: EventAgent, Agent: &a}) }

func (d *Daemon) post(agentID, author, kind, text string) {
	m, err := d.store.AddMessage(agentID, author, kind, text)
	if err != nil {
		log.Printf("store message from %s failed: %v", author, err)
		return
	}
	d.hub.Publish(AppEvent{Type: EventMessage, Message: &m})
}

func (d *Daemon) notify(ctx context.Context, title, body string, high bool) {
	if err := d.push.Push(ctx, title, body, high); err != nil {
		log.Printf("push %q failed: %v", title, err)
	}
}

func (d *Daemon) setStatus(id, status string) {
	a, err := d.store.SetStatus(id, status)
	if err != nil {
		log.Printf("set status %s=%s failed: %v", id, status, err)
		return
	}
	d.publishAgent(a)
}

func (d *Daemon) createAgent(ctx context.Context, name, role, harness, model, task string) (Agent, error) {
	spec, err := lookupHarness(harness)
	if err != nil {
		return Agent{}, err
	}
	id := randomHex(4)
	token := randomHex(24)
	container := "sshido-agent-" + id
	stateDir := "/home/agent/" + spec.stateDir
	cspec := ContainerSpec{
		Name:  container,
		Image: d.cfg.AgentImage,
		Env: map[string]string{
			"SSHIDO_AGENT_ID":    id,
			"SSHIDO_AGENT_TOKEN": token,
			"SSHIDO_BUS":         "/bus/bus.sock",
			"CLAUDE_CONFIG_DIR":  "/home/agent/.claude",
		},
		Labels: map[string]string{"sshido.agents": "1", "sshido.agent.id": id, "sshido.agent.role": role},
		Volumes: map[string]string{
			d.cfg.BusVolume:       "/bus",
			d.cfg.WorkspaceVolume: "/workspace",
			"sshido-auth-" + strings.TrimPrefix(spec.stateDir, "."): stateDir,
		},
		User:    "agent",
		WorkDir: "/workspace",
	}
	if err := d.pods.Create(ctx, cspec); err != nil {
		return Agent{}, fmt.Errorf("create container for %s: %w", name, err)
	}
	if err := d.pods.Start(ctx, container); err != nil {
		return Agent{}, fmt.Errorf("start container for %s: %w", name, err)
	}
	chown, err := d.pods.Exec(ctx, container, ExecSpec{
		Cmd: []string{"chown", "agent:agent", "/workspace", stateDir}, User: "0",
	})
	if err != nil || chown.ExitCode != 0 {
		return Agent{}, fmt.Errorf("prepare volumes for %s: %v %s", name, err, truncate(string(chown.Stderr), 200))
	}
	a, err := d.store.AddAgent(Agent{
		ID: id, Name: name, Role: role, Harness: harness, Model: model,
		Status: StatusIdle, Task: task, Container: container,
	}, token)
	if err != nil {
		return Agent{}, err
	}
	d.publishAgent(a)
	return a, nil
}

func (d *Daemon) orchestrator(ctx context.Context) (Agent, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	a, err := d.store.Orchestrator()
	if errors.Is(err, ErrNotFound) {
		return d.createAgent(ctx, "orchestrator", RoleOrchestrator, d.cfg.OrchestratorHarness, d.cfg.OrchestratorModel, "")
	}
	if err != nil {
		return Agent{}, err
	}
	if err := d.pods.Start(ctx, a.Container); err != nil {
		return Agent{}, fmt.Errorf("restart orchestrator container: %w", err)
	}
	return a, nil
}

func (d *Daemon) enqueue(a Agent, prompt string) {
	fresh := make(chan string, 64)
	actual, loaded := d.queues.LoadOrStore(a.ID, fresh)
	queue := actual.(chan string)
	if !loaded {
		go d.drain(a.ID, queue)
	}
	select {
	case queue <- prompt:
	default:
		log.Printf("turn queue for agent %s is full; dropping a turn", a.ID)
		d.post(a.ID, a.Name, KindError, "Too many queued messages for this agent; one was dropped.")
	}
}

func (d *Daemon) drain(id string, queue chan string) {
	for prompt := range queue {
		d.runTurn(id, prompt)
	}
}

func (d *Daemon) runTurn(id, prompt string) {
	a, err := d.store.Agent(id)
	if err != nil {
		log.Printf("turn for missing agent %s: %v", id, err)
		return
	}
	if a.Status == StatusStopped {
		log.Printf("turn for stopped agent %s skipped", id)
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), d.cfg.TurnTimeout)
	defer cancel()
	d.setStatus(id, StatusWorking)
	result, err := d.execTurn(ctx, a, prompt)
	if err != nil {
		d.turnFailed(ctx, a, err)
		return
	}
	if err := d.store.SetSession(id, result.Session); err != nil {
		log.Printf("save session for %s: %v", id, err)
	}
	d.setStatus(id, StatusIdle)
	d.turnDone(ctx, a, result.Text)
}

func (d *Daemon) execTurn(ctx context.Context, a Agent, prompt string) (TurnResult, error) {
	spec, err := lookupHarness(a.Harness)
	if err != nil {
		return TurnResult{}, err
	}
	text := prompt
	if a.Session == "" {
		text = firstTurnPrompt(a.Role, a.Name, prompt)
	}
	turn := Turn{Prompt: text, Session: a.Session, Model: a.Model, LocalURL: d.cfg.LocalURL}
	if spec.promptViaFile {
		path, err := d.writePrompt(a.ID, text)
		if err != nil {
			return TurnResult{}, err
		}
		turn = Turn{PromptFile: path, Session: a.Session, Model: a.Model, LocalURL: d.cfg.LocalURL}
	}
	cmd, err := spec.command(turn)
	if err != nil {
		return TurnResult{}, err
	}
	res, err := d.pods.Exec(ctx, a.Container, ExecSpec{Cmd: cmd, User: "agent", WorkDir: "/workspace"})
	if err != nil {
		return TurnResult{}, err
	}
	parsed, err := spec.parse(res.Stdout)
	if err != nil {
		return TurnResult{}, fmt.Errorf("%w (exit %d, stderr: %s)", err, res.ExitCode, truncate(strings.TrimSpace(string(res.Stderr)), 300))
	}
	return parsed, nil
}

func (d *Daemon) writePrompt(id, text string) (string, error) {
	dir := filepath.Join(d.cfg.BusDir, "prompts", id)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("prompt dir: %w", err)
	}
	name := fmt.Sprintf("%d.txt", time.Now().UnixNano())
	if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
		return "", fmt.Errorf("write prompt: %w", err)
	}
	return filepath.Join("/bus/prompts", id, name), nil
}

func (d *Daemon) turnDone(ctx context.Context, a Agent, text string) {
	if a.Role == RoleOrchestrator {
		d.post(a.ID, a.Name, KindReply, text)
		d.notify(ctx, "Agents replied", text, false)
		return
	}
	d.post(a.ID, a.Name, KindDone, text)
	d.relayToOrchestrator(ctx, workerFinishedPrompt(a.Name, a.ID, text))
}

func (d *Daemon) turnFailed(ctx context.Context, a Agent, err error) {
	log.Printf("turn for %s (%s) failed: %v", a.Name, a.ID, err)
	d.setStatus(a.ID, StatusFailed)
	d.post(a.ID, a.Name, KindError, err.Error())
	if a.Role == RoleOrchestrator {
		d.notify(ctx, "Agents error", err.Error(), true)
		return
	}
	d.relayToOrchestrator(ctx, workerFailedPrompt(a.Name, a.ID, err.Error()))
}

func (d *Daemon) relayToOrchestrator(ctx context.Context, prompt string) {
	orch, err := d.orchestrator(ctx)
	if err != nil {
		log.Printf("cannot reach orchestrator to relay a worker result: %v", err)
		d.post("", "sshido", KindError, "The orchestrator could not be started: "+err.Error())
		return
	}
	d.enqueue(orch, prompt)
}

func (d *Daemon) HandleUserMessage(ctx context.Context, text string) error {
	if strings.TrimSpace(text) == "" {
		return errors.New("empty message")
	}
	d.post("", "you", KindUser, text)
	orch, err := d.orchestrator(ctx)
	if err != nil {
		d.post("", "sshido", KindError, "The orchestrator could not be started: "+err.Error())
		return err
	}
	d.enqueue(orch, text)
	return nil
}

func (d *Daemon) StopAgent(ctx context.Context, id string) error {
	a, err := d.store.Agent(id)
	if err != nil {
		return err
	}
	if err := d.pods.Stop(ctx, a.Container); err != nil {
		return err
	}
	d.setStatus(id, StatusStopped)
	return nil
}

func (d *Daemon) Recover(ctx context.Context) error {
	agents, err := d.store.Agents()
	if err != nil {
		return err
	}
	for _, a := range agents {
		d.recoverAgent(ctx, a)
	}
	return nil
}

func (d *Daemon) recoverAgent(ctx context.Context, a Agent) {
	if a.Status == StatusStopped {
		return
	}
	exists, err := d.pods.Exists(ctx, a.Container)
	if err != nil || !exists {
		log.Printf("agent %s container %s is gone (%v); marking stopped", a.ID, a.Container, err)
		d.setStatus(a.ID, StatusStopped)
		return
	}
	if err := d.pods.Start(ctx, a.Container); err != nil {
		log.Printf("restart agent %s container: %v", a.ID, err)
	}
	if a.Status != StatusWorking {
		return
	}
	d.setStatus(a.ID, StatusIdle)
	d.post(a.ID, a.Name, KindError, "This agent's turn was interrupted by a restart. Send it a message to continue.")
}
