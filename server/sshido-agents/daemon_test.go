package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakePods struct {
	mu      sync.Mutex
	created []ContainerSpec
	started map[string]int
	stopped map[string]bool
	prompts map[string][]string
	replies map[string][]string
	missing map[string]bool
	removed []string
}

func newFakePods() *fakePods {
	return &fakePods{
		started: map[string]int{}, stopped: map[string]bool{}, prompts: map[string][]string{},
		replies: map[string][]string{}, missing: map[string]bool{},
	}
}

func (f *fakePods) Create(_ context.Context, spec ContainerSpec) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.created = append(f.created, spec)
	return nil
}

func (f *fakePods) Start(_ context.Context, name string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.started[name]++
	return nil
}

func (f *fakePods) Stop(_ context.Context, name string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.stopped[name] = true
	return nil
}

func (f *fakePods) Remove(_ context.Context, name string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.removed = append(f.removed, name)
	return nil
}

func (f *fakePods) Exists(_ context.Context, name string) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return !f.missing[name], nil
}

func (f *fakePods) script(container string, replies ...string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.replies[container] = append(f.replies[container], replies...)
}

func (f *fakePods) Exec(_ context.Context, name string, spec ExecSpec) (ExecResult, error) {
	if spec.Cmd[0] == "chown" {
		return ExecResult{}, nil
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	f.prompts[name] = append(f.prompts[name], spec.Cmd[2])
	queue := f.replies[name]
	if len(queue) == 0 {
		return ExecResult{Stdout: claudeReply("default reply", name)}, nil
	}
	f.replies[name] = queue[1:]
	if queue[0] == "!fail" {
		return ExecResult{Stdout: []byte(`{"type":"result","subtype":"error_during_execution","is_error":true,"result":"boom"}`), ExitCode: 1}, nil
	}
	return ExecResult{Stdout: claudeReply(queue[0], name)}, nil
}

func claudeReply(text, session string) []byte {
	out, _ := json.Marshal(map[string]any{"type": "result", "subtype": "success", "is_error": false, "result": text, "session_id": "sess-" + session})
	return out
}

type fakePush struct {
	mu    sync.Mutex
	sends []string
}

func (p *fakePush) Push(_ context.Context, title, body string, high bool) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.sends = append(p.sends, fmt.Sprintf("%s|%v|%s", title, high, body))
	return nil
}

func (p *fakePush) all() []string {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]string{}, p.sends...)
}

func testDaemon(t *testing.T) (*Daemon, *fakePods, *fakePush) {
	t.Helper()
	dir := t.TempDir()
	store, err := openStore(filepath.Join(dir, "agents.db"), time.Now)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	cfg := Config{
		DataDir: dir, BusDir: dir, AgentImage: "img", OrchestratorHarness: HarnessClaude,
		Workers:         WorkerChoice{Mode: ChoiceFixed, Harness: HarnessClaude},
		WorkspaceVolume: "ws", WorkspaceDir: filepath.Join(dir, "workspace"), BusVolume: "bus", TurnTimeout: time.Minute,
	}
	if err := os.MkdirAll(cfg.WorkspaceDir, 0o755); err != nil {
		t.Fatal(err)
	}
	pods, push := newFakePods(), &fakePush{}
	if _, err := store.AddChat(firstChatTitle); err != nil {
		t.Fatal(err)
	}
	d := newDaemon(cfg, store, pods, push)
	t.Cleanup(func() { waitIdleDaemon(t, d) })
	return d, pods, push
}

func waitIdleDaemon(t *testing.T, d *Daemon) {
	t.Helper()
	done := make(chan struct{})
	go func() {
		d.inflight.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Error("agent turns still running after the test")
	}
}

func firstChat(t *testing.T, d *Daemon) string {
	t.Helper()
	chats, err := d.store.Chats()
	if err != nil || len(chats) == 0 {
		t.Fatalf("no chat: %v", err)
	}
	return chats[0].ID
}

