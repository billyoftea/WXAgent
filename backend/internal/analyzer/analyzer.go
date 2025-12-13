package analyzer

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/billyoftea/wxagent/go_backend/internal/llm"
)

// Message 消息结构
type Message struct {
	CreateTime    int64  `json:"create_time"`
	FormattedTime string `json:"formatted_time"`
	Type          string `json:"type"`
	StrContent    string `json:"str_content"`
	Sender        string `json:"sender,omitempty"`
	SenderName    string `json:"sender_name,omitempty"`
	SenderWxid    string `json:"sender_wxid,omitempty"`
	SessionName   string `json:"-"` // 添加会话名称字段，不输出到JSON
}

// Session 会话结构
type Session struct {
	SessionID   string    `json:"session_id"`
	SessionName string    `json:"session_name"`
	Messages    []Message `json:"messages"`
}

// SessionMessages 会话消息集合
type SessionMessages struct {
	SessionName string
	Messages    []Message
}

// Analyzer 分析器
type Analyzer struct {
	exportDir string
	llmClient *llm.Client
}

// New 创建分析器
func New(exportDir string, llmClient *llm.Client) *Analyzer {
	return &Analyzer{
		exportDir: exportDir,
		llmClient: llmClient,
	}
}

// AnalyzeOptions 分析选项
type AnalyzeOptions struct {
	StartDate    string   // 开始日期 YYYY-MM-DD
	EndDate      string   // 结束日期 YYYY-MM-DD
	SessionNames []string // 指定会话名称，为空则全部
	MaxTokens    int      // 每段最大token数，默认80000（约100K字符，留余量）
	OutputFile   string   // 输出文件路径
}

// AnalyzeResult 分析结果
type AnalyzeResult struct {
	TotalMessages int      `json:"total_messages"`
	TotalSessions int      `json:"total_sessions"`
	ChunkCount    int      `json:"chunk_count"`
	Summaries     []string `json:"summaries"`
	FinalSummary  string   `json:"final_summary"`
	OutputFile    string   `json:"output_file"`
}

