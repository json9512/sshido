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
	Workers             WorkerChoice
	LocalURL            string
	NotifyURL           string
	WorkspaceVolume     string
	WorkspaceDir        string
	BusVolume           string
	HostName            string
	HostDirs            []HostDir
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
	if _, err := lookupHarness(orchestrator); err != nil {
		return Config{}, err
	}
	workers, err := parseWorkerChoice(env("SSHIDO_WORKER_CHOICE", ChoiceFixed), env("SSHIDO_WORKER_HARNESS", orchestrator),
		env("SSHIDO_WORKER_MODEL", ""), env("SSHIDO_WORKER_HARNESSES", ""), env("SSHIDO_WORKER_LOCAL_MODEL", ""))
	if err != nil {
		return Config{}, err
	}
	hostDirs, err := parseHostDirs(os.Getenv("SSHIDO_HOST_DIRS"))
	if err != nil {
		return Config{}, err
	}
	cfg := Config{
		DataDir:             env("SSHIDO_DATA_DIR", "/data"),
		BusDir:              env("SSHIDO_BUS_DIR", "/bus"),
		PodmanSocket:        env("SSHIDO_PODMAN_SOCKET", "/run/podman.sock"),
		AgentImage:          env("SSHIDO_AGENT_IMAGE", "localhost/sshido-agent:dev"),
		OrchestratorHarness: orchestrator,
		OrchestratorModel:   env("SSHIDO_ORCHESTRATOR_MODEL", ""),
		Workers:             workers,
		LocalURL:            env("SSHIDO_LOCAL_URL", ""),
		NotifyURL:           env("SSHIDO_NOTIFY_URL", ""),
		WorkspaceVolume:     env("SSHIDO_WORKSPACE_VOLUME", "sshido-agents-workspace"),
		WorkspaceDir:        env("SSHIDO_WORKSPACE_DIR", "/workspace"),
		BusVolume:           env("SSHIDO_BUS_VOLUME", "sshido-agents-bus"),
		HostName:            env("SSHIDO_HOST_NAME", "agents"),
		HostDirs:            hostDirs,
		TurnTimeout:         time.Duration(minutes) * time.Minute,
	}
	return cfg, nil
}

type Daemon struct {
	cfg      Config
	store    *Store
	pods     Containers
	hub      *Hub
	push     Pusher
	queues   sync.Map
	inflight sync.WaitGroup
	mu       sync.Mutex
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

func (d *Daemon) publishChat(c Chat) { d.hub.Publish(AppEvent{Type: EventChat, Chat: &c}) }

func (d *Daemon) post(chatID, agentID, author, kind, text string) {
	m, err := d.store.AddMessage(chatID, agentID, author, kind, text)
	if err != nil {
		log.Printf("store message from %s in chat %s failed: %v", author, chatID, err)
		return
	}
	d.hub.Publish(AppEvent{Type: EventMessage, Message: &m})
}

func (d *Daemon) notify(ctx context.Context, title, body string, high bool) {
	if err := d.push.Push(ctx, title, body, high); err != nil {
		log.Printf("push %q failed: %v", title, err)
	}
}

func (d *Daemon) chatTitle(id string) string {
	c, err := d.store.Chat(id)
	if err != nil {
		log.Printf("title of chat %s: %v", id, err)
		return "Agents"
	}
	return c.Title
}

func (d *Daemon) setStatus(id, status string) {
	a, err := d.store.SetStatus(id, status)
	if err != nil {
		log.Printf("set status %s=%s failed: %v", id, status, err)
		return
	}
	d.publishAgent(a)
}

func (d *Daemon) containerSpec(id, role, token string, spec harnessSpec) ContainerSpec {
	return ContainerSpec{
		Name:  "sshido-agent-" + id,
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
			"sshido-auth-" + strings.TrimPrefix(spec.stateDir, "."): "/home/agent/" + spec.stateDir,
			loginsVolume: loginsDir,
		},
		Binds:   d.cfg.HostDirs,
		Ports:   []int{desktopPort},
		User:    "agent",
		WorkDir: "/workspace",
	}
}

