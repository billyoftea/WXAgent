import 'package:flutter/material.dart';
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
  final TextEditingController _promptCtrl = TextEditingController();
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
    });
    try {
      final result = await widget.controller.api.runSummary(
        startDate: _startDate,
        endDate: _endDate,
        sessions: _selectedSessions.isEmpty ? null : _selectedSessions.toList(),
        summaryPrompt: _useCustomPrompt ? _promptCtrl.text.trim() : null,
      );
      setState(() {
        _resultContent = result.content;
        _summaryPath = result.outputPath;
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
