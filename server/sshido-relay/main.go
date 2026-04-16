package main

import (
	"crypto/rand"
	"database/sql"
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
	_ "modernc.org/sqlite"
)

type config struct {
	addr       string
	dbPath     string
	keyPath    string
	keyID      string
	teamID     string
	bundleID   string
	production bool
	publicURL  string
}

type server struct {
	cfg    config
	db     *sql.DB
	apns   *apns2.Client
	bundle string
}

func main() {
	cfg := config{}
	flag.StringVar(&cfg.addr, "addr", "0.0.0.0:8787", "listen address")
	flag.StringVar(&cfg.dbPath, "db", "sshido-relay.db", "sqlite path")
	flag.StringVar(&cfg.keyPath, "key", "", "APNs .p8 file path")
	flag.StringVar(&cfg.keyID, "key-id", "", "APNs Key ID")
	flag.StringVar(&cfg.teamID, "team-id", "", "Apple Team ID")
	flag.StringVar(&cfg.bundleID, "bundle-id", "com.sshido.app", "iOS bundle id")
	flag.BoolVar(&cfg.production, "production", false, "use production APNs")
	flag.StringVar(&cfg.publicURL, "public-url", "http://127.0.0.1:8787", "public base URL returned to clients")
	flag.Parse()

	s, err := newServer(cfg)
	if err != nil {
		log.Fatal(err)
	}
	defer s.db.Close()

	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.health)
	mux.HandleFunc("/subscribe", s.subscribe)
	mux.HandleFunc("/n/", s.notify)
	mux.HandleFunc("/", s.root)

	log.Printf("sshido push server on %s (apns=%v)", cfg.addr, s.apns != nil)
	log.Fatal(http.ListenAndServe(cfg.addr, mux))
}

func newServer(cfg config) (*server, error) {
	db, err := sql.Open("sqlite", cfg.dbPath)
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}
	if _, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS subscribers (
			id           TEXT PRIMARY KEY,
			device_token TEXT NOT NULL,
			created_at   INTEGER NOT NULL,
			updated_at   INTEGER NOT NULL,
			notify_count INTEGER NOT NULL DEFAULT 0
		);
		CREATE INDEX IF NOT EXISTS idx_subscribers_device ON subscribers(device_token);
	`); err != nil {
		return nil, fmt.Errorf("schema: %w", err)
	}

	s := &server{cfg: cfg, db: db, bundle: cfg.bundleID}

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

func (s *server) health(w http.ResponseWriter, _ *http.Request) {
	if err := s.db.Ping(); err != nil {
		http.Error(w, "db down", 503)
		return
	}
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
	now := time.Now().Unix()
	var id string
	row := s.db.QueryRow(`SELECT id FROM subscribers WHERE device_token = ?`, req.DeviceToken)
	switch err := row.Scan(&id); {
	case errors.Is(err, sql.ErrNoRows):
		id = randomID()
		if _, err := s.db.Exec(
			`INSERT INTO subscribers(id,device_token,created_at,updated_at) VALUES(?,?,?,?)`,
			id, req.DeviceToken, now, now,
		); err != nil {
			http.Error(w, "db insert failed", 500)
			return
		}
	case err != nil:
		http.Error(w, "db error", 500)
		return
	default:
		_, _ = s.db.Exec(`UPDATE subscribers SET updated_at = ? WHERE id = ?`, now, id)
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(subscribeResp{
		ID:        id,
		NotifyURL: strings.TrimRight(s.cfg.publicURL, "/") + "/n/" + id,
	})
}

type notifyReq struct {
	Title      string `json:"title"`
	Body       string `json:"body"`
	Priority   string `json:"priority"` // "high" | "normal"
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
	var deviceToken string
	if err := s.db.QueryRow(`SELECT device_token FROM subscribers WHERE id = ?`, id).Scan(&deviceToken); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			http.Error(w, "unknown subscriber", 404)
			return
		}
		http.Error(w, "db error", 500)
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
		DeviceToken: deviceToken,
		Topic:       firstNonEmpty(req.Topic, s.bundle),
		Payload:     pl,
	}
	if req.Priority == "high" {
		n.Priority = apns2.PriorityHigh
	} else {
		n.Priority = apns2.PriorityLow
	}

	if s.apns == nil {
		log.Printf("[notify-stub] id=%s title=%q body=%q prio=%s",
			id, req.Title, req.Body, req.Priority)
		_, _ = s.db.Exec(`UPDATE subscribers SET notify_count = notify_count + 1 WHERE id = ?`, id)
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
		deviceToken[:min(8, len(deviceToken))], s.apnsHostLabel(),
		req.SessionRef, req.HostRef)
	if !res.Sent() {
		http.Error(w, fmt.Sprintf("apns %d %s", res.StatusCode, res.Reason), 502)
		return
	}
	_, _ = s.db.Exec(`UPDATE subscribers SET notify_count = notify_count + 1 WHERE id = ?`, id)
	w.WriteHeader(204)
}

func (s *server) apnsHostLabel() string {
	if s.cfg.production {
		return "production"
	}
	return "development"
}

func min(a, b int) int { if a < b { return a }; return b }

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
