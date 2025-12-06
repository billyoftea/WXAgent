# WXAgent 全自动化实现方案

## 🎯 目标
将当前需要 GUI 操作的 echotrace 改造为完全自动化的命令行工具，实现端到端的无人值守聊天记录导出和分析。

---

## 📋 实现步骤

### Phase 1: 提取解密核心代码（1-2天）

#### 1.1 分析 go_decrypt 结构
```
modules/echotrace/go_decrypt/
├── internal/
│   ├── decrypt/
│   │   └── windows/      # Windows 版本解密逻辑
│   └── unlock/           # 数据库解锁
└── main.go               # C 导出接口
```

#### 1.2 提取到后端
将解密逻辑复制到：
```
backend/internal/wxdb/
├── decrypt/
│   ├── decryptor.go      # 解密器接口
│   ├── v4_decryptor.go   # 微信 4.x 版本解密实现
│   └── cipher.go         # AES 加密算法
```

#### 1.3 移除 CGO 依赖
- go_decrypt 使用 CGO 导出 C 接口
- 我们只需要纯 Go 实现
- 移除 `import "C"` 相关代码

---

### Phase 2: 实现数据库读取（1天）

#### 2.1 安装依赖
```bash
cd backend
go get github.com/mattn/go-sqlite3
# 或使用纯 Go 实现
go get modernc.org/sqlite
```

#### 2.2 实现数据库操作
```go
// backend/internal/wxdb/database.go
package wxdb

type Database struct {
    path string
    key  string
    db   *sql.DB
}

func OpenDatabase(path, key string) (*Database, error) {
    // 1. 解密数据库
    decryptor := decrypt.NewV4Decryptor()
    tempDB, err := decryptor.DecryptToTemp(path, key)
    
    // 2. 打开解密后的数据库
    db, err := sql.Open("sqlite3", tempDB)
    
    return &Database{path: path, key: key, db: db}, nil
}

func (d *Database) QueryMessages(sessionID string, startTime, endTime int64) ([]Message, error) {
    query := `
        SELECT localId, talkerId, msgSvrId, type, subType, 
               isSender, createTime, sequence, statusEx, flagEx, 
               status, msgServerSeq, msgSequence, strTalker, 
               strContent, displayContent, reserved0, reserved1, 
               reserved3, reserved4, reserved5, reserved6, 
               compressContent, bytesExtra, bytesTrans
        FROM MSG
        WHERE strTalker = ?
          AND createTime >= ?
          AND createTime < ?
        ORDER BY createTime ASC
    `
    
    rows, err := d.db.Query(query, sessionID, startTime, endTime)
    // ... 解析结果
}
```

---

### Phase 3: 实现导出器（1-2天）

#### 3.1 核心导出逻辑
```go
// backend/internal/wxdb/exporter.go
type Exporter struct {
    db          *Database
    outputDir   string
    stateFile   string
    incremental bool
}

func (e *Exporter) ExportAll() error {
    // 1. 获取所有会话列表
    sessions, err := e.db.ListSessions()
    
    // 2. 遍历导出
    for _, session := range sessions {
        // 读取上次导出状态
        lastState := e.loadState(session.ID)
        
        // 增量导出：只导出新消息
        startTime := lastState.LastMessageTime
        messages, err := e.db.QueryMessages(
            session.ID, 
            startTime, 
            time.Now().Unix(),
        )
        
        // 保存为 JSON
        e.saveToJSON(session.ID, messages)
        
        // 更新状态
        e.saveState(session.ID, newState)
    }
}
```

#### 3.2 增量导出状态管理
```go
// backend/internal/wxdb/state.go
type ExportState struct {
    SessionID       string    `json:"session_id"`
    LastMessageID   int64     `json:"last_message_id"`
    LastMessageTime int64     `json:"last_message_time"`
    LastExportTime  time.Time `json:"last_export_time"`
    MessageCount    int       `json:"message_count"`
}

func LoadExportState(sessionID, stateDir string) (*ExportState, error) {
    statePath := filepath.Join(stateDir, sessionID+".export_state")
    // 读取并解析 JSON
}

func SaveExportState(state *ExportState, stateDir string) error {
    statePath := filepath.Join(stateDir, state.SessionID+".export_state")
    // 序列化并保存 JSON
}
```

---

### Phase 4: 集成到 Pipeline（0.5天）

