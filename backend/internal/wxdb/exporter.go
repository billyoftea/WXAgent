package wxdb

import (
	"context"
	"crypto/md5"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/billyoftea/wxagent/go_backend/internal/state"
	"github.com/billyoftea/wxagent/go_backend/internal/wxdb/decrypt"
	_ "modernc.org/sqlite"
)

// ExportConfig 瀵煎嚭閰嶇疆
type ExportConfig struct {
	WeChatDataDir string       // 寰俊鏁版嵁鐩綍
	DBKey         string       // 鏁版嵁搴撳瘑閽?
	OutputDir     string       // 杈撳嚭鐩綍
	Sessions      []string     // 瑕佸鍑虹殑浼氳瘽ID锛屼负绌哄垯瀵煎嚭鎵€鏈?
	StartDate     string       // 寮€濮嬫棩鏈?YYYY-MM-DD
	EndDate       string       // 缁撴潫鏃ユ湡 YYYY-MM-DD
	Incremental   bool         // 澧為噺瀵煎嚭
	StateStore    *state.Store // 状态存储（用于增量导出）
}

// Message models the subset of fields required for export.
type Message struct {
	CreateTime      int64  `json:"create_time"`
	FormattedTime   string `json:"formatted_time"`  // 可读时间格式
	Type            string `json:"type"`            // readable type label
	StrContent      string `json:"str_content"`
	IsSender        int    `json:"is_sender"`
}

// messageTypeMap maps message type codes to human-readable labels.
var messageTypeMap = map[int]string{
	1:     "\u6587\u672c",
	3:     "\u56fe\u7247",
	34:    "\u8bed\u97f3",
	42:    "\u540d\u7247",
	43:    "\u89c6\u9891",
	47:    "\u8868\u60c5",
	48:    "\u4f4d\u7f6e",
	49:    "\u5206\u4eab\u94fe\u63a5",
	10000: "\u7cfb\u7edf\u6d88\u606f",
	10002: "\u64a4\u56de\u6d88\u606f",
}

// Session holds session metadata.
type Session struct {
	SessionID    string    `json:"session_id"`
	SessionName  string    `json:"session_name"`
	Messages     []Message `json:"messages"`
	ExportTime   string    `json:"export_time"`
	MessageCount int       `json:"message_count"`
}

// ContactInfo 鑱旂郴浜轰俊鎭?
type ContactInfo struct {
	UsrName  string
	NickName string
}

// Exporter 寰俊鏁版嵁搴撳鍑哄櫒
type Exporter struct {
	config ExportConfig
}

// NewExporter 鍒涘缓瀵煎嚭鍣?
func NewExporter(config ExportConfig) *Exporter {
	return &Exporter{config: config}
}

