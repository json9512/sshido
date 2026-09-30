package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRelayPushSendsPlainText(t *testing.T) {
	got := make(chan map[string]string, 1)
	relay := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]string
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Errorf("decode: %v", err)
		}
		got <- body
		w.WriteHeader(http.StatusNoContent)
	}))
	defer relay.Close()

	push := newRelayPusher(relay.URL, "mac")
	if err := push.Push(context.Background(), "**Check** replied", "## Summary\n\n- `main.go` is **fixed**\n- see [PR](https://x/1)", true); err != nil {
		t.Fatal(err)
	}
	body := <-got
	if body["title"] != "Check replied" {
		t.Fatalf("title %q", body["title"])
	}
	if body["body"] != "Summary\n\nmain.go is fixed\nsee PR" {
		t.Fatalf("body %q", body["body"])
	}
	if body["priority"] != "high" || body["hostRef"] != "mac" || body["sessionRef"] != "agents" {
		t.Fatalf("fields %v", body)
	}
}
