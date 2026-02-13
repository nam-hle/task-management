package app

import "github.com/nhle/task-management/internal/keys"

// KeyMap is re-exported from the keys package so existing code that
// references app.KeyMap continues to work.
type KeyMap = keys.KeyMap

// DefaultKeyMap delegates to keys.DefaultKeyMap.
func DefaultKeyMap() *KeyMap {
	return keys.DefaultKeyMap()
}
