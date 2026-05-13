package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"golang.org/x/time/rate"
)

func newTestServer(t *testing.T) *server {
	t.Helper()
	store, err := newSQLiteStore(":memory:")
	if err != nil {
		t.Fatalf("newSQLiteStore: %v", err)
	}
	t.Cleanup(func() { _ = store.Close() })
	return &server{
		cfg:    config{publicURL: "http://test.example", privacyContact: "privacy@sshido.com"},
		store:  store,
		bundle: "com.sshido.app",
		// apns nil → notify handler returns 202 "queued (no APNs configured)"
	}
}

// MaxBytesReader needs an http.ResponseWriter; httptest.NewRecorder
// satisfies it. We test the handlers directly so we don't pull in
// the rate-limit middleware (covered separately below).

func TestSubscribeBodyCap(t *testing.T) {
	s := newTestServer(t)
	// Build valid-looking JSON whose string value blows past the 1 KiB
	// cap. Junk-byte garbage (2 MiB of 'a') would trip the JSON syntax
	// error before MaxBytesReader gets a chance, so use a real field.
	huge := strings.Repeat("a", 2<<20) // 2 MiB
	body := `{"deviceToken":"` + huge + `"}`
	req := httptest.NewRequest(http.MethodPost, "/subscribe", strings.NewReader(body))
	w := httptest.NewRecorder()
	s.subscribe(w, req)
	if w.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("expected 413 for oversized /subscribe; got %d body=%q", w.Code, w.Body.String())
	}
}

func TestNotifyBodyCap(t *testing.T) {
	s := newTestServer(t)
	// Seed a subscriber so LookupByID succeeds before we hit the body cap.
	sub, err := s.store.UpsertByDeviceToken(t.Context(), "devtok123", func() string { return "fixedID" }, time.Now().Unix())
	if err != nil {
		t.Fatalf("seed subscriber: %v", err)
	}

	huge := strings.Repeat("a", 2<<20) // 2 MiB
	body := `{"title":"` + huge + `"}`
	req := httptest.NewRequest(http.MethodPost, "/n/"+sub.ID, strings.NewReader(body))
	w := httptest.NewRecorder()
	s.notify(w, req)
	if w.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("expected 413 for oversized /n/<id>; got %d body=%q", w.Code, w.Body.String())
	}
}

func TestSubscribeHappyPath(t *testing.T) {
	s := newTestServer(t)
	req := httptest.NewRequest(http.MethodPost, "/subscribe", strings.NewReader(`{"deviceToken":"abc"}`))
	w := httptest.NewRecorder()
	s.subscribe(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200; got %d body=%q", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), `"id":`) || !strings.Contains(w.Body.String(), `"notifyURL":`) {
		t.Fatalf("unexpected response body: %q", w.Body.String())
	}
}

func TestRateLimitReturns429(t *testing.T) {
	// Tight bucket so the test runs fast: 1 rps with burst 3.
	// 10 immediate requests from the same IP should yield ~3 passes
	// and ~7 throttled (the bucket refills at 1 rps).
	lim := newIPLimiter(rate.Limit(1), 3)
	s := newTestServer(t)
	h := lim.middleware(s.subscribe)

	var throttled, accepted int
	for i := 0; i < 10; i++ {
		req := httptest.NewRequest(http.MethodPost, "/subscribe", strings.NewReader(`{"deviceToken":"abc"}`))
		req.RemoteAddr = "203.0.113.7:1234"
		w := httptest.NewRecorder()
		h(w, req)
		switch w.Code {
		case http.StatusTooManyRequests:
			throttled++
		case http.StatusOK:
			accepted++
		}
	}
	if throttled == 0 {
		t.Fatalf("expected at least one 429 after 10 rapid requests; got accepted=%d throttled=%d", accepted, throttled)
	}
	if accepted == 0 {
		t.Fatalf("expected at least one 200 (burst capacity); got accepted=%d throttled=%d", accepted, throttled)
	}
}

func TestRateLimitIsPerIP(t *testing.T) {
	// Different source IPs share neither the bucket nor each other's
	// throttling — each gets its own limiter.
	lim := newIPLimiter(rate.Limit(1), 2)
	s := newTestServer(t)
	h := lim.middleware(s.subscribe)

	send := func(ip string) int {
		req := httptest.NewRequest(http.MethodPost, "/subscribe", strings.NewReader(`{"deviceToken":"abc"}`))
		req.RemoteAddr = ip + ":4444"
		w := httptest.NewRecorder()
		h(w, req)
		return w.Code
	}

	// Exhaust IP A's burst.
	_ = send("203.0.113.1")
	_ = send("203.0.113.1")
	if code := send("203.0.113.1"); code != http.StatusTooManyRequests {
		t.Fatalf("expected IP A to be throttled by 3rd request; got %d", code)
	}
	// IP B should still get a fresh bucket.
	if code := send("203.0.113.2"); code != http.StatusOK {
		t.Fatalf("expected IP B to be accepted; got %d", code)
	}
}

func TestClientIPParsesXForwardedFor(t *testing.T) {
	cases := map[string]string{
		"203.0.113.5":                              "203.0.113.5",
		"203.0.113.5, 10.0.0.1":                    "203.0.113.5",
		"  203.0.113.5  ,  10.0.0.1 ":              "203.0.113.5",
		"2001:db8::1, 192.168.1.1":                 "2001:db8::1",
	}
	for header, want := range cases {
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.Header.Set("X-Forwarded-For", header)
		got := clientIP(req)
		if got != want {
			t.Fatalf("clientIP(%q) = %q; want %q", header, got, want)
		}
	}
}

func TestClientIPFallsBackToRemoteAddr(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "198.51.100.7:55555"
	if got := clientIP(req); got != "198.51.100.7" {
		t.Fatalf("clientIP fallback = %q; want 198.51.100.7", got)
	}
}
