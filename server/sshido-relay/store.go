package main

import (
	"context"
	"errors"
)

var ErrNotFound = errors.New("not found")

type Subscriber struct {
	ID          string
	DeviceToken string
	CreatedAt   int64
	UpdatedAt   int64
	NotifyCount int64
}

type Store interface {
	UpsertByDeviceToken(ctx context.Context, deviceToken string, newIDFn func() string, now int64) (Subscriber, error)
	LookupByID(ctx context.Context, id string) (Subscriber, error)
	IncrementNotifyCount(ctx context.Context, id string) error
	Close() error
	HealthCheck(ctx context.Context) error
}