#### 4.1 添加新命令
```go
// backend/cmd/wxagent_backend/main.go
func main() {
    switch cmd {
    case "export":
        // 旧方式：调用 echotrace GUI
        runExport(pipe)
    case "export-auto":
        // 新方式：自动化导出
        runExportAuto(pipe)
    // ...
    }
}

func runExportAuto(p *pipeline.Pipeline) {
    // 读取微信数据路径
    wechatDataDir := p.Config.WechatDataPath
    
    // 获取密钥
    key, err := p.WxKey.LoadKeys()
    if err != nil {
        // 自动启动 wx_key
        key, err = p.RefreshKey(true, 120, 5)
    }
    
    // 执行自动导出
    exporter := wxdb.NewExporter(wxdb.ExportConfig{
        WeChatDataDir: wechatDataDir,
        DBKey:         key.DbKey,
        OutputDir:     p.Config.ExportDir,
        Incremental:   true,
    })
    
    if err := exporter.Export(); err != nil {
        fmt.Fprintf(os.Stderr, "Export failed: %v\n", err)
        os.Exit(1)
    }
    
    fmt.Println("✓ Export completed successfully")
}
```

#### 4.2 更新配置文件
```json
{
  "wechat_data_path": "C:\\Users\\YourName\\Documents\\WeChat Files\\wxid_xxx",
  "export_dir": "../output",
  "auto_export": {
    "enabled": true,
    "incremental": true,
    "sessions": []  // 空则导出所有
  }
}
```

---

### Phase 5: 测试和优化（1天）

#### 5.1 单元测试
```go
// backend/internal/wxdb/exporter_test.go
func TestExportSession(t *testing.T) {
    exporter := NewExporter(ExportConfig{
        WeChatDataDir: "./testdata",
        DBKey:         "test_key",
        OutputDir:     "./output",
    })
    
    err := exporter.ExportSession("test_session_id")
    assert.NoError(t, err)
}
```

#### 5.2 集成测试
```powershell
# 完整流程测试
.\wxagent_backend.exe refresh-key
.\wxagent_backend.exe export-auto
.\wxagent_backend.exe summarize
```

#### 5.3 性能优化
- 并发导出多个会话
- 增量导出减少 I/O
- 数据库连接池

---

## 🎯 最终用户体验

### 一键自动化
```powershell
# 方式1: 分步执行
.\wxagent_backend.exe refresh-key    # 获取密钥
.\wxagent_backend.exe export-auto    # 自动导出
.\wxagent_backend.exe summarize      # 生成总结

# 方式2: 一键完成（推荐）
.\wxagent_backend.exe start --auto-export
```

### 配置文件示例
```json
{
  "wechat_data_path": "自动检测",
  "auto_export": {
    "enabled": true,
    "incremental": true,
    "schedule": "daily",
    "time": "02:00"
  },
  "llm": {
    "provider": "ark",
    "api_key": "${ARK_API_KEY}"
  }
}
```

---

## 📊 工作量评估

| 阶段 | 任务 | 预计时间 | 难度 |
|------|------|---------|------|
| Phase 1 | 提取解密代码 | 1-2天 | ⭐⭐⭐ |
| Phase 2 | 数据库读取 | 1天 | ⭐⭐ |
| Phase 3 | 导出器实现 | 1-2天 | ⭐⭐⭐ |
| Phase 4 | Pipeline集成 | 0.5天 | ⭐ |
| Phase 5 | 测试优化 | 1天 | ⭐⭐ |
| **总计** | | **4.5-6.5天** | |

---

## 🚀 快速启动（最小化实现）

如果时间紧张，可以先实现核心功能：

### 简化版（2-3天）
1. ✅ 复用 go_decrypt DLL
2. ✅ 基础 SQLite 读取
3. ✅ 简单 JSON 导出
4. ❌ 跳过增量导出
5. ❌ 跳过性能优化

```go
// 最小化实现
func QuickExport(wechatDir, key, outputDir string) error {
    // 1. 调用 go_decrypt.dll 解密
    decryptedDB := callGoDecrypt(wechatDir, key)
    
    // 2. 读取所有消息
    db, _ := sql.Open("sqlite3", decryptedDB)
    rows, _ := db.Query("SELECT * FROM MSG")
    
    // 3. 保存为 JSON
    messages := parseRows(rows)
    saveJSON(outputDir, messages)
    
    return nil
}
```

这样可以快速实现自动化，后续再迭代优化。

---

## ✅ 验收标准

- [ ] 无需打开任何 GUI 窗口
- [ ] 命令行一键完成导出
- [ ] 支持增量导出
- [ ] 导出速度 < 30秒（1000条消息）
- [ ] JSON 格式与 echotrace 兼容
- [ ] 错误处理完善
- [ ] 文档完整

---

## 📝 注意事项

1. **数据库加密**: 微信 4.x 使用 SQLCipher，需要正确的解密实现
2. **文件权限**: 微信运行时数据库文件可能被锁定
3. **路径检测**: 不同用户的微信数据路径不同，需要自动检测
4. **兼容性**: 确保与不同微信版本兼容

---

## 🔗 相关资源

- echotrace go_decrypt: `modules/echotrace/go_decrypt/`
- SQLCipher 文档: https://www.zetetic.net/sqlcipher/
- 微信数据库结构: 参考 echotrace 文档

---

**更新时间**: 2025-12-05
**状态**: 方案设计完成，待实施
