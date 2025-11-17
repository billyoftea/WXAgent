import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../widgets/page_container.dart';
import '../widgets/section_card.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _wechatCtrl = TextEditingController();
  final TextEditingController _exportCtrl = TextEditingController();
  final TextEditingController _summaryCtrl = TextEditingController();
  final TextEditingController _historyCtrl = TextEditingController();
  final TextEditingController _llmBaseCtrl = TextEditingController();
  final TextEditingController _llmModelCtrl = TextEditingController();
  final TextEditingController _llmKeyCtrl = TextEditingController();

  static const double _fixedTemperature = 0.7;
  bool _loading = false;
  bool _savingPaths = false;
  bool _savingLlm = false;
  String? _configPath;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _wechatCtrl.dispose();
    _exportCtrl.dispose();
    _summaryCtrl.dispose();
    _historyCtrl.dispose();
    _llmBaseCtrl.dispose();
    _llmModelCtrl.dispose();
    _llmKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    _safeSetState(() {
      _loading = true;
      _message = null;
    });
    try {
      final response = await widget.controller.api.fetchConfig();
      final data =
          (response['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      final llm = data['llm'] as Map? ?? const {};
      _safeSetState(() {
        _configPath = response['path'] as String?;
        _wechatCtrl.text = data['wechat_data_path'] as String? ?? '';
        _exportCtrl.text = data['export_dir'] as String? ?? '';
        _summaryCtrl.text = data['summary_output'] as String? ?? '';
        _historyCtrl.text = data['summary_history_dir'] as String? ?? '';
        _llmBaseCtrl.text = llm['base_url'] as String? ?? '';
        _llmModelCtrl.text = llm['model'] as String? ?? '';
        _llmKeyCtrl.text = llm['api_key'] as String? ?? '';
      });
    } catch (err) {
      _safeSetState(() {
        _message = err.toString();
      });
    } finally {
      _safeSetState(() {
        _loading = false;
      });
    }
  }

  Future<void> _selectDirectory(
    TextEditingController controller,
    String label,
  ) async {
    final path = await getDirectoryPath(confirmButtonText: '选择 $label');
    if (path != null) {
      setState(() {
        controller.text = path;
      });
    }
  }

  Future<void> _selectFile(
    TextEditingController controller,
    String label,
  ) async {
    final location = await getSaveLocation(suggestedName: label);
    if (location != null) {
      setState(() {
        controller.text = location.path;
      });
    }
  }

  Future<void> _updatePaths() async {
    _safeSetState(() => _savingPaths = true);
    try {
      await widget.controller.api.updateConfig({
        'wechat_data_path': _wechatCtrl.text,
        'export_dir': _exportCtrl.text,
        'summary_output': _summaryCtrl.text,
        'summary_history_dir': _historyCtrl.text,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('路径设置已保存')));
    } catch (err) {
      _safeSetState(() => _message = err.toString());
    } finally {
      _safeSetState(() => _savingPaths = false);
    }
  }

  Future<void> _updateLlm() async {
    _safeSetState(() => _savingLlm = true);
    try {
      await widget.controller.api.updateConfig({
        'llm': {
          'base_url': _llmBaseCtrl.text,
          'model': _llmModelCtrl.text,
          'api_key': _llmKeyCtrl.text,
          'temperature': _fixedTemperature,
        },
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('LLM 设置已保存')));
    } catch (err) {
      _safeSetState(() => _message = err.toString());
    } finally {
      _safeSetState(() => _savingLlm = false);
    }
  }

  Future<void> _testLlm() async {
    _safeSetState(() {
      _savingLlm = true;
      _message = null;
    });
    try {
      final result = await widget.controller.api.testLlm();
      _safeSetState(() {
        _message =
            result['message'] as String? ??
            (result['success'] == true ? 'LLM 接口可用' : '测试失败');
      });
    } catch (err) {
      _safeSetState(() => _message = err.toString());
    } finally {
      _safeSetState(() => _savingLlm = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageContainer(
      title: '设置',
      subtitle: '调整路径、导出位置以及大模型参数，所有配置写入 config.json（${_configPath ?? '--'}）。',
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
        SectionCard(
          title: '路径设置',
          child: Column(
            children: [
              _PathRow(
                label: '微信数据路径',
                controller: _wechatCtrl,
                onBrowse: () => _selectDirectory(_wechatCtrl, '数据路径'),
              ),
              const SizedBox(height: 12),
              _PathRow(
                label: '导出目录',
                controller: _exportCtrl,
                onBrowse: () => _selectDirectory(_exportCtrl, '导出目录'),
              ),
              const SizedBox(height: 12),
              _PathRow(
                label: '总结输出文件',
                controller: _summaryCtrl,
                onBrowse: () => _selectFile(_summaryCtrl, 'summary_result.md'),
              ),
              const SizedBox(height: 12),
              _PathRow(
                label: '总结历史目录',
                controller: _historyCtrl,
                onBrowse: () => _selectDirectory(_historyCtrl, '历史目录'),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _savingPaths ? null : _updatePaths,
                  child: _savingPaths
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text('保存路径设置'),
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: '大模型 API',
          actions: [
            TextButton.icon(
              onPressed: _savingLlm ? null : _testLlm,
              icon: const Icon(Icons.bolt),
              label: const Text('测试连接'),
            ),
          ],
          child: Column(
            children: [
              TextField(
                controller: _llmBaseCtrl,
                decoration: const InputDecoration(labelText: 'Base URL'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _llmModelCtrl,
                decoration: const InputDecoration(labelText: '模型名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _llmKeyCtrl,
                decoration: const InputDecoration(labelText: 'API Key'),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Temperature 固定为 $_fixedTemperature，用于保证输出稳定。',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _savingLlm ? null : _updateLlm,
                  child: _savingLlm
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text('保存 LLM 设置'),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: TextStyle(
                    color: _message!.contains('可用')
                        ? Colors.green
                        : Colors.redAccent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }
}

class _PathRow extends StatelessWidget {
  const _PathRow({
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
      children: [
        Expanded(
          child: TextField(
            controller: controller,
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