func (d *Daemon) startContainer(ctx context.Context, name string, cspec ContainerSpec, spec harnessSpec) error {
	if err := d.pods.Create(ctx, cspec); err != nil {
		return fmt.Errorf("create container for %s: %w", name, err)
	}
	if err := d.pods.Start(ctx, cspec.Name); err != nil {
		return fmt.Errorf("start container for %s: %w", name, err)
	}
	chown, err := d.pods.Exec(ctx, cspec.Name, ExecSpec{
		Cmd: []string{"chown", "agent:agent", "/workspace", "/home/agent/" + spec.stateDir, loginsDir}, User: "0",
	})
	if err != nil || chown.ExitCode != 0 {
		return fmt.Errorf("prepare volumes for %s: %v %s", name, err, truncate(string(chown.Stderr), 200))
	}
	return nil
}

func (d *Daemon) createAgent(ctx context.Context, draft Agent) (Agent, error) {
	spec, err := lookupHarness(draft.Harness)
	if err != nil {
		return Agent{}, err
	}
	id := randomHex(4)
	token := randomHex(24)
	cspec := d.containerSpec(id, draft.Role, token, spec)
	if err := d.startContainer(ctx, draft.Name, cspec, spec); err != nil {
		return Agent{}, err
	}
	a, err := d.store.AddAgent(Agent{
		ID: id, ChatID: draft.ChatID, Name: draft.Name, Role: draft.Role, Harness: draft.Harness, Model: draft.Model,
		Status: StatusIdle, Task: draft.Task, Goal: draft.Goal, WorkStatus: draft.WorkStatus,
		Mounts: setupFingerprint(d.cfg.HostDirs), Container: cspec.Name,
	}, token)
	if err != nil {
		return Agent{}, err
	}
	d.writeRecord(a)
	d.publishAgent(a)
	return a, nil
}

func (d *Daemon) recontain(ctx context.Context, a Agent) error {
	spec, err := lookupHarness(a.Harness)
	if err != nil {
		return err
	}
	if err := d.pods.Remove(ctx, a.Container); err != nil {
		return fmt.Errorf("remove old container for %s: %w", a.Name, err)
	}
	token := randomHex(24)
	if err := d.startContainer(ctx, a.Name, d.containerSpec(a.ID, a.Role, token, spec), spec); err != nil {
		return err
	}
	_, err = d.store.Recontain(a.ID, token, setupFingerprint(d.cfg.HostDirs))
	return err
}

func (d *Daemon) orchestrator(ctx context.Context, chatID string) (Agent, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	a, err := d.store.Orchestrator(chatID)
	if errors.Is(err, ErrNotFound) {
		return d.createAgent(ctx, Agent{
			ChatID: chatID, Name: "orchestrator", Role: RoleOrchestrator,
			Harness: d.cfg.OrchestratorHarness, Model: d.cfg.OrchestratorModel,
		})
	}
	if err != nil {
		return Agent{}, err
	}
	if err := d.pods.Start(ctx, a.Container); err != nil {
		return Agent{}, fmt.Errorf("restart orchestrator container: %w", err)
	}
	return a, nil
}

func recordOf(a Agent) Record {
	return Record{Goal: a.Goal, WorkStatus: a.WorkStatus, Verification: a.Verification, Verdict: a.Verdict, VerdictNote: a.VerdictNote}
}

func (d *Daemon) writeRecord(a Agent) {
	if err := writeRecordFiles(d.cfg.WorkspaceDir, a); err != nil {
		log.Printf("record files for %s: %v", a.ID, err)
	}
}

func (d *Daemon) logEntry(a Agent, entry string) {
	if err := appendLogEntry(d.cfg.WorkspaceDir, a.ID, time.Now(), entry); err != nil {
		log.Printf("%v", err)
	}
}

func (d *Daemon) saveRecord(a Agent, r Record, entry string) (Agent, error) {
	updated, err := d.store.SetRecord(a.ID, r)
	if err != nil {
		return Agent{}, err
	}
	d.writeRecord(updated)
	d.logEntry(updated, entry)
	d.publishAgent(updated)
	return updated, nil
}

