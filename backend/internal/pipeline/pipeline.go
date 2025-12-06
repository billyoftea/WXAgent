package pipeline

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/billyoftea/wxagent/go_backend/internal/config"
	"github.com/billyoftea/wxagent/go_backend/internal/dataset"
	"github.com/billyoftea/wxagent/go_backend/internal/echotrace"
	"github.com/billyoftea/wxagent/go_backend/internal/llm"
	"github.com/billyoftea/wxagent/go_backend/internal/state"
	"github.com/billyoftea/wxagent/go_backend/internal/summarizer"
	"github.com/billyoftea/wxagent/go_backend/internal/wxdb"
	"github.com/billyoftea/wxagent/go_backend/internal/wxkey"
)

type Pipeline struct {
	Config    *config.PipelineConfig
	State     *state.Store
	WxKey     *wxkey.Bridge
	Echotrace *echotrace.Runner
}

func New(cfg *config.PipelineConfig) (*Pipeline, error) {
	fmt.Printf("[DEBUG] State file path from config: %s\n", cfg.StateFile)
	s := state.New(cfg.StateFile)
	if err := s.Load(); err != nil {
		// Log warning but continue? Or fail?
		// For now, just continue with empty state if load fails (e.g. permission),
		// but New() usually shouldn't fail on logic errors.
		// Let's assume it's fine.
		fmt.Printf("Warning: failed to load state: %v\n", err)
	}

	return &Pipeline{
		Config:    cfg,
		State:     s,
		WxKey:     wxkey.New(cfg.WxKeySharedPrefs, cfg.WxKeyCommand),
		Echotrace: echotrace.New(cfg.EchotraceCommand),
	}, nil
}

func (p *Pipeline) RefreshKey(autoLaunch bool, waitSeconds int, pollInterval int) (*wxkey.KeyPayload, error) {
	payload, err := p.WxKey.LoadKeys()
	if err == nil && payload.DbKey != "" {
		return payload, nil
	}

	if !autoLaunch {
		return nil, fmt.Errorf("key not found and auto_launch is false")
	}

	fmt.Println("⚠️ Key not found, launching wx_key...")
	if err := p.WxKey.Launch(false); err != nil {
		return nil, fmt.Errorf("launch wx_key: %w", err)
	}

	deadline := time.Now().Add(time.Duration(waitSeconds) * time.Second)
	ticker := time.NewTicker(time.Duration(pollInterval) * time.Second)
	defer ticker.Stop()

	for time.Now().Before(deadline) {
		<-ticker.C
		payload, err := p.WxKey.LoadKeys()
		if err == nil && payload.DbKey != "" {
			fmt.Println("✅ Key detected")
			return payload, nil
		}
	}

	return nil, fmt.Errorf("timeout waiting for key")
}

func (p *Pipeline) TriggerExport(extraArgs []string, silent bool) error {
	return p.Echotrace.Run(extraArgs, silent)
}

func (p *Pipeline) RunSummary(startDate, endDate string, incremental bool, questions []string) (map[string]any, error) {
	// 1. Build Dataset
	builder := dataset.NewBuilder(p.Config.ExportDir, p.State)

	// Determine allowed sessions from config if not empty
	// allowedSessions := p.Config.TargetSessions
	var allowedSessions []string

	fmt.Println("🔍 Building dataset...")
	result, err := builder.Build(startDate, endDate, incremental, allowedSessions)
	if err != nil {
		return nil, fmt.Errorf("build dataset: %w", err)
	}

	if len(result.Dataset) == 0 {
		return map[string]any{
			"status":  "no_data",
			"message": "No messages found to summarize",
		}, nil
	}

	fmt.Printf("📊 Found %d sessions with new messages.\n", len(result.Dataset))

	// 2. Initialize LLM & Summarizer
	llmClient := llm.NewClient(p.Config.LLM)
	summ := summarizer.New(llmClient)

	// 3. Summarize each session
	summaries := make(map[string]string)
	ctx := context.Background()

	for sessionName, messages := range result.Dataset {
		fmt.Printf("🤖 Summarizing %s (%d messages)...\n", sessionName, len(messages))
		summary, err := summ.SummarizeSession(ctx, sessionName, messages)
		if err != nil {
			fmt.Printf("❌ Failed to summarize %s: %v\n", sessionName, err)
			summaries[sessionName] = fmt.Sprintf("Error: %v", err)
		} else {
			summaries[sessionName] = summary
		}
	}

	// 4. Save results
	outputFile := filepath.Join(p.Config.ExportDir, "summary_result_go.md")
	if err := saveSummaryMarkdown(outputFile, summaries); err != nil {
		return nil, fmt.Errorf("save summary: %w", err)
	}

	// 5. Save state
	if incremental {
		if err := p.State.Save(); err != nil {
			fmt.Printf("⚠️ Failed to save state: %v\n", err)
		}
	}

	return map[string]any{
		"status":      "success",
		"output_file": outputFile,
		"stats":       result.Stats,
	}, nil
}

