package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
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
	if _, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS chats (
			id         TEXT PRIMARY KEY,
			title      TEXT NOT NULL,
			kind       TEXT NOT NULL,
			turn_cap   INTEGER NOT NULL DEFAULT 0,
			status     TEXT NOT NULL,
			created_at INTEGER NOT NULL
		);
	`); err != nil {
		return nil, fmt.Errorf("store chats schema: %w", err)
	}
	for _, column := range []struct{ table, def string }{
		{"messages", "attach_name TEXT NOT NULL DEFAULT ''"},
		{"messages", "attach_path TEXT NOT NULL DEFAULT ''"},
		{"messages", "attach_mime TEXT NOT NULL DEFAULT ''"},
		{"messages", "attach_size INTEGER NOT NULL DEFAULT 0"},
		{"messages", "chat_id TEXT NOT NULL DEFAULT ''"},
		{"agents", "chat_id TEXT NOT NULL DEFAULT ''"},
		{"agents", "seen INTEGER NOT NULL DEFAULT 0"},
		{"agents", "mounts TEXT NOT NULL DEFAULT ''"},
		{"agents", "briefed TEXT NOT NULL DEFAULT ''"},
		{"agents", "goal TEXT NOT NULL DEFAULT ''"},
		{"agents", "work_status TEXT NOT NULL DEFAULT ''"},
		{"agents", "verification TEXT NOT NULL DEFAULT ''"},
		{"agents", "verdict TEXT NOT NULL DEFAULT ''"},
		{"agents", "verdict_note TEXT NOT NULL DEFAULT ''"},
	} {
		if _, err := db.Exec("ALTER TABLE " + column.table + " ADD COLUMN " + column.def); err != nil && !strings.Contains(err.Error(), "duplicate column") {
			return nil, fmt.Errorf("migrate %s %s: %w", column.table, column.def, err)
		}
	}
	store := &Store{db: db, now: now}
	if err := store.adoptUnchattedRows(); err != nil {
		return nil, err
	}
	return store, nil
}

const firstChatTitle = "Agents"

func (s *Store) adoptUnchattedRows() error {
	var orphans int
	if err := s.db.QueryRow(`SELECT (SELECT COUNT(*) FROM messages WHERE chat_id = '') + (SELECT COUNT(*) FROM agents WHERE chat_id = '')`).Scan(&orphans); err != nil {
		return fmt.Errorf("count rows without a chat: %w", err)
	}
	if orphans == 0 {
		return nil
	}
	tx, err := s.db.Begin()
	if err != nil {
		return fmt.Errorf("migrate to chats: %w", err)
	}
	defer tx.Rollback()
	id := randomHex(4)
	if _, err := tx.Exec(`INSERT INTO chats (id, title, kind, turn_cap, status, created_at) VALUES (?, ?, 'orchestrated', 0, 'idle', ?)`,
		id, firstChatTitle, s.now().UnixMilli()); err != nil {
		return fmt.Errorf("create first chat: %w", err)
	}
	for _, table := range []string{"messages", "agents"} {
		if _, err := tx.Exec(`UPDATE `+table+` SET chat_id = ? WHERE chat_id = ''`, id); err != nil {
			return fmt.Errorf("move %s into the first chat: %w", table, err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("migrate to chats: %w", err)
	}
	return nil
}

func (s *Store) AddChat(title string) (Chat, error) {
	c := Chat{ID: randomHex(4), Title: title, CreatedAt: s.now().UnixMilli()}
	if _, err := s.db.Exec(`INSERT INTO chats (id, title, kind, turn_cap, status, created_at) VALUES (?, ?, 'orchestrated', 0, 'idle', ?)`,
		c.ID, c.Title, c.CreatedAt); err != nil {
		return Chat{}, fmt.Errorf("add chat: %w", err)
	}
	return c, nil
}

const chatColumns = `id, title, created_at`

func scanChat(row interface{ Scan(...any) error }) (Chat, error) {
	var c Chat
	err := row.Scan(&c.ID, &c.Title, &c.CreatedAt)
	return c, err
}

func (s *Store) Chat(id string) (Chat, error) {
	c, err := scanChat(s.db.QueryRow(`SELECT `+chatColumns+` FROM chats WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return Chat{}, ErrNotFound
	}
	if err != nil {
		return Chat{}, fmt.Errorf("chat %s: %w", id, err)
	}
	return c, nil
}