// Export 鎵ц瀵煎嚭
func (e *Exporter) Export() error {
	// 1. 鏌ユ壘鎵€鏈?message_*.db 鏂囦欢
	messageDBDir := filepath.Join(e.config.WeChatDataDir, "db_storage", "message")
	if _, err := os.Stat(messageDBDir); os.IsNotExist(err) {
		return fmt.Errorf("message database directory not found: %s", messageDBDir)
	}

	// 鎵弿鎵€鏈?message_*.db 鏂囦欢
	entries, err := os.ReadDir(messageDBDir)
	if err != nil {
		return fmt.Errorf("read message directory: %w", err)
	}

	var messageDBs []string
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		// 鍖归厤 message_0.db, message_1.db 绛?
		if strings.HasPrefix(name, "message_") && strings.HasSuffix(name, ".db") && !strings.Contains(name, "fts") && !strings.Contains(name, "resource") {
			messageDBs = append(messageDBs, filepath.Join(messageDBDir, name))
		}
	}

	if len(messageDBs) == 0 {
		return fmt.Errorf("no message database files found in %s", messageDBDir)
	}

	fmt.Printf("Found %d message database file(s)\n", len(messageDBs))

	// 2. 澶勭悊姣忎釜鏁版嵁搴撴枃浠?
	allSessions := make(map[string]bool)
	wxidCache := make(map[string]string) // Msg_<md5(wxid)> -> wxid cache
	contactNames := e.loadContactNames()
	if len(contactNames) > 0 {
		fmt.Printf("Loaded %d contact display names\n", len(contactNames))
	} else {
		fmt.Println("Loaded 0 contact display names (will fall back to wxid)")
	}

	for _, dbPath := range messageDBs {
		fmt.Printf("\nProcessing: %s\n", filepath.Base(dbPath))

		// 瑙ｅ瘑鏁版嵁搴?
		tempDBPath := filepath.Join(os.TempDir(), fmt.Sprintf("wxagent_decrypted_%s_%d.db",
			filepath.Base(dbPath), time.Now().Unix()))
		defer os.Remove(tempDBPath)

		fmt.Println("  Decrypting...")
		decryptor := decrypt.NewV4Decryptor()
		ctx := context.Background()

		if err := decryptor.DecryptToFile(ctx, dbPath, e.config.DBKey, tempDBPath); err != nil {
			fmt.Printf("  [!] Failed to decrypt: %v\n", err)
			continue
		}

		fmt.Println("  鉁?Decrypted")

		// 鎵撳紑瑙ｅ瘑鍚庣殑鏁版嵁搴?
		db, err := sql.Open("sqlite", tempDBPath)
		if err != nil {
			fmt.Printf("  [!] Failed to open: %v\n", err)
			continue
		}

		// 构建 Msg_<md5(wxid)> -> wxid 映射并累积
		fmt.Println("  Building wxid mapping...")
		wxidMap, err := e.buildWxidMap(db)
		if err != nil {
			fmt.Printf("  [!] Failed to build wxid map: %v\n", err)
		} else {
			for table, wxid := range wxidMap {
				if _, exists := wxidCache[table]; !exists {
					wxidCache[table] = wxid
				}
			}
			fmt.Printf("  [+] Mapped %d sessions (total %d)\n", len(wxidMap), len(wxidCache))
		}

		// 鍒楀嚭鎵€鏈夎〃
		tables, err := e.listTables(db)
		if err != nil {
			db.Close()
			fmt.Printf("  [!] Failed to list tables: %v\n", err)
			continue
		}
		fmt.Printf("  Tables: %v\n", tables)

		// 鏌ヨ浼氳瘽鍒楄〃
		sessions, err := e.getSessions(db)
		if err != nil {
			db.Close()
			fmt.Printf("  [!] Failed to get sessions: %v\n", err)
			continue
		}

		fmt.Printf("  Found %d sessions\n", len(sessions))

		// 瀵煎嚭浼氳瘽
		for _, sessionID := range sessions {
			if allSessions[sessionID] {
				continue // 宸茬粡瀵煎嚭杩囪繖涓細璇濅簡
			}

			if err := e.exportSession(db, sessionID, wxidCache, contactNames); err != nil {
				fmt.Printf("  [!] Failed to export %s: %v\n", sessionID, err)
				continue
			}
			allSessions[sessionID] = true
		}

		db.Close()
	}

	fmt.Printf("\n[OK] Exported %d unique sessions\n", len(allSessions))

	// 保存状态（用于增量导出）
	if e.config.Incremental && e.config.StateStore != nil {
		if err := e.config.StateStore.Save(); err != nil {
			fmt.Printf("⚠️ Failed to save export state: %v\n", err)
		} else {
			fmt.Println("✓ Export state saved")
		}
	}

	return nil
}

func (e *Exporter) getSessions(db *sql.DB) ([]string, error) {
	// 濡傛灉鎸囧畾浜嗕細璇濆垪琛紝鐩存帴杩斿洖
	if len(e.config.Sessions) > 0 {
		return e.config.Sessions, nil
	}

	// 寰俊浣跨敤 Msg_{md5(wxid)} 浣滀负琛ㄥ悕锛屾墍浠ユ垜浠煡璇㈡墍鏈?Msg_ 寮€澶寸殑琛?
	query := `SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Msg_%' ORDER BY name`
	rows, err := db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var sessions []string
	for rows.Next() {
		var tableName string
		if err := rows.Scan(&tableName); err != nil {
			continue
		}
		// 琛ㄥ悕鏍煎紡: Msg_<md5>锛屾垜浠殏鏃剁敤琛ㄥ悕浣滀负 session ID
		sessions = append(sessions, tableName)
	}

	return sessions, nil
}

