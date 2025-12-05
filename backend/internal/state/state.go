package state

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

// Store mirrors wx_agent.state.PipelineState for incremental tracking.
type Store struct {
	path     string
	mu       sync.Mutex
	loaded   bool
	Sessions map[string]SessionState `json:"sessions"`
	Meta     map[string]string       `json:"meta"`
}

// SessionState captures the latest timestamp processed per session.
type SessionState struct {
	LastTimestamp int64 `json:"last_timestamp"`
	LastCount     int   `json:"last_count,omitempty"`
}

// New returns an empty Store bound to path.
func New(path string) *Store {
	return &Store{
		path:     path,
		Sessions: make(map[string]SessionState),
		Meta:     make(map[string]string),
	}
}

// Load populates the store from disk, ignoring missing files.
func (s *Store) Load() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.loaded {
		return nil
	}
	if s.path == "" {
		return errors.New("state path is empty")
	}
	raw, err := os.ReadFile(s.path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			s.loaded = true
			return nil
		}
		return fmt.Errorf("read state: %w", err)
	}
	if err := json.Unmarshal(raw, s); err != nil {
		return fmt.Errorf("parse state: %w", err)
	}
	if s.Sessions == nil {
		s.Sessions = make(map[string]SessionState)
	}
	if s.Meta == nil {
		s.Meta = make(map[string]string)
	}
	s.loaded = true
	return nil
}

// Save writes the store back to disk.
func (s *Store) Save() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.path == "" {
		return errors.New("state path is empty")
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return fmt.Errorf("create state dir: %w", err)
	}
	payload := struct {
		Sessions map[string]SessionState `json:"sessions"`
		Meta     map[string]string       `json:"meta"`
	}{Sessions: s.Sessions, Meta: s.Meta}
	raw, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		return fmt.Errorf("encode state: %w", err)
	}
	if err := os.WriteFile(s.path, raw, 0o644); err != nil {
		return fmt.Errorf("write state: %w", err)
	}
	return nil
}

// LastTimestamp returns the stored timestamp for a session.
func (s *Store) LastTimestamp(sessionID string) int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	if entry, ok := s.Sessions[sessionID]; ok {
		return entry.LastTimestamp
	}
	return 0
}

// UpdateSession records the latest timestamp and message count.
func (s *Store) UpdateSession(sessionID string, timestamp int64, count int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	current := s.Sessions[sessionID]
	if timestamp > current.LastTimestamp {
		current.LastTimestamp = timestamp
	}
	if count > 0 {
		current.LastCount = count
	}
	s.Sessions[sessionID] = current
}
