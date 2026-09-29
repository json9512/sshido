package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	_ "modernc.org/sqlite"
)

var ErrNotFound = errors.New("not found")

type Store struct {
	db  *sql.DB
	now func() time.Time
}

func openStore(path string, now func() time.Time) (*Store, error) {
	db, err := sql.Open("sqlite", path+"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)")
	if err != nil {
		return nil, fmt.Errorf("open store: %w", err)
	}
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS messages (
			id         INTEGER PRIMARY KEY AUTOINCREMENT,
			agent_id   TEXT NOT NULL DEFAULT '',
			author     TEXT NOT NULL,
			kind       TEXT NOT NULL,
			text       TEXT NOT NULL,
			created_at INTEGER NOT NULL
		);
		CREATE TABLE IF NOT EXISTS agents (
			id         TEXT PRIMARY KEY,
			name       TEXT NOT NULL,
			role       TEXT NOT NULL,
			harness    TEXT NOT NULL,
			model      TEXT NOT NULL DEFAULT '',
			status     TEXT NOT NULL,
			task       TEXT NOT NULL DEFAULT '',
			session    TEXT NOT NULL DEFAULT '',
			container  TEXT NOT NULL,
			token_hash TEXT NOT NULL,
			created_at INTEGER NOT NULL,
			updated_at INTEGER NOT NULL
		);
	`); err != nil {
		return nil, fmt.Errorf("store schema: %w", err)
	}
	return &Store{db: db, now: now}, nil
}

func (s *Store) Close() error { return s.db.Close() }

func tokenHash(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func (s *Store) AddMessage(agentID, author, kind, text string) (Message, error) {
	created := s.now().UnixMilli()
	res, err := s.db.Exec(
		`INSERT INTO messages (agent_id, author, kind, text, created_at) VALUES (?, ?, ?, ?, ?)`,
		agentID, author, kind, text, created)
	if err != nil {
		return Message{}, fmt.Errorf("add message: %w", err)
	}
	id, err := res.LastInsertId()
	if err != nil {
		return Message{}, fmt.Errorf("add message id: %w", err)
	}
	return Message{ID: id, AgentID: agentID, Author: author, Kind: kind, Text: text, CreatedAt: created}, nil
}

func (s *Store) MessagesSince(since int64) ([]Message, error) {
	rows, err := s.db.Query(
		`SELECT id, agent_id, author, kind, text, created_at FROM messages WHERE id > ? ORDER BY id`, since)
	if err != nil {
		return nil, fmt.Errorf("messages since: %w", err)
	}
	defer rows.Close()
	var out []Message
	for rows.Next() {
		var m Message
		if err := rows.Scan(&m.ID, &m.AgentID, &m.Author, &m.Kind, &m.Text, &m.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan message: %w", err)
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

func (s *Store) AddAgent(a Agent, token string) (Agent, error) {
	now := s.now().UnixMilli()
	stored := Agent{
		ID: a.ID, Name: a.Name, Role: a.Role, Harness: a.Harness, Model: a.Model,
		Status: a.Status, Task: a.Task, Container: a.Container, CreatedAt: now, UpdatedAt: now,
	}
	_, err := s.db.Exec(
		`INSERT INTO agents (id, name, role, harness, model, status, task, session, container, token_hash, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, '', ?, ?, ?, ?)`,
		stored.ID, stored.Name, stored.Role, stored.Harness, stored.Model, stored.Status, stored.Task,
		stored.Container, tokenHash(token), now, now)
	if err != nil {
		return Agent{}, fmt.Errorf("add agent: %w", err)
	}
	return stored, nil
}

const agentColumns = `id, name, role, harness, model, status, task, session, container, created_at, updated_at`

func scanAgent(row interface{ Scan(...any) error }) (Agent, error) {
	var a Agent
	err := row.Scan(&a.ID, &a.Name, &a.Role, &a.Harness, &a.Model, &a.Status, &a.Task, &a.Session,
		&a.Container, &a.CreatedAt, &a.UpdatedAt)
	return a, err
}

func (s *Store) Agent(id string) (Agent, error) {
	a, err := scanAgent(s.db.QueryRow(`SELECT `+agentColumns+` FROM agents WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return Agent{}, ErrNotFound
	}
	if err != nil {
		return Agent{}, fmt.Errorf("agent %s: %w", id, err)
	}
	return a, nil
}

func (s *Store) AgentByToken(token string) (Agent, error) {
	a, err := scanAgent(s.db.QueryRow(`SELECT `+agentColumns+` FROM agents WHERE token_hash = ?`, tokenHash(token)))
	if errors.Is(err, sql.ErrNoRows) {
		return Agent{}, ErrNotFound
	}
	if err != nil {
		return Agent{}, fmt.Errorf("agent by token: %w", err)
	}
	return a, nil
}

func (s *Store) Orchestrator() (Agent, error) {
	a, err := scanAgent(s.db.QueryRow(
		`SELECT `+agentColumns+` FROM agents WHERE role = ? ORDER BY created_at LIMIT 1`, RoleOrchestrator))
	if errors.Is(err, sql.ErrNoRows) {
		return Agent{}, ErrNotFound
	}
	if err != nil {
		return Agent{}, fmt.Errorf("orchestrator: %w", err)
	}
	return a, nil
}

func (s *Store) Agents() ([]Agent, error) {
	rows, err := s.db.Query(`SELECT ` + agentColumns + ` FROM agents ORDER BY created_at`)
	if err != nil {
		return nil, fmt.Errorf("agents: %w", err)
	}
	defer rows.Close()
	var out []Agent
	for rows.Next() {
		a, err := scanAgent(rows)
		if err != nil {
			return nil, fmt.Errorf("scan agent: %w", err)
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

func (s *Store) SetStatus(id, status string) (Agent, error) {
	if _, err := s.db.Exec(`UPDATE agents SET status = ?, updated_at = ? WHERE id = ?`,
		status, s.now().UnixMilli(), id); err != nil {
		return Agent{}, fmt.Errorf("set status %s: %w", id, err)
	}
	return s.Agent(id)
}

func (s *Store) SetSession(id, session string) error {
	if _, err := s.db.Exec(`UPDATE agents SET session = ?, updated_at = ? WHERE id = ?`,
		session, s.now().UnixMilli(), id); err != nil {
		return fmt.Errorf("set session %s: %w", id, err)
	}
	return nil
}
