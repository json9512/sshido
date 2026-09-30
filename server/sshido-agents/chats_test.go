package main

import (
	"context"
	"database/sql"
	"errors"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakePicker struct {
	mu      sync.Mutex
	picks   []int
	states  []string
	offered []int
	fail    error
}

func (f *fakePicker) Pick(_ context.Context, state, _ string, options []PickOption) (Pick, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.states = append(f.states, state)
	f.offered = append(f.offered, len(options))
	if f.fail != nil {
		return Pick{}, f.fail
	}
	if len(f.picks) == 0 {
		return Pick{Index: len(options) - 1}, nil
	}
	if f.picks[0] >= len(options) {
		return Pick{}, errors.New("fake picker scripted an option that was not offered")
	}
	next := f.picks[0]
	f.picks = f.picks[1:]
	return Pick{Index: next}, nil
}

func (f *fakePicker) calls() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.states)
}

func groupDaemon(t *testing.T, picker Picker) (*Daemon, *fakePods, *fakePush) {
	t.Helper()
	d, pods, push := testDaemon(t)
	return newDaemon(d.cfg, d.store, pods, push, picker), pods, push
}

func createGroup(t *testing.T, d *Daemon, turnCap int, names ...string) Chat {
	t.Helper()
	members := make([]MemberSpec, 0, len(names))
	for _, n := range names {
		members = append(members, MemberSpec{Name: n})
	}
	c, err := d.CreateChat(context.Background(), AppRequest{Op: OpCreateChat, Title: "crew", Kind: ChatGroup, TurnCap: turnCap, Members: members})
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func chatReplies(t *testing.T, d *Daemon, chatID string) []string {
	t.Helper()
	msgs, err := d.store.ChatMessagesAfter(chatID, 0)
	if err != nil {
		t.Fatal(err)
	}
	out := []string{}
	for _, m := range msgs {
		if m.Kind == KindReply {
			out = append(out, m.Author+":"+m.Text)
		}
	}
	return out
}

func waitIdle(t *testing.T, d *Daemon, chatID string, pickerCalls func() int, want int) {
	t.Helper()
	waitFor(t, "round to finish", func() bool {
		c, err := d.store.Chat(chatID)
		return err == nil && c.Status == ChatIdle && pickerCalls() >= want
	})
}

func memberContainer(t *testing.T, d *Daemon, chatID, name string) string {
	t.Helper()
	agents, err := d.store.ChatAgents(chatID)
	if err != nil {
		t.Fatal(err)
	}
	for _, a := range agents {
		if a.Name == name {
			return a.Container
		}
	}
	t.Fatalf("no member %s", name)
	return ""
}

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
		if err != nil || len(chats) != 1 || chats[0].Title != "Agents" || chats[0].Kind != ChatOrchestrated {
			t.Fatalf("pass %d: want one migrated chat, got %+v %v", pass, chats, err)
		}
		orch, err := store.Orchestrator(chats[0].ID)
		if err != nil || orch.ID != "a1" || orch.Session != "sess" {
			t.Fatalf("pass %d: orchestrator not moved: %+v %v", pass, orch, err)
		}
		msgs, err := store.ChatMessagesAfter(chats[0].ID, 0)
		if err != nil || len(msgs) != 1 || msgs[0].Text != "old message" {
			t.Fatalf("pass %d: history not moved: %+v %v", pass, msgs, err)
		}
		store.Close()
	}
}