func waitFor(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

func messagesOfKind(t *testing.T, d *Daemon, kind string) []Message {
	t.Helper()
	all, err := d.store.MessagesSince(0)
	if err != nil {
		t.Fatal(err)
	}
	var out []Message
	for _, m := range all {
		if m.Kind == kind {
			out = append(out, m)
		}
	}
	return out
}

func tokenOf(t *testing.T, pods *fakePods, role string) (string, string) {
	t.Helper()
	pods.mu.Lock()
	defer pods.mu.Unlock()
	for _, c := range pods.created {
		if c.Labels["sshido.agent.role"] == role {
			return c.Env["SSHIDO_AGENT_TOKEN"], c.Name
		}
	}
	t.Fatalf("no %s container created", role)
	return "", ""
}

func TestUserMessageGetsOrchestratorReply(t *testing.T) {
	d, pods, push := testDaemon(t)
	if err := d.HandleUserMessage(context.Background(), firstChat(t, d), "build me a thing"); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "orchestrator reply", func() bool { return len(messagesOfKind(t, d, KindReply)) == 1 })

	_, container := tokenOf(t, pods, RoleOrchestrator)
	pods.mu.Lock()
	prompt := pods.prompts[container][0]
	pods.mu.Unlock()
	if !strings.Contains(prompt, "You are the orchestrator") || !strings.HasSuffix(prompt, "build me a thing") {
		t.Fatalf("first turn should carry the brief and the message, got %q", truncate(prompt, 120))
	}
	orch, _ := d.store.Orchestrator(firstChat(t, d))
	if orch.Session != "sess-"+container || orch.Status != StatusIdle {
		t.Fatalf("orchestrator not idle with a session: %+v", orch)
	}
	if got := push.all(); len(got) != 1 || !strings.HasPrefix(got[0], "Agents replied|false|") {
		t.Fatalf("want one normal push, got %v", got)
	}

	if err := d.HandleUserMessage(context.Background(), firstChat(t, d), "and another"); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "second reply", func() bool { return len(messagesOfKind(t, d, KindReply)) == 2 })
	pods.mu.Lock()
	second := pods.prompts[container][1]
	pods.mu.Unlock()
	if !strings.HasPrefix(second, "Your work record") || !strings.Contains(second, "Request from the person:\n\nand another") ||
		!strings.HasSuffix(second, promptSeparator+"and another") || strings.Contains(second, "You are the orchestrator") {
		t.Fatalf("resumed turns should send the record and the message, got %q", second)
	}
	if len(pods.created) != 1 {
		t.Fatalf("orchestrator container should be reused, created %d", len(pods.created))
	}
}

func TestSpawnedWorkerReportsBackToOrchestrator(t *testing.T) {
	d, pods, _ := testDaemon(t)
	if err := d.HandleUserMessage(context.Background(), firstChat(t, d), "start"); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "orchestrator", func() bool { return len(messagesOfKind(t, d, KindReply)) == 1 })
	token, orchContainer := tokenOf(t, pods, RoleOrchestrator)

	resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: token, Op: BusSpawn, Name: "tests", Goal: "tests pass", Task: "write the tests"}))
	if !resp.OK || resp.AgentID == "" {
		t.Fatalf("spawn failed: %+v", resp)
	}
	waitFor(t, "worker done", func() bool { return len(messagesOfKind(t, d, KindDone)) == 1 })
	waitFor(t, "orchestrator follow-up", func() bool { return len(messagesOfKind(t, d, KindReply)) == 2 })

	pods.mu.Lock()
	followUp := pods.prompts[orchContainer][1]
	pods.mu.Unlock()
	if !strings.Contains(followUp, `Subagent "tests"`) || !strings.Contains(followUp, "default reply") ||
		!strings.Contains(followUp, "Goal: tests pass") || !strings.Contains(followUp, "agentctl verdict --to "+resp.AgentID) {
		t.Fatalf("orchestrator should get the worker's report, got %q", truncate(followUp, 200))
	}
	worker, err := d.store.Agent(resp.AgentID)
	if err != nil || worker.Role != RoleWorker || worker.Task != "write the tests" {
		t.Fatalf("worker not recorded: %+v %v", worker, err)
	}
}

