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
	PickerModel         string
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
		WorkerHarness:       env("SSHIDO_WORKER_HARNESS", orchestrator),
		WorkerModel:         env("SSHIDO_WORKER_MODEL", ""),
		LocalURL:            env("SSHIDO_LOCAL_URL", ""),
		PickerModel:         env("SSHIDO_PICKER_MODEL", ""),
		NotifyURL:           env("SSHIDO_NOTIFY_URL", ""),
		WorkspaceVolume:     env("SSHIDO_WORKSPACE_VOLUME", "sshido-agents-workspace"),
		WorkspaceDir:        env("SSHIDO_WORKSPACE_DIR", "/workspace"),
		BusVolume:           env("SSHIDO_BUS_VOLUME", "sshido-agents-bus"),
		HostName:            env("SSHIDO_HOST_NAME", "agents"),
		HostDirs:            hostDirs,
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
	picker Picker
	queues sync.Map
	mu     sync.Mutex
}

func newDaemon(cfg Config, store *Store, pods Containers, push Pusher, picker Picker) *Daemon {
	return &Daemon{cfg: cfg, store: store, pods: pods, hub: newHub(), push: push, picker: picker}
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

func (d *Daemon) setChatStatus(id, status string) {
	c, err := d.store.SetChatStatus(id, status)
	if err != nil {
		log.Printf("set chat status %s=%s failed: %v", id, status, err)
		return
	}
	d.publishChat(c)
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
		},
		Binds:   d.cfg.HostDirs,
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
		Cmd: []string{"chown", "agent:agent", "/workspace", "/home/agent/" + spec.stateDir}, User: "0",
	})
	if err != nil || chown.ExitCode != 0 {
		return fmt.Errorf("prepare volumes for %s: %v %s", name, err, truncate(string(chown.Stderr), 200))
	}
	return nil
}

func (d *Daemon) createAgent(ctx context.Context, chatID, name, role, harness, model, task string) (Agent, error) {
	spec, err := lookupHarness(harness)
	if err != nil {
		return Agent{}, err
	}
	id := randomHex(4)
	token := randomHex(24)
	cspec := d.containerSpec(id, role, token, spec)
	if err := d.startContainer(ctx, name, cspec, spec); err != nil {
		return Agent{}, err
	}
	a, err := d.store.AddAgent(Agent{
		ID: id, ChatID: chatID, Name: name, Role: role, Harness: harness, Model: model,
		Status: StatusIdle, Task: task, Mounts: mountsFingerprint(d.cfg.HostDirs), Container: cspec.Name,
	}, token)
	if err != nil {
		return Agent{}, err
	}
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
	_, err = d.store.Recontain(a.ID, token, mountsFingerprint(d.cfg.HostDirs))
	return err
}

func (d *Daemon) orchestrator(ctx context.Context, chatID string) (Agent, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	a, err := d.store.Orchestrator(chatID)
	if errors.Is(err, ErrNotFound) {
		return d.createAgent(ctx, chatID, "orchestrator", RoleOrchestrator, d.cfg.OrchestratorHarness, d.cfg.OrchestratorModel, "")
	}
	if err != nil {
		return Agent{}, err
	}
	if err := d.pods.Start(ctx, a.Container); err != nil {
		return Agent{}, fmt.Errorf("restart orchestrator container: %w", err)
	}
	return a, nil
}

