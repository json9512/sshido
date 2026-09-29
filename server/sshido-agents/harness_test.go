package main

import (
	"errors"
	"reflect"
	"strings"
	"testing"
)

const claudeSample = `{"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"38cfd6d5-87b0-4f55-a981-7aafc568e28a","num_turns":1}`

const codexSample = `{"type":"thread.started","thread_id":"01a0eb1e-97ca-77a0-a3fe-86c1410f9b5e"}
{"type":"item.completed","item":{"id":"item_0","type":"error","message":"Model metadata for ` + "`qwen3.6:35b-instruct`" + ` not found. Defaulting to fallback metadata; this can degrade performance and cause issues."}}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"ok"}}
{"type":"turn.completed","usage":{"input_tokens":6385,"output_tokens":2}}`

const grokSample = `{"text":"ok","stopReason":"end_turn","sessionId":"01a0eb1c-e65f-71b1-a5f6-0231cd37f260","requestId":"11b04204","num_turns":1}`

func TestParseClaude(t *testing.T) {
	got, err := parseClaude([]byte("warning line\n" + claudeSample))
	if err != nil {
		t.Fatal(err)
	}
	want := TurnResult{Text: "ok", Session: "38cfd6d5-87b0-4f55-a981-7aafc568e28a"}
	if got != want {
		t.Fatalf("got %+v want %+v", got, want)
	}
}

func TestParseClaudeError(t *testing.T) {
	_, err := parseClaude([]byte(`{"type":"result","subtype":"error_max_turns","is_error":true,"result":"stopped"}`))
	if !errors.Is(err, ErrTurnFailed) {
		t.Fatalf("want ErrTurnFailed, got %v", err)
	}
}

func TestParseCodexIgnoresWarningItems(t *testing.T) {
	got, err := parseCodex([]byte(codexSample))
	if err != nil {
		t.Fatal(err)
	}
	want := TurnResult{Text: "ok", Session: "01a0eb1e-97ca-77a0-a3fe-86c1410f9b5e"}
	if got != want {
		t.Fatalf("got %+v want %+v", got, want)
	}
}

func TestParseCodexTurnFailed(t *testing.T) {
	out := `{"type":"thread.started","thread_id":"t1"}
{"type":"turn.failed","error":{"message":"rate limited"}}`
	_, err := parseCodex([]byte(out))
	if !errors.Is(err, ErrTurnFailed) {
		t.Fatalf("want ErrTurnFailed, got %v", err)
	}
}

func TestParseCodexNoMessage(t *testing.T) {
	_, err := parseCodex([]byte(`{"type":"thread.started","thread_id":"t1"}`))
	if !errors.Is(err, ErrTurnFailed) {
		t.Fatalf("want ErrTurnFailed, got %v", err)
	}
}

func TestParseGrok(t *testing.T) {
	got, err := parseGrok([]byte(grokSample))
	if err != nil {
		t.Fatal(err)
	}
	want := TurnResult{Text: "ok", Session: "01a0eb1c-e65f-71b1-a5f6-0231cd37f260"}
	if got != want {
		t.Fatalf("got %+v want %+v", got, want)
	}
}

func TestParseGrokStopReason(t *testing.T) {
	_, err := parseGrok([]byte(`{"text":"","stopReason":"max_turns","sessionId":"s"}`))
	if !errors.Is(err, ErrTurnFailed) {
		t.Fatalf("want ErrTurnFailed, got %v", err)
	}
}

func TestParseGemini(t *testing.T) {
	got, err := parseGemini([]byte(`{"response":"ok","stats":{}}`))
	if err != nil {
		t.Fatal(err)
	}
	if got.Text != "ok" || got.Session != geminiResumeLatest {
		t.Fatalf("got %+v", got)
	}
	if _, err := parseGemini([]byte(`{"error":{"message":"quota"}}`)); !errors.Is(err, ErrTurnFailed) {
		t.Fatalf("want ErrTurnFailed, got %v", err)
	}
}

func TestParseNoJSON(t *testing.T) {
	if _, err := parseClaude([]byte("not json at all")); err == nil {
		t.Fatal("want error for output without JSON")
	}
}

func TestCommands(t *testing.T) {
	cases := []struct {
		harness string
		turn    Turn
		want    []string
	}{
		{HarnessClaude, Turn{Prompt: "hi"},
			[]string{"claude", "-p", "hi", "--output-format", "json", "--dangerously-skip-permissions"}},
		{HarnessClaude, Turn{Prompt: "hi", Session: "s1", Model: "opus"},
			[]string{"claude", "-p", "hi", "--output-format", "json", "--dangerously-skip-permissions", "--model", "opus", "--resume", "s1"}},
		{HarnessCodex, Turn{Prompt: "hi", Session: "t1"},
			[]string{"codex", "exec", "--json", "--skip-git-repo-check", "--dangerously-bypass-approvals-and-sandbox", "resume", "t1", "hi"}},
		{HarnessLocal, Turn{Prompt: "hi", Model: "qwen", LocalURL: "http://host.containers.internal:8083/v1"},
			[]string{"codex", "exec", "--json", "--skip-git-repo-check", "--dangerously-bypass-approvals-and-sandbox",
				"-c", "model_provider=local", "-c", `model_providers.local.name="local"`,
				"-c", `model_providers.local.base_url="http://host.containers.internal:8083/v1"`,
				"-c", `model_providers.local.wire_api="responses"`, "-m", "qwen", "hi"}},
		{HarnessGemini, Turn{Prompt: "hi", Session: geminiResumeLatest},
			[]string{"gemini", "-p", "hi", "-o", "json", "--yolo", "--resume", "latest"}},
		{HarnessGrok, Turn{PromptFile: "/bus/p.txt", Session: "g1"},
			[]string{"grok", "--prompt-file", "/bus/p.txt", "--output-format", "json", "--always-approve", "--resume", "g1"}},
	}
	for _, c := range cases {
		spec, err := lookupHarness(c.harness)
		if err != nil {
			t.Fatal(err)
		}
		got, err := spec.command(c.turn)
		if err != nil {
			t.Fatalf("%s: %v", c.harness, err)
		}
		if !reflect.DeepEqual(got, c.want) {
			t.Fatalf("%s:\n got %q\nwant %q", c.harness, got, c.want)
		}
	}
}

func TestLocalNeedsEndpointAndModel(t *testing.T) {
	if _, err := localCommand(Turn{Prompt: "hi", Model: "qwen"}); err == nil {
		t.Fatal("want error without endpoint")
	}
	if _, err := localCommand(Turn{Prompt: "hi", LocalURL: "http://x"}); err == nil {
		t.Fatal("want error without model")
	}
}

func TestUnknownHarness(t *testing.T) {
	if _, err := lookupHarness("aider"); err == nil {
		t.Fatal("want error for unknown harness")
	}
}

func TestFirstTurnPromptsDescribeComputerUse(t *testing.T) {
	for _, role := range []string{RoleOrchestrator, RoleWorker} {
		prompt := firstTurnPrompt(role, "w", "do it")
		for _, want := range []string{"agent-browser open", "network access", "/workspace"} {
			if !strings.Contains(prompt, want) {
				t.Fatalf("%s brief lacks %q", role, want)
			}
		}
	}
}
