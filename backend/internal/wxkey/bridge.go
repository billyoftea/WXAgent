package wxkey

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"

	"github.com/billyoftea/wxagent/go_backend/internal/config"
)

type KeyPayload struct {
	DbKey       string `json:"db_key"`
	ImageXorKey string `json:"image_xor_key"`
	ImageAesKey string `json:"image_aes_key"`
	Timestamp   string `json:"timestamp"`
	Raw         map[string]any
}

type Bridge struct {
	prefsPath string
	cmd       config.CommandSpec
}

func New(prefsPath string, cmd config.CommandSpec) *Bridge {
	return &Bridge{
		prefsPath: prefsPath,
		cmd:       cmd,
	}
}

func (b *Bridge) LoadKeys() (*KeyPayload, error) {
	if b.prefsPath == "" {
		return nil, fmt.Errorf("prefs path is empty")
	}

	// Expand ~ if present (though config loader usually handles this, safe to double check or rely on config)
	// The config loader in internal/config already resolves paths, so we assume absolute path here.

	data, err := os.ReadFile(b.prefsPath)
	if err != nil {
		return nil, fmt.Errorf("read prefs %s: %w", b.prefsPath, err)
	}

	var raw map[string]any
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, fmt.Errorf("parse prefs: %w", err)
	}

	getString := func(keys ...string) string {
		for _, k := range keys {
			if v, ok := raw[k].(string); ok && v != "" {
				return v
			}
		}
		return ""
	}

	dbKey := getString("flutter.wechat_db_key", "wechat_db_key")
	ts := getString("flutter.key_timestamp", "key_timestamp", "flutter.image_key_timestamp")
	xorKey := getString("flutter.image_xor_key")
	aesKey := getString("flutter.image_aes_key")

	return &KeyPayload{
		DbKey:       dbKey,
		ImageXorKey: xorKey,
		ImageAesKey: aesKey,
		Timestamp:   ts,
		Raw:         raw,
	}, nil
}

func (b *Bridge) Launch(wait bool) error {
	cmdPath := b.cmd.Path
	if cmdPath == "" {
		return fmt.Errorf("wx_key command path not configured")
	}

	cmd := exec.Command(cmdPath, b.cmd.Args...)
	cmd.Dir = b.cmd.Cwd
	cmd.Env = os.Environ()
	for k, v := range b.cmd.Env {
		cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
	}

	if wait {
		return cmd.Run()
	}
	return cmd.Start()
}
