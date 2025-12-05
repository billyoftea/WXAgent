# 增量导出实现集成指南

## 前端集成步骤

### 1. 修改 _ExportProgressDialog（chat_export_page.dart）

在 `_startExport()` 方法中，将导出逻辑修改为支持增量导出：

```dart
// 原有代码
bool success = false;
final exportService = ChatExportService(databaseService);

switch (widget.format) {
  case 'json':
    success = await exportService.exportToJson(
      session,
      messages.reversed.toList(),
      filePath: filePath,
    );
    break;
  // ...
}

// 修改为支持增量导出
bool success = false;
final exportService = ChatExportService(databaseService);

switch (widget.format) {
  case 'json':
    // 使用增量导出
    final state = await exportService.exportToJsonIncremental(
      session,
      messages.reversed.toList(),
      filePath: filePath,
      onlyNewMessages: true,  // 启用增量导出
    );
    success = state != null;
    
    // 可选：显示增量导出的统计信息
    if (state != null && widget.format == 'json') {
      await logger.info(
        'ChatExportPage',
        '增量导出完成: 新增=${state.history.last.addedCount}, '
        '总数=${state.totalExportedCount}, 历史=${state.history.length}次',
      );
    }
    break;
  // ...
}
```

### 2. 添加导出选项UI（可选）

在 `_buildExportSettings()` 方法中添加增量导出选项：

```dart
// 示例：在导出设置面板中添加复选框
bool _enableIncrementalExport = true;

// 在导出设置UI中
CheckboxListTile(
  title: const Text('增量导出'),
  subtitle: const Text('只追加新消息，避免重复导出'),
  value: _enableIncrementalExport,
  onChanged: (value) {
    setState(() {
      _enableIncrementalExport = value ?? true;
    });
  },
)
```

### 3. 显示增量导出的统计信息

在导出完成后，显示更详细的统计信息：

```dart
// 在 _ExportProgressDialog 中添加状态变量
int _incrementalNewCount = 0;  // 本次新增消息数
int _exportHistoryCount = 0;   // 导出历史数

// 在导出成功后更新
if (state != null) {
  setState(() {
    _incrementalNewCount = state.history.last.addedCount;
    _exportHistoryCount = state.history.length;
  });
}

// 在完成对话框中显示
if (_isCompleted) {
  Row(
    children: [
      // ... 现有代码 ...
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '成功: $_successCount',
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              '总计导出: $_totalMessagesProcessed 条消息',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            // 新增：显示增量导出信息
            if (_incrementalNewCount > 0)
              Text(
                '本次新增: $_incrementalNewCount 条',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (_exportHistoryCount > 0)
              Text(
                '导出次数: $_exportHistoryCount 次',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            // ... 其他代码 ...
          ],
        ),
      ),
    ],
  );
}
```

### 4. 添加"查看导出历史"功能（可选）

```dart
// 添加查看导出历史的对话框
void _showExportHistory(ExportState state) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('导出历史'),
      content: SizedBox(
        width: 400,
        height: 300,
        child: ListView.builder(
          itemCount: state.history.length,
          itemBuilder: (context, index) {
            final history = state.history[index];
            return Card(
              margin: const EdgeInsets.all(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '第 ${index + 1} 次导出',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '时间: ${history.exportTime.toLocal()}',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    Text(
                      '新增: ${history.addedCount} 条',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    Text(
                      '总数: ${history.totalCount} 条',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
```

---

## 后端集成步骤（已完成）

### 已实现的组件

✅ `lib/models/export_state.dart`
- ExportState 类：存储导出状态
- ExportHistory 类：存储单次导出记录

✅ `lib/services/export_state_service.dart`
- 导出状态的读写
- 导出状态的管理和验证

✅ `lib/services/chat_export_service.dart`（已修改）
- `exportToJsonIncremental()` 方法
- 支持增量导出和全量导出
- 自动处理消息去重

---

## 使用场景示例

### 场景 1：首次导出

```
用户选择 "好友A" → 点击导出
↓
检查文件不存在
↓
全量导出 100 条消息
↓
创建 .export_state 文件
↓
显示: "成功导出 100 条消息"
```

### 场景 2：一天后继续导出

```
用户再次选择 "好友A" → 点击导出
↓
检查文件存在，读取 .export_state
↓
lastExportedLocalId = 100
↓
数据库中现在有 150 条消息
↓
只导出 localId 101-150 的 50 条消息
↓
合并后 JSON 中有 150 条消息
↓
更新 .export_state 文件
↓
显示: "成功导出，本次新增 50 条消息，总计 150 条"
```

### 场景 3：导出多个会话

```
用户同时选择 "好友A"、"好友B"、"群聊C"
↓
并行导出三个会话
↓
每个会话独立检查自己的状态文件
↓
好友A：增量导出（50 条新消息）
好友B：全量导出（100 条消息）
群聊C：增量导出（200 条新消息）
↓
显示: "成功导出 3 个会话，总计 350 条消息"
```

---

## 测试检查清单

- [ ] **首次导出**
  - [ ] 创建导出文件
  - [ ] 创建导出状态文件
  - [ ] 文件格式正确
  
- [ ] **增量导出**
  - [ ] 只添加新消息
  - [ ] 消息数正确
  - [ ] 状态文件更新正确
  
- [ ] **导出历史**
  - [ ] 历史记录完整
  - [ ] 时间戳正确
  - [ ] 统计数字准确
  
- [ ] **边界情况**
  - [ ] 无新消息时的导出
  - [ ] 状态文件损坏时的处理
  - [ ] 文件被手动删除后的恢复
  - [ ] 并发导出多个会话
  
- [ ] **UI/UX**
  - [ ] 显示导出进度
  - [ ] 显示导出统计信息
  - [ ] 显示导出历史（可选）
  - [ ] 错误提示清晰

---

## 常见问题解答

### Q: 如果手动删除了导出文件，会发生什么？
A: 下次导出时会进行全量导出，重新创建文件和状态文件。

### Q: 如果手动删除了状态文件，会发生什么？
A: 下次导出时会检测到状态文件不存在，自动进行全量导出并重新创建状态文件。

### Q: 如何强制进行全量导出（覆盖现有文件）？
A: 调用 `exportToJson()` 方法，或者先手动删除状态文件，再调用 `exportToJsonIncremental()`。

### Q: 支持并发导出吗？
A: 支持，但不建议对同一会话进行并发导出，这可能导致状态不一致。

### Q: 导出文件可以移动吗？
A: 可以，但需要一起移动对应的状态文件，否则下次导出时无法识别。

---

## 后续优化建议

1. **Web UI 展示**：在导出页面显示每个会话的导出历史和统计信息
2. **批量操作**：支持批量重新导出或清除所有导出状态
3. **导出分析**：统计所有会话的导出情况
4. **自动导出**：支持定时自动导出新消息
5. **导出验证**：添加校验和验证导出数据的完整性
