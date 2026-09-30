package main

import (
	"errors"
	"fmt"
	"strings"
)

const (
	ChoiceFixed        = "fixed"
	ChoiceOrchestrator = "orchestrator"
)

type WorkerChoice struct {
	Mode       string
	Harness    string
	Model      string
	Allowed    []string
	LocalModel string
}

var harnessLabels = map[string]string{
	HarnessClaude: "Claude Code",
	HarnessCodex:  "Codex",
	HarnessGemini: "Gemini CLI",
	HarnessGrok:   "Grok",
	HarnessLocal:  "a local model",
}

func parseWorkerChoice(mode, harness, model, allowed, localModel string) (WorkerChoice, error) {
	switch mode {
	case ChoiceFixed:
		if _, err := lookupHarness(harness); err != nil {
			return WorkerChoice{}, err
		}
		if harness == HarnessLocal && strings.TrimSpace(model) == "" {
			return WorkerChoice{}, errors.New("SSHIDO_WORKER_MODEL is required when subagents run on the local harness")
		}
		return WorkerChoice{Mode: ChoiceFixed, Harness: harness, Model: strings.TrimSpace(model)}, nil
	case ChoiceOrchestrator:
		names, err := allowedHarnesses(allowed)
		if err != nil {
			return WorkerChoice{}, err
		}
		if contains(names, HarnessLocal) && strings.TrimSpace(localModel) == "" {
			return WorkerChoice{}, errors.New("SSHIDO_WORKER_LOCAL_MODEL is required when the local harness is allowed")
		}
		return WorkerChoice{Mode: ChoiceOrchestrator, Allowed: names, LocalModel: strings.TrimSpace(localModel)}, nil
	}
	return WorkerChoice{}, fmt.Errorf("SSHIDO_WORKER_CHOICE must be %q or %q, got %q", ChoiceFixed, ChoiceOrchestrator, mode)
}

func allowedHarnesses(raw string) ([]string, error) {
	names := []string{}
	for _, part := range strings.Split(raw, ",") {
		name := strings.TrimSpace(part)
		if name == "" || contains(names, name) {
			continue
		}
		if _, err := lookupHarness(name); err != nil {
			return nil, err
		}
		names = append(names, name)
	}
	if len(names) == 0 {
		return nil, errors.New("SSHIDO_WORKER_HARNESSES must list at least one harness when the orchestrator decides")
	}
	return names, nil
}

func contains(list []string, want string) bool {
	for _, v := range list {
		if v == want {
			return true
		}
	}
	return false
}

func (c WorkerChoice) pick(harness, model string) (string, string, error) {
	if c.Mode == ChoiceOrchestrator {
		return c.pickAllowed(strings.TrimSpace(harness), strings.TrimSpace(model))
	}
	return c.pickFixed(strings.TrimSpace(harness), strings.TrimSpace(model))
}

func (c WorkerChoice) pickFixed(harness, model string) (string, string, error) {
	if harness != "" && harness != c.Harness {
		return "", "", fmt.Errorf("the person set subagents to run on %s; leave out --harness", c.Harness)
	}
	if model != "" && c.Model != "" && model != c.Model {
		return "", "", fmt.Errorf("the person set subagents to use model %s; leave out --model", c.Model)
	}
	return c.Harness, firstNonEmpty(c.Model, model), nil
}

func (c WorkerChoice) pickAllowed(harness, model string) (string, string, error) {
	chosen := firstNonEmpty(harness, c.Allowed[0])
	if !contains(c.Allowed, chosen) {
		return "", "", fmt.Errorf("harness %q is not allowed; the person allows %s", chosen, strings.Join(c.Allowed, ", "))
	}
	if chosen == HarnessLocal {
		return chosen, firstNonEmpty(model, c.LocalModel), nil
	}
	return chosen, model, nil
}

func (c WorkerChoice) spawnFlags() string {
	if c.Mode == ChoiceOrchestrator {
		return " --harness " + strings.Join(c.Allowed, "|") + " [--model <model>]"
	}
	return ""
}

func (c WorkerChoice) describe(name string) string {
	if name == HarnessLocal && c.LocalModel != "" {
		return fmt.Sprintf("local (%s on the person's own machine)", c.LocalModel)
	}
	return fmt.Sprintf("%s (%s)", name, harnessLabels[name])
}

func (c WorkerChoice) help() string {
	if c.Mode != ChoiceOrchestrator {
		model := ""
		if c.Model != "" {
			model = " with model " + c.Model
		}
		return fmt.Sprintf("\nSubagents run on %s%s, as the person set it.\n", harnessLabels[c.Harness], model)
	}
	options := make([]string, 0, len(c.Allowed))
	for _, name := range c.Allowed {
		options = append(options, "  "+c.describe(name))
	}
	return "\nChoose the harness for each subagent from the ones the person allows:\n" + strings.Join(options, "\n") +
		"\nFrontier harnesses are stronger on hard, open-ended work. A local model is private and free per token, " +
		"but weaker and may not see pictures. Without --harness a subagent gets " + c.Allowed[0] + ".\n"
}

func orchestratorPrompt(c WorkerChoice) string {
	return fmt.Sprintf(orchestratorBrief, c.spawnFlags(), maxLiveWorkers, c.help())
}
