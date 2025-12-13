package pipeline

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/billyoftea/wxagent/go_backend/internal/analyzer"
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
	// 使用 Go 原生导出，不再调用 echotrace GUI
	// 解析参数
	var wechatDir, startDate, endDate string
	for i := 0; i < len(extraArgs); i++ {
		switch extraArgs[i] {
		case "--wechat-dir":
			if i+1 < len(extraArgs) {
				wechatDir = extraArgs[i+1]
				i++
			}
		case "--start-date":
			if i+1 < len(extraArgs) {
				startDate = extraArgs[i+1]
				i++
			}
		case "--end-date":
			if i+1 < len(extraArgs) {
				endDate = extraArgs[i+1]
				i++
			}
		}
	}
	return p.ExportAuto(wechatDir, startDate, endDate)
}

// TriggerExportLegacy 保留原来的 echotrace GUI 调用（备用）
func (p *Pipeline) TriggerExportLegacy(extraArgs []string, silent bool) error {
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

	// 2. 使用 Go 原生导出 (ExportAuto)，不再调用 echotrace GUI
	// 解析 exportArgs 获取可能的参数
	var wechatDir, startDate, endDate string
	for i := 0; i < len(exportArgs); i++ {
		switch exportArgs[i] {
		case "--wechat-dir":
			if i+1 < len(exportArgs) {
				wechatDir = exportArgs[i+1]
				i++
			}
		case "--start-date":
			if i+1 < len(exportArgs) {
				startDate = exportArgs[i+1]
				i++
			}
		case "--end-date":
			if i+1 < len(exportArgs) {
				endDate = exportArgs[i+1]
				i++
			}
		}
	}

	exportErr := p.ExportAuto(wechatDir, startDate, endDate)

	// 统计导出结果
	sessions, _ := p.ListSessions()

	// 计算总消息数
	totalMessages := 0
	for _, s := range sessions {
		// 尝试多种类型，因为 JSON 解析可能返回不同类型
		if count, ok := s["messages"].(int); ok {
			totalMessages += count
		} else if count, ok := s["messages"].(int64); ok {
			totalMessages += int(count)
		} else if count, ok := s["messages"].(float64); ok {
			totalMessages += int(count)
		}
	}

	// 返回前端期望的格式
	result := map[string]any{
		"status":        "success",
		"key":           key,
		"export":        exportErr == nil, // 前端检查这个字段
		"dataset_ready": len(sessions) > 0,
		"sessions":      len(sessions),
		"messages":      totalMessages,
	}

	if exportErr != nil {
		result["export_error"] = exportErr.Error()
	}

	return result, nil
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
		Incremental:   false, // 默认完全导出，不使用增量模式
		StateStore:    p.State,
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

func (p *Pipeline) AnalyzeChat(startDate, endDate string, sessionNames []string, maxTokens int, outputFile string) (*analyzer.AnalyzeResult, error) {
	// 创建 LLM 客户端
	llmClient := llm.NewClient(p.Config.LLM)

	// 创建分析器
	a := analyzer.New(p.Config.ExportDir, llmClient)

	// 执行分析
	ctx := context.Background()
	result, err := a.Analyze(ctx, analyzer.AnalyzeOptions{
		StartDate:    startDate,
		EndDate:      endDate,
		SessionNames: sessionNames,
		MaxTokens:    maxTokens,
		OutputFile:   outputFile,
	})

	if err != nil {
		return nil, fmt.Errorf("analyze chat: %w", err)
	}

	return result, nil
}

func (p *Pipeline) ListExportStates() ([]map[string]any, error) {
	// Scan export directory and collect session metadata with export state
	sessions, err := p.ListSessions()
	if err != nil {
		return nil, err
	}

	// Enhance with state information
	for i := range sessions {
		sessionID := fmt.Sprintf("%v", sessions[i]["session_id"])
		if sessionID != "" {
			lastTS := p.State.LastTimestamp(sessionID)
			if lastTS > 0 {
				sessions[i]["last_export_time"] = time.Unix(lastTS, 0).Format(time.RFC3339)
				sessions[i]["state_file_exists"] = true
			}
		}
	}

	return sessions, nil
}

func (p *Pipeline) DescribeSession(file, startDate, endDate string) (map[string]any, error) {
	// Read and analyze a specific session file
	// This is a placeholder - implement based on your needs
	return map[string]any{
		"file":       file,
		"start_date": startDate,
		"end_date":   endDate,
		"message":    "Session description not yet implemented",
	}, nil
}

func (p *Pipeline) ListSummaryHistory(limit int) ([]map[string]any, error) {
	historyDir := p.Config.SummaryHistoryDir
	if historyDir == "" {
		historyDir = filepath.Join(p.Config.SummaryOutput, "history")
	}

	// Ensure directory exists
	if _, err := os.Stat(historyDir); os.IsNotExist(err) {
		return []map[string]any{}, nil
	}

	entries, err := os.ReadDir(historyDir)
	if err != nil {
		return nil, fmt.Errorf("read history dir: %w", err)
	}

	var history []map[string]any
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		name := entry.Name()
		if !strings.HasSuffix(name, ".md") && !strings.HasSuffix(name, ".txt") {
			continue
		}

		info, err := entry.Info()
		if err != nil {
			continue
		}

		fullPath := filepath.Join(historyDir, name)
		history = append(history, map[string]any{
			"name":     name,
			"path":     fullPath,
			"size":     info.Size(),
			"modified": info.ModTime().Format(time.RFC3339),
		})

		if limit > 0 && len(history) >= limit {
			break
		}
	}

	return history, nil
}

