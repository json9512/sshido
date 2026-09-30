package main

import (
	"context"
	"encoding/json"
	"io"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestPickSumsLetterVariants(t *testing.T) {
	top := map[string]float64{"A": -2.0, " B": -1.5, "B": -1.5, "C": -3, "b": -0.1, "<think>": -0.01}
	pick, err := pickFromLogprobs(top, 3, "m")
	if err != nil {
		t.Fatal(err)
	}
	if pick.Index != 1 {
		t.Fatalf("B variants should win, got %d %v", pick.Index, pick.Probs)
	}
	sum := pick.Probs[0] + pick.Probs[1] + pick.Probs[2]
	if math.Abs(sum-1) > 1e-9 {
		t.Fatalf("probabilities sum to %v", sum)
	}
	if _, err := pickFromLogprobs(map[string]float64{"<think>": 0}, 3, "m"); err == nil {
		t.Fatal("no option letter must be an error")
	}
	missing, err := pickFromLogprobs(map[string]float64{"C": -0.5}, 3, "m")
	if err != nil || missing.Index != 2 || missing.Probs[0] != 0 {
		t.Fatalf("absent letters get zero: %+v %v", missing, err)
	}
}

func TestLocalPickerRequest(t *testing.T) {
	var got map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			t.Errorf("path %s", r.URL.Path)
		}
		body, _ := io.ReadAll(r.Body)
		json.Unmarshal(body, &got)
		io.WriteString(w, `{"choices":[{"logprobs":{"content":[{"top_logprobs":[{"token":"B","logprob":-0.02},{"token":"A","logprob":-4.6}]}]}}]}`)
	}))
	defer server.Close()
	picker := newPicker(server.URL+"/v1/", "qwen3.6:35b-instruct")
	pick, err := picker.Pick(context.Background(), "state", "Who?", []PickOption{{Name: "poet", Description: "p"}, {Name: "critic", Description: "c"}})
	if err != nil || pick.Index != 1 {
		t.Fatalf("pick %+v %v", pick, err)
	}
	if got["max_tokens"] != float64(1) || got["logprobs"] != true || got["temperature"] != float64(0) || got["model"] != "qwen3.6:35b-instruct" {
		t.Fatalf("request %v", got)
	}
	content := got["messages"].([]any)[0].(map[string]any)["content"].(string)
	if !strings.HasSuffix(content, "A) poet: p\nB) critic: c\nAnswer with the letter only.") {
		t.Fatalf("prompt %q", content)
	}
}

func TestLocalPickerErrors(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "no such model", http.StatusNotFound)
	}))
	defer server.Close()
	if _, err := newPicker(server.URL, "m").Pick(context.Background(), "s", "q", []PickOption{{Name: "a"}}); err == nil || !strings.Contains(err.Error(), "http 404") {
		t.Fatalf("want http error, got %v", err)
	}
	if _, ok := newPicker("", "m").(noPicker); !ok {
		t.Fatal("no URL means no picker")
	}
	if _, ok := newPicker("http://x", " ").(noPicker); !ok {
		t.Fatal("no model means no picker")
	}
}

func TestClipHistoryKeepsRunesWhole(t *testing.T) {
	long := strings.Repeat("가", pickerHistoryChars) + "a"
	clipped := clipHistory(long)
	if !strings.HasPrefix(clipped, "[earlier messages removed]\n가") || !utf8.ValidString(clipped) {
		t.Fatalf("clipped badly: %q", clipped[:40])
	}
	if clipHistory("short") != "short" {
		t.Fatal("short history must pass through")
	}
}
