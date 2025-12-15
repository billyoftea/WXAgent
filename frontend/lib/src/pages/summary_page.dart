import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../models/models.dart';
import '../services/wx_agent_api.dart';
import '../widgets/page_container.dart';
import '../widgets/section_card.dart';

class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  final TextEditingController _promptCtrl = TextEditingController();
  final ScrollController _streamScrollCtrl = ScrollController(); // 流式输出滚动控制器
  bool _useCustomPrompt = false;
  String? _startDate;
  String? _endDate;
  final Set<String> _selectedSessions = {};
  List<SessionMeta> _sessions = const [];
  bool _loadingSessions = false;
  bool _running = false;
  String? _resultContent;
  String? _summaryPath;
  String? _error;

  // 后端返回的统计信息
  int? _totalMessages;
  int? _totalSessions;
  int? _chunkCount;
  String? _summaryMode;
  List<String>? _processLogs; // 处理过程日志

  // 流式输出状态
  String _streamLog = ''; // 流式日志
  String _streamAiOutput = ''; // AI 流式输出
  int _currentStep = 0; // 当前步骤
  int _totalSteps = 6; // 总步骤数
  bool _userScrolling = false; // 用户是否正在手动滚动

  List<SummaryHistoryEntry> _history = const [];
  SummaryHistoryEntry? _selectedHistory;
  bool _historyLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadHistory();
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _streamScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    final text = DateFormat('yyyy-MM-dd').format(picked);
    setState(() {
      if (isStart) {
        _startDate = text;
      } else {
        _endDate = text;
      }
    });
  }

  void _clearDate(bool isStart) {
    setState(() {
      if (isStart) {
        _startDate = null;
      } else {
        _endDate = null;
      }
    });
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loadingSessions = true;
    });
    try {
      final sessions = await widget.controller.api.listSessions();
      setState(() {
        _sessions = sessions;
      });
    } finally {
      setState(() {
        _loadingSessions = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
    });
    try {
      final entries = await widget.controller.api.listSummaryHistory();
      setState(() {
        _history = entries;
      });
    } finally {
      setState(() {
        _historyLoading = false;
      });
    }
  }

  Future<void> _runSummary() async {
    setState(() {
      _running = true;
      _error = null;
      // 清空旧的统计信息和流式输出
      _totalMessages = null;
      _totalSessions = null;
      _chunkCount = null;
      _summaryMode = null;
      _processLogs = null;
      _streamLog = '';
      _streamAiOutput = '';
      _currentStep = 0;
      _resultContent = null;
      _userScrolling = false; // 重置滚动状态
    });

    try {
      // 使用流式 API
      String finalContent = '';
      String? outputPath;

      await for (final event in widget.controller.api.runSummaryStream(
        startDate: _startDate,
        endDate: _endDate,
        sessions: _selectedSessions.isEmpty ? null : _selectedSessions.toList(),
      )) {
        if (!mounted) return;

        switch (event.type) {
          case 'log':
            setState(() {
              _streamLog += '${event.content}\n';
              _currentStep = event.step ?? _currentStep;
              _totalSteps = event.total ?? _totalSteps;
            });
            // 自动滚动到底部
            _scrollToBottom();
            break;
          case 'ai_chunk':
            setState(() {
              _streamAiOutput += event.content;
              _currentStep = event.step ?? _currentStep;
            });
            _scrollToBottom();
            break;
          case 'progress':
            setState(() {
              _currentStep = event.step ?? _currentStep;
            });
            break;
          case 'done':
            // 分析完成
            break;
          case 'error':
            setState(() {
              _error = event.content;
            });
            break;
          case 'result':
            // 解析最终结果（result 事件的 content 是 JSON 数据）
            // 但我们在 SSE 中已经逐步发送了 content，这里用于获取统计信息
            // event.content 可能包含完整结果的 JSON
            // 由于 SSE result 事件格式，我们需要在服务端已包含这些信息
            setState(() {
              // 最终内容通过 ai_chunk 已累积，这里设置结果
              finalContent = _streamAiOutput;
            });
            break;
        }
      }

      // 设置最终结果
      setState(() {
        _resultContent = finalContent.isNotEmpty ? finalContent : _streamAiOutput;
        _summaryMode = 'merged';
      });

      await _loadHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('AI 总结完成')));
    } catch (err) {
      setState(() {
        _error = err.toString();
      });
    } finally {
      setState(() {
        _running = false;
      });
    }
  }

  void _scrollToBottom() {
    // 如果用户正在手动滚动，不自动滚动
    if (_userScrolling) return;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_streamScrollCtrl.hasClients) {
        _streamScrollCtrl.animateTo(
          _streamScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 检查是否接近底部（用于判断是否恢复自动滚动）
  bool _isNearBottom() {
    if (!_streamScrollCtrl.hasClients) return true;
    final position = _streamScrollCtrl.position;
    // 距离底部 50 像素以内认为是在底部
    return position.maxScrollExtent - position.pixels < 50;
  }

  Future<void> _selectSessions() async {
    if (_loadingSessions) return;
    final temp = Set<String>.from(_selectedSessions);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          builder: (_, controller) {
            return StatefulBuilder(
              builder: (context, setModalState) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '选择会话',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          controller: controller,
                          itemCount: _sessions.length,
                          itemBuilder: (context, index) {
                            final session = _sessions[index];
                            final selected = temp.contains(session.sessionId);
                            return CheckboxListTile(
                              value: selected,
                              title: Text(session.displayName),
                              subtitle: Text(
                                session.category ?? session.sessionType ?? '--',
                              ),
                              onChanged: (value) {
                                setModalState(() {
                                  if (value == true) {
                                    temp.add(session.sessionId);
                                  } else {
                                    temp.remove(session.sessionId);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              setModalState(() => temp.clear());
                            },
                            child: const Text('清空选择'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _selectedSessions
                                  ..clear()
                                  ..addAll(temp);
                              });
                              Navigator.pop(context);
                            },
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _loadHistoryContent(SummaryHistoryEntry entry) async {
    setState(() {
      _historyLoading = true;
    });
    try {
      final content = await widget.controller.api.readSummaryHistory(
        entry.path,
      );
      setState(() {
        _resultContent = content;
        _summaryPath = entry.path;
        _selectedHistory = entry;
      });
    } finally {
      setState(() {
        _historyLoading = false;
      });
    }
  }

  Future<void> _copyResult() async {
    final text = _resultContent;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制总结内容')));
  }

  Future<void> _openSummaryFile() async {
    if (_summaryPath == null) return;
    await launchUrl(Uri.file(_summaryPath!));
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade300),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          color: Colors.blue.shade700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageContainer(
      title: '聊天记录 AI 总结',
      subtitle: '选择会话与时间范围，使用默认或自定义 Prompt 调用大模型生成 Markdown 总结，并支持历史记录管理。',
      children: [
        SectionCard(
          title: '过滤条件与提示词',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: '开始日期',
                      value: _startDate,
                      onPick: () => _pickDate(isStart: true),
                      onClear: () => _clearDate(true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _DateField(
                      label: '结束日期',
                      value: _endDate,
                      onPick: () => _pickDate(isStart: false),
                      onClear: () => _clearDate(false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: _loadingSessions ? null : _selectSessions,
                    icon: _loadingSessions
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(Icons.checklist),
                    label: Text(
                      _selectedSessions.isEmpty
                          ? '选择会话（可多选）'
                          : '已选 ${_selectedSessions.length} 个会话',
                    ),
                  ),
                  if (_selectedSessions.isNotEmpty)
                    TextButton(
                      onPressed: () =>
                          setState(() => _selectedSessions.clear()),
                      child: const Text('清空会话'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '提示：未选择任何会话时，将默认使用全部会话生成总结。',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<bool>(
                    value: false,
                    groupValue: _useCustomPrompt,
                    onChanged: (value) =>
                        setState(() => _useCustomPrompt = value ?? false),
                    title: const Text('使用默认总结提示词'),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    groupValue: _useCustomPrompt,
                    onChanged: (value) =>
                        setState(() => _useCustomPrompt = value ?? false),
                    title: const Text('使用自定义提示词'),
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: TextField(
                      controller: _promptCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: '输入自定义提示词，例如“围绕 AI 相关的对话生成总结”。',
                      ),
                    ),
                    crossFadeState: _useCustomPrompt
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 300),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _running ? null : _runSummary,
                icon: _running
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.auto_awesome),
                label: const Text('开始总结'),
              ),
            ],
          ),
        ),
        SectionCard(
          title: '当前总结 / 历史记录',
          actions: [
            IconButton(
              tooltip: '刷新历史记录',
              onPressed: _historyLoading ? null : _loadHistory,
              icon: _historyLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '复制结果',
              onPressed: _resultContent == null ? null : _copyResult,
              icon: const Icon(Icons.copy_all),
            ),
            IconButton(
              tooltip: '打开总结文件',
              onPressed: _summaryPath == null ? null : _openSummaryFile,
              icon: const Icon(Icons.folder_open),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<SummaryHistoryEntry>(
                value: _selectedHistory,
                decoration: const InputDecoration(labelText: '查看历史总结'),
                items: _history
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry,
                        child: Text(entry.name),
                      ),
                    )
                    .toList(),
                onChanged: (entry) {
                  if (entry != null) {
                    _loadHistoryContent(entry);
                  }
                },
              ),
              // 显示后端返回的统计信息
              if (_totalMessages != null || _totalSessions != null || _chunkCount != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.analytics, size: 20, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        '分析统计: ',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      if (_totalMessages != null) ...[
                        const SizedBox(width: 8),
                        _buildStatChip('消息', '$_totalMessages 条'),
                      ],
                      if (_totalSessions != null) ...[
                        const SizedBox(width: 8),
                        _buildStatChip('会话', '$_totalSessions 个'),
                      ],
                      if (_chunkCount != null && _chunkCount! > 0) ...[
                        const SizedBox(width: 8),
                        _buildStatChip('分段', '$_chunkCount 段'),
                      ],
                      if (_summaryMode != null) ...[
                        const SizedBox(width: 8),
                        _buildStatChip('模式', _summaryMode == 'merged' ? '合并分析' : '逐会话'),
                      ],
                    ],
                  ),
                ),
              ],
              // 显示处理过程日志
              if (_processLogs != null && _processLogs!.isNotEmpty) ...[
                const SizedBox(height: 12),
                ExpansionTile(
                  title: Row(
                    children: [
                      Icon(Icons.terminal, size: 20, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Text(
                        '处理日志 (${_processLogs!.length} 条)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  backgroundColor: Colors.green.shade50,
                  collapsedBackgroundColor: Colors.green.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.green.shade200),
                  ),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.green.shade200),
                  ),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _processLogs!.join('\n'),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // 流式输出显示区域（运行中或有流式输出时显示）
              if (_running || _streamLog.isNotEmpty || _streamAiOutput.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade700),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题栏
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade800,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(7),
                            topRight: Radius.circular(7),
                          ),
                        ),
                        child: Row(
                          children: [
                            if (_running) ...[
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ] else ...[
                              const Icon(Icons.check_circle, size: 14, color: Colors.green),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              _running 
                                  ? '处理中... (步骤 $_currentStep/$_totalSteps)'
                                  : '处理完成',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            const Spacer(),
                            if (!_running && (_streamLog.isNotEmpty || _streamAiOutput.isNotEmpty))
                              IconButton(
                                icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: '清除输出',
                                onPressed: () {
                                  setState(() {
                                    _streamLog = '';
                                    _streamAiOutput = '';
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                      // 内容区域
                      Stack(
                        children: [
                          Container(
                            height: 200,
                            padding: const EdgeInsets.all(12),
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is ScrollStartNotification) {
                                  // 用户开始滚动
                                  if (notification.dragDetails != null) {
                                    setState(() {
                                      _userScrolling = true;
                                    });
                                  }
                                } else if (notification is ScrollEndNotification) {
                                  // 滚动结束，检查是否在底部附近
                                  if (_isNearBottom()) {
                                setState(() {
                                  _userScrolling = false;
                                });
                              }
                            }
                            return false;
                          },
                          child: SingleChildScrollView(
                            controller: _streamScrollCtrl,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 日志输出
                                if (_streamLog.isNotEmpty)
                                  SelectableText(
                                    _streamLog,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                // AI 输出
                                if (_streamAiOutput.isNotEmpty) ...[
                                  if (_streamLog.isNotEmpty) const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade800,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: SelectableText(
                                      _streamAiOutput,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: Colors.greenAccent,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                          ),
                          // 回到底部按钮（用户向上滚动时显示）
                          if (_userScrolling && _running)
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Material(
                                color: Colors.blue.shade600,
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    setState(() {
                                      _userScrolling = false;
                                    });
                                    _scrollToBottom();
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.arrow_downward, size: 14, color: Colors.white),
                                        SizedBox(width: 4),
                                        Text(
                                          '回到底部',
                                          style: TextStyle(color: Colors.white, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                padding: const EdgeInsets.all(16),
                child: _historyLoading && _resultContent == null
                    ? const Center(child: CircularProgressIndicator())
                    : SizedBox(
                        height: 320,
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _resultContent ?? '暂无总结，请先生成或选择历史文件。',
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                      ),
              ),
              if (_summaryPath != null) ...[
                const SizedBox(height: 8),
                Text(
                  '输出文件：$_summaryPath',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final String? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: onPick,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: value == null ? null : onClear,
              ),
            ],
          ),
        ),
        child: Text(value ?? '未选择'),
      ),
    );
  }
}