func TestChatsHaveTheirOwnOrchestrator(t *testing.T) {
	d, pods, _ := testDaemon(t)
	first := firstChat(t, d)
	second, err := d.CreateChat(context.Background(), AppRequest{Title: "side project", Kind: ChatOrchestrated})
	if err != nil {
		t.Fatal(err)
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
	for _, m := range messagesOfKind(t, d, KindReply) {
		orch, _ := d.store.Orchestrator(m.ChatID)
		if m.AgentID != orch.ID {
			t.Fatalf("reply %+v landed in the wrong chat", m)
		}
	}

	tokenA := pods.created[0].Env["SSHIDO_AGENT_TOKEN"]
	listed := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: tokenA, Op: BusList}))
	if !listed.OK || len(listed.Agents) != 1 || listed.Agents[0].ID != a.ID {
		t.Fatalf("list must show only the caller's chat: %+v", listed)
	}
	if resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: tokenA, Op: BusSend, To: b.ID, Text: "hi"})); resp.OK {
		t.Fatal("an orchestrator must not message an agent in another chat")
	}
	if err := d.HandleUserMessage(context.Background(), "nope", "x"); err == nil {
		t.Fatal("a message to an unknown chat must fail")
	}
}

func TestGroupRoundFollowsThePicker(t *testing.T) {
	picker := &fakePicker{picks: []int{0, 1}}
	d, pods, push := groupDaemon(t, picker)
	chat := createGroup(t, d, 6, "poet", "critic")
	poet := memberContainer(t, d, chat.ID, "poet")
	critic := memberContainer(t, d, chat.ID, "critic")
	pods.script(poet, "rain on tin roofs")
	pods.script(critic, "good, tighten line two")

	if err := d.HandleUserMessage(context.Background(), chat.ID, "write a haiku and critique it"); err != nil {
		t.Fatal(err)
	}
	waitIdle(t, d, chat.ID, picker.calls, 3)
	got := strings.Join(chatReplies(t, d, chat.ID), " | ")
	if got != "poet:rain on tin roofs | critic:good, tighten line two" {
		t.Fatalf("replies %q", got)
	}
	pods.mu.Lock()
	poetPrompt, criticPrompt := pods.prompts[poet][0], pods.prompts[critic][0]
	pods.mu.Unlock()
	if !strings.Contains(poetPrompt, `You are "poet"`) || !strings.Contains(poetPrompt, "- critic (claude)") {
		t.Fatalf("first member turn needs the roster brief: %q", truncate(poetPrompt, 300))
	}
	if !strings.Contains(criticPrompt, "you: write a haiku") || !strings.Contains(criticPrompt, "poet: rain on tin roofs") {
		t.Fatalf("critic must see the person and the poet: %q", criticPrompt)
	}
	picker.mu.Lock()
	lastState := picker.states[2]
	offered := picker.offered
	picker.mu.Unlock()
	if offered[0] != 2 || offered[1] != 3 || offered[2] != 3 {
		t.Fatalf("the first pick after the person speaks must not offer handing back; offered %v", offered)
	}
	if !strings.Contains(lastState, "in order: poet, critic. The last reply was from critic.") || !strings.Contains(lastState, `latest message: "write a haiku and critique it"`) {
		t.Fatalf("picker state must say who replied since the person spoke: %q", lastState)
	}
	waitFor(t, "round push", func() bool { return len(push.all()) == 1 })
	if !strings.HasPrefix(push.all()[0], "crew replied|false|good, tighten") {
		t.Fatalf("push %v", push.all())
	}

	picker.mu.Lock()
	picker.picks = []int{0}
	picker.mu.Unlock()
	pods.script(poet, "revised")
	if err := d.HandleUserMessage(context.Background(), chat.ID, "go again"); err != nil {
		t.Fatal(err)
	}
	waitIdle(t, d, chat.ID, picker.calls, 5)
	pods.mu.Lock()
	again := pods.prompts[poet][1]
	pods.mu.Unlock()
	if strings.Contains(again, "rain on tin roofs") || !strings.Contains(again, "critic: good, tighten") || !strings.Contains(again, "you: go again") {
		t.Fatalf("second poet turn must carry only what it has not seen: %q", again)
	}
}

