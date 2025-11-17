from pathlib import Path
from textwrap import dedent
path = Path('wx_agent_app/lib/src/pages/analysis_page.dart')
text = path.read_text(encoding='utf-8')
start = text.index('class _AnalysisResultView')
end = text.index('class _StatCard', start)
new_block = dedent("""
class _AnalysisResultView extends StatelessWidget {
  const _AnalysisResultView({required this.result});

  final AnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final breakdown = result.breakdown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _StatCard(label: '总消息数', value: '\'),
            _StatCard(label: '覆盖会话', value: '\'),
            _StatCard(
              label: '群聊消息',
              value: '\ 条',
            ),
            _StatCard(
              label: '私聊消息',
              value: '\ 条',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          '活跃时间段分布',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _buildHourlyDistribution(context),
        const SizedBox(height: 24),
        Text(
          '高频会话 Top \',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _buildTopTable(),
      ],
    );
  }

  Widget _buildTopTable() {
    if (result.top.isEmpty) {
      return const Text('暂无统计结果，先执行导出任务。');
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('会话')),
          DataColumn(label: Text('类别')),
          DataColumn(label: Text('消息统计')),
          DataColumn(label: Text('群成员占比')),
        ],
        rows: result.top.map((item) {
          final category = item.category ?? item.sessionType ?? '--';
          final bool isPrivate = category == 'single';
          final sent = item.sentMessages ?? 0;
          final received = item.receivedMessages ?? 0;
          final messageText = isPrivate
              ? '\ 条 · 我: \ | 对方: \'
              : '\ 条';
          final participants = item.participants ?? const [];
          return DataRow(
            cells: [
              DataCell(Text(item.displayName)),
              DataCell(Text(category == 'group' ? '群聊' : '私聊')),
              DataCell(Text(messageText)),
              DataCell(
                participants.isEmpty
                    ? const Text('--')
                    : Text(
                        participants
                            .take(3)
                            .map((p) {
                              final ratio =
                                  (double.tryParse(p['ratio'].toString()) ?? 0) * 100;
                              return '\ \%';
                            })
                            .join(' / '),
                      ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHourlyDistribution(BuildContext context) {
    final data = result.hourlyDistribution;
    if (data.isEmpty || data.every((value) => value == 0)) {
      return const Text('暂无活跃时间段数据。');
    }
    final maxValue = data.reduce(math.max).clamp(1, double.infinity);
    return SizedBox(
      height: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int hour = 0; hour < data.length; hour++) ...[
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: 110,
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 12,
                      height: 110 * (data[hour] / maxValue),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('\:00',
                      style: const TextStyle(fontSize: 11)),
                  Text('\',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
""")
text = text[:start] + new_block + text[end:]
path.write_text(text, encoding='utf-8')