func (p *Pipeline) ReadSummaryHistory(path string) (string, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read history file: %w", err)
	}
	return string(content), nil
}

func (p *Pipeline) ExportFiltered(selected, files []string, startDate, endDate, outputDir string, singleFile bool) (map[string]any, error) {
	// This is a placeholder for filtered export functionality
	// Implement based on your specific requirements
	return map[string]any{
		"status":      "success",
		"selected":    selected,
		"files":       files,
		"start_date":  startDate,
		"end_date":    endDate,
		"output_dir":  outputDir,
		"single_file": singleFile,
		"message":     "Filtered export not yet fully implemented",
	}, nil
}

func (p *Pipeline) GetConfig() map[string]any {
	return map[string]any{
		"path": p.Config.ConfigPath,
		"data": map[string]any{
			"export_dir":          p.Config.ExportDir,
			"summary_output":      p.Config.SummaryOutput,
			"summary_history_dir": p.Config.SummaryHistoryDir,
			"state_file":          p.Config.StateFile,
			"llm": map[string]any{
				"base_url": p.Config.LLM.BaseURL,
				"model":    p.Config.LLM.Model,
				"api_key":  p.Config.LLM.APIKey,
			},
		},
	}
}

func (p *Pipeline) UpdateConfig(values map[string]any) (map[string]any, error) {
	// Update configuration values
	// This is a simplified implementation - you may want to add validation
	if v, ok := values["export_dir"].(string); ok {
		p.Config.ExportDir = v
	}
	if v, ok := values["summary_output"].(string); ok {
		p.Config.SummaryOutput = v
	}
	if v, ok := values["summary_history_dir"].(string); ok {
		p.Config.SummaryHistoryDir = v
	}

	// Update LLM config
	if llmData, ok := values["llm"].(map[string]any); ok {
		if v, ok := llmData["base_url"].(string); ok {
			p.Config.LLM.BaseURL = v
		}
		if v, ok := llmData["model"].(string); ok {
			p.Config.LLM.Model = v
		}
		if v, ok := llmData["api_key"].(string); ok {
			p.Config.LLM.APIKey = v
		}
	}

	// Note: Not saving to file in this implementation
	// You would need to implement proper config file writing

	return map[string]any{
		"status":  "success",
		"message": "Configuration updated (in-memory only)",
	}, nil
}