// Analyze 执行分析
func (a *Analyzer) Analyze(ctx context.Context, opts AnalyzeOptions) (*AnalyzeResult, error) {
	// 设置默认值
	if opts.MaxTokens == 0 {
		opts.MaxTokens = 80000 // DeepSeek支持128K，设置80K留余量
	}
	if opts.OutputFile == "" {
		opts.OutputFile = filepath.Join(a.exportDir, "chat_analysis.md")
	}

	fmt.Println("🔍 Step 1: 加载并合并所有JSON消息...")
	sessionMessagesList, err := a.loadAndMergeMessagesBySession(opts)
	if err != nil {
		return nil, fmt.Errorf("load messages: %w", err)
	}

	if len(sessionMessagesList) == 0 {
		return nil, fmt.Errorf("no messages found in the specified date range")
	}

	// 统计总消息数
	totalMessages := 0
	var sessionNames []string
	for _, sm := range sessionMessagesList {
		totalMessages += len(sm.Messages)
		sessionNames = append(sessionNames, sm.SessionName)
	}

	// 显示时间范围统计（取第一个和最后一个会话的时间）
	if len(sessionMessagesList) > 0 && len(sessionMessagesList[0].Messages) > 0 {
		firstMsg := sessionMessagesList[0].Messages[0]
		lastSession := sessionMessagesList[len(sessionMessagesList)-1]
		lastMsg := lastSession.Messages[len(lastSession.Messages)-1]

		firstTime, _ := time.Parse("2006-01-02 15:04:05", firstMsg.FormattedTime)
		lastTime, _ := time.Parse("2006-01-02 15:04:05", lastMsg.FormattedTime)

		fmt.Printf("  [DEBUG] 实际消息时间范围: %s 至 %s\n",
			firstTime.Format("2006-01-02 15:04:05"),
			lastTime.Format("2006-01-02 15:04:05"))
	}

	fmt.Printf("✓ 已加载 %d 条消息来自 %d 个会话\n", totalMessages, len(sessionNames))

	fmt.Println("\n📅 Step 2: 按会话格式化消息...")
	formattedContent := a.formatMessagesBySession(sessionMessagesList)
	fmt.Printf("✓ 格式化完成，总字符数: %d\n", len(formattedContent))
	fmt.Printf("  [统计] 平均每条消息: %.1f 字符\n", float64(len(formattedContent))/float64(totalMessages))

	fmt.Println("\n✂️  Step 3: 分段处理（考虑token限制）...")
	chunks := a.splitIntoChunks(formattedContent, opts.MaxTokens)
	fmt.Printf("✓ 分为 %d 段\n", len(chunks))
	fmt.Printf("  [统计] MaxTokens设置: %d, 每段最大字符数: %d\n", opts.MaxTokens, int(float64(opts.MaxTokens)/0.8))
	if len(chunks) > 1 {
		for i, chunk := range chunks {
			fmt.Printf("  [统计] 第 %d 段: %d 字符 (~%.0f tokens)\n", i+1, len(chunk), float64(len(chunk))*0.8)
		}
	}

	// 保存切片内容到txt文件
	chunksFile := filepath.Join(a.exportDir, "chunks_preview.txt")
	if err := a.saveChunksToFile(chunksFile, chunks); err != nil {
		fmt.Printf("⚠️  保存切片预览失败: %v\n", err)
	} else {
		fmt.Printf("  [调试] 切片内容已保存到: %s\n", chunksFile)
	}

	fmt.Println("\n🤖 Step 4: 逐段调用DeepSeek进行总结...")
	var chunkSummaries []string
	for i, chunk := range chunks {
		fmt.Printf("  处理第 %d/%d 段...\n", i+1, len(chunks))
		summary, err := a.summarizeChunk(ctx, chunk, i+1, len(chunks))
		if err != nil {
			return nil, fmt.Errorf("summarize chunk %d: %w", i+1, err)
		}
		chunkSummaries = append(chunkSummaries, summary)
		fmt.Printf("  ✓ 完成第 %d 段\n", i+1)
	}

	fmt.Println("\n🔄 Step 5: 合并所有总结生成最终报告...")
	finalSummary, err := a.mergeSummaries(ctx, chunkSummaries)
	if err != nil {
		return nil, fmt.Errorf("merge summaries: %w", err)
	}

	fmt.Println("\n💾 Step 6: 保存分析报告...")
	if err := a.saveReport(opts.OutputFile, sessionNames, totalMessages, opts.StartDate, opts.EndDate, chunkSummaries, finalSummary); err != nil {
		return nil, fmt.Errorf("save report: %w", err)
	}

	fmt.Printf("✓ 报告已保存到: %s\n", opts.OutputFile)

	return &AnalyzeResult{
		TotalMessages: totalMessages,
		TotalSessions: len(sessionNames),
		ChunkCount:    len(chunks),
		Summaries:     chunkSummaries,
		FinalSummary:  finalSummary,
		OutputFile:    opts.OutputFile,
	}, nil
}

// loadAndMergeMessages 加载并合并所有消息
func (a *Analyzer) loadAndMergeMessages(opts AnalyzeOptions) ([]Message, []string, error) {
	files, err := filepath.Glob(filepath.Join(a.exportDir, "*.json"))
	if err != nil {
		return nil, nil, fmt.Errorf("glob export dir: %w", err)
	}

	allowedSessions := make(map[string]bool)
	for _, s := range opts.SessionNames {
		allowedSessions[s] = true
	}

	var allMessages []Message
	sessionSet := make(map[string]bool)

	for _, file := range files {
		// 跳过状态文件
		if strings.HasSuffix(file, ".export_state") {
			continue
		}

		session, err := loadSession(file)
		if err != nil {
			fmt.Printf("⚠️  跳过文件 %s: %v\n", filepath.Base(file), err)
			continue
		}

		// 过滤公众号（session_id 以 gh_ 开头）
		if strings.HasPrefix(session.SessionID, "gh_") {
			continue
		}

		// 过滤会话
		if len(allowedSessions) > 0 && !allowedSessions[session.SessionName] {
			continue
		}

		// 过滤并收集消息
		hasValidMessages := false
		for _, msg := range session.Messages {
			// 使用 formatted_time 进行时间过滤
			if msg.FormattedTime == "" {
				continue
			}

			// 提取日期部分 "2025-11-28 13:37:27" -> "2025-11-28"
			msgDate := msg.FormattedTime
			if len(msgDate) >= 10 {
				msgDate = msgDate[:10]
			}

			// 时间过滤（字符串比较）
			if opts.StartDate != "" && msgDate < opts.StartDate {
				continue
			}
			if opts.EndDate != "" && msgDate > opts.EndDate {
				continue
			}

			// 清理消息内容
			msg.StrContent = a.cleanMessageContent(msg)
			allMessages = append(allMessages, msg)
			hasValidMessages = true
		}

		// 只有当会话有有效消息时才加入统计
		if hasValidMessages {
			sessionSet[session.SessionName] = true
		}
	}

	// 按时间排序
	sort.Slice(allMessages, func(i, j int) bool {
		return allMessages[i].CreateTime < allMessages[j].CreateTime
	})

	sessionNames := make([]string, 0, len(sessionSet))
	for name := range sessionSet {
		sessionNames = append(sessionNames, name)
	}
	sort.Strings(sessionNames)

	return allMessages, sessionNames, nil
}

