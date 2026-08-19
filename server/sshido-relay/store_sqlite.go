package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"

	_ "modernc.org/sqlite"
)

type sqliteStore struct {
	db *sql.DB
}

func newSQLiteStore(path string) (*sqliteStore, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}
	if _, err := db.Exec(`
        CREATE TABLE IF NOT EXISTS subscribers (
            id           TEXT PRIMARY KEY,
            device_token TEXT NOT NULL,
            created_at   INTEGER NOT NULL,
            updated_at   INTEGER NOT NULL,
            notify_count INTEGER NOT NULL DEFAULT 0,
            muted        INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_subscribers_device ON subscribers(device_token);
    `); err != nil {
		return nil, fmt.Errorf("schema: %w", err)
	}
	if _, err := db.Exec(`ALTER TABLE subscribers ADD COLUMN muted INTEGER NOT NULL DEFAULT 0`); err != nil {
		if !strings.Contains(err.Error(), "duplicate column") {
			return nil, fmt.Errorf("migrate muted column: %w", err)
		}
	}
	return &sqliteStore{db: db}, nil
}

func (s *sqliteStore) UpsertByDeviceToken(_ context.Context, deviceToken string, newIDFn func() string, now int64, muted *bool) (Subscriber, error) {
	var id string
	var currentMuted bool
	row := s.db.QueryRow(`SELECT id, muted FROM subscribers WHERE device_token = ?`, deviceToken)
	switch err := row.Scan(&id, &currentMuted); {
	case errors.Is(err, sql.ErrNoRows):
		id = newIDFn()
		newMuted := muted != nil && *muted
		if _, err := s.db.Exec(
			`INSERT INTO subscribers(id,device_token,created_at,updated_at,muted) VALUES(?,?,?,?,?)`,
			id, deviceToken, now, now, newMuted,
		); err != nil {
			return Subscriber{}, fmt.Errorf("insert: %w", err)
		}
		return Subscriber{ID: id, DeviceToken: deviceToken, CreatedAt: now, UpdatedAt: now, Muted: newMuted}, nil
	case err != nil:
		return Subscriber{}, fmt.Errorf("query: %w", err)
	default:
		if muted != nil {
			currentMuted = *muted
		}
		if _, err := s.db.Exec(`UPDATE subscribers SET updated_at = ?, muted = ? WHERE id = ?`, now, currentMuted, id); err != nil {
			return Subscriber{}, fmt.Errorf("update: %w", err)
		}
		return Subscriber{ID: id, DeviceToken: deviceToken, UpdatedAt: now, Muted: currentMuted}, nil
	}
}

func (s *sqliteStore) LookupByID(_ context.Context, id string) (Subscriber, error) {
	var sub Subscriber
	sub.ID = id
	err := s.db.QueryRow(
		`SELECT device_token, created_at, updated_at, notify_count, muted FROM subscribers WHERE id = ?`, id,
	).Scan(&sub.DeviceToken, &sub.CreatedAt, &sub.UpdatedAt, &sub.NotifyCount, &sub.Muted)
	if errors.Is(err, sql.ErrNoRows) {
		return Subscriber{}, ErrNotFound
	}
	if err != nil {
		return Subscriber{}, err
	}
	return sub, nil
}

func (s *sqliteStore) IncrementNotifyCount(_ context.Context, id string) error {
	_, err := s.db.Exec(`UPDATE subscribers SET notify_count = notify_count + 1 WHERE id = ?`, id)
	return err
}

func (s *sqliteStore) Close() error { return s.db.Close() }

func (s *sqliteStore) HealthCheck(_ context.Context) error { return s.db.Ping() }
