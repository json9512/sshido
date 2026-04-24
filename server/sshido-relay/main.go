package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/sideshow/apns2"
	"github.com/sideshow/apns2/payload"
	"github.com/sideshow/apns2/token"
)

type config struct {
	addr              string
	storage           string // "sqlite" | "firestore"
	dbPath            string
	firestoreProject  string
	firestoreColl     string
	keyPath           string
	keyID             string
	teamID            string
	bundleID          string
	production        bool
	publicURL         string
}

type server struct {
	cfg    config
	store  Store
	apns   *apns2.Client
	bundle string
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func envBool(k string, def bool) bool {
	v := os.Getenv(k)
	if v == "" {
		return def
	}
	return v == "1" || strings.EqualFold(v, "true") || strings.EqualFold(v, "yes")
}

func main() {
	cfg := config{}
	flag.StringVar(&cfg.addr, "addr", env("ADDR", "0.0.0.0:8787"), "listen address")
	flag.StringVar(&cfg.storage, "storage", env("STORAGE", "sqlite"), "storage backend: sqlite | firestore")
	flag.StringVar(&cfg.dbPath, "db", env("DB_PATH", "sshido-relay.db"), "sqlite path (sqlite backend only)")
	flag.StringVar(&cfg.firestoreProject, "firestore-project", env("GOOGLE_CLOUD_PROJECT", ""), "GCP project id (firestore backend)")
	flag.StringVar(&cfg.firestoreColl, "firestore-collection", env("FIRESTORE_COLLECTION", "subscribers"), "firestore collection name")
	flag.StringVar(&cfg.keyPath, "key", env("APNS_KEY_PATH", ""), "APNs .p8 file path")
	flag.StringVar(&cfg.keyID, "key-id", env("APNS_KEY_ID", ""), "APNs Key ID")
	flag.StringVar(&cfg.teamID, "team-id", env("APNS_TEAM_ID", ""), "Apple Team ID")
	flag.StringVar(&cfg.bundleID, "bundle-id", env("APNS_BUNDLE_ID", "com.sshido.app"), "iOS bundle id")
	flag.BoolVar(&cfg.production, "production", envBool("APNS_PRODUCTION", false), "use production APNs")
	flag.StringVar(&cfg.publicURL, "public-url", env("PUBLIC_URL", "http://127.0.0.1:8787"), "public base URL returned to clients")
	flag.Parse()

	if p := os.Getenv("PORT"); p != "" {
		cfg.addr = "0.0.0.0:" + p
	}

	s, err := newServer(cfg)
	if err != nil {
		log.Fatal(err)
	}
	defer s.store.Close()

	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.health)
	mux.HandleFunc("/subscribe", s.subscribe)
	mux.HandleFunc("/n/", s.notify)
	mux.HandleFunc("/privacy", s.privacy)
	mux.HandleFunc("/", s.landing)

	log.Printf("sshido push server on %s (storage=%s apns=%v)", cfg.addr, cfg.storage, s.apns != nil)
	log.Fatal(http.ListenAndServe(cfg.addr, mux))
}

func newServer(cfg config) (*server, error) {
	ctx := context.Background()
	var store Store
	switch strings.ToLower(cfg.storage) {
	case "firestore":
		fs, err := newFirestoreStore(ctx, cfg.firestoreProject, cfg.firestoreColl)
		if err != nil {
			return nil, err
		}
		store = fs
	case "sqlite", "":
		ss, err := newSQLiteStore(cfg.dbPath)
		if err != nil {
			return nil, err
		}
		store = ss
	default:
		return nil, fmt.Errorf("unknown storage %q", cfg.storage)
	}

	s := &server{cfg: cfg, store: store, bundle: cfg.bundleID}

	if cfg.keyPath != "" && cfg.keyID != "" && cfg.teamID != "" {
		raw, err := os.ReadFile(cfg.keyPath)
		if err != nil {
			return nil, fmt.Errorf("read key: %w", err)
		}
		authKey, err := token.AuthKeyFromBytes(raw)
		if err != nil {
			return nil, fmt.Errorf("parse key: %w", err)
		}
		tk := &token.Token{AuthKey: authKey, KeyID: cfg.keyID, TeamID: cfg.teamID}
		client := apns2.NewTokenClient(tk)
		if cfg.production {
			client = client.Production()
		} else {
			client = client.Development()
		}
		s.apns = client
	} else {
		log.Print("APNs not configured; /n/<id> will log only")
	}
	return s, nil
}

