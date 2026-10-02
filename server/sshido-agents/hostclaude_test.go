package main

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
)

func TestParseHostClaudeHome(t *testing.T) {
	cases := map[string]string{"": "", "  ": "", "/home/pi/": "/home/pi", "/home/pi": "/home/pi"}
	for raw, want := range cases {
		got, err := parseHostClaudeHome(raw)
		if err != nil || got != want {
			t.Fatalf("parse %q = %q, %v; want %q", raw, got, err, want)
		}
	}
	for _, bad := range []string{"home/pi", "/", "~"} {
		if _, err := parseHostClaudeHome(bad); err == nil {
			t.Fatalf("parse %q should fail", bad)
		}
	}
}

func harness(t *testing.T, name string) harnessSpec {
	t.Helper()
	spec, err := lookupHarness(name)
	if err != nil {
		t.Fatal(err)
	}
	return spec
}

func TestClaudeAgentsShareTheHostClaudeConfig(t *testing.T) {
	d, _, _ := testDaemon(t)
	d.cfg.HostClaudeHome = "/home/pi"
	spec := d.containerSpec("a1", RoleOrchestrator, "tok", harness(t, HarnessClaude))
	if spec.Env["CLAUDE_CONFIG_DIR"] != "/home/pi/.claude" {
		t.Fatalf("CLAUDE_CONFIG_DIR %q", spec.Env["CLAUDE_CONFIG_DIR"])
	}
	if _, ok := spec.Volumes["sshido-auth-claude"]; ok {
		t.Fatal("a Claude agent sharing the host config must not mount its own auth volume")
	}
	want := []WritableBind{
		{Source: "/home/pi/.claude", Target: "/home/pi/.claude"},
		{Source: "/home/pi/.claude.json", Target: "/home/pi/.claude/.claude.json"},
	}
	if !reflect.DeepEqual(spec.Writable, want) {
		t.Fatalf("writable binds %+v", spec.Writable)
	}
	if !spec.KeepID {
		t.Fatal("the agent user must map to the host user to write the host config")
	}
	if got := strings.Join(ownershipCommand(spec), " "); got != "find /workspace /home/agent/.logins ! -user agent -exec chown -h agent:agent {} +" {
		t.Fatalf("ownership command %q", got)
	}
}

func TestOtherHarnessesKeepTheirAuthVolumeButShareTheUserMapping(t *testing.T) {
	d, _, _ := testDaemon(t)
	d.cfg.HostClaudeHome = "/home/pi"
	spec := d.containerSpec("w1", RoleWorker, "tok", harness(t, HarnessCodex))
	if spec.Volumes["sshido-auth-codex"] != "/home/agent/.codex" {
		t.Fatalf("volumes %v", spec.Volumes)
	}
	if len(spec.Writable) != 0 || spec.Env["CLAUDE_CONFIG_DIR"] != agentClaudeDir {
		t.Fatalf("a Codex worker got the host Claude config: %+v %q", spec.Writable, spec.Env["CLAUDE_CONFIG_DIR"])
	}
	if !spec.KeepID {
		t.Fatal("every agent on a sharing host needs the same user mapping so /workspace stays writable for all")
	}
}

func TestWithoutAHostClaudeHomeNothingChanges(t *testing.T) {
	d, _, _ := testDaemon(t)
	spec := d.containerSpec("a1", RoleOrchestrator, "tok", harness(t, HarnessClaude))
	if spec.Env["CLAUDE_CONFIG_DIR"] != agentClaudeDir || spec.Volumes["sshido-auth-claude"] != agentClaudeDir {
		t.Fatalf("env %v volumes %v", spec.Env, spec.Volumes)
	}
	if spec.KeepID || len(spec.Writable) != 0 {
		t.Fatalf("keep-id %v writable %v", spec.KeepID, spec.Writable)
	}
	if got := strings.Join(ownershipCommand(spec), " "); got != "chown agent:agent /workspace /home/agent/.claude /home/agent/.logins" {
		t.Fatalf("ownership command %q", got)
	}
	if setupFingerprint(nil, "") != "desktop=6080\nlogins="+loginsVolume {
		t.Fatalf("fingerprint without a Claude home changed: %q", setupFingerprint(nil, ""))
	}
	if setupFingerprint(nil, "/home/pi") == setupFingerprint(nil, "") {
		t.Fatal("turning on the host Claude config must recreate agent containers")
	}
}

func TestCreateBodyForSharedClaudeConfig(t *testing.T) {
	out, err := json.Marshal(map[string]any{
		"mounts": writableBinds([]WritableBind{{Source: "/home/pi/.claude", Target: "/home/pi/.claude"}}),
		"userns": usernsFor(true),
		"none":   usernsFor(false),
	})
	if err != nil {
		t.Fatal(err)
	}
	want := `{"mounts":[{"destination":"/home/pi/.claude","source":"/home/pi/.claude","type":"bind","options":["rbind"]}],"none":null,"userns":{"nsmode":"keep-id","value":"uid=1001,gid=1001"}}`
	if string(out) != want {
		t.Fatalf("body %s", out)
	}
}
