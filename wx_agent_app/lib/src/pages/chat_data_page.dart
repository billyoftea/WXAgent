import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../models/models.dart';
import '../widgets/page_container.dart';
import '../widgets/section_card.dart';

class ChatDataPage extends StatefulWidget {
  const ChatDataPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ChatDataPage> createState() => _ChatDataPageState();
}

class _ChatDataPageState extends State<ChatDataPage> {
  final TextEditingController _wechatPathCtrl = TextEditingController();
  final TextEditingController _exportDirCtrl = TextEditingController();
  final TextEditingController _waitSecondsCtrl = TextEditingController(text: '90');
  final TextEditingController _pollIntervalCtrl = TextEditingController(text: '3');
  final TextEditingController _extraArgsCtrl = TextEditingController();

  bool _loading = false;
  bool _actionLoading = false;
  bool _detectingPath = false;
  bool _autoDetectTried = false;
  String? _error;
  Map<String, dynamic>? _statusExport;
  List<SessionMeta> _sessions = const [];
  List<SessionMeta> _sessionPool = const [];
  Set<String> _selectedSessionFiles = <String>{};
  bool _sessionsLoading = false;
  String _sessionSearch = '';
  String? _sessionFilter;
  DateTimeRange? _manualRange;
  bool _manualExporting = false;
  bool _singleFileExport = true;
  String? _customOutputDir;
  bool _fullRefreshRunning = false;
  bool _exportOnlyRunning = false;
  bool _autoLaunchWxKey = true;
  Map<String, dynamic>? _lastFullRefresh;
  DateTime? _lastFullRefreshAt;
  bool? _lastExportOnlySuccess;
  DateTime? _lastExportTimestamp;

