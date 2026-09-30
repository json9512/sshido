package main

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestOpenStoreMovesOldRowsIntoOneChat(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agents.db")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`
		CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT, agent_id TEXT NOT NULL DEFAULT '', author TEXT NOT NULL, kind TEXT NOT NULL, text TEXT NOT NULL, created_at INTEGER NOT NULL);
		CREATE TABLE agents (id TEXT PRIMARY KEY, name TEXT NOT NULL, role TEXT NOT NULL, harness TEXT NOT NULL, model TEXT NOT NULL DEFAULT '', status TEXT NOT NULL, task TEXT NOT NULL DEFAULT '', session TEXT NOT NULL DEFAULT '', container TEXT NOT NULL, token_hash TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
		INSERT INTO messages (author, kind, text, created_at) VALUES ('you', 'user', 'old message', 1);
		INSERT INTO agents VALUES ('a1', 'orchestrator', 'orchestrator', 'claude', '', 'idle', '', 'sess', 'sshido-agent-a1', 'h', 1, 1);
	`); err != nil {
		t.Fatal(err)
	}
	db.Close()

	for pass := 0; pass < 2; pass++ {
		store, err := openStore(path, time.Now)
		if err != nil {
			t.Fatal(err)
		}
		chats, err := store.Chats()
		if err != nil || len(chats) != 1 || chats[0].Title != "Agents" {
			t.Fatalf("pass %d: want one migrated chat, got %+v %v", pass, chats, err)
		}
		orch, err := store.Orchestrator(chats[0].ID)
		if err != nil || orch.ID != "a1" || orch.Session != "sess" || orch.Goal != "" {
			t.Fatalf("pass %d: orchestrator not moved: %+v %v", pass, orch, err)
		}
		msgs, err := store.ChatMessagesAfter(chats[0].ID, 0)
		if err != nil || len(msgs) != 1 || msgs[0].Text != "old message" {
			t.Fatalf("pass %d: history not moved: %+v %v", pass, msgs, err)
		}
		store.Close()
	}
}

func TestGroupChatMembersAreRetired(t *testing.T) {
	d, pods, _ := testDaemon(t)
	if _, err := d.store.db.Exec(`INSERT INTO chats (id, title, kind, turn_cap, status, created_at) VALUES ('g1', 'haiku', 'group', 6, 'picking', 1)`); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"poet", "critic"} {
		if _, err := d.store.AddAgent(Agent{ID: name, ChatID: "g1", Name: name, Role: RoleMember, Harness: HarnessClaude, Status: StatusIdle, Container: "sshido-agent-" + name}, "tok-"+name); err != nil {
			t.Fatal(err)
		}
	}
	d.post("g1", "", "you", KindUser, "write a haiku")

	for pass := 0; pass < 2; pass++ {
		if err := d.Recover(context.Background()); err != nil {
			t.Fatal(err)
		}
	}
	for _, name := range []string{"poet", "critic"} {
		a, _ := d.store.Agent(name)
		if a.Status != StatusStopped || !pods.stopped["sshido-agent-"+name] {
			t.Fatalf("member %s not stopped: %+v", name, a)
		}
	}
	notes := 0
	for _, m := range messagesOfKind(t, d, KindProgress) {
		if strings.Contains(m.Text, "now led by an orchestrator") {
			notes++
		}
	}
	if notes != 2 {
		t.Fatalf("want one notice per member, once: %d", notes)
	}
	chat, err := d.store.Chat("g1")
	if err != nil || chat.Title != "haiku" {
		t.Fatalf("the group chat must stay: %+v %v", chat, err)
	}
	if err := d.HandleUserMessage(context.Background(), "g1", "continue"); err != nil {
		t.Fatal(err)
	}
	if orch, err := d.store.Orchestrator("g1"); err != nil || orch.Role != RoleOrchestrator {
		t.Fatalf("the old group chat must get an orchestrator: %+v %v", orch, err)
	}
	if resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: "tok-poet", Op: BusLog, Text: "x"})); !resp.OK {
		t.Fatalf("a retired member keeps its token for its own record: %+v", resp)
	}
}

func TestChatsHaveTheirOwnOrchestrator(t *testing.T) {
	d, pods, _ := testDaemon(t)
	first := firstChat(t, d)
	second, err := d.CreateChat("side project")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := d.CreateChat("   "); err == nil {
		t.Fatal("a chat without a title must be refused")
	}
	for _, id := range []string{first, second.ID} {
		if err := d.HandleUserMessage(context.Background(), id, "hello "+id); err != nil {
			t.Fatal(err)
		}
	}
	waitFor(t, "both replies", func() bool { return len(messagesOfKind(t, d, KindReply)) == 2 })
	a, _ := d.store.Orchestrator(first)
	b, _ := d.store.Orchestrator(second.ID)
	if a.ID == b.ID || a.ChatID != first || b.ChatID != second.ID {
		t.Fatalf("chats share an orchestrator: %+v %+v", a, b)
	}

	tokenA := pods.created[0].Env["SSHIDO_AGENT_TOKEN"]
	listed := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: tokenA, Op: BusList}))
	if !listed.OK || len(listed.Agents) != 1 || listed.Agents[0].ID != a.ID {
		t.Fatalf("list must show only the caller's chat: %+v", listed)
	}
	for _, op := range []string{BusSend, BusVerdict, BusRecord, BusStop} {
		req := BusRequest{Token: tokenA, Op: op, To: b.ID, Text: "hi", Kind: VerdictFail}
		if resp := d.handleBus(context.Background(), mustJSON(t, req)); resp.OK {
			t.Fatalf("%s must not reach an agent in another chat", op)
		}
	}
	if err := d.HandleUserMessage(context.Background(), "nope", "x"); err == nil {
		t.Fatal("a message to an unknown chat must fail")
	}
}

func TestDeleteChatRemovesEverything(t *testing.T) {
	d, pods, _ := testDaemon(t)
	chat, err := d.CreateChat("doomed")
	if err != nil {
		t.Fatal(err)
	}
	orch, err := d.orchestrator(context.Background(), chat.ID)
	if err != nil {
		t.Fatal(err)
	}
	token, _ := tokenOf(t, pods, RoleOrchestrator)
	worker := spawnWorker(t, d, token, "w")
	waitFor(t, "worker turn", func() bool { return len(messagesOfKind(t, d, KindDone)) == 1 })
	events, unsubscribe := d.hub.Subscribe()
	defer unsubscribe()
	if err := d.DeleteChat(context.Background(), chat.ID); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "chatRemoved", func() bool {
		select {
		case ev := <-events:
			return ev.Type == EventChatRemoved && ev.ChatID == chat.ID
		default:
			return false
		}
	})
	if _, err := d.store.Chat(chat.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("chat still stored: %v", err)
	}
	agents, _ := d.store.ChatAgents(chat.ID)
	msgs, _ := d.store.ChatMessagesAfter(chat.ID, 0)
	if len(agents) != 0 || len(msgs) != 0 || len(pods.removed) != 2 {
		t.Fatalf("left behind: agents %d messages %d removed %v", len(agents), len(msgs), pods.removed)
	}
	for _, id := range []string{orch.ID, worker} {
		if _, err := os.Stat(filepath.Join(d.cfg.WorkspaceDir, recordRoot, id)); !os.IsNotExist(err) {
			t.Fatalf("record of %s left behind: %v", id, err)
		}
	}
	if err := d.DeleteChat(context.Background(), chat.ID); err == nil {
		t.Fatal("deleting a missing chat must fail")
	}
}

func TestAppHelloSendsChatsFirst(t *testing.T) {
	d, _, _ := testDaemon(t)
	if _, err := d.orchestrator(context.Background(), firstChat(t, d)); err != nil {
		t.Fatal(err)
	}
	out := make(chan AppEvent, 16)
	d.appHello(0, out)
	close(out)
	types := []string{}
	for ev := range out {
		types = append(types, ev.Type)
	}
	if strings.Join(types, ",") != "chat,agent,ready" {
		t.Fatalf("hello order %v", types)
	}
}

func TestContainersPublishTheDesktopOnLoopback(t *testing.T) {
	d, pods, _ := testDaemon(t)
	if _, err := d.orchestrator(context.Background(), firstChat(t, d)); err != nil {
		t.Fatal(err)
	}
	if ports := pods.created[0].Ports; len(ports) != 1 || ports[0] != desktopPort {
		t.Fatalf("ports %v", ports)
	}
	out := string(mustJSON(t, loopbackPorts([]int{desktopPort})))
	if out != `[{"container_port":6080,"host_ip":"127.0.0.1","protocol":"tcp"}]` {
		t.Fatalf("portmappings %s", out)
	}
}