// loadAndMergeMessagesBySession 按会话加载并合并消息
func (a *Analyzer) loadAndMergeMessagesBySession(opts AnalyzeOptions) ([]SessionMessages, error) {
	files, err := filepath.Glob(filepath.Join(a.exportDir, "*.json"))
	if err != nil {
		return nil, fmt.Errorf("glob export dir: %w", err)
	}

	allowedSessions := make(map[string]bool)
	for _, s := range opts.SessionNames {
		allowedSessions[s] = true
	}

	var sessionMessagesList []SessionMessages

	for _, file := range files {
		// 跳过状态文件
		if strings.HasSuffix(file, ".export_state") {
			continue
		}

		session, err := loadSession(file)
		if err != nil {
			fmt.Printf("⚠️  跳过文件 %s: %v\n", filepath.Base(file), err)
			continue
		}

		// 过滤公众号（session_id 以 gh_ 开头）
		if strings.HasPrefix(session.SessionID, "gh_") {
			continue
		}

		// 过滤会话
		if len(allowedSessions) > 0 && !allowedSessions[session.SessionName] {
			continue
		}

		// 过滤并收集消息
		var validMessages []Message
		for _, msg := range session.Messages {
			// 使用 formatted_time 进行时间过滤
			if msg.FormattedTime == "" {
				continue
			}

			// 提取日期部分 "2025-11-28 13:37:27" -> "2025-11-28"
			msgDate := msg.FormattedTime
			if len(msgDate) >= 10 {
				msgDate = msgDate[:10]
			}

			// 时间过滤（字符串比较）
			if opts.StartDate != "" && msgDate < opts.StartDate {
				continue
			}
			if opts.EndDate != "" && msgDate > opts.EndDate {
				continue
			}

			// 清理消息内容
			msg.StrContent = a.cleanMessageContent(msg)
			msg.SessionName = session.SessionName // 添加会话名称
			validMessages = append(validMessages, msg)
		}

		// 只有当会话有有效消息时才加入
		if len(validMessages) > 0 {
			// 按时间排序该会话的消息
			sort.Slice(validMessages, func(i, j int) bool {
				return validMessages[i].FormattedTime < validMessages[j].FormattedTime
			})

			sessionMessagesList = append(sessionMessagesList, SessionMessages{
				SessionName: session.SessionName,
				Messages:    validMessages,
			})
		}
	}

	// 按会话名称排序（可选）
	sort.Slice(sessionMessagesList, func(i, j int) bool {
		return sessionMessagesList[i].SessionName < sessionMessagesList[j].SessionName
	})

	return sessionMessagesList, nil
}

// cleanMessageContent 清理消息内容
func (a *Analyzer) cleanMessageContent(msg Message) string {
	content := msg.StrContent

	// 处理不支持的消息类型
	if msg.Type == "系统消息" {
		return "[不支持的消息类型]"
	}
	if msg.Type == "表情" || msg.Type == "动画表情" {
		return "[表情消息]"
	}
	if msg.Type == "图片消息" {
		return "[图片]"
	}
	if msg.Type == "语音消息" {
		return "[语音]"
	}
	if msg.Type == "视频消息" {
		return "[视频]"
	}
	if msg.Type == "文件消息" {
		return "[文件]"
	}
	if msg.Type == "位置消息" {
		return "[位置]"
	}
	if msg.Type == "名片消息" {
		return "[名片]"
	}

	// 处理接龙消息等特殊类型
	if strings.Contains(msg.Type, "未知消息类型") {
		// 尝试解析BytesExtra中的接龙内容
		// 这里可能需要根据实际情况调整
		if content != "" {
			return content
		}
		return "[特殊消息]"
	}

	return content
}