func newWork(a Agent) Record {
	return Record{Goal: a.Goal, WorkStatus: WorkInProgress}
}

func (d *Daemon) recordPrompt(a Agent) string {
	full, err := readLog(d.cfg.WorkspaceDir, a.ID)
	if err != nil {
		log.Printf("%v", err)
	}
	return recordBrief(a, logTail(full, logTailBytes))
}

func (d *Daemon) serial(key string, job func()) bool {
	fresh := make(chan func(), 64)
	actual, loaded := d.queues.LoadOrStore(key, fresh)
	queue := actual.(chan func())
	if !loaded {
		go drain(queue)
	}
	d.inflight.Add(1)
	tracked := func() {
		defer d.inflight.Done()
		job()
	}
	select {
	case queue <- tracked:
		return true
	default:
		d.inflight.Done()
		log.Printf("queue %s is full; dropping a job", key)
		return false
	}
}

func drain(queue chan func()) {
	for job := range queue {
		job()
	}
}

func (d *Daemon) enqueue(a Agent, prompt string) {
	if !d.serial(a.ID, func() { d.runTurn(a.ID, prompt) }) {
		d.post(a.ChatID, a.ID, a.Name, KindError, "Too many queued messages for this agent; one was dropped.")
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
	text, err := d.turnWithRetry(ctx, a, prompt)
	if err != nil {
		d.turnFailed(ctx, a, err)
		return
	}
	d.turnDone(ctx, a, text)
}

const retryPrompt = "Your previous turn was cut off by a connection error before it finished. " +
	"Read your work record and continue where you left off."

var transientMarkers = []string{
	"stream disconnected", "stream closed", "connection reset", "connection refused",
	"broken pipe", "timed out", "unexpected eof",
}

func isTransient(err error) bool {
	msg := strings.ToLower(err.Error())
	for _, marker := range transientMarkers {
		if strings.Contains(msg, marker) {
			return true
		}
	}
	return false
}

func (d *Daemon) turnWithRetry(ctx context.Context, a Agent, prompt string) (string, error) {
	text, err := d.turn(ctx, a, prompt)
	if err == nil || !isTransient(err) || ctx.Err() != nil {
		return text, err
	}
	log.Printf("turn for %s (%s) dropped; retrying once: %v", a.Name, a.ID, err)
	d.logEntry(a, "Turn dropped by a connection error; retrying once: "+err.Error())
	d.post(a.ChatID, a.ID, a.Name, KindProgress, "The connection to the model dropped. Retrying.")
	return d.turn(ctx, d.fresh(a), retryPrompt)
}

func (d *Daemon) turn(ctx context.Context, a Agent, prompt string) (string, error) {
	d.setStatus(a.ID, StatusWorking)
	result, err := d.execTurn(ctx, a, prompt)
	if err != nil {
		log.Printf("turn for %s (%s) failed: %v", a.Name, a.ID, err)
		d.setStatus(a.ID, StatusFailed)
		return "", err
	}
	if err := d.store.SetSession(a.ID, result.Session); err != nil {
		log.Printf("save session for %s: %v", a.ID, err)
	}
	d.setStatus(a.ID, StatusIdle)
	return result.Text, nil
}

func (d *Daemon) execTurn(ctx context.Context, a Agent, prompt string) (TurnResult, error) {
	spec, err := lookupHarness(a.Harness)
	if err != nil {
		return TurnResult{}, err
	}
	text, err := d.promptFor(a, prompt)
	if err != nil {
		return TurnResult{}, err
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
		log.Printf("turn output for %s (%s), exit %d\nstderr:\n%s\nstdout tail:\n%s",
			a.Name, a.ID, res.ExitCode, tail(string(res.Stderr), 4000), tail(string(res.Stdout), 2000))
		return TurnResult{}, fmt.Errorf("%w (exit %d, stderr: %s)", err, res.ExitCode, truncate(strings.TrimSpace(string(res.Stderr)), 300))
	}
	return parsed, nil
}

const promptSeparator = "\n\n---\n\n"

func tail(s string, n int) string {
	trimmed := strings.TrimSpace(s)
	if len(trimmed) <= n {
		return trimmed
	}
	return "…" + strings.ToValidUTF8(trimmed[len(trimmed)-n:], "")
}

func (d *Daemon) promptFor(a Agent, prompt string) (string, error) {
	withRecord := d.recordPrompt(a) + promptSeparator + prompt
	current := setupFingerprint(d.cfg.HostDirs)
	if a.Session != "" && a.Briefed == current {
		return withRecord, nil
	}
	if err := d.store.SetBriefed(a.ID, current); err != nil {
		return "", err
	}
	if a.Session != "" {
		return environmentChanged(d.cfg.HostDirs) + promptSeparator + withRecord, nil
	}
	return firstTurnPrompt(a, withRecord, orchestratorPrompt(d.cfg.Workers), d.cfg.HostDirs), nil
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
	d.logEntry(a, "Turn finished. Reply:\n\n"+truncate(text, 2000))
	if a.Role == RoleOrchestrator {
		d.post(a.ChatID, a.ID, a.Name, KindReply, text)
		d.notify(ctx, d.chatTitle(a.ChatID)+" replied", text, false)
		return
	}
	d.post(a.ChatID, a.ID, a.Name, KindDone, text)
	d.relayToOrchestrator(ctx, a.ChatID, workerFinishedPrompt(d.fresh(a), text))
}

func (d *Daemon) turnFailed(ctx context.Context, a Agent, err error) {
	d.logEntry(a, "Turn failed: "+err.Error())
	d.post(a.ChatID, a.ID, a.Name, KindError, err.Error())
	if a.Role == RoleOrchestrator {
		d.notify(ctx, d.chatTitle(a.ChatID)+" error", err.Error(), true)
		return
	}
	d.relayToOrchestrator(ctx, a.ChatID, workerFailedPrompt(d.fresh(a), err.Error()))
}

func (d *Daemon) fresh(a Agent) Agent {
	current, err := d.store.Agent(a.ID)
	if err != nil {
		log.Printf("reload agent %s: %v", a.ID, err)
		return a
	}
	return current
}

func (d *Daemon) relayToOrchestrator(ctx context.Context, chatID, prompt string) {
	orch, err := d.orchestrator(ctx, chatID)
	if err != nil {
		log.Printf("cannot reach orchestrator of chat %s to relay a subagent result: %v", chatID, err)
		d.post(chatID, "", "sshido", KindError, "The orchestrator could not be started: "+err.Error())
		return
	}
	d.enqueue(orch, prompt)
}

func (d *Daemon) HandleUserMessage(ctx context.Context, chatID, text string) error {
	if strings.TrimSpace(text) == "" {
		return errors.New("empty message")
	}
	chat, err := d.store.Chat(chatID)
	if err != nil {
		return fmt.Errorf("chat %q: %w", chatID, err)
	}
	d.post(chat.ID, "", "you", KindUser, text)
	orch, err := d.orchestrator(ctx, chat.ID)
	if err != nil {
		d.post(chat.ID, "", "sshido", KindError, "The orchestrator could not be started: "+err.Error())
		return err
	}
	updated, err := d.saveRecord(orch, newWork(orch), "Request from the person:\n\n"+text)
	if err != nil {
		log.Printf("record the request for %s: %v", orch.ID, err)
		updated = orch
	}
	d.enqueue(updated, text)
	return nil
}

func (d *Daemon) CreateChat(title string) (Chat, error) {
	trimmed := strings.TrimSpace(title)
	if trimmed == "" {
		return Chat{}, errors.New("a chat needs a title")
	}
	c, err := d.store.AddChat(trimmed)
	if err != nil {
		return Chat{}, err
	}
	d.publishChat(c)
	return c, nil
}

func (d *Daemon) DeleteChat(ctx context.Context, id string) error {
	if _, err := d.store.Chat(id); err != nil {
		return err
	}
	agents, err := d.store.ChatAgents(id)
	if err != nil {
		return err
	}
	for _, a := range agents {
		if err := d.pods.Remove(ctx, a.Container); err != nil {
			return fmt.Errorf("remove %s: %w", a.Name, err)
		}
	}
	if err := d.store.DeleteChat(id); err != nil {
		return err
	}
	for _, a := range agents {
		if err := os.RemoveAll(filepath.Join(d.cfg.WorkspaceDir, recordRoot, a.ID)); err != nil {
			log.Printf("remove the record of %s: %v", a.ID, err)
		}
	}
	d.hub.Publish(AppEvent{Type: EventChatRemoved, ChatID: id})
	return nil
}

func (d *Daemon) SignedIn(ctx context.Context, id string) error {
	a, err := d.store.Agent(id)
	if err != nil {
		return err
	}
	if a.Status == StatusStopped {
		return fmt.Errorf("%s is stopped", a.Name)
	}
	d.post(a.ChatID, "", "you", KindUser, "Signed in on "+a.Name+"'s desktop.")
	note := d.keepLogins(ctx, a)
	updated, err := d.saveRecord(a, newWork(a), "The person signed in on the desktop.")
	if err != nil {
		log.Printf("record the sign-in for %s: %v", a.ID, err)
		updated = a
	}
	d.enqueue(updated, signedInPrompt+note)
	return nil
}

func (d *Daemon) keepLogins(ctx context.Context, a Agent) string {
	res, err := d.pods.Exec(ctx, a.Container, ExecSpec{Cmd: []string{"browser-logins", "save"}, User: "agent", WorkDir: "/workspace"})
	if err == nil && res.ExitCode == 0 {
		return ""
	}
	detail := truncate(execFailure(res, err), 300)
	log.Printf("keep the browser sign-ins of %s: %s", a.ID, detail)
	d.post(a.ChatID, a.ID, a.Name, KindError, "The sign-in works in this browser, but could not be kept for other agents: "+detail)
	return "\n\nThe sign-in could not be kept for other agents: " + detail
}

func execFailure(res ExecResult, err error) string {
	if err != nil {
		return err.Error()
	}
	return fmt.Sprintf("exit %d: %s", res.ExitCode, strings.TrimSpace(string(res.Stderr)))
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
	d.logEntry(a, "Stopped.")
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
	if a.Role == RoleMember {
		d.retireMember(ctx, a)
		return
	}
	exists, err := d.pods.Exists(ctx, a.Container)
	if err != nil || !exists {
		log.Printf("agent %s container %s is gone (%v); marking stopped", a.ID, a.Container, err)
		d.setStatus(a.ID, StatusStopped)
		return
	}
	d.restartAgent(ctx, a)
	if a.Status != StatusWorking {
		return
	}
	d.setStatus(a.ID, StatusIdle)
	d.post(a.ChatID, a.ID, a.Name, KindError, "This agent's turn was interrupted by a restart. Send it a message to continue.")
}

func (d *Daemon) restartAgent(ctx context.Context, a Agent) {
	if a.Mounts == setupFingerprint(d.cfg.HostDirs) {
		if err := d.pods.Start(ctx, a.Container); err != nil {
			log.Printf("restart agent %s container: %v", a.ID, err)
		}
		return
	}
	log.Printf("agent %s: container setup changed; recreating its container", a.ID)
	if err := d.recontain(ctx, a); err != nil {
		log.Printf("recreate agent %s container: %v", a.ID, err)
		d.setStatus(a.ID, StatusFailed)
		d.post(a.ChatID, a.ID, a.Name, KindError, "Could not set up this agent's container again: "+err.Error())
	}
}

func (d *Daemon) retireMember(ctx context.Context, a Agent) {
	if err := d.pods.Stop(ctx, a.Container); err != nil {
		log.Printf("stop group member %s: %v", a.ID, err)
	}
	d.setStatus(a.ID, StatusStopped)
	d.post(a.ChatID, a.ID, a.Name, KindProgress,
		"Group chats are now led by an orchestrator, so "+a.Name+" was stopped. Send a message to continue with the orchestrator.")
}
