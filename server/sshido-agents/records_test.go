package main

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func spawnWorker(t *testing.T, d *Daemon, orchToken, name string) string {
	t.Helper()
	resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: orchToken, Op: BusSpawn, Name: name, Goal: "hello.txt says hi", Task: "write hello.txt"}))
	if !resp.OK {
		t.Fatalf("spawn %s: %+v", name, resp)
	}
	return resp.AgentID
}

func workerToken(t *testing.T, pods *fakePods, id string) string {
	t.Helper()
	pods.mu.Lock()
	defer pods.mu.Unlock()
	for _, c := range pods.created {
		if c.Labels["sshido.agent.id"] == id {
			return c.Env["SSHIDO_AGENT_TOKEN"]
		}
	}
	t.Fatalf("no container for %s", id)
	return ""
}

func readRecordFile(t *testing.T, d *Daemon, id, name string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(d.cfg.WorkspaceDir, recordRoot, id, name))
	if err != nil {
		t.Fatal(err)
	}
	return strings.TrimSpace(string(data))
}

func orchestratorToken(t *testing.T, d *Daemon, pods *fakePods) string {
	t.Helper()
	if _, err := d.orchestrator(context.Background(), firstChat(t, d)); err != nil {
		t.Fatal(err)
	}
	token, _ := tokenOf(t, pods, RoleOrchestrator)
	return token
}

func bus(t *testing.T, d *Daemon, req BusRequest) BusResponse {
	t.Helper()
	return d.handleBus(context.Background(), mustJSON(t, req))
}

func TestWorkerRecordAndOrchestratorVerdict(t *testing.T) {
	d, pods, _ := testDaemon(t)
	orchToken := orchestratorToken(t, d, pods)
	id := spawnWorker(t, d, orchToken, "writer")
	waitFor(t, "worker turn", func() bool { return len(messagesOfKind(t, d, KindDone)) == 1 })
	token := workerToken(t, pods, id)

	if got := readRecordFile(t, d, id, "goal.md"); got != "hello.txt says hi" {
		t.Fatalf("goal.md = %q", got)
	}
	if got := readRecordFile(t, d, id, "status.md"); got != WorkInProgress {
		t.Fatalf("status.md = %q", got)
	}
	if !strings.Contains(readRecordFile(t, d, id, logFile), "Spawned by the orchestrator.") {
		t.Fatal("spawn not in the track record")
	}

	if resp := bus(t, d, BusRequest{Token: token, Op: BusStatus, Kind: WorkDone}); resp.OK {
		t.Fatal("done without a verification must be denied")
	}
	if resp := bus(t, d, BusRequest{Token: token, Op: BusStatus, Kind: "finished"}); resp.OK {
		t.Fatal("unknown status must be denied")
	}
	if resp := bus(t, d, BusRequest{Token: token, Op: BusVerify, Text: "  "}); resp.OK {
		t.Fatal("empty verification must be denied")
	}
	for _, req := range []BusRequest{
		{Token: token, Op: BusLog, Text: "wrote hello.txt"},
		{Token: token, Op: BusVerify, Text: "cat hello.txt printed hi"},
		{Token: token, Op: BusStatus, Kind: WorkDone, Text: "all good"},
	} {
		if resp := bus(t, d, req); !resp.OK {
			t.Fatalf("%s: %+v", req.Op, resp)
		}
	}
	if resp := bus(t, d, BusRequest{Token: token, Op: BusVerdict, To: "self", Kind: VerdictPass, Text: "I did well"}); resp.OK {
		t.Fatal("a subagent must not give verdicts")
	}
	if resp := bus(t, d, BusRequest{Token: orchToken, Op: BusVerdict, To: id, Kind: "maybe", Text: "x"}); resp.OK {
		t.Fatal("a verdict other than pass or fail must be denied")
	}
	if resp := bus(t, d, BusRequest{Token: orchToken, Op: BusVerdict, To: id, Kind: VerdictPass}); resp.OK {
		t.Fatal("a verdict without a reason must be denied")
	}
	if resp := bus(t, d, BusRequest{Token: orchToken, Op: BusVerdict, To: id, Kind: VerdictPass, Text: "checked the evidence"}); !resp.OK {
		t.Fatalf("verdict: %+v", resp)
	}

	w, _ := d.store.Agent(id)
	if w.WorkStatus != WorkDone || w.Verification != "cat hello.txt printed hi" || w.Verdict != VerdictPass || w.VerdictNote != "checked the evidence" {
		t.Fatalf("record not stored: %+v", w)
	}
	if got := readRecordFile(t, d, id, "verdict.md"); got != "pass: checked the evidence" {
		t.Fatalf("verdict.md = %q", got)
	}
	logText := readRecordFile(t, d, id, logFile)
	for _, want := range []string{"wrote hello.txt", "Verification:\n\ncat hello.txt printed hi", "Status: done - all good", "Verdict from the orchestrator: pass - checked the evidence", "Turn finished."} {
		if !strings.Contains(logText, want) {
			t.Fatalf("track record lacks %q:\n%s", want, logText)
		}
	}
	progress := messagesOfKind(t, d, KindProgress)
	if last := progress[len(progress)-1]; last.Text != "Verdict for writer: pass. checked the evidence" {
		t.Fatalf("verdict not posted in the chat: %+v", last)
	}
}

