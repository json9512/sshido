package main

import "sync"

type Hub struct {
	mu   sync.Mutex
	subs map[chan AppEvent]struct{}
}

func newHub() *Hub { return &Hub{subs: map[chan AppEvent]struct{}{}} }

func (h *Hub) Subscribe() (<-chan AppEvent, func()) {
	ch := make(chan AppEvent, 256)
	h.mu.Lock()
	h.subs[ch] = struct{}{}
	h.mu.Unlock()
	return ch, func() {
		h.mu.Lock()
		defer h.mu.Unlock()
		if _, ok := h.subs[ch]; !ok {
			return
		}
		delete(h.subs, ch)
		close(ch)
	}
}

func (h *Hub) Publish(ev AppEvent) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for ch := range h.subs {
		select {
		case ch <- ev:
		default:
			delete(h.subs, ch)
			close(ch)
		}
	}
}
