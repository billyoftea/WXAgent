# WXAgent：微信聊天记录智能整理系统

> 集成 wx_key + echotrace + LLM，实现自动化的微信聊天记录提取、导出和智能总结

## 🎯 项目简介

WXAgent 是一个完整的微信聊天记录智能整理解决方案，通过整合三大核心模块：

1. **wx_key** - 通过 DLL Hook 提取微信数据库与图片解密密钥
2. **echotrace** - 借助密钥读取微信数据库并导出结构化 JSON（支持增量导出）
3. **LLM 智能总结** - 调用大语言模型对聊天记录进行智能分析和总结

**核心目标**：
- ✅ 一键生成"每日新增聊天纪要"
- ✅ 支持自定义问题智能问答
- ✅ 提供统一的图形化操作界面
- ✅ 完全本地化处理，保护隐私安全

---

## 📁 项目结构

```
WXAgent/
├── frontend/              # Flutter 前端应用（统一用户界面）
├── backend/               # Go 后端服务（整合所有功能逻辑）
├── modules/               # 核心功能模块
│   ├── wx_key/           # 微信密钥提取模块
│   └── echotrace/        # 聊天记录导出模块
├── output/               # 导出的聊天记录 JSON 文件
├── docs/                 # 项目文档和设计资料
├── scripts/              # 构建和工具脚本
└── README.md             # 本文档
```

---

## 🚀 快速开始

### 环境要求

- **操作系统**：Windows 10/11
- **开发环境**：
  - Go 1.21+
  - Flutter 3.0+
  - Dart SDK 3.0+
- **LLM API**：支持 DeepSeek V3、字节火山方舟、OpenAI 等

### 安装步骤

#### 1. 克隆仓库

```powershell
git clone https://github.com/billyoftea/WXAgent.git
cd WXAgent
```

#### 2. 配置 LLM API Key

```powershell
# 设置环境变量（根据您使用的 LLM 服务商选择）
$env:ARK_API_KEY="your_api_key_here"          # 字节火山方舟
# 或
$env:OPENAI_API_KEY="your_api_key_here"       # OpenAI
# 或
$env:DEEPSEEK_API_KEY="your_api_key_here"     # DeepSeek
```

#### 3. 编译项目

```powershell
# 编译 Go 后端服务
cd backend
go mod download
go build -o wxagent_backend.exe ./cmd
cd ..

# 编译 Flutter 前端应用
cd frontend
flutter pub get
flutter build windows --release
cd ..

# 编译核心模块 - wx_key
cd modules/wx_key
flutter pub get
flutter build windows --release
cd ../..

# 编译核心模块 - echotrace
cd modules/echotrace
flutter pub get
flutter build windows --release
cd ../..
```

#### 4. 运行应用

**方式一：启动完整服务**

```powershell
# 1. 启动后端服务（在一个终端窗口）
cd backend
.\wxagent_backend.exe

# 2. 启动前端界面（在另一个终端窗口）
cd frontend\build\windows\runner\Release
.\wx_agent_app.exe
```

**方式二：独立使用模块**

```powershell
# 仅使用 wx_key 提取密钥
cd modules\wx_key\build\windows\runner\Release
.\wx_key.exe

# 仅使用 echotrace 导出聊天记录
cd modules\echotrace\build\windows\runner\Release
.\echotrace.exe
```

---

## 💡 使用指南

### 基本工作流程

1. **提取密钥**
   - 运行 wx_key 模块，提取微信数据库解密密钥
   - 密钥会保存在 `%APPDATA%\com.example\wx_key\shared_preferences.json`

2. **导出聊天记录**
   - 运行 echotrace 模块，使用密钥导出聊天记录
   - JSON 文件会保存在 `output/` 目录下
   - 支持增量导出（`.export_state` 文件记录导出进度）

3. **智能总结**
   - 通过前端界面选择日期范围
   - 输入自定义问题（可选）
   - 点击"生成总结"按钮
   - 查看智能分析结果

### 配置说明

后端配置文件位于 `backend/config.json`（如果不存在，请从 `config.example.json` 复制）：

```json
{
  "export_dir": "../output",
  "state_file": "../.wx_agent_state.json",
  "wx_key_shared_prefs": "%APPDATA%\\com.example\\wx_key\\shared_preferences.json",
  "llm_config": {
    "model": "deepseek-chat",
    "temperature": 0.7,
    "max_tokens": 4000,
    "api_base": "https://api.deepseek.com/v1"
  },
  "custom_questions": [
    "今天有哪些重要的工作任务？",
    "有哪些招聘或职业机会信息？",
    "有什么值得关注的技术讨论？"
  ]
}
```

---

## 🏗️ 架构设计

```
┌─────────────────────────────────────────────────────┐
│                   Flutter Frontend                   │
│            (统一用户界面 - wx_agent_app)              │
└──────────────────────┬──────────────────────────────┘
                       │ HTTP/gRPC
                       ↓
┌─────────────────────────────────────────────────────┐
│                    Go Backend                        │
│              (业务逻辑整合 - backend/)                │
│  ┌──────────────┬──────────────┬──────────────┐    │
│  │  密钥管理    │  数据读取    │  LLM 调用    │    │
│  └──────────────┴──────────────┴──────────────┘    │
└───────────┬─────────────────────────┬───────────────┘
            │                         │
            ↓                         ↓
┌───────────────────┐     ┌───────────────────────┐
│     wx_key        │     │     echotrace         │
│  (Flutter DLL)    │     │   (Flutter/Go)        │
│   密钥提取模块     │     │  聊天记录导出模块      │
└───────────────────┘     └───────────────────────┘
            │                         │
            └────────────┬────────────┘
                         ↓
            ┌────────────────────────┐
            │   output/ 目录          │
            │  JSON + .export_state  │
            └────────────────────────┘
```

---

## 🔧 开发指南

### 项目技术栈

- **Frontend**: Flutter/Dart
- **Backend**: Go
- **核心模块**: Flutter (wx_key, echotrace)
- **AI/LLM**: 支持多种大模型 API

### 构建脚本

项目提供了便捷的构建脚本（位于 `scripts/` 目录）：

```powershell
# 一键编译所有模块
.\scripts\build_all.ps1

# 编译并打包为单一可执行文件
.\scripts\build_bundle.ps1 -Configuration Release
```

### 贡献代码

欢迎提交 Pull Request！请确保：
1. 代码符合项目风格
2. 添加必要的测试
3. 更新相关文档

---

## 📝 常见问题

### Q: 为什么需要提取密钥？
A: 微信数据库是加密存储的，需要通过 wx_key 提取解密密钥才能读取聊天记录。

### Q: 数据安全吗？
A: 所有数据处理都在本地完成，仅在调用 LLM 总结时会上传文本内容（不包含原始数据库）。

### Q: 支持哪些 LLM 服务？
A: 支持兼容 OpenAI API 格式的服务，包括 DeepSeek、字节火山方舟、OpenAI、本地 Ollama 等。

### Q: 能否导出历史聊天记录？
A: 可以。echotrace 支持选择日期范围导出历史记录。

---

## 📄 许可证

本项目基于 MIT 许可证开源。详见 [LICENSE](LICENSE) 文件。

---

## 🙏 致谢

- [wx_key](https://github.com/xxx/wx_key) - 微信密钥提取
- [echotrace](https://github.com/xxx/echotrace) - 聊天记录导出
- Flutter、Go 社区的贡献

---

## 📮 联系方式

- **GitHub**: [billyoftea/WXAgent](https://github.com/billyoftea/WXAgent)
- **Issues**: 欢迎提交问题和建议

---

*最后更新：2025年12月5日*