  final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadSessionPool();
  }

  @override
  void dispose() {
    _wechatPathCtrl.dispose();
    _exportDirCtrl.dispose();
    _waitSecondsCtrl.dispose();
    _pollIntervalCtrl.dispose();
    _extraArgsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    _safeSetState(() {
      _loading = true;
      _error = null;
    });
    try {
      final configResp = await widget.controller.api.fetchConfig();
      final config =
          (configResp['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      final status = await widget.controller.api.getStatus();
      final sessions = await widget.controller.api.listExportStates();
      final detectedWechatPath = config['wechat_data_path'] as String? ?? '';
      final detectedExportDir = config['export_dir'] as String? ?? '';
      _safeSetState(() {
        _wechatPathCtrl.text = detectedWechatPath;
        _exportDirCtrl.text = detectedExportDir;
        _statusExport = (status['export'] as Map?)?.cast<String, dynamic>();
        _sessions = sessions;
      });
      if (detectedWechatPath.isEmpty && !_autoDetectTried) {
        _autoDetectTried = true;
        unawaited(_autoDetectWechatPath());
      }
    } catch (err) {
      _safeSetState(() {
        _error = err.toString();
      });
    } finally {
      _safeSetState(() {
        _loading = false;
      });
    }
  }

  Future<void> _selectDirectory({
    required String label,
    required TextEditingController controller,
    required String field,
  }) async {
    final path = await getDirectoryPath(confirmButtonText: '选择 $label');
    if (path == null) return;
    await _updateConfig(field, path);
    controller.text = path;
  }


  Future<void> _autoDetectWechatPath() async {
    if (_detectingPath) return;
    _safeSetState(() {
      _detectingPath = true;
      _error = null;
    });
    try {
      final homeDir = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      if (homeDir.isEmpty) {
        throw Exception('Unable to determine current user directory');
      }
      final sep = Platform.pathSeparator;
      final candidates = [
        '$homeDir${sep}Documents${sep}xwechat_files',
        '$homeDir${sep}Documents${sep}WeChat Files',
      ];
      for (final base in candidates) {
        final dir = Directory(base);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list()) {
          if (entity is! Directory) continue;
          final dbStorage = Directory('${entity.path}${sep}db_storage');
          if (await dbStorage.exists()) {
            await widget.controller.api.updateConfig({'wechat_data_path': base});
            _safeSetState(() {
              _wechatPathCtrl.text = base;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Detected WeChat data directory: $base')),
              );
            }
            return;
          }
        }
      }
      _safeSetState(() {
        _error = 'Auto detection failed, please select the directory manually.';
      });
    } catch (err) {
      _safeSetState(() {
        _error = 'Auto detection failed: $err';
      });
    } finally {
      _safeSetState(() {
        _detectingPath = false;
      });
    }
  }

  Future<void> _updateConfig(String field, String value) async {
    _safeSetState(() {
      _actionLoading = true;
      _error = null;
    });
    try {
      await widget.controller.api.updateConfig({field: value});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated $field')),
      );
    } catch (err) {
      _safeSetState(() {
        _error = err.toString();
      });
    } finally {
      _safeSetState(() {
        _actionLoading = false;
      });
    }
  }

  Future<void> _openFile(String? path) async {
    if (path == null || path.isEmpty) return;
    await launchUrl(Uri.file(path));
  }

  Future<void> _loadSessionPool() async {
    _safeSetState(() {
      _sessionsLoading = true;
    });
    try {
      final sessions = await widget.controller.api.listSessions();
      final validFiles = sessions
          .map((s) => s.file)
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toSet();
      _safeSetState(() {
        _sessionPool = sessions;
        _sessionsLoading = false;
        _selectedSessionFiles.removeWhere((file) => !validFiles.contains(file));
      });
    } catch (err) {
      _safeSetState(() {
        _sessionsLoading = false;
        _error = err.toString();
      });
    }
  }

  List<SessionMeta> get _filteredManualSessions {
    final query = _sessionSearch.trim().toLowerCase();
    return _sessionPool.where((session) {
      final name = session.displayName.toLowerCase();
      final matchesSearch =
          query.isEmpty || name.contains(query) || session.sessionId.contains(query);
      final type = (session.category ?? session.sessionType ?? '').toLowerCase();
      bool matchesFilter = true;
      if (_sessionFilter == 'group') {
        matchesFilter = type.contains('group') || type.contains('chatroom');
      } else if (_sessionFilter == 'single') {
        matchesFilter =
            type.contains('single') || (!type.contains('chatroom') && !type.contains('group'));
      }
      return matchesSearch && matchesFilter;
    }).toList();
  }

  void _toggleSessionSelection(String? file) {
    if (file == null || file.isEmpty) return;
    _safeSetState(() {
      if (_selectedSessionFiles.contains(file)) {
        _selectedSessionFiles.remove(file);
      } else {
        _selectedSessionFiles.add(file);
      }
    });
  }

  void _toggleSelectAllSessions(bool selectAll) {
    final items = _filteredManualSessions
        .map((session) => session.file)
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList();
    _safeSetState(() {
      if (selectAll) {
        _selectedSessionFiles = items.toSet();
      } else {
        _selectedSessionFiles.clear();
      }
    });
  }

  Future<void> _pickManualRange() async {
    final initial = _manualRange ??
        DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 7)),
          end: DateTime.now(),
        );
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initial,
      firstDate: DateTime(2013, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _safeSetState(() {
        _manualRange = picked;
      });
    }
  }

  void _clearManualRange() {
    _safeSetState(() {
      _manualRange = null;
    });
  }

  Future<void> _pickManualOutputDir() async {
    final picked = await getDirectoryPath(confirmButtonText: '选择导出目录');
    if (picked != null) {
      _safeSetState(() {
        _customOutputDir = picked;
      });
    }
  }

  Future<void> _runManualExport() async {
    if (_selectedSessionFiles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least one session to export')),
        );
      }
      return;
    }
    final startDate =
        _manualRange == null ? null : _dateFormatter.format(_manualRange!.start);
    final endDate =
        _manualRange == null ? null : _dateFormatter.format(_manualRange!.end);
    _safeSetState(() {
      _manualExporting = true;
      _error = null;
    });
    try {
      final response = await widget.controller.api.exportFiltered(
        files: _selectedSessionFiles.toList(),
        startDate: startDate,
        endDate: endDate,
        outputDir: _customOutputDir?.isEmpty ?? true ? null : _customOutputDir,
        singleFile: _singleFileExport,
      );
      if (!mounted) return;
      final exported = (response['files'] as List?)?.cast<String>() ?? const [];
      final count = response['count'] ?? exported.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported $count messages'),
        ),
      );
      await _loadData();
    } catch (err) {
      _safeSetState(() {
        _error = err.toString();
      });
    } finally {
      _safeSetState(() {
        _manualExporting = false;
      });
    }
  }

  Future<void> _runFullRefresh() async {
    if (_fullRefreshRunning) return;
    final waitSeconds = _parsePositiveInt(_waitSecondsCtrl, 90, min: 10, max: 600);
    final pollInterval = _parsePositiveInt(_pollIntervalCtrl, 3, min: 1, max: 60);
    _safeSetState(() {
      _fullRefreshRunning = true;
      _error = null;
    });
    try {
      final result = await widget.controller.api.runFullRefresh(
        autoLaunchKey: _autoLaunchWxKey,
        waitSeconds: waitSeconds,
        pollInterval: pollInterval,
        exportArgs: _extraArgsOrNull(),
      );
      _safeSetState(() {
        _lastFullRefresh = result;
        _lastFullRefreshAt = DateTime.now();
      });
      if (!mounted) return;
      final processed = result['messages'] ?? result['sessions'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出完成，处理 $processed 条记录')),
      );
      await _loadData();
    } catch (err) {
      _safeSetState(() {
        _error = err.toString();
      });
    } finally {
      _safeSetState(() {
        _fullRefreshRunning = false;
      });
    }
  }

  Future<void> _triggerExportOnly() async {
    if (_exportOnlyRunning) return;
    _safeSetState(() {
      _exportOnlyRunning = true;
      _error = null;
    });
    try {
      final ok = await widget.controller.api.triggerExport(
        extraArgs: _extraArgsOrNull(),
        silent: true,
      );
      _safeSetState(() {
        _lastExportOnlySuccess = ok;
        _lastExportTimestamp = DateTime.now();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '已触发导出，稍后刷新可见结果' : '导出命令执行失败'),
        ),
      );
      if (ok) {
        await _loadData();
      }
    } catch (err) {
      _safeSetState(() {
        _lastExportOnlySuccess = false;
        _lastExportTimestamp = DateTime.now();
        _error = err.toString();
      });
    } finally {
      _safeSetState(() {
        _exportOnlyRunning = false;
      });
    }
  }

  int _parsePositiveInt(
    TextEditingController controller,
    int fallback, {
    int min = 1,
    int max = 600,
  }) {
    final value = int.tryParse(controller.text.trim());
    if (value == null) return fallback;
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  List<String>? _extraArgsOrNull() {
    final text = _extraArgsCtrl.text.trim();
    if (text.isEmpty) return null;
    final args = text.split(RegExp(r'\s+')).where((arg) => arg.isNotEmpty).toList();
    return args.isEmpty ? null : args;
  }

  String _manualRangeLabel() {
    if (_manualRange == null) {
      return '全部时间';
    }
    final start = _dateFormatter.format(_manualRange!.start);
    final end = _dateFormatter.format(_manualRange!.end);
    return '$start - $end';
  }

  Widget _buildManualExportPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: '搜索会话',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => _safeSetState(() {
                  _sessionSearch = value;
                }),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _sessionsLoading ? null : () => _loadSessionPool(),
              icon: const Icon(Icons.refresh),
              label: const Text('刷新会话'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            _buildFilterChip('全部', null),
            _buildFilterChip('单聊', 'single'),
            _buildFilterChip('群聊', 'group'),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _toggleSelectAllSessions(true),
                child: const Text('全选筛选结果'),
              ),
              TextButton(
                onPressed: () => _toggleSelectAllSessions(false),
                child: const Text('清空选择'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 280,
          child: _buildSessionList(),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '已选择 ${_selectedSessionFiles.length} 个会话',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _manualRange == null ? null : _clearManualRange,
              icon: const Icon(Icons.clear_all),
              label: const Text('清除时间范围'),
            ),
            ElevatedButton.icon(
              onPressed: _pickManualRange,
              icon: const Icon(Icons.date_range),
              label: Text(_manualRangeLabel()),
            ),
          ],
        ),
        SwitchListTile(
          value: _singleFileExport,
          onChanged: (value) => _safeSetState(() {
            _singleFileExport = value;
          }),
          title: const Text('合并为单个 JSON 文件'),
          subtitle: const Text('关闭后将为每个会话生成独立文件'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('自定义输出目录（可选）'),
                  Text(
                    _customOutputDir?.isNotEmpty == true
                        ? _customOutputDir!
                        : '留空则使用配置文件中的导出目录',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _pickManualOutputDir,
              icon: const Icon(Icons.folder_open),
              label: const Text('选择'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _manualExporting ? null : _runManualExport,
            icon: _manualExporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.file_upload),
            label: const Text('导出选中会话'),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionList() {
    if (_sessionsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final sessions = _filteredManualSessions;
    if (sessions.isEmpty) {
      return const Center(child: Text('未检测到可导出的会话，请先刷新或执行解密导出。'));
    }
    return ListView.separated(
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final session = sessions[index];
        final file = session.file;
        final enabled = file != null && file.isNotEmpty;
        final selected = enabled && _selectedSessionFiles.contains(file);
        final subtitle = StringBuffer();
        if (session.messages > 0) {
          subtitle.write('消息 ${session.messages}');
        }
        if (session.lastTimestamp != null) {
          subtitle
            ..write(' · ')
            ..write(session.lastTimestamp);
        }
        return CheckboxListTile(
          dense: true,
          enabled: enabled,
          value: selected,
          onChanged: enabled ? (_) => _toggleSessionSelection(file) : null,
          title: Text(session.displayName),
          subtitle: subtitle.isEmpty ? null : Text(subtitle.toString()),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String? filterValue) {
    final selected = _sessionFilter == filterValue;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _safeSetState(() {
        _sessionFilter = filterValue;
      }),
    );
  }
  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Widget _buildRefreshSummary() {
    final result = _lastFullRefresh ?? const {};
    final key = (result['key'] as Map?)?.cast<String, dynamic>();
    final keyError = result['key_error'] as String?;
    final exportOk = result['export'] == true;
    final datasetReady = result['dataset_ready'] == true;
    final sessions = result['sessions'] ?? 0;
    final messages = result['messages'] ?? 0;
    final ranAt = _lastFullRefreshAt == null
        ? null
        : DateFormat('yyyy-MM-dd HH:mm:ss').format(_lastFullRefreshAt!);
    final metrics = [
      _MetricItem('密钥', key != null ? '已更新' : keyError != null ? '失败' : '未更新'),
      _MetricItem('导出', exportOk ? '成功' : '失败'),
      _MetricItem('数据集', datasetReady ? '可用' : '未生成'),
      _MetricItem('会话数', '$sessions'),
      _MetricItem('消息数', '$messages'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ranAt == null ? '最近运行结果' : '最近运行结果（$ranAt）',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: metrics.map((item) => _MetricChip(item: item)).toList(),
          ),
          if (key != null && key['timestamp'] != null) ...[
            const SizedBox(height: 12),
            Text('密钥时间：${key['timestamp']}'),
          ],
          if (keyError != null && key == null) ...[
            const SizedBox(height: 12),
            Text(
              '密钥错误：$keyError',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExportStatusChip() {
    if (_lastExportTimestamp == null) {
      return const SizedBox.shrink();
    }
    final success = _lastExportOnlySuccess == true;
    final timeText = DateFormat('HH:mm:ss').format(_lastExportTimestamp!);
    final color = success ? Colors.green : Colors.redAccent;
    final label = success ? '导出命令已触发（$timeText）' : '导出失败（$timeText）';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final export = _statusExport;
    return PageContainer(
      title: '聊天记录读取与导出',
      subtitle: '设置微信数据路径并执行增量/全量导出，导出结果将保存为 JSON 供后续分析与总结使用。',
      children: [
        SectionCard(
          title: '聊天数据源配置',
          subtitle: '指向微信本地数据目录和导出目录，WXAgent 会根据路径直接读取数据库。',
          actions: [
            TextButton.icon(
              onPressed: _loading ? null : _loadData,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: const Text('刷新状态'),
            ),
          ],
          child: Column(
            children: [
              _PathField(
                label: '微信数据路径',
                controller: _wechatPathCtrl,
                onBrowse: () => _selectDirectory(
                  label: '微信数据路径',
                  controller: _wechatPathCtrl,
                  field: 'wechat_data_path',
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _actionLoading ? null : _autoDetectWechatPath,
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('自动检测'),
                ),
              ),
              const SizedBox(height: 16),
              _PathField(
                label: '聊天导出目录',
                controller: _exportDirCtrl,
                onBrowse: () => _selectDirectory(
                  label: '导出目录',
                  controller: _exportDirCtrl,
                  field: 'export_dir',
                ),
              ),
              const SizedBox(height: 20),
              if (export != null) _ExportMetrics(export: export),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 12),
              Text(
                '导出操作请在下方“WXAgent 内置导出器”中完成，执行完毕后点击“刷新状态”同步结果。',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'WXAgent 内置导出器',
          subtitle: '通过 WXAgent 后端直接调用 Go 解密与 JSON 导出流程，无需再嵌入 EchoTrace。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                value: _autoLaunchWxKey,
                onChanged: (value) => _safeSetState(() {
                  _autoLaunchWxKey = value;
                }),
                title: const Text('缺少密钥时自动启动 wx_key'),
                subtitle: const Text('开启后一键导出会尝试注入密钥，再执行解密'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _waitSecondsCtrl,
                      decoration: const InputDecoration(
                        labelText: '等待秒数',
                        helperText: '等待 wx_key 写入密钥的时间（建议 60-120s）',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _pollIntervalCtrl,
                      decoration: const InputDecoration(
                        labelText: '轮询间隔（秒）',
                        helperText: '检测 SharedPreferences 的频率',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _extraArgsCtrl,
                decoration: const InputDecoration(
                  labelText: '附加导出参数（可选）',
                  hintText: '--fast --skip-images',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _fullRefreshRunning ? null : _runFullRefresh,
                    icon: _fullRefreshRunning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: const Text('一键解密 + 导出'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _exportOnlyRunning ? null : _triggerExportOnly,
                    icon: _exportOnlyRunning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_upload_outlined),
                    label: const Text('仅执行导出'),
                  ),
                ],
              ),
              if (_lastFullRefresh != null) ...[
                const SizedBox(height: 16),
                _buildRefreshSummary(),
              ],
              if (_lastExportTimestamp != null) ...[
                const SizedBox(height: 16),
                _buildExportStatusChip(),
              ],
            ],
          ),
        ),
        SectionCard(
          title: '导出会话列表',
          subtitle: '展示当前导出目录中的会话、消息数量及最近同步时间，可快速跳转查看 JSON。',
          child: _buildSessionTable(),
        ),
        SectionCard(
          title: '会话筛选与自定义导出',
          subtitle: '在 WXAgent 中直接完成会话筛选、时间过滤和导出格式选择，无需再切换其他应用。',
          child: _buildManualExportPanel(),
        ),
      ],
    );
  }

  Widget _buildSessionTable() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sessions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('尚未检测到导出的会话，请先执行一次导出。')),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('会话')),
          DataColumn(label: Text('类别')),
          DataColumn(label: Text('消息数')),
          DataColumn(label: Text('上次导出')),
          DataColumn(label: Text('状态文件')),
          DataColumn(label: Text('操作')),
        ],
        rows: _sessions.map((session) {
          return DataRow(
            cells: [
              DataCell(Text(session.displayName)),
              DataCell(Text(session.category ?? session.sessionType ?? '--')),
              DataCell(Text('${session.messages}')),
              DataCell(Text(session.lastExportTime ?? '--')),
              DataCell(Text(session.stateFileExists ? '已生成' : '无')),
              DataCell(
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => _openFile(session.file),
                      child: const Text('打开 JSON'),
                    ),
                    TextButton(
                      onPressed: session.stateFileExists
                          ? () => _openFile(session.stateFile)
                          : null,
                      child: const Text('查看状态'),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _PathField extends StatelessWidget {
  const _PathField({
    required this.label,
    required this.controller,
    required this.onBrowse,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            readOnly: true,
            decoration: InputDecoration(labelText: label),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: onBrowse,
          icon: const Icon(Icons.folder_open),
          label: const Text('选择'),
        ),
      ],
    );
  }
}

class _ExportMetrics extends StatelessWidget {
  const _ExportMetrics({required this.export});

  final Map<String, dynamic> export;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MetricItem('导出目录', export['export_dir'] as String? ?? '--'),
      _MetricItem('会话数', '${export['sessions'] ?? 0}'),
      _MetricItem('消息数', '${export['messages'] ?? 0}'),
      _MetricItem('最近导出', export['last_export_time'] as String? ?? '--'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: items.map((item) => _MetricChip(item: item)).toList(),
      ),
    );
  }
}

class _MetricItem {
  const _MetricItem(this.label, this.value);
  final String label;
  final String value;
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.item});

  final _MetricItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(item.value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
