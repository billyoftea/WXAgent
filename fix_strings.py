from pathlib import Path
path = Path('wx_agent_app/lib/src/pages/analysis_page.dart')
text = path.read_text(encoding='utf-8')
text = text.replace("subtitle: '以统计视图拆分群�?/ 私聊，辅助定位高频互动会话�?", "subtitle: '以统计视图拆分群聊/私聊，辅助定位高频互动会话。'")
text = text.replace("title: '统计筛选条�?", "title: '统计筛选条件'")
text = text.replace("subtitle: '选择分析时间范围、会话类别以�?Top N 数量，支持全量或增量导出后的数据集�?", "subtitle: '选择分析时间范围、会话类别以及 Top N 数量，支持全量或增量导出后的数据集。'")
path.write_text(text, encoding='utf-8')
