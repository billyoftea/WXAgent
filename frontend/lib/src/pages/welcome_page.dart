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
  @override
  Widget build(BuildContext context) {
    return PageContainer(
      title: '欢迎使用 WXAgent',
      subtitle: 'WXAgent 帮你在本地完成微信聊天记录的解密、导出、分析与 AI 总结，数据仅存放在你的电脑里。',
      children: [
        SectionCard(
          title: '产品概览',
          subtitle: '集成密钥获取、聊天导出、数据分析、AI 总结，一键跑完整流程。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIntroBullet('仅用于查看/分析自己的聊天记录，所有数据留在本地。'),
              _buildIntroBullet('支持增量导出，避免重复操作。'),
              _buildIntroBullet('分析视图展示高频会话和活跃成员。'),
              _buildIntroBullet('AI 总结可用默认或自定义提示词，生成 Markdown 报告。'),
            ],
          ),
        ),
        SectionCard(
          title: '快速上手',
          subtitle: '按以下步骤完成一次完整运行：',
          child: Column(
            children: const [
              _StepTile(
                index: 1,
                title: '读取密钥',
                description: '在“密钥获取”页点击读取，系统会自动保存最新的数据库密钥。',
              ),
              Divider(),
              _StepTile(
                index: 2,
                title: '导出聊天记录',
                description: '检测本地微信数据路径，解密并导出聊天记录，可选全量或增量模式。',
              ),
              Divider(),
              _StepTile(
                index: 3,
                title: '聊天分析',
                description: '按时间筛选，查看群聊/好友的消息统计、高频会话和活跃成员。',
              ),
              Divider(),
              _StepTile(
                index: 4,
                title: 'AI 总结',
                description: '选择会话、时间范围与提示词，生成 Markdown 总结，可随时查看历史结果。',
              ),
            ],
          ),
        ),
        SectionCard(
          title: '使用须知',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('· WXAgent 仅供个人本地分析，请勿用于未获授权的数据。'),
              SizedBox(height: 8),
              Text('· 所有敏感处理均在本地完成，使用前请确保遵守所在地法律法规。'),
              SizedBox(height: 8),
              Text('· 如遇问题，可在设置页导出日志或联系维护者。'),
            ],
          ),
        ),
        SectionCard(
          title: '联系作者',
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
          const Text('• ', style: TextStyle(fontSize: 20, height: 1.2)),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
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
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary.withAlpha((0.15 * 255).round()),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$index',
            style: TextStyle(color: primary, fontWeight: FontWeight.bold),
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
