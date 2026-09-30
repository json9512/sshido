package main

import (
	"context"
	"strings"
	"testing"
)

func TestParseWorkerChoice(t *testing.T) {
	fixed, err := parseWorkerChoice(ChoiceFixed, HarnessCodex, " gpt-5 ", "", "")
	if err != nil || fixed.Harness != HarnessCodex || fixed.Model != "gpt-5" {
		t.Fatalf("fixed: %+v %v", fixed, err)
	}
	decides, err := parseWorkerChoice(ChoiceOrchestrator, "", "", "claude, local,claude", "qwen")
	if err != nil || strings.Join(decides.Allowed, ",") != "claude,local" || decides.LocalModel != "qwen" {
		t.Fatalf("orchestrator decides: %+v %v", decides, err)
	}
	for _, bad := range [][5]string{
		{ChoiceFixed, "nope", "", "", ""},
		{ChoiceFixed, HarnessLocal, "", "", ""},
		{ChoiceOrchestrator, "", "", "", ""},
		{ChoiceOrchestrator, "", "", "claude,nope", ""},
		{ChoiceOrchestrator, "", "", "local", ""},
		{"sometimes", HarnessClaude, "", "", ""},
	} {
		if _, err := parseWorkerChoice(bad[0], bad[1], bad[2], bad[3], bad[4]); err == nil {
			t.Fatalf("want an error for %v", bad)
		}
	}
}

func TestPickFixed(t *testing.T) {
	c := WorkerChoice{Mode: ChoiceFixed, Harness: HarnessLocal, Model: "qwen"}
	if h, m, err := c.pick("", ""); err != nil || h != HarnessLocal || m != "qwen" {
		t.Fatalf("default: %s %s %v", h, m, err)
	}
	if _, _, err := c.pick(HarnessClaude, ""); err == nil {
		t.Fatal("another harness must be refused when the person fixed it")
	}
	if _, _, err := c.pick("", "llama"); err == nil {
		t.Fatal("another model must be refused when the person fixed it")
	}
	open := WorkerChoice{Mode: ChoiceFixed, Harness: HarnessClaude}
	if h, m, err := open.pick(HarnessClaude, "opus"); err != nil || h != HarnessClaude || m != "opus" {
		t.Fatalf("a model may be chosen when none is fixed: %s %s %v", h, m, err)
	}
}

func TestPickAllowed(t *testing.T) {
	c := WorkerChoice{Mode: ChoiceOrchestrator, Allowed: []string{HarnessCodex, HarnessLocal}, LocalModel: "qwen"}
	if h, m, err := c.pick("", ""); err != nil || h != HarnessCodex || m != "" {
		t.Fatalf("default is the first allowed: %s %s %v", h, m, err)
	}
	if h, m, err := c.pick(HarnessLocal, ""); err != nil || h != HarnessLocal || m != "qwen" {
		t.Fatalf("local gets the person's local model: %s %s %v", h, m, err)
	}
	if _, _, err := c.pick(HarnessClaude, ""); err == nil || !strings.Contains(err.Error(), "codex, local") {
		t.Fatalf("a harness outside the allowed set must be refused with the list: %v", err)
	}
}

func TestOrchestratorPromptDescribesChoice(t *testing.T) {
	fixed := orchestratorPrompt(WorkerChoice{Mode: ChoiceFixed, Harness: HarnessClaude, Model: "opus"})
	if strings.Contains(fixed, "--harness") || !strings.Contains(fixed, "Subagents run on Claude Code with model opus") {
		t.Fatalf("fixed prompt: %q", fixed)
	}
	decides := orchestratorPrompt(WorkerChoice{Mode: ChoiceOrchestrator, Allowed: []string{HarnessClaude, HarnessLocal}, LocalModel: "qwen"})
	for _, want := range []string{"--harness claude|local", "local (qwen on the person's own machine)", "Without --harness a subagent gets claude", "principles: what outcome they want", "agentctl verdict"} {
		if !strings.Contains(decides, want) {
			t.Fatalf("prompt lacks %q", want)
		}
	}
	if strings.Contains(decides, "%!") {
		t.Fatalf("format error in prompt: %q", decides)
	}
}

func TestSpawnFollowsTheChoice(t *testing.T) {
	d, pods, _ := testDaemon(t)
	d.cfg.Workers = WorkerChoice{Mode: ChoiceOrchestrator, Allowed: []string{HarnessCodex, HarnessLocal}, LocalModel: "qwen"}
	orchToken := orchestratorToken(t, d, pods)
	resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: orchToken, Op: BusSpawn, Name: "l", Goal: "g", Task: "t", Harness: HarnessLocal}))
	if !resp.OK {
		t.Fatal(resp.Error)
	}
	w, _ := d.store.Agent(resp.AgentID)
	if w.Harness != HarnessLocal || w.Model != "qwen" {
		t.Fatalf("spawned %+v", w)
	}
	if resp := d.handleBus(context.Background(), mustJSON(t, BusRequest{Token: orchToken, Op: BusSpawn, Name: "c", Goal: "g", Task: "t", Harness: HarnessClaude})); resp.OK {
		t.Fatal("spawn outside the allowed set must be denied")
	}
}
