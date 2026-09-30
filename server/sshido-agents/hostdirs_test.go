package main

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
)

func TestParseHostDirs(t *testing.T) {
	dirs, err := parseHostDirs(`["/Users/me/code", "/Volumes/data/code/", "/Users/me/My Notes"]`)
	if err != nil {
		t.Fatal(err)
	}
	want := []HostDir{
		{Name: "code", Source: "/Users/me/code"},
		{Name: "code-2", Source: "/Volumes/data/code"},
		{Name: "My-Notes", Source: "/Users/me/My Notes"},
	}
	if len(dirs) != len(want) {
		t.Fatalf("got %+v", dirs)
	}
	for i := range want {
		if dirs[i] != want[i] {
			t.Fatalf("dir %d: got %+v want %+v", i, dirs[i], want[i])
		}
	}
	if dirs[1].Target() != "/host/code-2" {
		t.Fatalf("target %s", dirs[1].Target())
	}
	for _, bad := range []string{`["relative/path"]`, `["/"]`, `"/Users/me"`} {
		if _, err := parseHostDirs(bad); err == nil {
			t.Fatalf("%s: want an error", bad)
		}
	}
	if none, err := parseHostDirs(""); err != nil || none != nil {
		t.Fatalf("empty: %+v %v", none, err)
	}
}

func TestCreateBodyMountsHostDirsReadOnly(t *testing.T) {
	binds := readOnlyBinds([]HostDir{{Name: "code", Source: "/Users/me/code"}})
	out, err := json.Marshal(binds)
	if err != nil {
		t.Fatal(err)
	}
	if string(out) != `[{"destination":"/host/code","source":"/Users/me/code","type":"bind","options":["ro","rbind"]}]` {
		t.Fatalf("mounts %s", out)
	}
	if selinuxFor(nil) != nil || strings.Join(selinuxFor([]HostDir{{}}), ",") != "disable" {
		t.Fatal("label=disable only when host folders are mounted")
	}
}

func TestAgentsGetHostDirsAndRecreateWhenTheyChange(t *testing.T) {
	d, pods, _ := testDaemon(t)
	d.cfg.HostDirs = []HostDir{{Name: "code", Source: "/Users/me/code"}}
	orch, err := d.orchestrator(context.Background(), firstChat(t, d))
	if err != nil {
		t.Fatal(err)
	}
	if len(pods.created[0].Binds) != 1 || orch.Mounts != "/host/code=/Users/me/code" {
		t.Fatalf("binds %+v mounts %q", pods.created[0].Binds, orch.Mounts)
	}
	oldToken := pods.created[0].Env["SSHIDO_AGENT_TOKEN"]

	if err := d.Recover(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(pods.created) != 1 {
		t.Fatal("unchanged host folders must not recreate the container")
	}

	d.cfg.HostDirs = []HostDir{{Name: "code", Source: "/Users/me/code"}, {Name: "notes", Source: "/Users/me/notes"}}
	if err := d.Recover(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(pods.created) != 2 || len(pods.created[1].Binds) != 2 || pods.created[1].Name != orch.Container {
		t.Fatalf("want the same container recreated with 2 binds, got %+v", pods.created)
	}
	if len(pods.removed) != 1 || pods.removed[0] != orch.Container {
		t.Fatalf("old container not removed: %v", pods.removed)
	}
	again, _ := d.store.Agent(orch.ID)
	if again.Session != orch.Session || !strings.Contains(again.Mounts, "/host/notes") {
		t.Fatalf("session must survive and mounts update: %+v", again)
	}
	if resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: oldToken, Op: BusList})); resp.OK {
		t.Fatal("the old container's token must stop working")
	}
	newToken := pods.created[1].Env["SSHIDO_AGENT_TOKEN"]
	if resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: newToken, Op: BusList})); !resp.OK {
		t.Fatalf("new token denied: %+v", resp)
	}
}

func TestNextTurnHearsAboutChangedHostDirs(t *testing.T) {
	d, pods, _ := testDaemon(t)
	d.cfg.HostDirs = []HostDir{{Name: "code", Source: "/Users/me/code"}}
	chat := firstChat(t, d)
	orch, err := d.orchestrator(context.Background(), chat)
	if err != nil {
		t.Fatal(err)
	}
	send := func(text string) string {
		t.Helper()
		before := len(messagesOfKind(t, d, KindReply))
		if err := d.HandleUserMessage(context.Background(), chat, text); err != nil {
			t.Fatal(err)
		}
		waitFor(t, "reply", func() bool { return len(messagesOfKind(t, d, KindReply)) == before+1 })
		pods.mu.Lock()
		defer pods.mu.Unlock()
		prompts := pods.prompts[orch.Container]
		return prompts[len(prompts)-1]
	}
	if first := send("one"); !strings.Contains(first, "/host/code") {
		t.Fatalf("first turn must carry the folders: %q", truncate(first, 200))
	}
	if second := send("two"); second != "two" {
		t.Fatalf("unchanged folders must not be repeated, got %q", second)
	}
	d.cfg.HostDirs = []HostDir{{Name: "code", Source: "/Users/me/code"}, {Name: "notes", Source: "/Users/me/notes"}}
	third := send("three")
	if !strings.HasPrefix(third, "Note: the person changed the shared host folders") || !strings.Contains(third, "/host/notes") || !strings.HasSuffix(third, "three") {
		t.Fatalf("changed folders must be announced once: %q", third)
	}
	if fourth := send("four"); fourth != "four" {
		t.Fatalf("the change must be announced only once, got %q", fourth)
	}
	d.cfg.HostDirs = nil
	if fifth := send("five"); !strings.Contains(fifth, "stopped sharing host folders") {
		t.Fatalf("removing all folders must be announced: %q", fifth)
	}
}

func TestBriefListsHostDirs(t *testing.T) {
	dirs := []HostDir{{Name: "code", Source: "/Users/me/code"}}
	for _, role := range []string{RoleOrchestrator, RoleWorker, RoleMember} {
		prompt := firstTurnPrompt(Agent{Role: role, Name: "w"}, "x", dirs, nil)
		if !strings.Contains(prompt, "/host/code   (the person's /Users/me/code)") || !strings.Contains(prompt, "read-only") {
			t.Fatalf("%s brief lacks host folders: %q", role, prompt)
		}
	}
	if strings.Contains(firstTurnPrompt(Agent{Role: RoleWorker}, "x", nil, nil), "Host folders") {
		t.Fatal("no host folders section without folders")
	}
}