// formatMessages 格式化消息列表
func (a *Analyzer) formatMessages(messages []Message) string {
	var sb strings.Builder

	for _, msg := range messages {
		// 格式：时间 | 发送者 | 消息内容
		sender := msg.SenderName
		if sender == "" {
			sender = msg.Sender
		}
		if sender == "" {
			sender = "未知"
		}

		timeStr := msg.FormattedTime
		if timeStr == "" && msg.CreateTime > 0 {
			t := time.Unix(msg.CreateTime, 0)
			timeStr = t.Format("2006-01-02 15:04:05")
		}

		sb.WriteString(fmt.Sprintf("[%s] %s: %s\n", timeStr, sender, msg.StrContent))
	}

	return sb.String()
}

// formatMessagesBySession 按会话格式化消息列表
func (a *Analyzer) formatMessagesBySession(sessionMessagesList []SessionMessages) string {
	var sb strings.Builder

	for _, sm := range sessionMessagesList {
		// 会话标题
		sb.WriteString(fmt.Sprintf("\n========== %s ==========\n\n", sm.SessionName))

		// 该会话的所有消息
		for _, msg := range sm.Messages {
			sender := msg.SenderName
			if sender == "" {
				sender = msg.Sender
			}
			if sender == "" {
				sender = "未知"
			}

			timeStr := msg.FormattedTime
			if timeStr == "" && msg.CreateTime > 0 {
				t := time.Unix(msg.CreateTime, 0)
				timeStr = t.Format("2006-01-02 15:04:05")
			}

			sb.WriteString(fmt.Sprintf("[%s] %s: %s\n", timeStr, sender, msg.StrContent))
		}

		sb.WriteString("\n") // 会话之间空一行
	}

	return sb.String()
}

// splitIntoChunks 分段
func (a *Analyzer) splitIntoChunks(content string, maxTokens int) []string {
	// 更准确的估计：1个字符约等于0.8个token（针对中英混合文本）
	// maxTokens = 300000 -> 约 375000 字符
	maxChars := int(float64(maxTokens) / 0.8)

	if len(content) <= maxChars {
		return []string{content}
	}

	var chunks []string
	lines := strings.Split(content, "\n")

	var currentChunk strings.Builder
	currentSize := 0

	for _, line := range lines {
		lineSize := len(line) + 1 // +1 for newline

		if currentSize+lineSize > maxChars && currentSize > 0 {
			// 当前块已满，保存并开始新块
			chunks = append(chunks, currentChunk.String())
			currentChunk.Reset()
			currentSize = 0
		}

		currentChunk.WriteString(line)
		currentChunk.WriteString("\n")
		currentSize += lineSize
	}

	// 添加最后一块
	if currentSize > 0 {
		chunks = append(chunks, currentChunk.String())
	}

	return chunks
}

// summarizeChunk 总结单个分段
func (a *Analyzer) summarizeChunk(ctx context.Context, chunk string, chunkNum, totalChunks int) (string, error) {
	prompt := fmt.Sprintf(`请总结以下微信群聊天记录的主要内容和讨论话题（这是第 %d/%d 段）：

%s

要求：
1. 用中文总结
2. 总结出主要话题和讨论内容
3. 提取出重要信息（如招聘信息、活动信息、通知事项等）
4. 概括参与者的主要观点或反应
5. 保持简洁，突出重点`, chunkNum, totalChunks, chunk)

	messages := []llm.ChatMessage{
		{
			Role:    "system",
			Content: "你是一个专业的微信聊天记录分析助手，擅长总结和提取关键信息。",
		},
		{
			Role:    "user",
			Content: prompt,
		},
	}

	return a.llmClient.ChatCompletion(ctx, messages)
}

