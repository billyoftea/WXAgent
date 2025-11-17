import 'package:flutter/material.dart';

import '../app.dart';
import '../widgets/page_container.dart';
import '../widgets/section_card.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  Map<String, dynamic>? _status;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await widget.controller.api.getStatus();
      setState(() {
        _status = status;
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageContainer(
      title: 'WELCOME! 欢迎使用 WXAgent',
      subtitle: 'WXAgent 帮助你解密、导出并分析本地微信聊天记录，同时提供 AI 总结能力，聊天记录解密和导出流程均在本地完成。本软件不会主动上传或者保留你的微信聊天记录，在使用大模型总结功能时，请确保你了解所使用的模型服务的隐私政策。',
      children: [
        SectionCard(
          title: '当前状态',
          actions: [
            TextButton.icon(
              onPressed: _loading ? null : _loadStatus,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
          ],
          child: _buildStatusOverview(),
        ),
        SectionCard(
          title: '产品介绍',
          subtitle: 'WXAgent 集成「密钥获取」「聊天记录读取与导出」「聊天分析」「AI 总结」四个模块，一次运行覆盖全流程。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIntroBullet('仅用于分析自己的聊天记录，所有信息都存储在本地，不会上传服务器。'),
              _buildIntroBullet('支持增量解密与导出，避免重复耗时操作。'),
              _buildIntroBullet('分析模块提供按联系人/群聊的统计视图，帮助你快速定位高频会话。'),
              _buildIntroBullet('AI 总结可使用默认 Prompt 或自定义提示词，生成 Markdown 报告。'),
            ],
          ),
        ),
        SectionCard(
          title: '新手指引',
          subtitle: '按照下列步骤快速完成一次完整流程。',
          child: Column(
            children: const [
              _StepTile(
                index: 1,
                title: '密钥获取',
                description: '在「密钥获取」页面点击读取密钥，系统会自动注入并保存最新的数据库密钥。',
              ),
              Divider(),
              _StepTile(
                index: 2,
                title: '聊天记录读取与导出',
                description: '检测本地微信数据路径，执行解密/导出，可选择全量或增量方式。',
              ),
              Divider(),
              _StepTile(
                index: 3,
                title: '聊天记录分析',
                description: '按时间范围查看群聊/私聊的消息统计、Top 会话和活跃成员。',
              ),
              Divider(),
              _StepTile(
                index: 4,
                title: '聊天记录 AI 总结',
                description: '选择联系人、时间范围以及提示词，一键生成 Markdown 总结，可随时回看历史结果。',
              ),
            ],
          ),
        ),
        SectionCard(
          title: '使用声明',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('· WXAgent 仅适用于个人本地数据分析，勿用于未授权的数据获取。'),
              SizedBox(height: 8),
              Text('· 所有敏感信息解析均在本地执行，操作前请确保遵守所在地法律法规。'),
              SizedBox(height: 8),
              Text('· 如遇问题，可通过设置页导出日志或直接联系作者。'),
            ],
          ),
        ),
        SectionCard(
          title: '作者联系',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _ContactRow(label: 'Email', value: 'xuang_work@foxmail.com'),
              SizedBox(height: 8),
              _ContactRow(label: 'GitHub', value: '@billyoftea'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIntroBullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•', style: TextStyle(fontSize: 20, height: 1.2)),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildStatusOverview() {
    if (_loading && _status == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: Colors.redAccent));
    }
    if (_status == null) {
      return const Text('尚未获取状态。');
    }
    final key = (_status!['key'] as Map?)?.cast<String, dynamic>() ?? {};
    final export = (_status!['export'] as Map?)?.cast<String, dynamic>() ?? {};
    final summary =
        (_status!['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        _StatusCard(
          title: '密钥',
          value: key['db_key'] != null ? '已读取' : '未读取',
          footer: '更新时间：${key['timestamp'] ?? '--'}',
        ),
        _StatusCard(
          title: '导出会话',
          value: '${export['sessions'] ?? 0} 个',
          footer: '消息总数：${export['messages'] ?? 0}',
        ),
        _StatusCard(
          title: '总结文件',
          value: summary['output_exists'] == true ? '已生成' : '未生成',
          footer: '最近修改：${summary['last_modified'] ?? '--'}',
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    required this.footer,
  });

  final String title;
  final String value;
  final String footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            footer,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.index,
    required this.title,
    required this.description,
  });

  final int index;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$index',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}