func (d *Daemon) serial(key string, job func()) bool {
	fresh := make(chan func(), 64)
	actual, loaded := d.queues.LoadOrStore(key, fresh)
	queue := actual.(chan func())
	if !loaded {
		go drain(queue)
	}
	select {
	case queue <- job:
		return true
	default:
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
	text, err := d.turn(ctx, a, prompt)
	if err != nil {
		d.turnFailed(ctx, a, err)
		return
	}
	d.turnDone(ctx, a, text)
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

func (d *Daemon) firstPrompt(a Agent, prompt string) (string, error) {
	if a.Role != RoleMember {
		return firstTurnPrompt(a, prompt, d.cfg.HostDirs, nil), nil
	}
	members, err := d.store.ChatAgents(a.ChatID)
	if err != nil {
		return "", err
	}
	return firstTurnPrompt(a, prompt, d.cfg.HostDirs, members), nil
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
		return TurnResult{}, fmt.Errorf("%w (exit %d, stderr: %s)", err, res.ExitCode, truncate(strings.TrimSpace(string(res.Stderr)), 300))
	}
	return parsed, nil
}

func (d *Daemon) promptFor(a Agent, prompt string) (string, error) {
	current := mountsFingerprint(d.cfg.HostDirs)
	if a.Session != "" && a.Briefed == current {
		return prompt, nil
	}
	if err := d.store.SetBriefed(a.ID, current); err != nil {
		return "", err
	}
	if a.Session != "" {
		return hostDirsChanged(d.cfg.HostDirs) + "\n\n---\n\n" + prompt, nil
	}
	return d.firstPrompt(a, prompt)
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
		d.post(a.ChatID, a.ID, a.Name, KindReply, text)
		d.notify(ctx, d.chatTitle(a.ChatID)+" replied", text, false)
		return
	}
	d.post(a.ChatID, a.ID, a.Name, KindDone, text)
	d.relayToOrchestrator(ctx, a.ChatID, workerFinishedPrompt(a.Name, a.ID, text))
}

func (d *Daemon) turnFailed(ctx context.Context, a Agent, err error) {
	d.post(a.ChatID, a.ID, a.Name, KindError, err.Error())
	if a.Role == RoleOrchestrator {
		d.notify(ctx, d.chatTitle(a.ChatID)+" error", err.Error(), true)
		return
	}
	d.relayToOrchestrator(ctx, a.ChatID, workerFailedPrompt(a.Name, a.ID, err.Error()))
}

