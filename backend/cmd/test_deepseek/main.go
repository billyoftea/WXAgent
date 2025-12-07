package main

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/billyoftea/wxagent/go_backend/internal/config"
	"github.com/billyoftea/wxagent/go_backend/internal/llm"
)

func main() {
	fmt.Println("=== DeepSeek API 测试 ===\n")

	// 配置 DeepSeek API
	cfg := config.LLMConfig{
		BaseURL:     "https://api.deepseek.com/v1",
		APIKey:      "sk-70b3bb08f690485b85bce660f6ec32fc",
		Model:       "deepseek-chat",
		Temperature: 0.7,
		Timeout:     30 * time.Second,
	}

	// 创建 LLM 客户端
	client := llm.NewClient(cfg)

	// 测试用例1: 简单问答
	fmt.Println("📝 测试1: 简单问答")
	testSimpleChat(client)

	fmt.Println("\n" + strings.Repeat("-", 50) + "\n")

	// 测试用例2: 微信聊天记录总结
	fmt.Println("📝 测试2: 微信聊天记录总结")
	testWeChatSummary(client)

	fmt.Println("\n" + strings.Repeat("-", 50) + "\n")

	// 测试用例3: 关键信息提取
	fmt.Println("📝 测试3: 关键信息提取")
	testKeyInfoExtraction(client)
}

func testSimpleChat(client *llm.Client) {
	ctx := context.Background()

	messages := []llm.ChatMessage{
		{
			Role:    "user",
			Content: "你好！请简单介绍一下你自己。",
		},
	}

	fmt.Println("请求消息:", messages[0].Content)
	fmt.Println("\n等待响应...")

	start := time.Now()
	response, err := client.ChatCompletion(ctx, messages)
	duration := time.Since(start)

	if err != nil {
		log.Printf("❌ 错误: %v\n", err)
		return
	}

	fmt.Printf("✅ 成功! (耗时: %.2fs)\n", duration.Seconds())
	fmt.Printf("响应: %s\n", response)
}

func testWeChatSummary(client *llm.Client) {
	ctx := context.Background()

	// 模拟微信聊天记录
	chatHistory := `
[2024-12-05 14:23:15] 张三: 明天下午两点开会，大家记得准时参加
[2024-12-05 14:25:32] 李四: 收到，会议室在哪里？
[2024-12-05 14:26:11] 张三: A座302会议室
[2024-12-05 14:28:45] 王五: 好的，我会准时到
[2024-12-05 15:02:33] 李四: 需要准备什么材料吗？
[2024-12-05 15:05:12] 张三: 带上上周的项目进度报告
[2024-12-05 15:10:28] 王五: 明白了
`

	messages := []llm.ChatMessage{
		{
			Role:    "system",
			Content: "你是一个专业的微信聊天记录分析助手，擅长总结和提取关键信息。",
		},
		{
			Role:    "user",
			Content: fmt.Sprintf("请总结以下微信聊天记录的主要内容：\n\n%s", chatHistory),
		},
	}

	fmt.Println("聊天记录长度:", len(chatHistory), "字符")
	fmt.Println("\n等待响应...")

	start := time.Now()
	response, err := client.ChatCompletion(ctx, messages)
	duration := time.Since(start)

	if err != nil {
		log.Printf("❌ 错误: %v\n", err)
		return
	}

	fmt.Printf("✅ 成功! (耗时: %.2fs)\n", duration.Seconds())
	fmt.Printf("总结结果:\n%s\n", response)
}

func testKeyInfoExtraction(client *llm.Client) {
	ctx := context.Background()

	chatHistory := `
[2024-12-05 09:15:23] HR小王: @全体成员 提醒大家，本月工资将在12月10日发放
[2024-12-05 10:32:11] 产品经理: 新版本计划在12月15日上线，请开发团队做好准备
[2024-12-05 11:45:37] 团队Leader: 周五晚上7点团建活动，地点：海底捞(万象城店)
[2024-12-05 14:20:15] 前台小李: 快递已到，请各位及时到前台领取
[2024-12-05 16:30:42] IT部门: 明天上午9-11点系统维护，期间无法访问内网
`

	messages := []llm.ChatMessage{
		{
			Role:    "system",
			Content: "你是一个信息提取助手。请从聊天记录中提取所有重要的时间、地点、事件信息，以JSON格式返回。",
		},
		{
			Role: "user",
			Content: fmt.Sprintf(`请从以下聊天记录中提取重要信息，以JSON格式返回，包含：时间、事件、地点（如果有）：

%s

请返回格式如：
{
  "events": [
    {"time": "...", "event": "...", "location": "..."}
  ]
}`, chatHistory),
		},
	}

	fmt.Println("提取模式: 结构化信息提取")
	fmt.Println("\n等待响应...")

	start := time.Now()
	response, err := client.ChatCompletion(ctx, messages)
	duration := time.Since(start)

	if err != nil {
		log.Printf("❌ 错误: %v\n", err)
		return
	}

	fmt.Printf("✅ 成功! (耗时: %.2fs)\n", duration.Seconds())
	fmt.Printf("提取结果:\n%s\n", response)
}