func TestPassVerdictNeedsVerificationAndSelfVerdict(t *testing.T) {
	d, pods, _ := testDaemon(t)
	orchToken := orchestratorToken(t, d, pods)
	id := spawnWorker(t, d, orchToken, "writer")
	if resp := bus(t, d, BusRequest{Token: orchToken, Op: BusVerdict, To: id, Kind: VerdictPass, Text: "looks fine"}); resp.OK {
		t.Fatal("pass without the subagent's verification must be denied")
	}
	if resp := bus(t, d, BusRequest{Token: orchToken, Op: BusVerdict, To: id, Kind: VerdictFail, Text: "no evidence"}); !resp.OK {
		t.Fatalf("fail must be allowed without verification: %+v", resp)
	}
	if resp := bus(t, d, BusRequest{Token: orchToken, Op: BusVerify, Text: "opened the page, it shows the list"}); !resp.OK {
		t.Fatalf("orchestrator verify: %+v", resp)
	}
	if resp := bus(t, d, BusRequest{Token: orchToken, Op: BusVerdict, To: "self", Kind: VerdictPass, Text: "meets the request"}); !resp.OK {
		t.Fatalf("self verdict: %+v", resp)
	}
	orch, _ := d.store.Orchestrator(firstChat(t, d))
	if orch.Verdict != VerdictPass {
		t.Fatalf("self verdict not stored: %+v", orch)
	}
}

func TestSendStartsNewWorkAndResumeCarriesRecord(t *testing.T) {
	d, pods, _ := testDaemon(t)
	orchToken := orchestratorToken(t, d, pods)
	id := spawnWorker(t, d, orchToken, "writer")
	waitFor(t, "first turn", func() bool { return len(messagesOfKind(t, d, KindDone)) == 1 })
	token := workerToken(t, pods, id)
	bus(t, d, BusRequest{Token: token, Op: BusVerify, Text: "ran it"})
	bus(t, d, BusRequest{Token: orchToken, Op: BusVerdict, To: id, Kind: VerdictFail, Text: "wrong file name"})

	if resp := bus(t, d, BusRequest{Token: orchToken, Op: BusSend, To: id, Text: "rename it to hi.txt"}); !resp.OK {
		t.Fatalf("send: %+v", resp)
	}
	waitFor(t, "second turn", func() bool { return len(messagesOfKind(t, d, KindDone)) == 2 })
	w, _ := d.store.Agent(id)
	if w.WorkStatus != WorkInProgress || w.Verdict != "" || w.Verification != "" || w.Goal != "hello.txt says hi" {
		t.Fatalf("new work must reset status, verification and verdict and keep the goal: %+v", w)
	}
	pods.mu.Lock()
	prompts := pods.prompts[w.Container]
	pods.mu.Unlock()
	first, second := prompts[0], prompts[1]
	if !strings.Contains(first, "You are a subagent") || !strings.Contains(first, "Goal: hello.txt says hi") || !strings.HasSuffix(first, "Task:\nwrite hello.txt") {
		t.Fatalf("first turn must carry the brief, the record and the task: %q", truncate(first, 300))
	}
	if !strings.HasPrefix(second, "Your work record (kept in "+agentRecordPath(id)+"/)") ||
		!strings.Contains(second, "Verdict from the orchestrator: fail - wrong file name") ||
		!strings.HasSuffix(second, "Message from the orchestrator:\n\nrename it to hi.txt") {
		t.Fatalf("resumed turn must start from the record: %q", second)
	}
}

