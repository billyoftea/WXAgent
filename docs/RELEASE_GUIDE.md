# WXAgent 发布指南

本文档说明如何打包和发布 WXAgent 应用程序。

## 项目结构

```
WXAgent/
├── backend/           # Go 后端
├── frontend/          # Flutter 前端
├── launcher/          # 启动器程序
├── modules/           # 子模块 (echotrace, wx_key)
├── scripts/           # 构建脚本
└── release/           # 打包输出目录
```

## 环境要求

### 构建环境
- **Go** 1.21 或更高版本
- **Flutter** 3.x 或更高版本
- **Windows** 10/11 (64-bit)

### 运行环境
- **Windows** 10/11 (64-bit)
- 无需安装 Go 或 Flutter

## 一键打包

### 方法 1: 使用批处理脚本

```batch
cd scripts
build_release.bat
```

### 方法 2: 使用 PowerShell 脚本

```powershell
cd scripts
.\build_release.ps1 -Configuration Release -OutputDir ".\release"
```

## 手动构建步骤

如果需要单独构建各组件：

### 1. 构建后端

```bash
cd backend
go build -ldflags="-s -w" -o wxagent_backend.exe ./cmd/wxagent_backend
```

### 2. 构建前端

```bash
cd frontend
flutter pub get
flutter build windows --release
```

构建产物位于: `frontend/build/windows/x64/runner/Release/`

### 3. 构建启动器

```bash
cd launcher
go build -ldflags="-s -w -H=windowsgui" -o WXAgent.exe .
```

使用 `-H=windowsgui` 可以隐藏控制台窗口。

## 发布包内容

打包完成后，`release/` 目录包含：

```
release/
├── WXAgent.exe              # 启动器 (双击即可启动)
├── wxagent_backend.exe      # 后端服务
├── wx_agent_app.exe         # 前端 Flutter 应用
├── flutter_windows.dll      # Flutter 运行时
├── data/                    # Flutter 资源
├── config.json              # 配置文件
└── modules/                 # 子模块
    ├── echotrace/          # 数据导出工具
    └── wx_key/             # 密钥获取工具
```

## 使用方法

### 推荐方式：使用启动器

双击 `WXAgent.exe`，将自动：
1. 启动后端服务 (端口 8080)
2. 启动前端界面

关闭前端窗口时，后端服务也会自动关闭。

### 启动器命令行参数

```bash
WXAgent.exe [选项]

选项:
  -port=8080        指定后端端口
  -console          显示后端控制台输出
  -backend-only     仅启动后端
  -frontend-only    仅启动前端
```

### 手动分别启动

```bash
# 启动后端
wxagent_backend.exe serve --port=8080

# 启动前端 (新窗口)
wx_agent_app.exe
```

## 配置文件

`config.json` 包含以下配置项：

```json
{
  "export_dir": "./output",
  "summary_output": "./output/summary.md",
  "summary_history_dir": "./output/history",
  "llm_base_url": "https://api.example.com/v1",
  "llm_api_key": "your-api-key",
  "llm_model": "gpt-4",
  "echotrace_path": "./modules/echotrace/echotrace.exe",
  "wx_key_path": "./modules/wx_key/wx_key.exe"
}
```

## 常见问题

### Q: 启动时提示找不到 DLL

确保 `flutter_windows.dll` 和 `data/` 目录与 `wx_agent_app.exe` 在同一目录。

### Q: 后端无法启动

1. 检查端口 8080 是否被占用
2. 检查 `config.json` 配置是否正确

### Q: 前端显示 "连接失败"

1. 确认后端已启动
2. 检查前端配置的 API 地址是否正确 (默认 http://localhost:8080)

## 发布清单

发布前请确认：

- [ ] 所有组件构建成功
- [ ] 配置文件已正确设置
- [ ] 测试启动器功能
- [ ] 测试手动启动功能
- [ ] 清理敏感信息（API Key 等）
- [ ] 更新版本号

## 版本历史

- **v1.0.0** - 初始发布