func (e *Exporter) exportSession(db *sql.DB, tableName string, wxidMap map[string]string, contactNames map[string]string) error {
	// tableName 格式: Msg_<md5(wxid)>
	// 从wxidMap获取wxid
	sessionID := wxidMap[tableName]
	if sessionID == "" {
		sessionID = tableName // 降级使用表名
	}

	// 获取显示名称
	sessionName := sessionID
	if name := contactNames[sessionID]; name != "" {
		sessionName = name
	}

	// 如果还是没找到名称，可能是因为sessionID有@chatroom后缀
	// 尝试移除后缀再查找
	if sessionName == sessionID && strings.HasSuffix(sessionID, "@chatroom") {
		baseID := strings.TrimSuffix(sessionID, "@chatroom")
		if name := contactNames[baseID]; name != "" {
			sessionName = name
		}
	}

	// 增量导出：获取上次导出的最后时间戳
	lastTimestamp := int64(0)
	if e.config.Incremental && e.config.StateStore != nil {
		lastTimestamp = e.config.StateStore.LastTimestamp(sessionID)
		if lastTimestamp > 0 {
			fmt.Printf("  [Incremental] Session %s: last timestamp %d\n", sessionID, lastTimestamp)
		}
	}

	// 构建查询，增量模式下只查询新消息
	var query string
	if lastTimestamp > 0 {
		query = fmt.Sprintf(`
			SELECT 
				create_time,
				local_type,
				message_content,
				real_sender_id
			FROM %s
			WHERE create_time > %d
			ORDER BY create_time ASC
		`, tableName, lastTimestamp)
	} else {
		query = fmt.Sprintf(`
			SELECT 
				create_time,
				local_type,
				message_content,
				real_sender_id
			FROM %s
			ORDER BY create_time ASC
		`, tableName)
	}

	rows, err := db.Query(query)
	if err != nil {
		return fmt.Errorf("query messages: %w", err)
	}
	defer rows.Close()

	var messages []Message
	maxTimestamp := lastTimestamp
	
	for rows.Next() {
		var msg Message
		var realSenderID sql.NullInt64
		var msgType int

		if err := rows.Scan(&msg.CreateTime, &msgType, &msg.StrContent, &realSenderID); err != nil {
			continue
		}

		// 格式化时间戳为可读格式
		msg.FormattedTime = time.Unix(msg.CreateTime, 0).Format("2006-01-02 15:04:05")

		// Translate message type to a readable label
		msg.Type = getMessageTypeName(msgType)
		if msg.Type == "??" {
			// Emoji payload is binary; use placeholder text
			msg.StrContent = "????"
		}

		// Mark as received when sender ID exists (self detection TBD)
		if realSenderID.Valid {
			msg.IsSender = 0 // default to received
		}

		messages = append(messages, msg)
		
		// 跟踪最大时间戳
		if msg.CreateTime > maxTimestamp {
			maxTimestamp = msg.CreateTime
		}
	}

	if len(messages) == 0 {
		// 没有新消息
		if lastTimestamp > 0 {
			fmt.Printf("  [OK] %s: No new messages (incremental)\n", sessionID)
		}
		return nil
	}

	// 增量模式：需要合并已有的消息
	if e.config.Incremental && lastTimestamp > 0 {
		// 读取已有的JSON文件
		fileName := sanitizeFilename(sessionName)
		if fileName == "" {
			fileName = sessionID
		} else if fileName != sessionID && sessionID != "" {
			fileName = fmt.Sprintf("%s_%s", fileName, sessionID)
		}
		outputPath := filepath.Join(e.config.OutputDir, fileName+".json")

		existingSession, err := e.loadExistingSession(outputPath)
		if err == nil && existingSession != nil {
			// 合并消息
			messages = append(existingSession.Messages, messages...)
		}
	}

	// Build JSON output
	session := Session{
		SessionID:    sessionID,
		SessionName:  sessionName,
		Messages:     messages,
		ExportTime:   time.Now().Format(time.RFC3339),
		MessageCount: len(messages),
	}

	// Prefer readable session name for file naming, append sessionID to avoid collisions
	fileName := sanitizeFilename(sessionName)
	if fileName == "" {
		fileName = sessionID
	} else if fileName != sessionID && sessionID != "" {
		fileName = fmt.Sprintf("%s_%s", fileName, sessionID)
	}
	outputPath := filepath.Join(e.config.OutputDir, fileName+".json")
	if err := e.saveSession(session, outputPath); err != nil {
		return err
	}

	// 更新状态（记录最新的时间戳）
	if e.config.Incremental && e.config.StateStore != nil && maxTimestamp > 0 {
		e.config.StateStore.UpdateSession(sessionID, maxTimestamp, len(messages))
	}

	fmt.Printf("  [OK] Exported %s: %d messages\n", sessionID, len(messages))
	return nil
}