func TestGroupRoundStopsAtTurnCap(t *testing.T) {
	picker := &fakePicker{picks: []int{0, 1, 0, 1, 0}}
	d, _, _ := groupDaemon(t, picker)
	chat := createGroup(t, d, 2, "a", "b")
	if err := d.HandleUserMessage(context.Background(), chat.ID, "talk"); err != nil {
		t.Fatal(err)
	}
	waitIdle(t, d, chat.ID, picker.calls, 2)
	waitFor(t, "cap notice", func() bool {
		for _, m := range messagesOfKind(t, d, KindProgress) {
			if strings.Contains(m.Text, "Turn limit reached (2 turns)") {
				return true
			}
		}
		return false
	})
	if n := len(chatReplies(t, d, chat.ID)); n != 2 {
		t.Fatalf("want 2 replies at a cap of 2, got %d", n)
	}
}

func TestGroupRoundReportsPickerFailure(t *testing.T) {
	picker := &fakePicker{fail: errors.New("model not loaded")}
	d, _, _ := groupDaemon(t, picker)
	chat := createGroup(t, d, 4, "a", "b")
	if err := d.HandleUserMessage(context.Background(), chat.ID, "talk"); err != nil {
		t.Fatal(err)
	}
	waitIdle(t, d, chat.ID, picker.calls, 1)
	waitFor(t, "picker error", func() bool {
		errs := messagesOfKind(t, d, KindError)
		return len(errs) == 1 && strings.Contains(errs[0].Text, "model not loaded")
	})
}

func TestCreateGroupChatValidation(t *testing.T) {
	plain, _, _ := testDaemon(t)
	two := []MemberSpec{{Name: "a"}, {Name: "b"}}
	if _, err := plain.CreateChat(context.Background(), AppRequest{Title: "g", Kind: ChatGroup, Members: two}); !errors.Is(err, ErrNoPicker) {
		t.Fatalf("group chat without a picker: %v", err)
	}
	d, _, _ := groupDaemon(t, &fakePicker{})
	cases := map[string]AppRequest{
		"no title":     {Kind: ChatGroup, Members: two},
		"bad kind":     {Title: "g", Kind: "party", Members: two},
		"one member":   {Title: "g", Kind: ChatGroup, Members: two[:1]},
		"same name":    {Title: "g", Kind: ChatGroup, Members: []MemberSpec{{Name: "a"}, {Name: "A"}}},
		"bad harness":  {Title: "g", Kind: ChatGroup, Members: []MemberSpec{{Name: "a"}, {Name: "b", Harness: "aider"}}},
		"cap too high": {Title: "g", Kind: ChatGroup, Members: two, TurnCap: 51},
	}
	for name, req := range cases {
		if _, err := d.CreateChat(context.Background(), req); err == nil {
			t.Fatalf("%s: want an error", name)
		}
	}
	c, err := d.CreateChat(context.Background(), AppRequest{Title: "g", Kind: ChatGroup, Members: two})
	if err != nil || c.TurnCap != defaultTurnCap {
		t.Fatalf("default turn cap: %+v %v", c, err)
	}
}

func TestDeleteChatRemovesEverything(t *testing.T) {
	d, pods, _ := groupDaemon(t, &fakePicker{})
	chat := createGroup(t, d, 3, "a", "b")
	d.post(chat.ID, "", "you", KindUser, "hi")
	events, unsubscribe := d.hub.Subscribe()
	defer unsubscribe()
	if err := d.DeleteChat(context.Background(), chat.ID); err != nil {
		t.Fatal(err)
	}
	if ev := <-events; ev.Type != EventChatRemoved || ev.ChatID != chat.ID {
		t.Fatalf("want chatRemoved, got %+v", ev)
	}
	if _, err := d.store.Chat(chat.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("chat still stored: %v", err)
	}
	agents, _ := d.store.ChatAgents(chat.ID)
	msgs, _ := d.store.ChatMessagesAfter(chat.ID, 0)
	if len(agents) != 0 || len(msgs) != 0 || len(pods.removed) != 2 {
		t.Fatalf("left behind: agents %d messages %d removed %v", len(agents), len(msgs), pods.removed)
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
