package main

import (
	"context"
	"errors"
	"fmt"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type firestoreStore struct {
	client *firestore.Client
	coll   string
}

func newFirestoreStore(ctx context.Context, projectID, collection string) (*firestoreStore, error) {
	if projectID == "" {
		return nil, fmt.Errorf("firestore: GOOGLE_CLOUD_PROJECT (or -firestore-project) required")
	}
	if collection == "" {
		collection = "subscribers"
	}
	client, err := firestore.NewClient(ctx, projectID)
	if err != nil {
		return nil, fmt.Errorf("firestore client: %w", err)
	}
	return &firestoreStore{client: client, coll: collection}, nil
}

func (s *firestoreStore) UpsertByDeviceToken(ctx context.Context, deviceToken string, newIDFn func() string, now int64) (Subscriber, error) {
	iter := s.client.Collection(s.coll).Where("device_token", "==", deviceToken).Limit(1).Documents(ctx)
	doc, err := iter.Next()
	iter.Stop()
	if err == nil {
		var sub Subscriber
		if err := doc.DataTo(&sub); err != nil {
			return Subscriber{}, fmt.Errorf("decode: %w", err)
		}
		sub.ID = doc.Ref.ID
		sub.UpdatedAt = now
		if _, err := doc.Ref.Update(ctx, []firestore.Update{{Path: "updated_at", Value: now}}); err != nil {
			return Subscriber{}, fmt.Errorf("update: %w", err)
		}
		return sub, nil
	}
	if !errors.Is(err, iterator.Done) {
		return Subscriber{}, fmt.Errorf("query: %w", err)
	}
	id := newIDFn()
	sub := Subscriber{
		ID:          id,
		DeviceToken: deviceToken,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	if _, err := s.client.Collection(s.coll).Doc(id).Set(ctx, map[string]any{
		"device_token": sub.DeviceToken,
		"created_at":   sub.CreatedAt,
		"updated_at":   sub.UpdatedAt,
		"notify_count": int64(0),
	}); err != nil {
		return Subscriber{}, fmt.Errorf("insert: %w", err)
	}
	return sub, nil
}

func (s *firestoreStore) LookupByID(ctx context.Context, id string) (Subscriber, error) {
	doc, err := s.client.Collection(s.coll).Doc(id).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return Subscriber{}, ErrNotFound
	}
	if err != nil {
		return Subscriber{}, err
	}
	data := doc.Data()
	return Subscriber{
		ID:          id,
		DeviceToken: asString(data["device_token"]),
		CreatedAt:   asInt64(data["created_at"]),
		UpdatedAt:   asInt64(data["updated_at"]),
		NotifyCount: asInt64(data["notify_count"]),
	}, nil
}

func (s *firestoreStore) IncrementNotifyCount(ctx context.Context, id string) error {
	_, err := s.client.Collection(s.coll).Doc(id).Update(ctx, []firestore.Update{
		{Path: "notify_count", Value: firestore.Increment(1)},
	})
	return err
}

func (s *firestoreStore) Close() error { return s.client.Close() }

func (s *firestoreStore) HealthCheck(ctx context.Context) error {
	_, err := s.client.Collection(s.coll).Limit(1).Documents(ctx).Next()
	if errors.Is(err, iterator.Done) {
		return nil
	}
	return err
}

func asString(v any) string {
	if s, ok := v.(string); ok {
		return s
	}
	return ""
}

func asInt64(v any) int64 {
	switch n := v.(type) {
	case int64:
		return n
	case int:
		return int64(n)
	case float64:
		return int64(n)
	}
	return 0
}