func (s *server) root(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	fmt.Fprintln(w, "sshido push server")
}

func (s *server) health(w http.ResponseWriter, r *http.Request) {
	if err := s.store.HealthCheck(r.Context()); err != nil {
		http.Error(w, "store down: "+err.Error(), 503)
		return
	}
	if s.apns == nil {
		// APNs intentionally unconfigured means notifications won't actually
		// be delivered; reporting this as a degraded state lets external
		// uptime probes catch a broken deploy early.
		http.Error(w, "apns unconfigured", 503)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Write([]byte("ok"))
}

type subscribeReq struct {
	DeviceToken string `json:"deviceToken"`
}
type subscribeResp struct {
	ID        string `json:"id"`
	NotifyURL string `json:"notifyURL"`
}

func (s *server) subscribe(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", 405)
		return
	}
	var req subscribeReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.DeviceToken == "" {
		http.Error(w, "bad body", 400)
		return
	}
	sub, err := s.store.UpsertByDeviceToken(r.Context(), req.DeviceToken, randomID, time.Now().Unix())
	if err != nil {
		log.Printf("subscribe err: %v", err)
		http.Error(w, "store error", 500)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(subscribeResp{
		ID:        sub.ID,
		NotifyURL: strings.TrimRight(s.cfg.publicURL, "/") + "/n/" + sub.ID,
	})
}

type notifyReq struct {
	Title      string `json:"title"`
	Body       string `json:"body"`
	Priority   string `json:"priority"`
	Topic      string `json:"topic"`
	Sound      string `json:"sound"`
	SessionRef string `json:"sessionRef"`
	HostRef    string `json:"hostRef"`
}

func (s *server) notify(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", 405)
		return
	}
	id := strings.TrimPrefix(r.URL.Path, "/n/")
	if id == "" || strings.Contains(id, "/") {
		http.Error(w, "missing id", 400)
		return
	}
	sub, err := s.store.LookupByID(r.Context(), id)
	if errors.Is(err, ErrNotFound) {
		http.Error(w, "unknown subscriber", 404)
		return
	}
	if err != nil {
		http.Error(w, "store error", 500)
		return
	}
	var req notifyReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad body", 400)
		return
	}
	if req.Title == "" {
		req.Title = "sshido"
	}
	if req.Sound == "" {
		req.Sound = "default"
	}
	pl := payload.NewPayload().
		AlertTitle(req.Title).
		AlertBody(req.Body).
		Sound(req.Sound).
		Custom("subscriber_id", id)
	if req.SessionRef != "" {
		pl = pl.Custom("session_ref", req.SessionRef)
	}
	if req.HostRef != "" {
		pl = pl.Custom("host_ref", req.HostRef)
	}

	n := &apns2.Notification{
		DeviceToken: sub.DeviceToken,
		Topic:       firstNonEmpty(req.Topic, s.bundle),
		Payload:     pl,
	}
	if req.Priority == "high" {
		n.Priority = apns2.PriorityHigh
	} else {
		n.Priority = apns2.PriorityLow
	}

	if s.apns == nil {
		log.Printf("[notify-stub] id=%s title=%q body=%q prio=%s", id, req.Title, req.Body, req.Priority)
		_ = s.store.IncrementNotifyCount(r.Context(), id)
		w.WriteHeader(202)
		w.Write([]byte("queued (no APNs configured)"))
		return
	}
	res, err := s.apns.Push(n)
	if err != nil {
		log.Printf("apns push err id=%s: %v", id, err)
		http.Error(w, "apns push failed", 502)
		return
	}
	log.Printf("apns push id=%s status=%d reason=%q apnsID=%s topic=%s prio=%s tokenPrefix=%s env=%s session=%q host=%q",
		id, res.StatusCode, res.Reason, res.ApnsID, n.Topic, req.Priority,
		sub.DeviceToken[:min(8, len(sub.DeviceToken))], s.apnsHostLabel(),
		req.SessionRef, req.HostRef)
	if !res.Sent() {
		http.Error(w, fmt.Sprintf("apns %d %s", res.StatusCode, res.Reason), 502)
		return
	}
	_ = s.store.IncrementNotifyCount(r.Context(), id)
	w.WriteHeader(204)
}

func (s *server) apnsHostLabel() string {
	if s.cfg.production {
		return "production"
	}
	return "development"
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func randomID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func firstNonEmpty(a, b string) string {
	if a != "" {
		return a
	}
	return b
}
