import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../models/models.dart';
import '../widgets/page_container.dart';
import '../widgets/section_card.dart';

class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  static const String _defaultChunkPrompt = '''
请分别总结以下微信群聊天记录的主要内容和讨论话题。
注意：以下文本包含来自不同群聊的消息，每个群聊用【群聊：群名】的格式标记，请按群聊分别总结。

{{content}}

要求：
1. 用中文总结
2. 分聊天对象进行总结，同一个群聊或者同一个聊天记录放在一起总结。
3. 总结出主要话题和讨论内容（用编号列出，并附上时间和讨论人（如果必要））
4. 提取出重要信息（如招聘信息、活动信息等），并注意引用原文！
5. 概括参与者的主要观点或反应
6. 标出最活跃的话题和讨论热度''';

  static const String _defaultFinalPrompt = '''
{{intro}}

{{summaries}}

要求：
1. 按群聊/话题重新组织内容，去掉重复叙述，但要保留所有关键细节、时间、人物与数量。
2. 识别跨批次连续的讨论并合并，补全上下文。
3. 输出 Markdown，包含：概览、按群聊的详细总结、关键行动项/待办/风险。''';

  final TextEditingController _chunkPromptCtrl = TextEditingController();
  final TextEditingController _finalPromptCtrl = TextEditingController();
  final ScrollController _streamScrollCtrl = ScrollController();

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

  int? _totalMessages;
  int? _totalSessions;
  int? _chunkCount;
  String? _summaryMode;

  String _streamLog = '';
  String _streamAiOutput = '';
  int _currentStep = 0;
  int _totalSteps = 6;
  bool _userScrolling = false;

  List<SummaryHistoryEntry> _history = const [];
  SummaryHistoryEntry? _selectedHistory;
  bool _historyLoading = false;

  @override
  void initState() {
    super.initState();
    _chunkPromptCtrl.text = _defaultChunkPrompt;
    _finalPromptCtrl.text = _defaultFinalPrompt;
    _loadSessions();
    _loadHistory();
  }

  @override
  void dispose() {
    _chunkPromptCtrl.dispose();
    _finalPromptCtrl.dispose();
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
    setState(() => _loadingSessions = true);
    try {
      final sessions = await widget.controller.api.listSessions();
      setState(() => _sessions = sessions);
    } finally {
      if (mounted) {
        setState(() => _loadingSessions = false);
      }
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _historyLoading = true);
    try {
      final entries = await widget.controller.api.listSummaryHistory();
      // 去重后按修改时间倒序
      final dedup = <String, SummaryHistoryEntry>{};
      for (final item in entries) {
        dedup[item.path] = item;
      }
      final list = dedup.values.toList();
      list.sort((a, b) {
        final left = b.modified ?? '';
        final right = a.modified ?? '';
        return left.compareTo(right);
      });
      setState(() {
        _history = list;
        if (_selectedHistory == null && list.isNotEmpty) {
          _selectedHistory = list.first;
        } else if (_selectedHistory != null &&
            !_history.any((item) => item.path == _selectedHistory!.path)) {
          _selectedHistory = list.isNotEmpty ? list.first : null;
        }
      });
      if (_selectedHistory != null) {
        await _loadHistoryContent(_selectedHistory!);
      }
    } finally {
      if (mounted) {
        setState(() => _historyLoading = false);
      }
    }
  }

  Future<void> _loadHistoryContent(SummaryHistoryEntry entry) async {
    setState(() => _historyLoading = true);
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
      if (mounted) {
        setState(() => _historyLoading = false);
      }
    }
  }

  Future<void> _runSummary() async {
    if (_useCustomPrompt) {
      final chunk = _chunkPromptCtrl.text;
      final finalPrompt = _finalPromptCtrl.text;
      if (!chunk.contains('{{content}}')) {
        setState(() {
          _error = '分段提示词必须包含 {{content}} 占位符（用于放入分段内容）。';
        });
        return;
      }
      if (!finalPrompt.contains('{{intro}}') ||
          !finalPrompt.contains('{{summaries}}')) {
        setState(() {
          _error = '最终提示词必须同时包含 {{intro}} 与 {{summaries}} 占位符。';
        });
        return;
      }
    }
    setState(() {
      _running = true;
      _error = null;
      _totalMessages = null;
      _totalSessions = null;
      _chunkCount = null;
      _summaryMode = null;
      _streamLog = '';
      _streamAiOutput = '';
      _currentStep = 0;
      _totalSteps = 6;
      _resultContent = null;
      _summaryPath = null;
      _userScrolling = false;
    });

    try {
      String finalContent = '';
      await for (final event in widget.controller.api.runSummaryStream(
        startDate: _startDate,
        endDate: _endDate,
        sessions: _selectedSessions.isEmpty ? null : _selectedSessions.toList(),
        chunkPrompt: _useCustomPrompt ? _chunkPromptCtrl.text : null,
        finalPrompt: _useCustomPrompt ? _finalPromptCtrl.text : null,
      )) {
        if (!mounted) return;
        switch (event.type) {
          case 'log':
            setState(() {
              if (event.content.isNotEmpty) {
                _streamLog += '${event.content}\n';
              }
              _currentStep = event.step ?? _currentStep;
              _totalSteps = event.total ?? _totalSteps;
            });
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
              _totalSteps = event.total ?? _totalSteps;
            });
            break;
          case 'error':
            setState(() {
              _error = event.content.isNotEmpty
                  ? event.content
                  : event.payload?['message']?.toString();
            });
            return;
          case 'result':
            setState(() {
              finalContent = event.content.isNotEmpty
                  ? event.content
                  : _streamAiOutput;
              final payload = event.payload ?? const {};
              _summaryPath = payload['output_path'] as String? ?? _summaryPath;
              _totalMessages = _asInt(payload['total_messages']);
              _totalSessions = _asInt(payload['total_sessions']);
              _chunkCount = _asInt(payload['chunk_count']);
              _summaryMode = payload['mode'] as String? ?? _summaryMode;
            });
            break;
          default:
            break;
        }
      }

      setState(() {
        _resultContent = finalContent.isNotEmpty
            ? finalContent
            : _streamAiOutput;
        _summaryMode = _summaryMode ?? 'merged';
      });

      await _loadHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('总结完成')));
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _scrollToBottom() {
    if (_userScrolling) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_streamScrollCtrl.hasClients) {
        _streamScrollCtrl.animateTo(
          _streamScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isNearBottom() {
    if (!_streamScrollCtrl.hasClients) return true;
    final position = _streamScrollCtrl.position;
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
                        'Select conversations',
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
                            onPressed: () => setModalState(temp.clear),
                            child: const Text('Clear'),
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
                            child: const Text('Apply'),
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

  Future<void> _copyResult() async {
    final text = _resultContent;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
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
        style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SummaryHistoryEntry? validSelectedHistory;
    if (_selectedHistory != null) {
      for (final item in _history) {
        if (item.path == _selectedHistory!.path) {
          validSelectedHistory = item;
          break;
        }
      }
    }

    return PageContainer(
      title: '聊天记录 AI 总结',
      subtitle: '对导出的聊天记录生成 Markdown 报告，可使用默认提示词或自定义分段/最终提示词。',
      children: [
        SectionCard(
          title: '筛选与提示词',
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
                          ? '选择需要总结的会话'
                          : '已选择 ${_selectedSessions.length} 个',
                    ),
                  ),
                  if (_selectedSessions.isNotEmpty)
                    TextButton(
                      onPressed: () =>
                          setState(() => _selectedSessions.clear()),
                      child: const Text('清空选择'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '不选择会话时将汇总全部可用聊天记录。',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text('提示词', style: TextStyle(fontWeight: FontWeight.w600)),
              RadioListTile<bool>(
                value: false,
                groupValue: _useCustomPrompt,
                onChanged: (value) =>
                    setState(() => _useCustomPrompt = value ?? false),
                title: const Text('使用默认提示词'),
              ),
              RadioListTile<bool>(
                value: true,
                groupValue: _useCustomPrompt,
                onChanged: (value) =>
                    setState(() => _useCustomPrompt = value ?? false),
                title: const Text('自定义提示词'),
              ),
              AnimatedCrossFade(
                firstChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _PromptPreview(
                      title: '默认分段提示词',
                      content: _defaultChunkPrompt,
                    ),
                    SizedBox(height: 8),
                    _PromptPreview(
                      title: '默认最终提示词',
                      content: _defaultFinalPrompt,
                    ),
                  ],
                ),
                secondChild: Column(
                  children: [
                    TextField(
                      controller: _chunkPromptCtrl,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: '分段提示词',
                        hintText:
                            '占位符：{{chunk_num}}、{{chunk_total}}、{{content}}',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _finalPromptCtrl,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: '最终提示词',
                        hintText:
                            '占位符：{{intro}}、{{summaries}}、{{summary_count}}',
                      ),
                    ),
                  ],
                ),
                crossFadeState: _useCustomPrompt
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
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
          title: '进度与历史',
          actions: [
            IconButton(
              tooltip: '刷新历史列表',
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
              tooltip: '打开文件',
              onPressed: _summaryPath == null ? null : _openSummaryFile,
              icon: const Icon(Icons.folder_open),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<SummaryHistoryEntry>(
                value: validSelectedHistory,
                decoration: const InputDecoration(labelText: '历史总结'),
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
              if (_totalMessages != null ||
                  _totalSessions != null ||
                  _chunkCount != null ||
                  _summaryMode != null) ...[
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
                        '统计',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      if (_totalMessages != null) ...[
                        const SizedBox(width: 8),
                        _buildStatChip('消息数', '$_totalMessages'),
                      ],
                      if (_totalSessions != null) ...[
                        const SizedBox(width: 8),
                        _buildStatChip('会话数', '$_totalSessions'),
                      ],
                      if (_chunkCount != null && _chunkCount! > 0) ...[
                        const SizedBox(width: 8),
                        _buildStatChip('分段', '$_chunkCount'),
                      ],
                      if (_summaryMode != null) ...[
                        const SizedBox(width: 8),
                        _buildStatChip(
                          '模式',
                          _summaryMode == 'merged' ? '跨会话合并' : '逐会话',
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (_running ||
                  _streamLog.isNotEmpty ||
                  _streamAiOutput.isNotEmpty) ...[
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
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
                              const Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              _running
                                  ? '处理中... ($_currentStep/$_totalSteps)'
                                  : '已完成',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            const Spacer(),
                            if (!_running &&
                                (_streamLog.isNotEmpty ||
                                    _streamAiOutput.isNotEmpty))
                              IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: '清除日志',
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
                      Stack(
                        children: [
                          Container(
                            height: 200,
                            padding: const EdgeInsets.all(12),
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is UserScrollNotification &&
                                    notification.direction !=
                                        ScrollDirection.idle) {
                                  setState(() => _userScrolling = true);
                                } else if (notification
                                    is ScrollEndNotification) {
                                  if (_isNearBottom()) {
                                    setState(() => _userScrolling = false);
                                  }
                                }
                                return false;
                              },
                              child: SingleChildScrollView(
                                controller: _streamScrollCtrl,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_streamLog.isNotEmpty)
                                      SelectableText(
                                        _streamLog,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                    if (_streamAiOutput.isNotEmpty) ...[
                                      if (_streamLog.isNotEmpty)
                                        const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade800,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
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
                                    setState(() => _userScrolling = false);
                                    _scrollToBottom();
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.arrow_downward,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          '回到底部',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
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
                            _resultContent ?? '暂无内容，请先运行总结或选择一条历史记录。',
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                      ),
              ),
              if (_summaryPath != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Saved to: $_summaryPath',
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

class _PromptPreview extends StatelessWidget {
  const _PromptPreview({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SelectableText(
            content,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ],
      ),
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
        child: Text(value ?? '未设置'),
      ),
    );
  }
}
