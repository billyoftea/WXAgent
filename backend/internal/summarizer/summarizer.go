package summarizer

import (
	"context"
	"fmt"
	"strings"

	"github.com/billyoftea/wxagent/go_backend/internal/llm"
)

const (
	MaxChunkChars = 6000 // Conservative limit for 8k/16k context models
)

type Summarizer struct {
	llm *llm.Client
}

func New(client *llm.Client) *Summarizer {
	return &Summarizer{
		llm: client,
	}
}

func (s *Summarizer) SummarizeSession(ctx context.Context, sessionName string, messages []string) (string, error) {
	if len(messages) == 0 {
		return "No messages to summarize.", nil
	}

	fullText := strings.Join(messages, "\n")
	chunks := splitText(fullText, MaxChunkChars)

	if len(chunks) == 1 {
		return s.summarizeChunk(ctx, sessionName, chunks[0], false)
	}

	// Map phase: summarize each chunk
	var chunkSummaries []string
	for i, chunk := range chunks {
		summary, err := s.summarizeChunk(ctx, sessionName, chunk, true)
		if err != nil {
			return "", fmt.Errorf("summarize chunk %d: %w", i, err)
		}
		chunkSummaries = append(chunkSummaries, summary)
	}

	// Reduce phase: summarize the summaries
	combined := strings.Join(chunkSummaries, "\n\n")
	return s.summarizeFinal(ctx, sessionName, combined)
}

func (s *Summarizer) summarizeChunk(ctx context.Context, sessionName, text string, isPartial bool) (string, error) {
	prompt := fmt.Sprintf("You are a helpful assistant summarizing a chat log for session '%s'.\n", sessionName)
	if isPartial {
		prompt += "This is a PARTIAL log. Summarize the key points, decisions, and interesting topics discussed. Be concise."
	} else {
		prompt += "Summarize the following chat log. Focus on key events, decisions, and topics. Use bullet points."
	}

	msgs := []llm.ChatMessage{
		{Role: "system", Content: prompt},
		{Role: "user", Content: text},
	}

	return s.llm.ChatCompletion(ctx, msgs)
}

func (s *Summarizer) summarizeFinal(ctx context.Context, sessionName, text string) (string, error) {
	prompt := fmt.Sprintf("You are a helpful assistant. Below are partial summaries of a chat log for session '%s'.\n", sessionName)
	prompt += "Combine these into a single, coherent, and comprehensive summary. Use Markdown formatting."

	msgs := []llm.ChatMessage{
		{Role: "system", Content: prompt},
		{Role: "user", Content: text},
	}

	return s.llm.ChatCompletion(ctx, msgs)
}

func splitText(text string, limit int) []string {
	if len(text) <= limit {
		return []string{text}
	}

	var chunks []string
	runes := []rune(text)

	for len(runes) > 0 {
		if len(runes) <= limit {
			chunks = append(chunks, string(runes))
			break
		}

		// Find a split point (newline) near the limit
		splitIdx := limit
		for i := limit; i > limit-500 && i > 0; i-- {
			if runes[i] == '\n' {
				splitIdx = i
				break
			}
		}

		chunks = append(chunks, string(runes[:splitIdx]))
		runes = runes[splitIdx:]
	}

	return chunks
}
