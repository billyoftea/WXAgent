# WXAgent 前端快速开始

## 前提条件

1. **Flutter SDK**: 需要 Flutter 3.9.2 或更高版本
2. **Dart SDK**: 随 Flutter 一起安装
3. **Visual Studio**: Windows 桌面开发（包含 C++ 工具）
4. **Go 后端**: 确保后端服务已编译

## 安装步骤

### 1. 安装 Flutter

如果尚未安装 Flutter，请按照以下步骤操作：

```powershell
# 下载 Flutter SDK
# 访问 https://flutter.dev/docs/get-started/install/windows

# 解压到合适的位置（例如 C:\flutter）

# 添加到 PATH 环境变量
$env:Path += ";C:\flutter\bin"

# 验证安装
flutter doctor
```

### 2. 克隆项目

```powershell
cd C:\Users\Lenovo\Desktop
git clone <repository-url>
cd WXAgent
```

### 3. 安装前端依赖

```powershell
cd frontend
flutter pub get
```

### 4. 检查开发环境

```powershell
flutter doctor -v
```

确保 Windows 桌面开发工具链已安装。

## 运行应用

### 开发模式

```powershell
# 在 frontend 目录下
flutter run -d windows
```

### 热重载

应用运行后，在终端输入：
- `r` - 热重载
- `R` - 热重启
- `q` - 退出

### 指定后端地址

如果后端运行在非默认地址，可以修改 `lib/src/app.dart`:

```dart
AppController({String? baseUrl})
  : _baseUrl = baseUrl?.trim().isNotEmpty == true
      ? baseUrl!.trim()
      : 'http://127.0.0.1:8000'  // 修改这里
```

## 构建发布版本

### 构建 Windows 可执行文件

```powershell
flutter build windows --release
```

构建产物位于：`build\windows\x64\runner\Release\`

### 打包分发

发布版本需要包含以下文件：
- `wx_agent_app.exe` - 主程序
- `flutter_windows.dll` - Flutter 运行库
- `data/` - 资源文件夹
- 后端可执行文件 `wxagent_backend.exe`

## 目录结构说明

```
frontend/
├── lib/
│   ├── main.dart              # 应用入口
│   └── src/
│       ├── app.dart          # 主应用框架
│       ├── pages/            # 各功能页面
│       ├── services/         # API 服务
│       ├── models/           # 数据模型
│       └── widgets/          # 通用组件
├── assets/
│   └── images/
│       └── wxagent_logo.png  # Logo（需添加）
├── pubspec.yaml              # 依赖配置
└── FRONTEND_GUIDE.md         # 详细开发指南
```

## 常见问题

### 1. Flutter Doctor 报错

**问题**: Visual Studio 未安装或缺少组件

**解决**: 安装 Visual Studio 2022 Community，选择"使用 C++ 的桌面开发"工作负载

### 2. 依赖安装失败

**问题**: `flutter pub get` 失败

**解决**:
```powershell
# 清理缓存
flutter clean
flutter pub cache repair

# 重新获取依赖
flutter pub get
```

### 3. 运行时错误

**问题**: 找不到后端服务

**解决**: 确保后端正在运行
```powershell
# 在另一个终端窗口
cd backend
go run cmd/wxagent_backend/main.go
```

### 4. Logo 文件缺失

**问题**: 启动时提示找不到 logo

**解决**: 
1. 准备一个 PNG 格式的 logo 文件
2. 放置到 `frontend/assets/images/wxagent_logo.png`
3. 确保 `pubspec.yaml` 中已声明：
```yaml
flutter:
  assets:
    - assets/images/wxagent_logo.png
```

## 开发工具推荐

### VS Code 扩展
- Flutter
- Dart
- Error Lens
- GitLens

### VS Code 配置

`.vscode/launch.json`:
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "WXAgent Frontend",
      "request": "launch",
      "type": "dart",
      "program": "lib/main.dart"
    }
  ]
}
```

## 调试技巧

### 1. 启用 DevTools

```powershell
# 运行应用后，在终端会显示 DevTools URL
# 在浏览器中打开该 URL 进行调试
```

### 2. 查看日志

应用运行时，所有 `print()` 和异常都会显示在终端。

### 3. 检查网络请求

在 `wx_agent_api.dart` 中添加日志：
```dart
print('API Request: ${_uri(path, query)}');
print('API Response: $response');
```

## 下一步

1. 阅读 [FRONTEND_GUIDE.md](FRONTEND_GUIDE.md) 了解详细架构
2. 查看 [ui设计.md](../ui设计.md) 了解设计规范
3. 运行后端服务并测试前端功能
4. 根据需要自定义页面和功能

## 联系支持

- 邮箱: xuang_work@foxmail.com
- GitHub: @billyoftea

---

祝开发愉快！ 🎉
