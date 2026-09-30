package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"strings"
	"time"
)

type PickOption struct {
	Name        string
	Description string
}

type Pick struct {
	Index int
	Probs []float64
}

type Picker interface {
	Pick(ctx context.Context, state, question string, options []PickOption) (Pick, error)
}

const pickLetters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

var ErrNoPicker = errors.New("group chats need a picker model (SSHIDO_PICKER_MODEL) on the local endpoint (SSHIDO_LOCAL_URL)")

type localPicker struct {
	url    string
	model  string
	client *http.Client
}

func newPicker(localURL, model string) Picker {
	if strings.TrimSpace(localURL) == "" || strings.TrimSpace(model) == "" {
		return noPicker{}
	}
	return &localPicker{
		url:    strings.TrimRight(localURL, "/") + "/chat/completions",
		model:  model,
		client: &http.Client{Timeout: 5 * time.Minute},
	}
}

func pickPrompt(state, question string, options []PickOption) string {
	lines := make([]string, 0, len(options))
	for i, o := range options {
		lines = append(lines, fmt.Sprintf("%c) %s: %s", pickLetters[i], o.Name, o.Description))
	}
	return state + "\n\n---\nQuestion: " + question + "\n" + strings.Join(lines, "\n") + "\nAnswer with the letter only."
}

type completionResponse struct {
	Choices []struct {
		Logprobs struct {
			Content []struct {
				TopLogprobs []struct {
					Token   string  `json:"token"`
					Logprob float64 `json:"logprob"`
				} `json:"top_logprobs"`
			} `json:"content"`
		} `json:"logprobs"`
	} `json:"choices"`
}

func (p *localPicker) Pick(ctx context.Context, state, question string, options []PickOption) (Pick, error) {
	if len(options) == 0 || len(options) > len(pickLetters) {
		return Pick{}, fmt.Errorf("picker needs 1 to %d options, got %d", len(pickLetters), len(options))
	}
	body, err := json.Marshal(map[string]any{
		"model":        p.model,
		"messages":     []map[string]string{{"role": "user", "content": pickPrompt(state, question, options)}},
		"max_tokens":   1,
		"temperature":  0,
		"logprobs":     true,
		"top_logprobs": 20,
		"cache_prompt": true,
	})
	if err != nil {
		return Pick{}, fmt.Errorf("encode picker request: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.url, bytes.NewReader(body))
	if err != nil {
		return Pick{}, fmt.Errorf("picker request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := p.client.Do(req)
	if err != nil {
		return Pick{}, fmt.Errorf("picker %s: %w", p.url, err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return Pick{}, fmt.Errorf("read picker response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return Pick{}, fmt.Errorf("picker %s: http %d: %s", p.url, resp.StatusCode, truncate(strings.TrimSpace(string(data)), 300))
	}
	var parsed completionResponse
	if err := json.Unmarshal(data, &parsed); err != nil {
		return Pick{}, fmt.Errorf("picker response: %w", err)
	}
	if len(parsed.Choices) == 0 || len(parsed.Choices[0].Logprobs.Content) == 0 {
		return Pick{}, fmt.Errorf("picker model %s returned no logprobs; the endpoint must support logprobs on chat completions", p.model)
	}
	top := map[string]float64{}
	for _, t := range parsed.Choices[0].Logprobs.Content[0].TopLogprobs {
		top[t.Token] = t.Logprob
	}
	return pickFromLogprobs(top, len(options), p.model)
}

func pickFromLogprobs(top map[string]float64, n int, model string) (Pick, error) {
	logits := make([]float64, n)
	found := false
	for i := range logits {
		logits[i] = letterLogprob(top, string(pickLetters[i]))
		found = found || !math.IsInf(logits[i], -1)
	}
	if !found {
		return Pick{}, fmt.Errorf("picker model %s answered with no option letter; use an instruct (non-thinking) model", model)
	}
	return Pick{Index: argmax(logits), Probs: softmax(logits)}, nil
}

func letterLogprob(top map[string]float64, letter string) float64 {
	total := math.Inf(-1)
	for token, lp := range top {
		if strings.TrimSpace(token) != letter {
			continue
		}
		total = logAddExp(total, lp)
	}
	return total
}

func logAddExp(a, b float64) float64 {
	if math.IsInf(a, -1) {
		return b
	}
	hi, lo := math.Max(a, b), math.Min(a, b)
	return hi + math.Log1p(math.Exp(lo-hi))
}

func argmax(values []float64) int {
	best := 0
	for i, v := range values {
		if v <= values[best] {
			continue
		}
		best = i
	}
	return best
}

func softmax(logits []float64) []float64 {
	peak := logits[argmax(logits)]
	weights := make([]float64, len(logits))
	sum := 0.0
	for i, v := range logits {
		weights[i] = math.Exp(v - peak)
		sum += weights[i]
	}
	probs := make([]float64, len(logits))
	for i, w := range weights {
		probs[i] = w / sum
	}
	return probs
}

type noPicker struct{}

func (noPicker) Pick(context.Context, string, string, []PickOption) (Pick, error) {
	return Pick{}, ErrNoPicker
}
