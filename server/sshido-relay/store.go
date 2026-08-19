package main

import (
	"context"
	"errors"
)

var ErrNotFound = errors.New("not found")

type Subscriber struct {
	ID          string `firestore:"-"`
	DeviceToken string `firestore:"device_token"`
	CreatedAt   int64  `firestore:"created_at"`
	UpdatedAt   int64  `firestore:"updated_at"`
	NotifyCount int64  `firestore:"notify_count"`
	Muted       bool   `firestore:"muted"`
}

type Store interface {
	// muted == nil preserves the subscriber's current muted state.
	UpsertByDeviceToken(ctx context.Context, deviceToken string, newIDFn func() string, now int64, muted *bool) (Subscriber, error)
	LookupByID(ctx context.Context, id string) (Subscriber, error)
	IncrementNotifyCount(ctx context.Context, id string) error
	Close() error
	HealthCheck(ctx context.Context) error
}