// mergeSummaries 合并所有总结
func (a *Analyzer) mergeSummaries(ctx context.Context, summaries []string) (string, error) {
	if len(summaries) == 1 {
		return summaries[0], nil
	}

	combinedSummaries := strings.Join(summaries, "\n\n---\n\n")

	prompt := fmt.Sprintf(`以下是对微信群聊天记录的多段总结，请将它们合并为一份完整、连贯的总结报告：

%s

要求：
1. 用中文撰写
2. 整合所有段落的关键信息，避免重复
3. 按主题或时间线组织内容
4. 突出重要信息（招聘、活动、通知等）
5. 使用Markdown格式，结构清晰
6. 如果有讨论的发展或决策过程，请体现出来`, combinedSummaries)

	messages := []llm.ChatMessage{
		{
			Role:    "system",
			Content: "你是一个专业的报告撰写助手，擅长整合和组织信息。",
		},
		{
			Role:    "user",
			Content: prompt,
		},
	}

	return a.llmClient.ChatCompletion(ctx, messages)
}

// saveReport 保存报告
func (a *Analyzer) saveReport(outputFile string, sessionNames []string, totalMessages int, startDate, endDate string, chunkSummaries []string, finalSummary string) error {
	var sb strings.Builder

	// 标题
	sb.WriteString("# 微信聊天记录分析报告\n\n")

	// 生成时间
	sb.WriteString(fmt.Sprintf("**生成时间**: %s\n\n", time.Now().Format("2006-01-02 15:04:05")))

	// 统计信息
	sb.WriteString("## 统计信息\n\n")
	sb.WriteString(fmt.Sprintf("- **分析消息数**: %d 条\n", totalMessages))
	sb.WriteString(fmt.Sprintf("- **涉及会话数**: %d 个\n", len(sessionNames)))
	sb.WriteString(fmt.Sprintf("- **分段数量**: %d 段\n\n", len(chunkSummaries)))

	// 会话列表
	sb.WriteString("### 涉及会话\n\n")
	for _, name := range sessionNames {
		sb.WriteString(fmt.Sprintf("- %s\n", name))
	}
	sb.WriteString("\n")

	// 时间范围
	sb.WriteString(fmt.Sprintf("- **时间范围**: %s 至 %s\n\n",
		startDate, endDate))

	sb.WriteString("---\n\n")

	// 最终总结
	sb.WriteString("## 总结报告\n\n")
	sb.WriteString(finalSummary)
	sb.WriteString("\n\n---\n\n")

	// 分段总结（可选，作为附录）
	if len(chunkSummaries) > 1 {
		sb.WriteString("## 附录：分段总结\n\n")
		for i, summary := range chunkSummaries {
			sb.WriteString(fmt.Sprintf("### 第 %d/%d 段\n\n", i+1, len(chunkSummaries)))
			sb.WriteString(summary)
			sb.WriteString("\n\n")
		}
	}

	return os.WriteFile(outputFile, []byte(sb.String()), 0644)
}

// saveChunksToFile 保存切片内容到txt文件（用于调试）
func (a *Analyzer) saveChunksToFile(outputFile string, chunks []string) error {
	var sb strings.Builder

	sb.WriteString("=== 微信聊天记录切片预览 ===\n\n")
	sb.WriteString(fmt.Sprintf("生成时间: %s\n", time.Now().Format("2006-01-02 15:04:05")))
	sb.WriteString(fmt.Sprintf("总段数: %d\n\n", len(chunks)))
	sb.WriteString(strings.Repeat("=", 80) + "\n\n")

	for i, chunk := range chunks {
		sb.WriteString(fmt.Sprintf("### 第 %d/%d 段 ###\n", i+1, len(chunks)))
		sb.WriteString(fmt.Sprintf("字符数: %d\n", len(chunk)))
		sb.WriteString(fmt.Sprintf("估算tokens: ~%.0f\n\n", float64(len(chunk))*0.8))
		sb.WriteString(strings.Repeat("-", 80) + "\n")
		sb.WriteString(chunk)
		sb.WriteString("\n")
		sb.WriteString(strings.Repeat("=", 80) + "\n\n")
	}

	return os.WriteFile(outputFile, []byte(sb.String()), 0644)
}

// loadSession 加载会话
func loadSession(path string) (*Session, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var session Session
	if err := json.Unmarshal(data, &session); err != nil {
		return nil, err
	}

	return &session, nil
}
