# WXAgent 前端开发指南

## 概述

WXAgent 前端使用 Flutter 开发，是一个跨平台桌面应用程序，用于管理和分析微信聊天记录。

## 项目结构

```
frontend/
├── lib/
│   ├── main.dart                 # 应用入口
│   └── src/
│       ├── app.dart             # 主应用框架和路由
│       ├── theme.dart           # 主题配置
│       ├── models/
│       │   └── models.dart      # 数据模型定义
│       ├── pages/               # 页面组件
│       │   ├── welcome_page.dart        # 欢迎页
│       │   ├── key_page.dart            # 密钥获取页
│       │   ├── chat_data_page.dart      # 聊天记录读取与导出页
│       │   ├── analysis_page.dart       # 聊天记录分析页
│       │   ├── summary_page.dart        # AI 总结页
│       │   └── settings_page.dart       # 设置页
│       ├── services/
│       │   └── wx_agent_api.dart        # 后端 API 客户端
│       └── widgets/            # 通用组件
│           ├── page_container.dart      # 页面容器
│           └── section_card.dart        # 区块卡片
├── assets/
│   └── images/
│       └── wxagent_logo.png    # 应用 Logo
└── pubspec.yaml                # 依赖配置
```

## 主要功能模块

### 1. 欢迎页 (welcome_page.dart)
- 显示产品介绍和使用声明
- 展示当前系统状态（密钥、导出、总结）
- 提供新手指引
- 显示作者联系方式

### 2. 密钥获取 (key_page.dart)
- 自动检测微信安装路径
- 读取和显示数据库密钥
- 支持复制密钥到剪贴板
- 显示微信环境状态

### 3. 聊天记录读取与导出 (chat_data_page.dart)
- 检测和配置微信数据路径
- 支持全量和增量解密
- 批量导出聊天记录为 JSON
- 会话筛选和搜索
- 显示导出历史和状态

### 4. 聊天记录分析 (analysis_page.dart)
- 按时间范围分析聊天数据
- 显示 Top N 活跃会话
- 统计消息类型分布
- 区分群聊和私聊统计
- 可视化展示分析结果

### 5. AI 总结 (summary_page.dart)
- 选择时间范围和会话
- 支持默认和自定义提示词
- 生成 Markdown 格式总结
- 查看和管理历史总结
- 支持保存和导出总结

### 6. 设置 (settings_page.dart)
- 配置各种路径（微信数据、导出、总结）
- 设置大模型 API（Base URL、Model、API Key）
- 测试 LLM 连接
- 保存和重载配置

## 后端 API 端点

前端通过 `WxAgentApiClient` 与后端 Go 服务通信。主要 API 端点包括：

### 基础接口
- `GET /health` - 健康检查
- `GET /status` - 获取系统状态

### 密钥管理
- `POST /refresh-key` - 刷新密钥
- `POST /wx-key/launch` - 启动密钥获取工具

### 数据导出
- `POST /export` - 触发导出
- `GET /export/states` - 获取导出状态
- `POST /full-refresh` - 全量刷新（密钥+导出）

### 会话管理
- `GET /sessions` - 列出所有会话
- `POST /sessions/describe` - 描述特定会话

### 分析与总结
- `POST /analysis/sessions` - 分析会话统计
- `POST /summary/run` - 运行 AI 总结
- `GET /summary/history` - 获取历史总结列表
- `GET /summary/history/content` - 读取历史总结内容
- `POST /summary/export` - 导出过滤后的数据

### 配置管理
- `GET /config` - 获取配置
- `PUT /config` - 更新配置
- `POST /config/reload` - 重载配置

### LLM 测试
- `POST /llm/test` - 测试 LLM 连接

## 数据模型

### KeyInfo
存储密钥信息：
- `dbKey` - 数据库密钥
- `imageXorKey` - 图片 XOR 密钥
- `imageAesKey` - 图片 AES 密钥
- `timestamp` - 最后更新时间

### SessionMeta
会话元数据：
- `sessionId` - 会话 ID
- `displayName` - 显示名称
- `sessionType` - 会话类型（群聊/私聊）
- `messages` - 消息数量
- `lastExportTime` - 最后导出时间

### AnalysisResult
分析结果：
- `top` - Top N 会话列表
- `breakdown` - 类型分布统计
- `totalMessages` - 总消息数
- `sessionCount` - 会话总数

### SummaryRunResult
总结运行结果：
- `messages` - 处理的消息数
- `sessions` - 处理的会话数
- `outputPath` - 输出文件路径
- `content` - 总结内容

## 开发指南

### 运行前端

```powershell
cd frontend
flutter pub get
flutter run -d windows
```

### 构建发布版本

```powershell
flutter build windows --release
```

### 添加新页面

1. 在 `lib/src/pages/` 创建新页面文件
2. 在 `app.dart` 中添加页面到 `WxAgentPage` 枚举
3. 在 `_WxAgentRootState._buildPage()` 中添加路由
4. 在侧边栏中添加导航项

### 添加新 API 接口

1. 在 `wx_agent_api.dart` 中添加方法
2. 定义请求/响应数据结构
3. 在需要的页面中调用 API

### 样式和主题

应用使用统一的主题，定义在 `theme.dart` 中：
- 主色调：蓝色
- 卡片样式：圆角、阴影
- 按钮样式：统一的 elevated/outlined/text 按钮

## 注意事项

### 异步状态管理
- 使用 `setState()` 更新 UI
- 使用 `_safeSetState()` 避免组件销毁后更新
- 适当显示加载状态和错误信息

### 错误处理
- 捕获并显示 API 错误
- 提供友好的错误提示
- 使用 SnackBar 显示操作结果

### 性能优化
- 大列表使用 `ListView.builder`
- 避免不必要的重建
- 及时释放资源（dispose controllers）

## 依赖库

- `http`: HTTP 请求
- `provider`: 状态管理
- `file_selector`: 文件选择器
- `url_launcher`: 打开链接/文件
- `intl`: 国际化和日期格式化
- `path`: 路径操作

## 后续开发建议

1. **图表可视化**: 在分析页面添加图表展示
2. **搜索优化**: 改进会话搜索和过滤功能
3. **导出格式**: 支持更多导出格式（CSV、Excel）
4. **主题切换**: 添加深色模式支持
5. **国际化**: 添加多语言支持
6. **测试**: 添加单元测试和集成测试

## 问题排查

### 后端连接失败
- 检查后端服务是否运行
- 验证 baseUrl 配置
- 查看控制台错误日志

### 密钥读取失败
- 确认微信客户端已登录
- 检查文件路径权限
- 查看后端日志

### 导出失败
- 验证微信数据路径
- 确认密钥正确
- 检查磁盘空间

## 联系方式

- Email: xuang_work@foxmail.com
- GitHub: @billyoftea

---

最后更新：2025年12月9日
