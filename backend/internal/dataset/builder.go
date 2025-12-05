package dataset

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/billyoftea/wxagent/go_backend/internal/state"
)

type Message struct {
	LocalID           int64  `json:"localId"`
	CreateTime        int64  `json:"createTime"`
	FormattedTime     string `json:"formattedTime"`
	Type              string `json:"type"`
	LocalType         int    `json:"localType"`
	Content           string `json:"content"`
	IsSend            int    `json:"isSend"`
	SenderUsername    string `json:"senderUsername"`
	SenderDisplayName string `json:"senderDisplayName"`
}

type SessionInfo struct {
	WxID        string `json:"wxid"`
	Nickname    string `json:"nickname"`
	Remark      string `json:"remark"`
	DisplayName string `json:"displayName"`
	Type        string `json:"type"`
}

type ExportMetadata struct {
	TotalMessageCount int64  `json:"totalMessageCount"`
	LastExportTime    string `json:"lastExportTime"`
}

type ChatLog struct {
	Session        SessionInfo    `json:"session"`
	Messages       []Message      `json:"messages"`
	ExportMetadata ExportMetadata `json:"exportMetadata"`
}

type Builder struct {
	exportDir string
	state     *state.Store
}

func NewBuilder(exportDir string, s *state.Store) *Builder {
	return &Builder{
		exportDir: exportDir,
		state:     s,
	}
}

type BuildResult struct {
	Dataset map[string][]string // SessionName -> []MessageContent
	Stats   []SessionStat
}

type SessionStat struct {
	DisplayName   string `json:"display_name"`
	Messages      int    `json:"messages"`
	LastTimestamp int64  `json:"last_timestamp"`
}

func (b *Builder) Build(startDate, endDate string, incremental bool, allowedSessions []string) (*BuildResult, error) {
	files, err := filepath.Glob(filepath.Join(b.exportDir, "*.json"))
	if err != nil {
		return nil, fmt.Errorf("glob export dir: %w", err)
	}

	startTs, endTs := parseDateRange(startDate, endDate)
	allowedSet := make(map[string]bool)
	for _, s := range allowedSessions {
		allowedSet[s] = true
	}

	dataset := make(map[string][]string)
	stats := []SessionStat{}

	for _, file := range files {
		if strings.HasSuffix(file, ".export_state") {
			continue
		}

		log, err := loadChatLog(file)
		if err != nil {
			// Skip malformed files
			continue
		}

		sessionName := log.Session.DisplayName
		if sessionName == "" {
			sessionName = log.Session.Nickname
		}
		if sessionName == "" {
			sessionName = "Unknown Session"
		}

		if len(allowedSet) > 0 && !allowedSet[sessionName] {
			continue
		}

		lastProcessedTs := int64(0)
		if incremental {
			lastProcessedTs = b.state.LastTimestamp(log.Session.WxID)
		}

		filteredMsgs := []string{}
		maxTs := lastProcessedTs

		for _, msg := range log.Messages {
			if msg.CreateTime <= lastProcessedTs {
				continue
			}
			if startTs > 0 && msg.CreateTime < startTs {
				continue
			}
			if endTs > 0 && msg.CreateTime > endTs {
				continue
			}

			if msg.CreateTime > maxTs {
				maxTs = msg.CreateTime
			}

			formatted := formatMessage(msg)
			filteredMsgs = append(filteredMsgs, formatted)
		}

		if len(filteredMsgs) > 0 {
			dataset[sessionName] = filteredMsgs
			stats = append(stats, SessionStat{
				DisplayName:   sessionName,
				Messages:      len(filteredMsgs),
				LastTimestamp: maxTs,
			})

			// Update state in memory (caller should save)
			b.state.UpdateSession(log.Session.WxID, maxTs, len(filteredMsgs))
		}
	}

	return &BuildResult{
		Dataset: dataset,
		Stats:   stats,
	}, nil
}

func loadChatLog(path string) (*ChatLog, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var log ChatLog
	if err := json.NewDecoder(f).Decode(&log); err != nil {
		return nil, err
	}
	return &log, nil
}

func parseDateRange(start, end string) (int64, int64) {
	var s, e int64
	if start != "" {
		if t, err := time.Parse("2006-01-02", start); err == nil {
			s = t.Unix()
		}
	}
	if end != "" {
		if t, err := time.Parse("2006-01-02", end); err == nil {
			// End of the day
			e = t.Add(24*time.Hour).Unix() - 1
		}
	}
	return s, e
}

func formatMessage(msg Message) string {
	sender := msg.SenderDisplayName
	if sender == "" {
		sender = msg.SenderUsername
	}

	content := msg.Content
	if msg.Type == "图片消息" || msg.LocalType == 3 {
		content = "[图片]"
	} else if msg.Type == "语音消息" || msg.LocalType == 34 {
		content = "[语音]"
	} else if msg.Type == "视频消息" || msg.LocalType == 43 {
		content = "[视频]"
	}

	return fmt.Sprintf("[%s] %s: %s", msg.FormattedTime, sender, content)
}

// ListSessionsMetadata returns basic info about all exported sessions
func (b *Builder) ListSessionsMetadata() ([]map[string]any, error) {
	files, err := filepath.Glob(filepath.Join(b.exportDir, "*.json"))
	if err != nil {
		return nil, err
	}

	results := []map[string]any{}
	for _, file := range files {
		if strings.HasSuffix(file, ".export_state") {
			continue
		}
		// Just read the beginning to get session info to be faster?
		// For now read full file, optimization later.
		log, err := loadChatLog(file)
		if err != nil {
			continue
		}

		results = append(results, map[string]any{
			"wxid":           log.Session.WxID,
			"displayName":    log.Session.DisplayName,
			"messageCount":   log.ExportMetadata.TotalMessageCount,
			"lastExportTime": log.ExportMetadata.LastExportTime,
			"file":           filepath.Base(file),
		})
	}

	// Sort by last export time desc
	sort.Slice(results, func(i, j int) bool {
		t1 := results[i]["lastExportTime"].(string)
		t2 := results[j]["lastExportTime"].(string)
		return t1 > t2
	})

	return results, nil
}