func TestRecordReadAndStopRules(t *testing.T) {
	d, pods, _ := testDaemon(t)
	orchToken := orchestratorToken(t, d, pods)
	a := spawnWorker(t, d, orchToken, "a")
	b := spawnWorker(t, d, orchToken, "b")
	tokenA := workerToken(t, pods, a)

	if resp := bus(t, d, BusRequest{Token: tokenA, Op: BusRecord, To: b}); resp.OK {
		t.Fatal("a subagent must not read another agent's record")
	}
	own := bus(t, d, BusRequest{Token: tokenA, Op: BusRecord})
	if !own.OK || !strings.Contains(own.Text, "Goal: hello.txt says hi") || !strings.Contains(own.Text, "Spawned by the orchestrator.") {
		t.Fatalf("own record: %+v", own)
	}
	if resp := bus(t, d, BusRequest{Token: orchToken, Op: BusRecord, To: b}); !resp.OK || !strings.Contains(resp.Text, "b ("+b+"), worker on claude") {
		t.Fatalf("orchestrator must read a subagent's record: %+v", resp)
	}
	if resp := bus(t, d, BusRequest{Token: tokenA, Op: BusStop, To: b}); resp.OK {
		t.Fatal("a subagent must not stop agents")
	}
	if resp := bus(t, d, BusRequest{Token: orchToken, Op: BusStop, To: "self"}); resp.OK {
		t.Fatal("the orchestrator must not stop itself")
	}
	if resp := bus(t, d, BusRequest{Token: orchToken, Op: BusStop, To: b}); !resp.OK {
		t.Fatalf("stop: %+v", resp)
	}
	if got, _ := d.store.Agent(b); got.Status != StatusStopped {
		t.Fatalf("b not stopped: %+v", got)
	}
	if resp := bus(t, d, BusRequest{Token: orchToken, Op: BusSend, To: b, Text: "more"}); resp.OK {
		t.Fatal("sending to a stopped subagent must be denied")
	}
}

func TestLiveSubagentLimit(t *testing.T) {
	d, pods, _ := testDaemon(t)
	orchToken := orchestratorToken(t, d, pods)
	ids := []string{}
	for i := 0; i < maxLiveWorkers; i++ {
		ids = append(ids, spawnWorker(t, d, orchToken, "w"))
	}
	over := BusRequest{Token: orchToken, Op: BusSpawn, Name: "one-more", Goal: "g", Task: "t"}
	if resp := bus(t, d, over); resp.OK || !strings.Contains(resp.Error, "agentctl stop") {
		t.Fatalf("spawn over the limit must be denied with a hint: %+v", resp)
	}
	if resp := bus(t, d, BusRequest{Token: orchToken, Op: BusStop, To: ids[0]}); !resp.OK {
		t.Fatal(resp.Error)
	}
	if resp := bus(t, d, over); !resp.OK {
		t.Fatalf("spawn after a stop must work: %+v", resp)
	}
}

func TestUserMessageStartsNewOrchestratorWork(t *testing.T) {
	d, pods, _ := testDaemon(t)
	orchToken := orchestratorToken(t, d, pods)
	bus(t, d, BusRequest{Token: orchToken, Op: BusGoal, Text: "a working todo app"})
	bus(t, d, BusRequest{Token: orchToken, Op: BusVerify, Text: "tests pass"})
	bus(t, d, BusRequest{Token: orchToken, Op: BusVerdict, To: "self", Kind: VerdictPass, Text: "done"})
	if err := d.HandleUserMessage(context.Background(), firstChat(t, d), "now add dark mode"); err != nil {
		t.Fatal(err)
	}
	orch, _ := d.store.Orchestrator(firstChat(t, d))
	if orch.Goal != "a working todo app" || orch.WorkStatus != WorkInProgress || orch.Verdict != "" || orch.Verification != "" {
		t.Fatalf("a new request must reopen the work and keep the goal: %+v", orch)
	}
	if !strings.Contains(readRecordFile(t, d, orch.ID, logFile), "Request from the person:\n\nnow add dark mode") {
		t.Fatal("the request is not in the track record")
	}
}

