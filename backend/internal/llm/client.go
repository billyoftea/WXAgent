package llm

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/billyoftea/wxagent/go_backend/internal/config"
)

type Client struct {
	cfg    config.LLMConfig
	client *http.Client
}

func NewClient(cfg config.LLMConfig) *Client {
	return &Client{
		cfg: cfg,
		client: &http.Client{
			// 流式请求不设置超时，通过 context 控制
			Timeout: 0,
		},
	}
}

// sanitizeAPIKey removes whitespace/control characters that would make the
// Authorization header invalid on some providers.
func sanitizeAPIKey(key string) string {
	clean := strings.TrimSpace(key)
	clean = strings.ReplaceAll(clean, "\r", "")
	clean = strings.ReplaceAll(clean, "\n", "")
	return clean
}

type ChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type ChatRequest struct {
	Model       string        `json:"model"`
	Messages    []ChatMessage `json:"messages"`
	Temperature float64       `json:"temperature"`
	Stream      bool          `json:"stream"`
}

type ChatResponse struct {
	Choices []struct {
		Message ChatMessage `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
		Type    string `json:"type"`
	} `json:"error,omitempty"`
}

// StreamChunk 流式响应的单个块
type StreamChunk struct {
	Choices []struct {
		Delta struct {
			Content string `json:"content"`
		} `json:"delta"`
		FinishReason string `json:"finish_reason"`
	} `json:"choices"`
}

// ChatCompletionStream 流式调用 API，实时输出内容
func (c *Client) ChatCompletionStream(ctx context.Context, messages []ChatMessage) (string, error) {
	reqBody := ChatRequest{
		Model:       c.cfg.Model,
		Messages:    messages,
		Temperature: c.cfg.Temperature,
		Stream:      true,
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	url := c.cfg.BaseURL
	if url == "" {
		url = "https://api.openai.com/v1"
	}
	endpoint := fmt.Sprintf("%s/chat/completions", strings.TrimRight(url, "/"))

	req, err := http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewBuffer(jsonBody))
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if apiKey := sanitizeAPIKey(c.cfg.APIKey); apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+apiKey)
	}
	req.Header.Set("Accept", "text/event-stream")

	resp, err := c.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("api error (status %d): %s", resp.StatusCode, string(body))
	}

	// 读取 SSE 流
	var fullContent strings.Builder
	scanner := bufio.NewScanner(resp.Body)
	chunkCount := 0
	lastPrintTime := time.Now()

	for scanner.Scan() {
		line := scanner.Text()

		// SSE 格式: "data: {...}" 或 "data: [DONE]"
		if !strings.HasPrefix(line, "data: ") {
			continue
		}

		data := strings.TrimPrefix(line, "data: ")
		if data == "[DONE]" {
			break
		}

		var chunk StreamChunk
		if err := json.Unmarshal([]byte(data), &chunk); err != nil {
			continue // 跳过解析失败的行
		}

		if len(chunk.Choices) > 0 {
			content := chunk.Choices[0].Delta.Content
			if content != "" {
				fullContent.WriteString(content)
				chunkCount++

				// 实时打印输出（每 100 个 chunk 或每 2 秒打印一次进度）
				fmt.Print(content)
				if chunkCount%100 == 0 || time.Since(lastPrintTime) > 2*time.Second {
					lastPrintTime = time.Now()
				}
			}

			if chunk.Choices[0].FinishReason == "stop" {
				break
			}
		}
	}

	if err := scanner.Err(); err != nil {
		return fullContent.String(), fmt.Errorf("read stream: %w", err)
	}

	fmt.Println() // 换行
	return fullContent.String(), nil
}

// StreamCallback 流式输出的回调函数类型
type StreamCallback func(chunk string)

// ChatCompletionWithCallback 带回调的流式调用，每个 chunk 都会触发回调
func (c *Client) ChatCompletionWithCallback(ctx context.Context, messages []ChatMessage, callback StreamCallback) (string, error) {
	reqBody := ChatRequest{
		Model:       c.cfg.Model,
		Messages:    messages,
		Temperature: c.cfg.Temperature,
		Stream:      true,
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	url := c.cfg.BaseURL
	if url == "" {
		url = "https://api.openai.com/v1"
	}
	endpoint := fmt.Sprintf("%s/chat/completions", strings.TrimRight(url, "/"))

	req, err := http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewBuffer(jsonBody))
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if apiKey := sanitizeAPIKey(c.cfg.APIKey); apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+apiKey)
	}
	req.Header.Set("Accept", "text/event-stream")

	resp, err := c.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("api error (status %d): %s", resp.StatusCode, string(body))
	}

	var fullContent strings.Builder
	scanner := bufio.NewScanner(resp.Body)

	for scanner.Scan() {
		line := scanner.Text()

		if !strings.HasPrefix(line, "data: ") {
			continue
		}

		data := strings.TrimPrefix(line, "data: ")
		if data == "[DONE]" {
			break
		}

		var chunk StreamChunk
		if err := json.Unmarshal([]byte(data), &chunk); err != nil {
			continue
		}

		if len(chunk.Choices) > 0 {
			content := chunk.Choices[0].Delta.Content
			if content != "" {
				fullContent.WriteString(content)
				// 触发回调
				if callback != nil {
					callback(content)
				}
			}

			if chunk.Choices[0].FinishReason == "stop" {
				break
			}
		}
	}

	if err := scanner.Err(); err != nil {
		return fullContent.String(), fmt.Errorf("read stream: %w", err)
	}

	return fullContent.String(), nil
}

// ChatCompletion 非流式调用（保留兼容性，内部使用流式实现）
func (c *Client) ChatCompletion(ctx context.Context, messages []ChatMessage) (string, error) {
	return c.ChatCompletionStream(ctx, messages)
}