func (s *Store) Chats() ([]Chat, error) {
	rows, err := s.db.Query(`SELECT ` + chatColumns + ` FROM chats ORDER BY created_at`)
	if err != nil {
		return nil, fmt.Errorf("chats: %w", err)
	}
	defer rows.Close()
	var out []Chat
	for rows.Next() {
		c, err := scanChat(rows)
		if err != nil {
			return nil, fmt.Errorf("scan chat: %w", err)
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Store) DeleteChat(id string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return fmt.Errorf("delete chat %s: %w", id, err)
	}
	defer tx.Rollback()
	for _, stmt := range []string{
		`DELETE FROM messages WHERE chat_id = ?`,
		`DELETE FROM agents WHERE chat_id = ?`,
		`DELETE FROM chats WHERE id = ?`,
	} {
		if _, err := tx.Exec(stmt, id); err != nil {
			return fmt.Errorf("delete chat %s: %w", id, err)
		}
	}
	return tx.Commit()
}

func (s *Store) Close() error { return s.db.Close() }

func tokenHash(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func (s *Store) AddMessage(chatID, agentID, author, kind, text string) (Message, error) {
	created := s.now().UnixMilli()
	res, err := s.db.Exec(
		`INSERT INTO messages (chat_id, agent_id, author, kind, text, created_at) VALUES (?, ?, ?, ?, ?, ?)`,
		chatID, agentID, author, kind, text, created)
	if err != nil {
		return Message{}, fmt.Errorf("add message: %w", err)
	}
	id, err := res.LastInsertId()
	if err != nil {
		return Message{}, fmt.Errorf("add message id: %w", err)
	}
	return Message{ID: id, ChatID: chatID, AgentID: agentID, Author: author, Kind: kind, Text: text, CreatedAt: created}, nil
}

func (s *Store) AddAttachment(chatID, agentID, author, caption string, att Attachment) (Message, error) {
	created := s.now().UnixMilli()
	res, err := s.db.Exec(
		`INSERT INTO messages (chat_id, agent_id, author, kind, text, created_at, attach_name, attach_path, attach_mime, attach_size)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		chatID, agentID, author, KindFile, caption, created, att.Name, att.Path, att.Mime, att.Size)
	if err != nil {
		return Message{}, fmt.Errorf("add attachment: %w", err)
	}
	id, err := res.LastInsertId()
	if err != nil {
		return Message{}, fmt.Errorf("add attachment id: %w", err)
	}
	return Message{ID: id, ChatID: chatID, AgentID: agentID, Author: author, Kind: KindFile, Text: caption, CreatedAt: created, Attachment: &att}, nil
}

const messageColumns = `id, chat_id, agent_id, author, kind, text, created_at, attach_name, attach_path, attach_mime, attach_size`

func scanMessage(row interface{ Scan(...any) error }) (Message, error) {
	var m Message
	var att Attachment
	if err := row.Scan(&m.ID, &m.ChatID, &m.AgentID, &m.Author, &m.Kind, &m.Text, &m.CreatedAt, &att.Name, &att.Path, &att.Mime, &att.Size); err != nil {
		return Message{}, err
	}
	if att.Path == "" {
		return m, nil
	}
	return Message{ID: m.ID, ChatID: m.ChatID, AgentID: m.AgentID, Author: m.Author, Kind: m.Kind, Text: m.Text, CreatedAt: m.CreatedAt, Attachment: &att}, nil
}

func (s *Store) Message(id int64) (Message, error) {
	m, err := scanMessage(s.db.QueryRow(`SELECT `+messageColumns+` FROM messages WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return Message{}, ErrNotFound
	}
	if err != nil {
		return Message{}, fmt.Errorf("message %d: %w", id, err)
	}
	return m, nil
}

func (s *Store) MessagesSince(since int64) ([]Message, error) {
	return s.queryMessages(`SELECT `+messageColumns+` FROM messages WHERE id > ? ORDER BY id`, since)
}

func (s *Store) ChatMessagesAfter(chatID string, after int64) ([]Message, error) {
	return s.queryMessages(`SELECT `+messageColumns+` FROM messages WHERE chat_id = ? AND id > ? ORDER BY id`, chatID, after)
}

func (s *Store) queryMessages(query string, args ...any) ([]Message, error) {
	rows, err := s.db.Query(query, args...)
	if err != nil {
		return nil, fmt.Errorf("messages: %w", err)
	}
	defer rows.Close()
	var out []Message
	for rows.Next() {
		m, err := scanMessage(rows)
		if err != nil {
			return nil, fmt.Errorf("scan message: %w", err)
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

func (s *Store) AddAgent(a Agent, token string) (Agent, error) {
	now := s.now().UnixMilli()
	stored := Agent{
		ID: a.ID, ChatID: a.ChatID, Name: a.Name, Role: a.Role, Harness: a.Harness, Model: a.Model,
		Status: a.Status, Task: a.Task, Goal: a.Goal, WorkStatus: a.WorkStatus,
		Mounts: a.Mounts, Container: a.Container, CreatedAt: now, UpdatedAt: now,
	}
	_, err := s.db.Exec(
		`INSERT INTO agents (id, chat_id, name, role, harness, model, status, task, goal, work_status, session, mounts, container, token_hash, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?, ?, ?, ?, ?)`,
		stored.ID, stored.ChatID, stored.Name, stored.Role, stored.Harness, stored.Model, stored.Status, stored.Task,
		stored.Goal, stored.WorkStatus, stored.Mounts, stored.Container, tokenHash(token), now, now)
	if err != nil {
		return Agent{}, fmt.Errorf("add agent: %w", err)
	}
	return stored, nil
}

const agentColumns = `id, chat_id, name, role, harness, model, status, task, goal, work_status, verification, verdict, verdict_note, session, mounts, briefed, container, created_at, updated_at`

func scanAgent(row interface{ Scan(...any) error }) (Agent, error) {
	var a Agent
	err := row.Scan(&a.ID, &a.ChatID, &a.Name, &a.Role, &a.Harness, &a.Model, &a.Status, &a.Task,
		&a.Goal, &a.WorkStatus, &a.Verification, &a.Verdict, &a.VerdictNote, &a.Session,
		&a.Mounts, &a.Briefed, &a.Container, &a.CreatedAt, &a.UpdatedAt)
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

func (s *Store) Orchestrator(chatID string) (Agent, error) {
	a, err := scanAgent(s.db.QueryRow(
		`SELECT `+agentColumns+` FROM agents WHERE chat_id = ? AND role = ? ORDER BY created_at LIMIT 1`, chatID, RoleOrchestrator))
	if errors.Is(err, sql.ErrNoRows) {
		return Agent{}, ErrNotFound
	}
	if err != nil {
		return Agent{}, fmt.Errorf("orchestrator: %w", err)
	}
	return a, nil
}

func (s *Store) Agents() ([]Agent, error) {
	return s.queryAgents(`SELECT ` + agentColumns + ` FROM agents ORDER BY created_at, rowid`)
}

func (s *Store) ChatAgents(chatID string) ([]Agent, error) {
	return s.queryAgents(`SELECT `+agentColumns+` FROM agents WHERE chat_id = ? ORDER BY created_at, rowid`, chatID)
}

func (s *Store) queryAgents(query string, args ...any) ([]Agent, error) {
	rows, err := s.db.Query(query, args...)
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

func (s *Store) SetRecord(id string, r Record) (Agent, error) {
	if _, err := s.db.Exec(`UPDATE agents SET goal = ?, work_status = ?, verification = ?, verdict = ?, verdict_note = ?, updated_at = ? WHERE id = ?`,
		r.Goal, r.WorkStatus, r.Verification, r.Verdict, r.VerdictNote, s.now().UnixMilli(), id); err != nil {
		return Agent{}, fmt.Errorf("set record %s: %w", id, err)
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

func (s *Store) SetBriefed(id, briefed string) error {
	if _, err := s.db.Exec(`UPDATE agents SET briefed = ? WHERE id = ?`, briefed, id); err != nil {
		return fmt.Errorf("set briefed %s: %w", id, err)
	}
	return nil
}

func (s *Store) Recontain(id, token, mounts string) (Agent, error) {
	if _, err := s.db.Exec(`UPDATE agents SET token_hash = ?, mounts = ?, updated_at = ? WHERE id = ?`,
		tokenHash(token), mounts, s.now().UnixMilli(), id); err != nil {
		return Agent{}, fmt.Errorf("recontain %s: %w", id, err)
	}
	return s.Agent(id)
}
