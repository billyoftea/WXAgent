# 增量导出架构设计文档

## 📋 概述

EchoTrace 现在支持 **增量导出** 功能，可以在不重复导出已有消息的情况下，持续追踪和更新聊天记录导出文件。

---

## 🏗️ 架构设计

### 核心组件

```
┌─────────────────────────────────────────────────────────────┐
│                      导出流程架构                              │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  ChatExportPage（前端UI）                            │   │
│  │  - 选择会话、格式、日期范围                           │   │
│  │  - 显示导出进度和历史                                │   │
│  └──────────────────────────────────────────────────────┘   │
│                            ↓                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  ChatExportService（导出服务）                       │   │
│  │  - exportToJson()           - 全量导出（覆盖）      │   │
│  │  - exportToJsonIncremental() - 增量导出（追加）      │   │
│  └──────────────────────────────────────────────────────┘   │
│                            ↓                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  DatabaseService（数据库服务）                       │   │
│  │  - getMessages()           - 获取所有消息            │   │
│  │  - getMessagesByDate()     - 按日期范围获取消息      │   │
│  └──────────────────────────────────────────────────────┘   │
│                            ↓                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  ExportStateService（状态管理服务）                  │   │
│  │  - getExportState()     - 读取导出状态             │   │
│  │  - saveExportState()    - 保存导出状态             │   │
│  │  - deleteExportState()  - 删除导出状态             │   │
│  └──────────────────────────────────────────────────────┘   │
│                            ↓                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  文件系统                                            │   │
│  │  ├── chat_record.json           (导出的聊天记录)    │   │
│  │  └── chat_record.json.export_state (导出状态元数据) │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## 📊 数据模型

### 1. ExportState 模型

```dart
class ExportState {
  String sessionWxid;           // 会话的 wxid
  String displayName;           // 会话的显示名称
  String filePath;              // 导出文件路径
  String format;                // 导出格式 (json/html/excel)
  int lastExportedLocalId;      // 最后导出的消息 localId
  int lastExportedTimestamp;    // 最后导出的消息时间戳
  int totalExportedCount;       // 已导出的总消息数
  DateTime firstExportTime;     // 首次导出时间
  DateTime lastExportTime;      // 最后导出时间
  List<ExportHistory> history;  // 导出历史记录
}
```

### 2. ExportHistory 模型

```dart
class ExportHistory {
  DateTime exportTime;    // 本次导出时间
  int addedCount;         // 本次新增的消息数
  int totalCount;         // 本次导出后的总消息数
  int lastLocalId;        // 本次导出的最后一条消息的 localId
}
```

---

## 💾 文件存储结构

### 文件命名和位置

```
导出目录/
├── 好友A.json                      # JSON 导出文件
├── 好友A.json.export_state         # 导出状态元数据
├── 好友B.json
├── 好友B.json.export_state
└── 群聊C.json
    └── 群聊C.json.export_state
```

### JSON 文件结构（增量导出）

```json
{
  "session": {
    "wxid": "wxid_xxx",
    "nickname": "好友名称",
    "remark": "备注",
    "displayName": "显示名称",
    "type": "私聊",
    "lastTimestamp": 1673779200
  },
  "messages": [
    {
      "localId": 1,
      "createTime": 1673779200,
      "formattedTime": "2023-01-15 10:00:00",
      "type": "文本消息",
      "localType": 1,
      "content": "你好",
      "isSend": 1,
      "senderUsername": "wxid_xxx",
      "senderDisplayName": "我",
      "source": "com.tencent.mm"
    },
    // ... 更多消息
  ],
  "exportMetadata": {
    "totalMessageCount": 1234,                    # 总消息数
    "firstExportTime": "2025-01-15T10:00:00Z",   # 首次导出时间
    "lastExportTime": "2025-01-15T15:30:00Z",    # 最后导出时间
    "lastExportedLocalId": 1234,                  # 最后导出的消息 ID
    "lastExportedTimestamp": 1673797400,         # 最后导出的消息时间戳
    "isIncremental": true,                        # 是否为增量导出
    "newMessagesCount": 50                        # 本次新增消息数
  }
}
```

### 导出状态文件结构 (.export_state)

```json
{
  "sessionWxid": "wxid_xxx",
  "displayName": "好友A",
  "filePath": "/path/to/好友A.json",
  "format": "json",
  "lastExportedLocalId": 1234,
  "lastExportedTimestamp": 1673797400,
  "totalExportedCount": 1234,
  "firstExportTime": "2025-01-15T10:00:00Z",
  "lastExportTime": "2025-01-15T15:30:00Z",
  "history": [
    {
      "exportTime": "2025-01-15T10:00:00Z",
      "addedCount": 500,
      "totalCount": 500,
      "lastLocalId": 500
    },
    {
      "exportTime": "2025-01-15T15:30:00Z",
      "addedCount": 734,
      "totalCount": 1234,
      "lastLocalId": 1234
    }
  ]
}
```

---

## 🔄 增量导出流程

### 首次导出

```
用户选择会话 → 点击导出
    ↓