// loadExistingSession 从文件加载已有的会话数据（用于增量导出合并）
func (e *Exporter) loadExistingSession(path string) (*Session, error) {
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

func (e *Exporter) saveSession(session Session, path string) error {
	// 纭繚杈撳嚭鐩綍瀛樺湪
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}

	// 鍒涘缓鏂囦欢
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()

	// 浣跨敤 Encoder 鍐欏叆 JSON,淇濈暀涓枃瀛楃涓嶈浆涔?
	encoder := json.NewEncoder(file)
	encoder.SetEscapeHTML(false)
	encoder.SetIndent("", "  ")
	return encoder.Encode(session)
}

func (e *Exporter) listTables(db *sql.DB) ([]string, error) {
	query := `SELECT name FROM sqlite_master WHERE type='table' ORDER BY name`
	rows, err := db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tables []string
	for rows.Next() {
		var tableName string
		if err := rows.Scan(&tableName); err != nil {
			continue
		}
		tables = append(tables, tableName)
	}

	return tables, nil
}

// buildWxidMap 浠?Name2Id 琛ㄦ瀯寤鸿〃鍚嶅埌wxid鐨勬槧灏?
// 琛ㄥ悕鏍煎紡: Msg_<MD5(wxid)>

// loadContactNames loads wxid -> display name (remark/nickname/alias) from contact databases.
func (e *Exporter) loadContactNames() map[string]string {
	results := make(map[string]string)
	if e.config.WeChatDataDir == "" {
		return results
	}

	_ = filepath.WalkDir(e.config.WeChatDataDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			return nil
		}
		lower := strings.ToLower(d.Name())
		if !strings.HasSuffix(lower, ".db") {
			return nil
		}
		if !strings.Contains(lower, "contact") {
			return nil
		}
		e.loadContactFile(path, results)
		return nil
	})
	return results
}

func (e *Exporter) loadContactFile(path string, results map[string]string) {
	tempPath := filepath.Join(os.TempDir(), fmt.Sprintf("wxagent_contact_%d.db", time.Now().UnixNano()))
	defer os.Remove(tempPath)

	decryptor := decrypt.NewV4Decryptor()
	ctx := context.Background()
	if err := decryptor.DecryptToFile(ctx, path, e.config.DBKey, tempPath); err != nil {
		return
	}

	db, err := sql.Open("sqlite", tempPath)
	if err != nil {
		return
	}
	defer db.Close()

	tables := []string{"contact", "Contact"}
	for _, table := range tables {
		rows, err := db.Query(fmt.Sprintf("SELECT username, remark, nick_name, alias FROM %s", table))
		if err != nil {
			continue
		}
		for rows.Next() {
			var username, remark, nick, alias sql.NullString
			if err := rows.Scan(&username, &remark, &nick, &alias); err != nil {
				continue
			}
			user := strings.TrimSpace(username.String)
			if user == "" {
				continue
			}
			display := firstNonEmpty(strings.TrimSpace(remark.String), strings.TrimSpace(nick.String), strings.TrimSpace(alias.String))
			if display == "" {
				continue
			}
			if _, exists := results[user]; !exists {
				results[user] = display
			}
		}
		rows.Close()
	}
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}
func (e *Exporter) buildWxidMap(db *sql.DB) (map[string]string, error) {
	wxidMap := make(map[string]string)

	// 浠嶯ame2Id鑾峰彇鎵€鏈墂xid
	rows, err := db.Query(`SELECT user_name FROM Name2Id`)
	if err != nil {
		return nil, fmt.Errorf("query Name2Id: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var wxid string
		if err := rows.Scan(&wxid); err != nil {
			continue
		}

		// 璁＄畻MD5
		hash := md5.Sum([]byte(wxid))
		md5Str := hex.EncodeToString(hash[:])
		tableName := "Msg_" + md5Str

		wxidMap[tableName] = wxid
	}

	return wxidMap, nil
}

// getMessageTypeName converts the numeric message type into a readable label.
func getMessageTypeName(typeCode int) string {
	if name, ok := messageTypeMap[typeCode]; ok {
		return name
	}
	return fmt.Sprintf("\u672a\u77e5\u7c7b\u578b(%d)", typeCode)
}

// sanitizeFilename removes Windows-invalid characters from a name used for output files.
func sanitizeFilename(name string) string {
	replacer := strings.NewReplacer(
		"<", "_",
		">", "_",
		":", "_",
		"\"", "_",
		"/", "_",
		"\\", "_",
		"|", "_",
		"?", "_",
		"*", "_",
	)
	clean := strings.TrimSpace(replacer.Replace(name))
	return clean
}
