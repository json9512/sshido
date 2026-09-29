package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

const (
	HarnessClaude = "claude"
	HarnessCodex  = "codex"
	HarnessGemini = "gemini"
	HarnessGrok   = "grok"
	HarnessLocal  = "local"
)

const geminiResumeLatest = "latest"

type Turn struct {
	Prompt     string
	PromptFile string
	Session    string
	Model      string
	LocalURL   string
}

type TurnResult struct {
	Text    string
	Session string
}

var ErrTurnFailed = errors.New("turn failed")

type harnessSpec struct {
	command       func(Turn) ([]string, error)
	parse         func([]byte) (TurnResult, error)
	stateDir      string
	promptViaFile bool
}

var harnesses = map[string]harnessSpec{
	HarnessClaude: {command: claudeCommand, parse: parseClaude, stateDir: ".claude"},
	HarnessCodex:  {command: codexCommand, parse: parseCodex, stateDir: ".codex"},
	HarnessLocal:  {command: localCommand, parse: parseCodex, stateDir: ".codex"},
	HarnessGemini: {command: geminiCommand, parse: parseGemini, stateDir: ".gemini"},
	HarnessGrok:   {command: grokCommand, parse: parseGrok, stateDir: ".grok", promptViaFile: true},
}

func lookupHarness(name string) (harnessSpec, error) {
	spec, ok := harnesses[name]
	if !ok {
		return harnessSpec{}, fmt.Errorf("unknown harness %q (use claude, codex, gemini, grok or local)", name)
	}
	return spec, nil
}

func withModel(args []string, flag, model string) []string {
	if model == "" {
		return args
	}
	return append(args, flag, model)
}

func claudeCommand(t Turn) ([]string, error) {
	args := []string{"claude", "-p", t.Prompt, "--output-format", "json", "--dangerously-skip-permissions"}
	args = withModel(args, "--model", t.Model)
	if t.Session == "" {
		return args, nil
	}
	return append(args, "--resume", t.Session), nil
}

var codexBase = []string{"codex", "exec", "--json", "--skip-git-repo-check", "--dangerously-bypass-approvals-and-sandbox"}

func codexTail(base []string, t Turn) []string {
	args := withModel(base, "-m", t.Model)
	if t.Session == "" {
		return append(args, t.Prompt)
	}
	return append(args, "resume", t.Session, t.Prompt)
}

func codexCommand(t Turn) ([]string, error) {
	return codexTail(append([]string{}, codexBase...), t), nil
}

func localCommand(t Turn) ([]string, error) {
	if t.LocalURL == "" {
		return nil, errors.New("local harness needs a model endpoint (SSHIDO_LOCAL_URL)")
	}
	if t.Model == "" {
		return nil, errors.New("local harness needs a model name")
	}
	provider := []string{
		"-c", "model_provider=local",
		"-c", `model_providers.local.name="local"`,
		"-c", fmt.Sprintf("model_providers.local.base_url=%q", t.LocalURL),
		"-c", `model_providers.local.wire_api="responses"`,
	}
	return codexTail(append(append([]string{}, codexBase...), provider...), t), nil
}

func geminiCommand(t Turn) ([]string, error) {
	args := withModel([]string{"gemini", "-p", t.Prompt, "-o", "json", "--yolo"}, "-m", t.Model)
	if t.Session == "" {
		return args, nil
	}
	return append(args, "--resume", geminiResumeLatest), nil
}

func grokCommand(t Turn) ([]string, error) {
	if t.PromptFile == "" {
		return nil, errors.New("grok harness needs a prompt file")
	}
	args := withModel([]string{"grok", "--prompt-file", t.PromptFile, "--output-format", "json", "--always-approve"}, "-m", t.Model)
	if t.Session == "" {
		return args, nil
	}
	return append(args, "--resume", t.Session), nil
}

func lastJSONObject(out []byte) (map[string]any, error) {
	lines := bytes.Split(bytes.TrimSpace(out), []byte("\n"))
	for i := len(lines) - 1; i >= 0; i-- {
		var obj map[string]any
		if json.Unmarshal(bytes.TrimSpace(lines[i]), &obj) == nil {
			return obj, nil
		}
	}
	var whole map[string]any
	if json.Unmarshal(bytes.TrimSpace(out), &whole) == nil {
		return whole, nil
	}
	return nil, fmt.Errorf("no JSON result in output: %q", truncate(string(out), 200))
}

func stringField(obj map[string]any, key string) string {
	v, _ := obj[key].(string)
	return v
}

func parseClaude(out []byte) (TurnResult, error) {
	obj, err := lastJSONObject(out)
	if err != nil {
		return TurnResult{}, err
	}
	isError, _ := obj["is_error"].(bool)
	if isError || stringField(obj, "subtype") != "success" {
		return TurnResult{}, fmt.Errorf("%w: claude %s: %s", ErrTurnFailed, stringField(obj, "subtype"), truncate(stringField(obj, "result"), 300))
	}
	return TurnResult{Text: stringField(obj, "result"), Session: stringField(obj, "session_id")}, nil
}

func parseCodex(out []byte) (TurnResult, error) {
	scanner := bufio.NewScanner(bytes.NewReader(out))
	scanner.Buffer(make([]byte, 0, 64*1024), 16*1024*1024)
	result := TurnResult{}
	failure := ""
	for scanner.Scan() {
		var ev map[string]any
		if json.Unmarshal(scanner.Bytes(), &ev) != nil {
			continue
		}
		result, failure = applyCodexEvent(ev, result, failure)
	}
	if err := scanner.Err(); err != nil {
		return TurnResult{}, fmt.Errorf("read codex events: %w", err)
	}
	if failure != "" {
		return TurnResult{}, fmt.Errorf("%w: codex: %s", ErrTurnFailed, truncate(failure, 300))
	}
	if result.Text == "" {
		return TurnResult{}, fmt.Errorf("%w: codex produced no agent message", ErrTurnFailed)
	}
	return result, nil
}

func applyCodexEvent(ev map[string]any, result TurnResult, failure string) (TurnResult, string) {
	switch stringField(ev, "type") {
	case "thread.started":
		return TurnResult{Text: result.Text, Session: stringField(ev, "thread_id")}, failure
	case "item.completed":
		item, _ := ev["item"].(map[string]any)
		if stringField(item, "type") != "agent_message" {
			return result, failure
		}
		return TurnResult{Text: stringField(item, "text"), Session: result.Session}, failure
	case "turn.failed":
		errObj, _ := ev["error"].(map[string]any)
		return result, firstNonEmpty(stringField(errObj, "message"), "turn failed")
	case "error":
		return result, firstNonEmpty(stringField(ev, "message"), "error")
	}
	return result, failure
}

func parseGemini(out []byte) (TurnResult, error) {
	obj, err := lastJSONObject(out)
	if err != nil {
		return TurnResult{}, err
	}
	if errObj, ok := obj["error"].(map[string]any); ok {
		return TurnResult{}, fmt.Errorf("%w: gemini: %s", ErrTurnFailed, truncate(stringField(errObj, "message"), 300))
	}
	return TurnResult{Text: stringField(obj, "response"), Session: geminiResumeLatest}, nil
}

func parseGrok(out []byte) (TurnResult, error) {
	obj, err := lastJSONObject(out)
	if err != nil {
		return TurnResult{}, err
	}
	stop := stringField(obj, "stopReason")
	if stop != "" && stop != "end_turn" {
		return TurnResult{}, fmt.Errorf("%w: grok stopped with %s", ErrTurnFailed, stop)
	}
	return TurnResult{Text: stringField(obj, "text"), Session: stringField(obj, "sessionId")}, nil
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
