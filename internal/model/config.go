package model

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/viper"
)

// SourceConfig holds the configuration for a single data source integration.
type SourceConfig struct {
	// ID is the unique identifier for this source instance.
	ID string `mapstructure:"id" yaml:"id"`

	// Type identifies the source kind (e.g., "jira", "bitbucket", "email").
	Type string `mapstructure:"type" yaml:"type"`

	// Name is the user-defined label for this source instance.
	Name string `mapstructure:"name" yaml:"name"`

	// BaseURL is the root URL of the source service.
	BaseURL string `mapstructure:"base_url" yaml:"base_url"`

	// Enabled controls whether this source is actively polled.
	Enabled bool `mapstructure:"enabled" yaml:"enabled"`

	// PollIntervalSec is how often (in seconds) to fetch updates.
	PollIntervalSec int `mapstructure:"poll_interval_sec" yaml:"poll_interval_sec"`

	// Config holds source-specific key-value settings
	// (e.g., project keys, board IDs, mailbox paths).
	Config map[string]string `mapstructure:"config" yaml:"config"`
}

// AIConfig holds settings for the AI assistant integration.
type AIConfig struct {
	Model     string `mapstructure:"model" yaml:"model"`
	MaxTokens int    `mapstructure:"max_tokens" yaml:"max_tokens"`
}

// DisplayConfig holds UI/rendering preferences.
type DisplayConfig struct {
	Theme           string `mapstructure:"theme" yaml:"theme"`
	PollIntervalSec int    `mapstructure:"poll_interval_sec" yaml:"poll_interval_sec"`
}

// AppConfig is the top-level application configuration.
type AppConfig struct {
	Sources []SourceConfig `mapstructure:"sources" yaml:"sources"`
	AI      AIConfig       `mapstructure:"ai" yaml:"ai"`
	Display DisplayConfig  `mapstructure:"display" yaml:"display"`
}

// DefaultConfigPath returns the default path for the configuration file,
// located at ~/.config/taskmanager/config.yaml.
func DefaultConfigPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return filepath.Join(".", "config.yaml")
	}
	return filepath.Join(home, ".config", "taskmanager", "config.yaml")
}

// defaultAppConfig returns a sensible default configuration.
func defaultAppConfig() *AppConfig {
	return &AppConfig{
		Sources: []SourceConfig{},
		AI: AIConfig{
			Model:     "claude-sonnet-4-20250514",
			MaxTokens: 4096,
		},
		Display: DisplayConfig{
			Theme:           "default",
			PollIntervalSec: 120,
		},
	}
}

// LoadConfig reads configuration from the given YAML file path using Viper.
// If the file does not exist, it returns a default configuration.
func LoadConfig(path string) (*AppConfig, error) {
	v := viper.New()
	v.SetConfigFile(path)
	v.SetConfigType("yaml")

	// Set defaults so missing keys resolve to sensible values.
	v.SetDefault("ai.model", "claude-sonnet-4-20250514")
	v.SetDefault("ai.max_tokens", 4096)
	v.SetDefault("display.theme", "default")
	v.SetDefault("display.poll_interval_sec", 120)

	if err := v.ReadInConfig(); err != nil {
		if _, ok := err.(*os.PathError); ok {
			return defaultAppConfig(), nil
		}
		if _, ok := err.(viper.ConfigFileNotFoundError); ok {
			return defaultAppConfig(), nil
		}
		return nil, fmt.Errorf("reading config %s: %w", path, err)
	}

	cfg := defaultAppConfig()
	if err := v.Unmarshal(cfg); err != nil {
		return nil, fmt.Errorf("parsing config %s: %w", path, err)
	}

	// Apply defaults for each source entry.
	for i := range cfg.Sources {
		if cfg.Sources[i].PollIntervalSec == 0 {
			cfg.Sources[i].PollIntervalSec = 120
		}
		if !cfg.Sources[i].Enabled {
			// Viper unmarshals missing bools as false; treat unset as true.
			// We use the raw viper value to distinguish explicit false from absent.
			key := fmt.Sprintf("sources.%d.enabled", i)
			if !v.IsSet(key) {
				cfg.Sources[i].Enabled = true
			}
		}
	}

	return cfg, nil
}

// SaveConfig writes the given configuration to a YAML file at path,
// creating parent directories if needed.
func SaveConfig(path string, cfg *AppConfig) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("creating config directory %s: %w", dir, err)
	}

	v := viper.New()
	v.SetConfigFile(path)
	v.SetConfigType("yaml")

	v.Set("sources", cfg.Sources)
	v.Set("ai", cfg.AI)
	v.Set("display", cfg.Display)

	if err := v.WriteConfigAs(path); err != nil {
		return fmt.Errorf("writing config to %s: %w", path, err)
	}

	return nil
}
