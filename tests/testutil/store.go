package testutil

import (
	"testing"

	"github.com/nhle/task-management/internal/store"
)

// NewTestStore creates an in-memory SQLiteStore with all migrations applied.
// It automatically closes the store when the test completes.
func NewTestStore(t *testing.T) *store.SQLiteStore {
	t.Helper()

	s, err := store.NewSQLiteStore(":memory:")
	if err != nil {
		t.Fatalf("creating test store: %v", err)
	}

	t.Cleanup(func() {
		if err := s.Close(); err != nil {
			t.Errorf("closing test store: %v", err)
		}
	})

	return s
}
