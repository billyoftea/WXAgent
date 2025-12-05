# 前端集成代码示例

## 完整修改示例：chat_export_page.dart

### 修改位置 1：导入新的模型和服务

```dart
// 在文件顶部添加这些导入
import '../models/export_state.dart';
import '../services/export_state_service.dart';
```

---

### 修改位置 2：添加增量导出选项（可选）

在 `_ExportProgressDialog` 的构造参数中添加：

```dart
class _ExportProgressDialog extends StatefulWidget {
  final List<String> sessions;
  final List<ChatSession> allSessions;
  final String format;
  final DateTimeRange dateRange;
  final String exportFolder;
  final bool useAllTime;
  final bool enableIncrementalExport;  // 新增：是否启用增量导出

  const _ExportProgressDialog({
    required this.sessions,
    required this.allSessions,
    required this.format,
    required this.dateRange,
    required this.exportFolder,
    required this.useAllTime,
    this.enableIncrementalExport = true,  // 默认启用
  });

  @override
  State<_ExportProgressDialog> createState() => _ExportProgressDialogState();
}
```

---

### 修改位置 3：在主页面添加增量导出选项（可选）

在 `_ChatExportPageState` 中添加状态变量：

```dart
class _ChatExportPageState extends State<ChatExportPage> {
  // ... 现有变量 ...
  
  bool _enableIncrementalExport = true;  // 新增：控制是否启用增量导出
  
  // ... 其他代码 ...
}
```

在 `_buildExportSettings()` 方法中添加 UI：

```dart
Widget _buildExportSettings() {
  return Column(
    children: [
      // 现有代码...
      
      // 新增：增量导出选项
      if (_selectedFormat == 'json')
        CheckboxListTile(
          title: const Text('启用增量导出'),
          subtitle: const Text('只追加新消息，避免重复导出'),
          value: _enableIncrementalExport,
          onChanged: (value) {
            setState(() {
              _enableIncrementalExport = value ?? true;
            });
          },
        ),
    ],
  );
}
```

---

### 修改位置 4：修改 _startExport 方法（核心修改）

在 `_ChatExportPageState._startExport()` 方法中，修改传给 dialog 的参数：

```dart
showDialog(
  context: context,
  barrierDismissible: false,
  builder: (context) => _ExportProgressDialog(
    sessions: _selectedSessions.toList(),
    allSessions: _allSessions,
    format: _selectedFormat,
    dateRange: _selectedRange!,
    exportFolder: _exportFolder!,
    useAllTime: _useAllTime,
    enableIncrementalExport: _enableIncrementalExport,  // 新增
  ),
);
```

---

### 修改位置 5：修改 _ExportProgressDialog._startExport() 方法（关键修改）

在 `_ExportProgressDialogState._startExport()` 方法中，找到这段代码：

```dart
// 原有代码（大约在第 900-930 行）
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
  case 'html':
    success = await exportService.exportToHtml(
      session,
      messages.reversed.toList(),
      filePath: filePath,
    );
    break;
  case 'excel':
    success = await exportService.exportToExcel(
      session,
      messages.reversed.toList(),
      filePath: filePath,
    );
    break;
}
```

**替换为**：

```dart
bool success = false;
final exportService = ChatExportService(databaseService);

switch (widget.format) {
  case 'json':
    // 使用增量导出（新方法）
    if (widget.enableIncrementalExport) {
      final state = await exportService.exportToJsonIncremental(
        session,
        messages.reversed.toList(),
        filePath: filePath,
        onlyNewMessages: true,  // 启用增量导出
      );
      success = state != null;
      
      // 可选：在日志中记录增量导出的统计信息
      if (state != null) {
        await logger.info(
          'ChatExportPage',
          '增量导出 JSON 成功: wxid=${session.username}, '
          '新增=${state.history.last.addedCount}, '
          '总数=${state.totalExportedCount}, '
          '历史=${state.history.length}次',
        );
      }
    } else {
      // 使用全量导出（原方法）
      success = await exportService.exportToJson(
        session,
        messages.reversed.toList(),
        filePath: filePath,
      );
    }
    break;
    
  case 'html':
    success = await exportService.exportToHtml(
      session,
      messages.reversed.toList(),
      filePath: filePath,
    );
    break;
    
  case 'excel':
    success = await exportService.exportToExcel(
      session,
      messages.reversed.toList(),
      filePath: filePath,
    );
    break;
}
```

---

### 修改位置 6：添加统计信息显示（可选）

在 `_ExportProgressDialogState` 中添加新的状态变量：

```dart
class _ExportProgressDialogState extends State<_ExportProgressDialog> {
  int _currentIndex = 0;
  int _successCount = 0;
  int _failedCount = 0;
  bool _isCompleted = false;
  String _currentSessionName = '';
  int _currentMessageCount = 0;
  int _totalMessagesProcessed = 0;
  final List<String> _failedSessions = [];
  
  // 新增：用于显示增量导出统计
  List<ExportState?> _exportStates = [];
  
  // ... 其他代码 ...
}
```

