package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type Pusher interface {
	Push(ctx context.Context, title, body string, high bool) error
}

type relayPusher struct {
	url    string
	host   string
	client *http.Client
}

func newRelayPusher(url, host string) Pusher {
	if url == "" {
		return noPush{}
	}
	return &relayPusher{url: url, host: host, client: &http.Client{Timeout: 10 * time.Second}}
}

func (p *relayPusher) Push(ctx context.Context, title, body string, high bool) error {
	priority := "normal"
	if high {
		priority = "high"
	}
	payload, err := json.Marshal(map[string]string{
		"title": title, "body": truncate(body, 400), "priority": priority,
		"sessionRef": "agents", "hostRef": p.host,
	})
	if err != nil {
		return fmt.Errorf("encode push: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.url, bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("push request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := p.client.Do(req)
	if err != nil {
		return fmt.Errorf("push: %w", err)
	}
	resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("push: relay answered http %d", resp.StatusCode)
	}
	return nil
}

type noPush struct{}

func (noPush) Push(context.Context, string, string, bool) error { return nil }