func (p *Pipeline) ReloadConfig() (map[string]any, error) {
	if p.Config.ConfigPath == "" {
		return nil, fmt.Errorf("no config path set")
	}

	newConfig, err := config.LoadPipeline(p.Config.ConfigPath)
	if err != nil {
		return nil, fmt.Errorf("reload config: %w", err)
	}

	*p.Config = *newConfig

	return map[string]any{
		"status":  "success",
		"message": "Configuration reloaded",
	}, nil
}

func (p *Pipeline) TestLLM(baseURL, model, apiKey string) (map[string]any, error) {
	// Create a test LLM config
	testConfig := config.LLMConfig{
		BaseURL:     baseURL,
		Model:       model,
		APIKey:      apiKey,
		Temperature: 0.7,
		Timeout:     30 * time.Second,
	}

	// Use existing config values if not provided
	if testConfig.BaseURL == "" {
		testConfig.BaseURL = p.Config.LLM.BaseURL
	}
	if testConfig.Model == "" {
		testConfig.Model = p.Config.LLM.Model
	}
	if testConfig.APIKey == "" {
		testConfig.APIKey = p.Config.LLM.APIKey
	}

	client := llm.NewClient(testConfig)
	ctx := context.Background()

	// Send a simple test message
	response, err := client.ChatCompletion(ctx, []llm.ChatMessage{
		{Role: "user", Content: "Hello! Please respond with 'OK' if you receive this message."},
	})

	if err != nil {
		return map[string]any{
			"status":  "failed",
			"error":   err.Error(),
			"message": "Failed to connect to LLM",
		}, nil
	}

	return map[string]any{
		"status":   "success",
		"response": response,
		"message":  "LLM connection test successful",
	}, nil
}

func (p *Pipeline) AnalyzeSessions(startDate, endDate string, topN int, sessionTypes []string) (map[string]any, error) {
	builder := dataset.NewBuilder(p.Config.ExportDir, p.State)

	result, err := builder.Build(startDate, endDate, false, nil)
	if err != nil {
		return nil, fmt.Errorf("build dataset: %w", err)
	}

	// Aggregate statistics
	totalMessages := 0
	sessionCount := len(result.Dataset)
	breakdown := make(map[string]int)

	type SessionStats struct {
		SessionID   string
		DisplayName string
		SessionType string
		Messages    int
	}

	var allSessions []SessionStats

	for sessionID, messages := range result.Dataset {
		totalMessages += len(messages)

		sessionType := "private"
		if strings.Contains(sessionID, "@chatroom") {
			sessionType = "group"
		}

		breakdown[sessionType]++

		allSessions = append(allSessions, SessionStats{
			SessionID:   sessionID,
			DisplayName: sessionID,
			SessionType: sessionType,
			Messages:    len(messages),
		})
	}

	// Sort by message count and get top N
	// Simple bubble sort for small datasets
	for i := 0; i < len(allSessions)-1; i++ {
		for j := 0; j < len(allSessions)-i-1; j++ {
			if allSessions[j].Messages < allSessions[j+1].Messages {
				allSessions[j], allSessions[j+1] = allSessions[j+1], allSessions[j]
			}
		}
	}

	// Get top N
	if topN > len(allSessions) {
		topN = len(allSessions)
	}
	topSessions := allSessions[:topN]

	// Convert to map format
	var topMaps []map[string]any
	for _, s := range topSessions {
		topMaps = append(topMaps, map[string]any{
			"session_id":   s.SessionID,
			"display_name": s.DisplayName,
			"session_type": s.SessionType,
			"messages":     s.Messages,
		})
	}

	return map[string]any{
		"top":            topMaps,
		"breakdown":      breakdown,
		"total_messages": totalMessages,
		"session_count":  sessionCount,
		"window": map[string]any{
			"start": startDate,
			"end":   endDate,
		},
	}, nil
}
