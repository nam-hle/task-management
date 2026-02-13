package credential

import (
	"fmt"

	"github.com/99designs/keyring"
)

const serviceName = "taskmanager"

// openKeyring returns a configured keyring instance.
func openKeyring() (keyring.Keyring, error) {
	ring, err := keyring.Open(keyring.Config{
		ServiceName: serviceName,
		AllowedBackends: []keyring.BackendType{
			keyring.KeychainBackend,
			keyring.SecretServiceBackend,
			keyring.WinCredBackend,
			keyring.PassBackend,
			keyring.FileBackend,
		},
		FileDir:                  "~/.config/taskmanager/credentials",
		FilePasswordFunc:         keyring.FixedStringPrompt("taskmanager-file-key"),
		KeychainTrustApplication: true,
	})
	if err != nil {
		return nil, fmt.Errorf("opening keyring: %w", err)
	}
	return ring, nil
}

// Get retrieves a credential value by key from the system keyring.
func Get(key string) (string, error) {
	ring, err := openKeyring()
	if err != nil {
		return "", err
	}

	item, err := ring.Get(key)
	if err != nil {
		return "", fmt.Errorf("getting credential %q: %w", key, err)
	}

	return string(item.Data), nil
}

// Set stores a credential value by key in the system keyring.
func Set(key string, value string) error {
	ring, err := openKeyring()
	if err != nil {
		return err
	}

	err = ring.Set(keyring.Item{
		Key:  key,
		Data: []byte(value),
	})
	if err != nil {
		return fmt.Errorf("setting credential %q: %w", key, err)
	}

	return nil
}

// Delete removes a credential by key from the system keyring.
func Delete(key string) error {
	ring, err := openKeyring()
	if err != nil {
		return err
	}

	err = ring.Remove(key)
	if err != nil {
		return fmt.Errorf("deleting credential %q: %w", key, err)
	}

	return nil
}