func saveSummaryMarkdown(path string, summaries map[string]string) error {
	var sb strings.Builder
	sb.WriteString("# Chat Summaries\n\n")
	sb.WriteString(fmt.Sprintf("Generated at: %s\n\n", time.Now().Format(time.DateTime)))

	for name, summary := range summaries {
		sb.WriteString(fmt.Sprintf("## %s\n\n", name))
		sb.WriteString(summary)
		sb.WriteString("\n\n---\n\n")
	}

	return os.WriteFile(path, []byte(sb.String()), 0644)
}

func (p *Pipeline) GetStatus() map[string]any {
	return map[string]any{
		"config_path": p.Config.ConfigPath,
		"export_dir":  p.Config.ExportDir,
		"state_file":  p.Config.StateFile,
	}
}

func (p *Pipeline) LaunchWxKey(extraArgs []string, wait bool) error {
	return p.WxKey.Launch(wait)
}

func (p *Pipeline) RunFullRefresh(autoLaunchKey bool, waitSeconds, pollInterval int, exportArgs []string) (map[string]any, error) {
	// 1. Refresh Key
	key, err := p.RefreshKey(autoLaunchKey, waitSeconds, pollInterval)
	if err != nil {
		return nil, fmt.Errorf("refresh key: %w", err)
	}

	// 2. Trigger Export
	if err := p.TriggerExport(exportArgs, false); err != nil {
		return nil, fmt.Errorf("trigger export: %w", err)
	}

	return map[string]any{
		"status": "success",
		"key":    key,
	}, nil
}

func (p *Pipeline) ListSessions() ([]map[string]any, error) {
	builder := dataset.NewBuilder(p.Config.ExportDir, p.State)
	return builder.ListSessionsMetadata()
}

func (p *Pipeline) ExportAuto(wechatDir, startDate, endDate string) error {
	// 获取密钥
	keyPayload, err := p.WxKey.LoadKeys()
	if err != nil || keyPayload.DbKey == "" {
		fmt.Println("⚠️ Database key not found, refreshing...")
		keyPayload, err = p.RefreshKey(true, 120, 5)
		if err != nil {
			return fmt.Errorf("get database key: %w", err)
		}
	}

	fmt.Printf("✓ Using database key: %s...\n", keyPayload.DbKey[:16])

	// 自动检测微信数据目录
	if wechatDir == "" {
		wechatDir, err = p.detectWeChatDataDir()
		if err != nil {
			return fmt.Errorf("detect WeChat data directory: %w", err)
		}
	}

	fmt.Printf("✓ WeChat data directory: %s\n", wechatDir)

	// 创建导出器
	exporter := wxdb.NewExporter(wxdb.ExportConfig{
		WeChatDataDir: wechatDir,
		DBKey:         keyPayload.DbKey,
		OutputDir:     p.Config.ExportDir,
		StartDate:     startDate,
		EndDate:       endDate,
		Incremental:   startDate == "", // 如果没有指定开始日期，则增量导出
		StateStore:    p.State,         // 传递状态存储用于增量导出
	})

	// 执行导出
	if err := exporter.Export(); err != nil {
		return fmt.Errorf("export failed: %w", err)
	}

	fmt.Println("✓ Export completed successfully")
	return nil
}

func (p *Pipeline) detectWeChatDataDir() (string, error) {
	userHome, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("get user home: %w", err)
	}

	// 微信数据可能的位置
	possiblePaths := []string{
		// 常见路径1: Documents\xwechat_files (新版微信)
		filepath.Join(userHome, "Documents", "xwechat_files"),
		// 常见路径2: Documents\WeChat Files (旧版微信)
		filepath.Join(userHome, "Documents", "WeChat Files"),
		// 常见路径3: AppData\Local\WeChat\WeChat Files
		filepath.Join(userHome, "AppData", "Local", "WeChat", "WeChat Files"),
	}

	fmt.Println("🔍 Searching for WeChat data directory...")

	for _, basePath := range possiblePaths {
		fmt.Printf("  Checking: %s\n", basePath)

		if _, err := os.Stat(basePath); os.IsNotExist(err) {
			continue
		}

		// 扫描该目录下的账号文件夹
		entries, err := os.ReadDir(basePath)
		if err != nil {
			continue
		}

		for _, entry := range entries {
			if !entry.IsDir() {
				continue
			}

			accountName := entry.Name()

			// 跳过系统文件夹
			if accountName == "All Users" || accountName == "Applet" {
				continue
			}

			// 检查是否包含 db_storage 目录
			dbStoragePath := filepath.Join(basePath, accountName, "db_storage")
			if stat, err := os.Stat(dbStoragePath); err == nil && stat.IsDir() {
				fullPath := filepath.Join(basePath, accountName)
				fmt.Printf("  ✓ Found: %s\n", fullPath)
				return fullPath, nil
			}
		}
	}

	return "", fmt.Errorf("WeChat data directory not found. Please specify with --wechat-dir.\n\nTried locations:\n  - %s\n  - %s\n  - %s",
		possiblePaths[0], possiblePaths[1], possiblePaths[2])
}