func TestLogTail(t *testing.T) {
	if got := logTail("## a\n\none\n\n", 100); got != "## a\n\none" {
		t.Fatalf("short log = %q", got)
	}
	long := "## 1\n\n" + strings.Repeat("x", 50) + "\n\n## 2\n\nlast entry\n\n"
	got := logTail(long, 30)
	if got != "[earlier entries are in log.md]\n## 2\n\nlast entry" {
		t.Fatalf("tail = %q", got)
	}
	if got := logTail("한국어"+strings.Repeat("y", 10), 11); !strings.HasPrefix(got, "[earlier entries are in log.md]\n") || !strings.HasSuffix(got, "yyyyyyyyyy") {
		t.Fatalf("tail without a heading must stay valid text: %q", got)
	}
}

func TestRecordFilesRefuseSymlinks(t *testing.T) {
	workspace := t.TempDir()
	outside := t.TempDir()
	if err := os.MkdirAll(filepath.Join(workspace, ".sshido"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(workspace, recordRoot)); err != nil {
		t.Fatal(err)
	}
	if err := writeRecordFiles(workspace, Agent{ID: "abc", Goal: "g"}); err == nil {
		t.Fatal("a records directory that points outside the workspace must be refused")
	}
	if entries, _ := os.ReadDir(filepath.Join(outside, "abc")); len(entries) != 0 {
		t.Fatalf("wrote outside the workspace: %v", entries)
	}

	inside := t.TempDir()
	dir := filepath.Join(inside, recordRoot, "abc")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(outside, "victim")
	if err := os.WriteFile(target, []byte("keep"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filepath.Join(dir, logFile)); err != nil {
		t.Fatal(err)
	}
	if err := appendLogEntry(inside, "abc", time.Now(), "x"); err == nil {
		t.Fatal("a symlinked log file must be refused")
	}
	if data, _ := os.ReadFile(target); string(data) != "keep" {
		t.Fatalf("followed the symlink: %q", data)
	}
}

func TestParseCtlRecordCommands(t *testing.T) {
	cases := []struct {
		args []string
		want BusRequest
	}{
		{[]string{"goal", "a", "working", "app"}, BusRequest{Op: BusGoal, Text: "a working app"}},
		{[]string{"log", "did it"}, BusRequest{Op: BusLog, Text: "did it"}},
		{[]string{"verify", "ran the tests"}, BusRequest{Op: BusVerify, Text: "ran the tests"}},
		{[]string{"status", "done", "all", "good"}, BusRequest{Op: BusStatus, Kind: WorkDone, Text: "all good"}},
		{[]string{"record"}, BusRequest{Op: BusRecord}},
		{[]string{"record", "--to", "ab12"}, BusRequest{Op: BusRecord, To: "ab12"}},
		{[]string{"stop", "--to", "ab12"}, BusRequest{Op: BusStop, To: "ab12"}},
		{[]string{"verdict", "--to", "ab12", "--fail", "no tests"}, BusRequest{Op: BusVerdict, To: "ab12", Kind: VerdictFail, Text: "no tests"}},
		{[]string{"verdict", "--pass", "--to", "self", "met"}, BusRequest{Op: BusVerdict, To: "self", Kind: VerdictPass, Text: "met"}},
		{[]string{"spawn", "--name", "w", "--goal", "g", "--task", "t", "--harness", "local"}, BusRequest{Op: BusSpawn, Name: "w", Goal: "g", Task: "t", Harness: "local"}},
	}
	for _, c := range cases {
		got, err := parseCtl(c.args)
		if err != nil || got != c.want {
			t.Fatalf("%v: got %+v %v, want %+v", c.args, got, err, c.want)
		}
	}
	for _, bad := range [][]string{{"status"}, {"verdict", "--to", "x", "why"}, {"verdict", "--pass", "--fail", "why"}} {
		if _, err := parseCtl(bad); err == nil {
			t.Fatalf("%v must fail", bad)
		}
	}
}