func TestBusDeniesBadTokenAndWorkerSpawn(t *testing.T) {
	d, pods, _ := testDaemon(t)
	if resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: "nope", Op: BusList})); resp.OK {
		t.Fatal("unknown token must be denied")
	}
	if resp := d.handleBus(context.Background(), []byte("{not json")); resp.OK {
		t.Fatal("malformed request must be denied")
	}
	if _, err := d.orchestrator(context.Background(), firstChat(t, d)); err != nil {
		t.Fatal(err)
	}
	orchToken, _ := tokenOf(t, pods, RoleOrchestrator)
	if resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: orchToken, Op: BusSpawn, Name: "w", Task: "t"})); resp.OK {
		t.Fatal("spawn without a goal must be denied")
	}
	spawned := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: orchToken, Op: BusSpawn, Name: "w", Goal: "g", Task: "t"}))
	if !spawned.OK {
		t.Fatalf("orchestrator spawn failed: %+v", spawned)
	}
	workerToken, _ := tokenOf(t, pods, RoleWorker)
	if resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: workerToken, Op: BusSpawn, Name: "x", Goal: "g", Task: "t"})); resp.OK {
		t.Fatal("a worker must not spawn agents")
	}
	if resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: workerToken, Op: BusSend, To: spawned.AgentID, Text: "hi"})); resp.OK {
		t.Fatal("a worker must not message agents")
	}
	if resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: workerToken, Op: BusReport, Kind: "done", Text: "x"})); resp.OK {
		t.Fatal("report kinds other than progress and needs_input must be denied")
	}
}

func TestNeedsInputReportPushesHigh(t *testing.T) {
	d, pods, push := testDaemon(t)
	if _, err := d.orchestrator(context.Background(), firstChat(t, d)); err != nil {
		t.Fatal(err)
	}
	token, _ := tokenOf(t, pods, RoleOrchestrator)
	resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: token, Op: BusReport, Kind: KindNeedsInput, Text: "which database?"}))
	if !resp.OK {
		t.Fatalf("report failed: %+v", resp)
	}
	if len(messagesOfKind(t, d, KindNeedsInput)) != 1 {
		t.Fatal("needs-input message not recorded")
	}
	if got := push.all(); len(got) != 1 || !strings.Contains(got[0], "|true|which database?") {
		t.Fatalf("want one high push, got %v", got)
	}
}

func TestFailedTurnIsReported(t *testing.T) {
	d, pods, push := testDaemon(t)
	orch, err := d.orchestrator(context.Background(), firstChat(t, d))
	if err != nil {
		t.Fatal(err)
	}
	pods.script(orch.Container, "!fail")
	if err := d.HandleUserMessage(context.Background(), firstChat(t, d), "go"); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "error message", func() bool { return len(messagesOfKind(t, d, KindError)) == 1 })
	a, _ := d.store.Agent(orch.ID)
	if a.Status != StatusFailed {
		t.Fatalf("status %q, want failed", a.Status)
	}
	waitFor(t, "error push", func() bool { return len(push.all()) == 1 })
	if !strings.HasPrefix(push.all()[0], "Agents error|true|") {
		t.Fatalf("want a high error push, got %v", push.all())
	}
}

func TestRecoverMarksInterruptedTurns(t *testing.T) {
	d, pods, _ := testDaemon(t)
	orch, err := d.orchestrator(context.Background(), firstChat(t, d))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := d.store.SetStatus(orch.ID, StatusWorking); err != nil {
		t.Fatal(err)
	}
	if err := d.Recover(context.Background()); err != nil {
		t.Fatal(err)
	}
	a, _ := d.store.Agent(orch.ID)
	if a.Status != StatusIdle || len(messagesOfKind(t, d, KindError)) != 1 {
		t.Fatalf("interrupted turn not recovered: %+v", a)
	}
	pods.missing[orch.Container] = true
	if err := d.Recover(context.Background()); err != nil {
		t.Fatal(err)
	}
	if a, _ := d.store.Agent(orch.ID); a.Status != StatusStopped {
		t.Fatalf("agent without a container should be stopped, got %q", a.Status)
	}
}

func TestAppHelloReplaysSince(t *testing.T) {
	d, _, _ := testDaemon(t)
	d.post(firstChat(t, d), "", "you", KindUser, "first")
	d.post(firstChat(t, d), "", "you", KindUser, "second")
	out := make(chan AppEvent, 16)
	d.appHello(1, out)
	close(out)
	var got []string
	for ev := range out {
		if ev.Type == EventMessage {
			got = append(got, ev.Message.Text)
		}
		if ev.Type == EventReady {
			got = append(got, "ready")
		}
	}
	if strings.Join(got, ",") != "second,ready" {
		t.Fatalf("replay since 1 = %v", got)
	}
}

func mustJSON(t *testing.T, v any) []byte {
	t.Helper()
	out, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return out
}