检查文件是否存在 → 不存在
    ↓
查询数据库获取所有消息
    ↓
构建 JSON 数据（messages 数组）
    ↓
写入 JSON 文件
    ↓
创建并保存 ExportState
    └─ lastExportedLocalId = 最后一条消息的 localId
    └─ totalExportedCount = 消息总数
    └─ history = [首次导出记录]
```

### 后续增量导出

```
用户选择同一会话 → 点击导出
    ↓
检查文件是否存在 → 存在
    ↓
读取 ExportState 文件 → 获得 lastExportedLocalId
    ↓
查询数据库获取所有消息
    ↓
过滤消息：只保留 localId > lastExportedLocalId 的消息
    ↓
读取现有的 JSON 文件 → 获取 messages 数组
    ↓
合并消息数据：
  newMessages = [现有消息] + [新增消息]
    ↓
更新 JSON 文件
  - messages: 更新为合并后的消息
  - exportMetadata: 更新计数和时间
    ↓
更新 ExportState
  - lastExportedLocalId = 最新消息的 localId
  - totalExportedCount = 新的总数
  - history: 添加本次导出记录
```

---

## 🎯 使用流程（前端）

### 代码示例

```dart
// 在 _ExportProgressDialog 中

final exportService = ChatExportService(databaseService);

// 方式 1：全量导出（覆盖）
bool success = await exportService.exportToJson(
  session,
  messages,
  filePath: filePath,
);

// 方式 2：增量导出（追加新消息）
ExportState? state = await exportService.exportToJsonIncremental(
  session,
  messages,
  filePath: filePath,
  onlyNewMessages: true,  // 只导出新消息
);

if (state != null) {
  print('导出成功！');
  print('总消息数: ${state.totalExportedCount}');
  print('本次新增: ${state.history.last.addedCount}');
  print('导出历史: ${state.history.length} 次');
}
```

---

## 💡 关键特性

### 1. **自动检测增量导出**
- 若文件不存在 → 进行全量导出
- 若文件存在且有状态文件 → 进行增量导出
- 若文件存在但无状态文件 → 覆盖全量导出

### 2. **消息去重**
- 使用 `localId` 作为消息唯一标识
- 只有 `localId > lastExportedLocalId` 的消息才会被添加
- 自动防止重复导出

### 3. **完整的导出历史**
- 记录每次导出的时间、新增消息数、总消息数
- 便于追踪数据变化
- 支持导出分析和统计

### 4. **灵活的文件存储**
- 状态文件与导出文件在同一目录
- 使用 `.export_state` 后缀防止冲突
- 支持文件移动（需手动更新路径）

---

## 🔧 后端实现详情

### ExportStateService 服务

| 方法 | 功能 | 参数 | 返回值 |
|------|------|------|--------|
| `getExportState()` | 读取导出状态 | jsonFilePath | ExportState\|null |
| `saveExportState()` | 保存导出状态 | state | bool |
| `deleteExportState()` | 删除导出状态 | jsonFilePath | bool |
| `listExportStates()` | 列出目录内的所有状态 | directory | List<ExportState> |
| `validateExportState()` | 验证状态文件有效性 | state | bool |

### ChatExportService 的增量导出方法

```dart
Future<ExportState?> exportToJsonIncremental(
  ChatSession session,
  List<Message> messages,
  {
    String? filePath,
    bool onlyNewMessages = true,
  }
)
```

**参数说明**：
- `session`: 聊天会话对象
- `messages`: 从数据库查询的所有消息（全量）
- `filePath`: 导出文件路径（可选，默认为文档目录）
- `onlyNewMessages`: 是否只导出新消息（默认 true）

**返回值**：
- 成功时返回更新后的 `ExportState` 对象
- 失败时返回 `null`

---

## 📈 性能优化

### 1. **内存效率**
- 使用流式处理（JSONL 格式可以进一步优化）
- 消息转换时不保存整个列表在内存中

### 2. **I/O 优化**
- 一次性读写文件（避免多次 I/O）
- 使用 StringBuilder 构建 JSON 字符串

### 3. **数据库查询优化**
- 仅查询需要的消息范围
- 支持日期范围过滤

---

## ⚠️ 注意事项

### 1. **文件移动**
若移动导出文件，需要更新状态文件中的 `filePath` 字段，或重新导出。

### 2. **手动编辑**
不建议手动编辑导出的 JSON 文件或状态文件，这会破坏增量导出的一致性。

### 3. **并发导出**
避免同时对同一会话进行多次导出，可能导致数据不一致。

### 4. **状态文件损坏**
若状态文件损坏，可以手动删除，下次导出时会自动创建新的状态文件。

---

## 🚀 后续改进方向

1. **JSONL 格式支持**：流式导出，内存占用恒定
2. **增量导出UI**：显示上次导出时间和新增消息数
3. **导出统计面板**：展示所有会话的导出状态和历史
4. **导出验证**：检验导出数据的完整性
5. **批量导出管理**：支持导出任务队列和后台处理