func (d *Daemon) relayToOrchestrator(ctx context.Context, chatID, prompt string) {
	orch, err := d.orchestrator(ctx, chatID)
	if err != nil {
		log.Printf("cannot reach orchestrator of chat %s to relay a worker result: %v", chatID, err)
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
	if chat.Kind == ChatGroup {
		d.startRound(chat)
		return nil
	}
	orch, err := d.orchestrator(ctx, chat.ID)
	if err != nil {
		d.post(chat.ID, "", "sshido", KindError, "The orchestrator could not be started: "+err.Error())
		return err
	}
	d.enqueue(orch, text)
	return nil
}

func (d *Daemon) startRound(chat Chat) {
	if d.serial("chat:"+chat.ID, func() { d.runRound(chat.ID) }) {
		return
	}
	d.post(chat.ID, "", "sshido", KindError, "Too many queued messages for this chat; one was dropped.")
}

const (
	defaultTurnCap = 6
	maxTurnCap     = 50
	maxMembers     = 12
)

func turnCapOf(requested int) (int, error) {
	if requested == 0 {
		return defaultTurnCap, nil
	}
	if requested < 1 || requested > maxTurnCap {
		return 0, fmt.Errorf("turn limit must be between 1 and %d", maxTurnCap)
	}
	return requested, nil
}

func (d *Daemon) validMembers(members []MemberSpec) ([]MemberSpec, error) {
	if len(members) < 2 || len(members) > maxMembers {
		return nil, fmt.Errorf("a group chat needs 2 to %d members, got %d", maxMembers, len(members))
	}
	out := make([]MemberSpec, 0, len(members))
	for _, m := range members {
		member, err := d.validMember(m, out)
		if err != nil {
			return nil, err
		}
		out = append(out, member)
	}
	return out, nil
}

func (d *Daemon) validMember(m MemberSpec, taken []MemberSpec) (MemberSpec, error) {
	name := strings.TrimSpace(m.Name)
	if name == "" {
		return MemberSpec{}, errors.New("every member needs a name")
	}
	if nameTaken(name, taken) {
		return MemberSpec{}, fmt.Errorf("two members are named %q", name)
	}
	harness := firstNonEmpty(m.Harness, d.cfg.WorkerHarness)
	if _, err := lookupHarness(harness); err != nil {
		return MemberSpec{}, err
	}
	model := strings.TrimSpace(m.Model)
	if harness == d.cfg.WorkerHarness && model == "" {
		model = d.cfg.WorkerModel
	}
	return MemberSpec{Name: name, Harness: harness, Model: model}, nil
}

func nameTaken(name string, taken []MemberSpec) bool {
	for _, t := range taken {
		if strings.EqualFold(t.Name, name) {
			return true
		}
	}
	return false
}

func (d *Daemon) CreateChat(ctx context.Context, req AppRequest) (Chat, error) {
	title := strings.TrimSpace(req.Title)
	if title == "" {
		return Chat{}, errors.New("a chat needs a title")
	}
	if req.Kind != ChatOrchestrated && req.Kind != ChatGroup {
		return Chat{}, fmt.Errorf("chat kind must be %q or %q", ChatOrchestrated, ChatGroup)
	}
	if req.Kind == ChatOrchestrated {
		return d.createOrchestratedChat(title)
	}
	if _, isNone := d.picker.(noPicker); isNone {
		return Chat{}, ErrNoPicker
	}
	members, err := d.validMembers(req.Members)
	if err != nil {
		return Chat{}, err
	}
	turnCap, err := turnCapOf(req.TurnCap)
	if err != nil {
		return Chat{}, err
	}
	c, err := d.store.AddChat(title, ChatGroup, turnCap)
	if err != nil {
		return Chat{}, err
	}
	for _, m := range members {
		d.addMember(ctx, c, m)
	}
	d.publishChat(c)
	return c, nil
}

func (d *Daemon) createOrchestratedChat(title string) (Chat, error) {
	c, err := d.store.AddChat(title, ChatOrchestrated, 0)
	if err != nil {
		return Chat{}, err
	}
	d.publishChat(c)
	return c, nil
}

func (d *Daemon) addMember(ctx context.Context, c Chat, m MemberSpec) {
	if _, err := d.createAgent(ctx, c.ID, m.Name, RoleMember, m.Harness, m.Model, ""); err != nil {
		log.Printf("create member %q of chat %s: %v", m.Name, c.ID, err)
		d.post(c.ID, "", "sshido", KindError, fmt.Sprintf("Could not start %s: %v", m.Name, err))
	}
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
	d.hub.Publish(AppEvent{Type: EventChatRemoved, ChatID: id})
	return nil
}

func (d *Daemon) runRound(chatID string) {
	chat, err := d.store.Chat(chatID)
	if err != nil {
		log.Printf("round for chat %s skipped: %v", chatID, err)
		return
	}
	d.endRound(chat, d.takeTurns(chat, 0, ""))
}

func (d *Daemon) takeTurns(chat Chat, turn int, last string) string {
	if turn >= chat.TurnCap {
		d.post(chat.ID, "", "sshido", KindProgress, fmt.Sprintf("Turn limit reached (%d turns). Your turn.", chat.TurnCap))
		return last
	}
	reply, more := d.roundStep(chat, turn > 0)
	if !more {
		return firstNonEmpty(reply, last)
	}
	return d.takeTurns(chat, turn+1, firstNonEmpty(reply, last))
}

func (d *Daemon) endRound(chat Chat, last string) {
	d.setChatStatus(chat.ID, ChatIdle)
	if last == "" {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	d.notify(ctx, chat.Title+" replied", last, false)
}

func activeMembers(agents []Agent) []Agent {
	out := []Agent{}
	for _, a := range agents {
		if a.Role != RoleMember || a.Status == StatusStopped {
			continue
		}
		out = append(out, a)
	}
	return out
}

func (d *Daemon) roundStep(chat Chat, handBack bool) (string, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), d.cfg.TurnTimeout)
	defer cancel()
	agents, err := d.store.ChatAgents(chat.ID)
	if err != nil {
		log.Printf("round for chat %s: %v", chat.ID, err)
		return "", false
	}
	members := activeMembers(agents)
	if len(members) == 0 {
		d.post(chat.ID, "", "sshido", KindError, "No members are running in this chat.")
		return "", false
	}
	history, err := d.store.ChatMessagesAfter(chat.ID, 0)
	if err != nil {
		log.Printf("round for chat %s: %v", chat.ID, err)
		return "", false
	}
	d.setChatStatus(chat.ID, ChatPicking)
	pick, err := d.picker.Pick(ctx, pickerState(chat, members, history), pickerQuestion(handBack), pickerOptions(members, handBack))
	if err != nil {
		log.Printf("picker for chat %s failed: %v", chat.ID, err)
		d.post(chat.ID, "", "sshido", KindError, "The picker could not choose who speaks next: "+err.Error())
		return "", false
	}
	log.Printf("picker for chat %s chose %d of %d, probabilities %v", chat.ID, pick.Index, len(members), pick.Probs)
	if pick.Index >= len(members) {
		return "", false
	}
	d.setChatStatus(chat.ID, ChatWorking)
	return d.memberTurn(ctx, members[pick.Index], history), true
}

