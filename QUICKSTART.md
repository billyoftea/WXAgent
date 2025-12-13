# 🚀 快速开始：微信聊天记录智能分析

## 5分钟上手指南

### 前置条件
✅ 已安装 Go（用于编译）
✅ 已导出微信聊天记录到 output 目录
✅ 已配置 DeepSeek API key（在 backend/config.json）

### 步骤 1: 编译程序（首次使用）

```powershell
cd C:\Users\Lenovo\Desktop\WXAgent\backend
go build -o wxagent_backend.exe ./cmd/wxagent_backend
```

### 步骤 2: 导出微信数据（如果还没有）

```powershell
# 自动导出最近的消息（增量模式）
.\wxagent_backend.exe export-auto

# 或指定日期范围
.\wxagent_backend.exe export-auto --start-date 2025-12-01 --end-date 2025-12-05
```

### 步骤 3: 智能分析聊天记录

```powershell
# 方式1: 最简单 - 分析所有导出的记录
.\wxagent_backend.exe analyze-chat

# 方式2: 分析最近3天
.\wxagent_backend.exe analyze-chat --start-date 2025-12-05

# 方式3: 分析特定会话
.\wxagent_backend.exe analyze-chat --sessions "【AFT】20-21-22-23-24-25"
```

### 步骤 4: 查看分析报告

```powershell
# 打开报告
notepad ..\output\chat_analysis.md
```

## 使用测试脚本（推荐）

我们提供了一个交互式测试脚本，更加友好：

```powershell
cd C:\Users\Lenovo\Desktop\WXAgent
.\test_chat_analysis.ps1
```

选择测试场景：
```
1. 分析所有聊天记录（最近导出的）
2. 分析最近3天的消息
3. 分析特定会话（手动输入会话名）
4. 查看可用的会话列表
5. 自定义参数测试
```

## 常用命令速查

### 查看帮助
```powershell
.\wxagent_backend.exe analyze-chat --help
```

### 分析指定日期
```powershell
.\wxagent_backend.exe analyze-chat --start-date 2025-12-01 --end-date 2025-12-05
```

### 分析多个会话
```powershell
.\wxagent_backend.exe analyze-chat --sessions "会话1,会话2,会话3"
```

### 自定义输出文件
```powershell
.\wxagent_backend.exe analyze-chat --output "my_analysis.md"
```

### 调整分段大小
```powershell
.\wxagent_backend.exe analyze-chat --max-tokens 50000
```

## 输出示例

运行后会看到：

```
=== 微信聊天记录智能分析 ===

🔍 Step 1: 加载并合并所有JSON消息...
✓ 已加载 1234 条消息来自 15 个会话

📅 Step 2: 按时间排序并格式化消息...
✓ 格式化完成，总字符数: 45678

✂️  Step 3: 分段处理（考虑token限制）...
✓ 分为 2 段

🤖 Step 4: 逐段调用DeepSeek进行总结...
  处理第 1/2 段...
  ✓ 完成第 1 段
  处理第 2/2 段...
  ✓ 完成第 2 段

🔄 Step 5: 合并所有总结生成最终报告...

💾 Step 6: 保存分析报告...
✓ 报告已保存到: output\chat_analysis.md

=== 分析完成 ===
✓ 分析消息: 1234 条
✓ 涉及会话: 15 个
✓ 分段处理: 2 段
✓ 报告保存: output\chat_analysis.md
```

## 报告示例

生成的报告格式（Markdown）：

```markdown
# 微信聊天记录分析报告

**生成时间**: 2025-12-07 10:30:00

## 统计信息

- **分析消息数**: 1234 条
- **涉及会话数**: 15 个
- **分段数量**: 2 段
- **时间范围**: 2025-12-01 10:00:00 至 2025-12-05 18:30:00

### 涉及会话

- 【AFT】20-21-22-23-24-25
- 【CAP管咨】24登机口
- ...

---

## 总结报告

### 主要讨论话题

1. **招新面试安排**
   - 确定了面试时间和地点
   - 讨论了面试流程和评分标准

2. **活动策划**
   - 计划12月中旬举办年终聚会
   - 需要确认场地和预算

### 重要信息提取

- 📅 **活动通知**: 12月15日下午2点，A座302会议室
- 📢 **招聘信息**: XXX公司招聘实习生，详见群公告
- ⚠️ **重要提醒**: 提交材料截止日期为12月10日

### 参与者观点

- 张三建议调整面试时间
- 李四提出了预算优化方案
- 王五负责场地预订

---

## 附录：分段总结

（详细的分段总结内容...）
```

## 常见问题速解

### Q: 找不到聊天记录？
```powershell
# 检查 output 目录
dir ..\output\*.json
```

### Q: API 调用失败？
检查 `backend/config.json` 中的 API key 是否正确

### Q: 分析太慢？
1. 减小日期范围
2. 只分析关键会话
3. 增加 max-tokens 值

### Q: 如何获取会话名？
运行测试脚本，选择选项 4 查看所有会话

## 完整工作流程

```powershell
# 1. 导出数据
cd C:\Users\Lenovo\Desktop\WXAgent\backend
.\wxagent_backend.exe export-auto

# 2. 分析数据
.\wxagent_backend.exe analyze-chat

# 3. 查看报告
notepad ..\output\chat_analysis.md
```

## 下一步

- 📖 阅读完整使用指南：`CHAT_ANALYSIS_GUIDE.md`
- 🧪 使用测试脚本：`test_chat_analysis.ps1`
- 📊 查看更多示例和高级用法

## 技术支持

遇到问题？查看：
1. `CHAT_ANALYSIS_GUIDE.md` - 详细使用指南
2. `API_INTEGRATION_COMPLETE.md` - 技术实现细节
3. `backend/internal/analyzer/analyzer.go` - 源代码

---

**提示**：第一次使用建议先用测试脚本熟悉功能！

```powershell
cd C:\Users\Lenovo\Desktop\WXAgent
.\test_chat_analysis.ps1
```

🎉 祝你使用愉快！
