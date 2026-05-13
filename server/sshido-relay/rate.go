package main

import (
	"net/http"
	"strings"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

// ipLimiter is a per-source-IP token-bucket rate limiter. It keeps a
// rate.Limiter for each IP it has seen and sweeps entries that haven't
// been touched within ttl.
//
// State is in-process only. Cloud Run runs up to max-instances copies,
// so the actual ceiling is rps × instances. The abuse vectors we care
// about (subscriber-spam, leaked-notify-URL spam) are unaffected by
// that ceiling — even 3× the per-instance limit kills the attack
// without affecting real users.
type ipLimiter struct {
	mu     sync.Mutex
	limits map[string]*ipEntry
	rps    rate.Limit
	burst  int
	ttl    time.Duration
}

type ipEntry struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

func newIPLimiter(rps rate.Limit, burst int) *ipLimiter {
	l := &ipLimiter{
		limits: map[string]*ipEntry{},
		rps:    rps,
		burst:  burst,
		ttl:    10 * time.Minute,
	}
	go l.sweepLoop()
	return l
}

func (l *ipLimiter) allow(ip string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	e, ok := l.limits[ip]
	now := time.Now()
	if !ok {
		e = &ipEntry{limiter: rate.NewLimiter(l.rps, l.burst), lastSeen: now}
		l.limits[ip] = e
		return e.limiter.Allow()
	}
	e.lastSeen = now
	return e.limiter.Allow()
}

func (l *ipLimiter) sweepLoop() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		cutoff := time.Now().Add(-l.ttl)
		l.mu.Lock()
		for ip, e := range l.limits {
			if e.lastSeen.Before(cutoff) {
				delete(l.limits, ip)
			}
		}
		l.mu.Unlock()
	}
}

func (l *ipLimiter) middleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !l.allow(clientIP(r)) {
			http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
			return
		}
		next(w, r)
	}
}

// clientIP extracts the originating client's IP from a request. Cloud
// Run sets X-Forwarded-For with the chain `client, lb1, lb2`; the
// leftmost entry is the real client. If the header is unset (local
// dev, direct requests), fall back to r.RemoteAddr stripped of port.
func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		if i := strings.Index(xff, ","); i >= 0 {
			return strings.TrimSpace(xff[:i])
		}
		return strings.TrimSpace(xff)
	}
	addr := r.RemoteAddr
	if i := strings.LastIndex(addr, ":"); i >= 0 {
		return addr[:i]
	}
	return addr
}