func unseenBy(member Agent, history []Message) []Message {
	out := []Message{}
	for _, m := range history {
		if m.ID <= member.Seen || m.AgentID == member.ID {
			continue
		}
		out = append(out, m)
	}
	return out
}

func (d *Daemon) memberTurn(ctx context.Context, member Agent, history []Message) string {
	prompt := memberTurnPrompt(unseenBy(member, history))
	if err := d.store.SetSeen(member.ID, history[len(history)-1].ID); err != nil {
		log.Printf("set seen for %s: %v", member.ID, err)
	}
	text, err := d.turn(ctx, member, prompt)
	if err != nil {
		d.post(member.ChatID, member.ID, member.Name, KindError, err.Error())
		return ""
	}
	d.post(member.ChatID, member.ID, member.Name, KindReply, text)
	return text
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
	chats, err := d.store.Chats()
	if err != nil {
		return err
	}
	for _, c := range chats {
		d.recoverChat(c)
	}
	agents, err := d.store.Agents()
	if err != nil {
		return err
	}
	for _, a := range agents {
		d.recoverAgent(ctx, a)
	}
	return nil
}

func (d *Daemon) recoverChat(c Chat) {
	if c.Status == ChatIdle {
		return
	}
	d.setChatStatus(c.ID, ChatIdle)
	d.post(c.ID, "", "sshido", KindError, "The group's turn was interrupted by a restart. Send a message to continue.")
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
	d.restartAgent(ctx, a)
	if a.Status != StatusWorking {
		return
	}
	d.setStatus(a.ID, StatusIdle)
	d.post(a.ChatID, a.ID, a.Name, KindError, "This agent's turn was interrupted by a restart. Send it a message to continue.")
}

func (d *Daemon) restartAgent(ctx context.Context, a Agent) {
	if a.Mounts == mountsFingerprint(d.cfg.HostDirs) {
		if err := d.pods.Start(ctx, a.Container); err != nil {
			log.Printf("restart agent %s container: %v", a.ID, err)
		}
		return
	}
	log.Printf("agent %s: host folders changed; recreating its container", a.ID)
	if err := d.recontain(ctx, a); err != nil {
		log.Printf("recreate agent %s container: %v", a.ID, err)
		d.setStatus(a.ID, StatusFailed)
		d.post(a.ChatID, a.ID, a.Name, KindError, "Could not apply the new host folders to this agent: "+err.Error())
	}
}