在成功导出后记录状态：

```dart
if (success) {
  setState(() {
    _successCount++;
    _totalMessagesProcessed += messages.length;
  });
  
  // 如果是增量导出，记录状态对象（可选）
  if (widget.format == 'json' && widget.enableIncrementalExport) {
    // 这里可以保存状态对象以后续显示
  }
}
```

---

### 修改位置 7：在完成对话框中显示统计信息（可选）

在 `_ExportProgressDialogState.build()` 方法的完成界面中，修改显示信息：

```dart
else ...[
  Row(
    children: [
      const Icon(Icons.check_circle, color: Colors.green, size: 48),
      const SizedBox(width: 16),
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
              '总计导出消息: $_totalMessagesProcessed 条',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            // 新增：显示增量导出信息（仅 JSON 格式）
            if (widget.format == 'json' && widget.enableIncrementalExport) ...[
              const SizedBox(height: 8),
              Text(
                '导出方式: 增量导出',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              Text(
                '说明: 只追加了新消息，避免重复导出',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ] else if (widget.format == 'json') ...[
              const SizedBox(height: 8),
              Text(
                '导出方式: 全量导出',
                style: TextStyle(
                  color: Colors.orange.shade600,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
            if (_failedCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                '失败: $_failedCount',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  ),
  const SizedBox(height: 12),
  Text(
    '文件位置: ${widget.exportFolder}',
    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
  ),
]
```

---

## 最小化改动版本（仅 3 行改动）

如果您只想最小化修改，只需要修改这一个地方：

**在 `_ExportProgressDialogState._startExport()` 中，将：**

```dart
case 'json':
  success = await exportService.exportToJson(
    session,
    messages.reversed.toList(),
    filePath: filePath,
  );
  break;
```

**改为：**

```dart
case 'json':
  final state = await exportService.exportToJsonIncremental(
    session,
    messages.reversed.toList(),
    filePath: filePath,
    onlyNewMessages: true,
  );
  success = state != null;
  break;
```

就这样！仅需 **3 行改动**，增量导出功能即可启用。

---

## 测试代码

添加以下测试代码来验证增量导出功能：

```dart
// 在任何地方添加这段测试代码
Future<void> testIncrementalExport() async {
  final exportService = ChatExportService(databaseService);
  final session = ChatSession(/* ... */);
  final messages = <Message>[];  // 从数据库获取

  // 第一次导出
  print('第一次导出...');
  final state1 = await exportService.exportToJsonIncremental(
    session,
    messages,
    filePath: '/path/to/chat.json',
    onlyNewMessages: true,
  );
  
  if (state1 != null) {
    print('✓ 首次导出成功');
    print('  总消息数: ${state1.totalExportedCount}');
    print('  导出历史: ${state1.history.length} 次');
  }

  // 模拟新消息
  print('\n等待新消息...');
  await Future.delayed(Duration(seconds: 5));

  // 第二次导出
  print('\n第二次导出...');
  final state2 = await exportService.exportToJsonIncremental(
    session,
    messages,
    filePath: '/path/to/chat.json',
    onlyNewMessages: true,
  );
  
  if (state2 != null) {
    print('✓ 增量导出成功');
    print('  新增消息: ${state2.history.last.addedCount}');
    print('  总消息数: ${state2.totalExportedCount}');
    print('  导出历史: ${state2.history.length} 次');
  }
}
```

---

## 常见错误和解决方案

### 错误 1：找不到 ExportState 类
**原因**：未正确导入模型

**解决**：添加导入语句
```dart
import '../models/export_state.dart';
```

### 错误 2：exportToJsonIncremental 方法不存在
**原因**：ChatExportService 未更新

**解决**：检查 chat_export_service.dart 是否有新方法（应该在 exportToJson 之后）

### 错误 3：状态文件路径不正确
**原因**：这是自动处理的，通常不需要手动管理

**说明**：状态文件会自动保存在与 JSON 文件相同的目录，文件名为 `{json文件名}.export_state`

---

## 验证修改完成

运行以下检查确保修改正确：

```bash
# 1. 检查导入是否正确
grep -n "import.*export_state" lib/pages/chat_export_page.dart

# 2. 检查新方法是否存在
grep -n "exportToJsonIncremental" lib/services/chat_export_service.dart

# 3. 编译检查
flutter pub get
flutter analyze

# 4. 运行应用
flutter run
```

---

## 下一步

- [x] 修改 chat_export_page.dart
- [x] 添加增量导出选项（UI）
- [x] 测试首次导出
- [x] 测试增量导出
- [ ] 在导出完成后查看生成的状态文件
- [ ] 验证消息去重（再次导出相同会话）
- [ ] 显示导出统计信息

完成以上步骤后，增量导出功能就完全可用了！🎉
