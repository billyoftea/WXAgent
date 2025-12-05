import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'pages/pages.dart';
import 'services/wx_agent_api.dart';
import 'theme.dart';

enum BackendState { idle, checking, starting, running, failed, skipped }

enum WxAgentPage { welcome, key, data, analysis, summary, settings }

class AppController extends ChangeNotifier {
  AppController({String? baseUrl})
    : _baseUrl = baseUrl?.trim().isNotEmpty == true
          ? baseUrl!.trim()
          : 'http://127.0.0.1:8000' {
    _api = WxAgentApiClient(baseUrl: _baseUrl);
    Future.microtask(() => ensureBackendReady());
  }

  late WxAgentApiClient _api;
  String _baseUrl;
  BackendState _backendState = BackendState.idle;
  String? _backendMessage;
  Process? _backendProcess;
  Future<void>? _backendFuture;
  bool _managesBackend = false;

  WxAgentApiClient get api => _api;
  String get baseUrl => _baseUrl;
  BackendState get backendState => _backendState;
  String? get backendMessage => _backendMessage;

  void setBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == _baseUrl) {
      if (normalized.isEmpty) return;
      return;
    }
    _baseUrl = normalized;
    _api.dispose();
    _api = WxAgentApiClient(baseUrl: _baseUrl);
    unawaited(ensureBackendReady(forceRestart: true));
    notifyListeners();
  }

  Future<void> ensureBackendReady({bool forceRestart = false}) {
    if (!_shouldAutoBootstrap) {
      _setBackendState(
        BackendState.skipped,
        'baseUrl 指向远程服务或已禁用自动启动，跳过内置后端。',
      );
      return Future.value();
    }
    if (_backendFuture != null) {
      return _backendFuture!;
    }
    _backendFuture = _runEnsureBackendReady(forceRestart: forceRestart);
    return _backendFuture!;
  }

  Future<void> restartBackend() => ensureBackendReady(forceRestart: true);

  Future<void> _runEnsureBackendReady({bool forceRestart = false}) async {
    try {
      if (forceRestart) {
        await _stopManagedBackend();
      }

      if (!forceRestart && _backendState == BackendState.running) {
        return;
      }

      _setBackendState(BackendState.checking, '检测本地后端服务…');
      if (!forceRestart && await _probeBackend()) {
        _managesBackend = false;
        _setBackendState(BackendState.running, '检测到已有后端服务。');
        return;
      }

      final executable = await _locateBackendExecutable();
      if (executable == null) {
        _setBackendState(
          BackendState.failed,
          '未找到 wx_agent_backend.exe，请将其放在应用目录或设置 WX_AGENT_BACKEND_EXE。',
        );
        return;
      }

      await _startBackendProcess(executable);
      final ready = await _waitForBackend(const Duration(seconds: 30));
      if (ready) {
        _setBackendState(BackendState.running, '后端已就绪。');
      } else {
        _setBackendState(
          BackendState.failed,
          '后端在 30 秒内未响应 /status。',
        );
        await _stopManagedBackend();
      }
    } catch (error, stackTrace) {
      _setBackendState(BackendState.failed, '自动启动后端失败：$error');
      debugPrint('Backend bootstrap failed: $error\n$stackTrace');
    } finally {
      _backendFuture = null;
    }
  }

  void _setBackendState(BackendState state, String? message) {
    if (_backendState == state && _backendMessage == message) {
      return;
    }
    _backendState = state;
    _backendMessage = message;
    notifyListeners();
  }

  bool get _shouldAutoBootstrap {
    final disableEnv = Platform.environment['WX_AGENT_DISABLE_EMBEDDED_BACKEND'];
    if (disableEnv != null && disableEnv.toLowerCase() == 'true') {
      return false;
    }
    if (!Platform.isWindows) {
      return false;
    }
    final uri = Uri.tryParse(_baseUrl);
    if (uri == null) {
      return false;
    }
    final host = uri.host.isEmpty ? '127.0.0.1' : uri.host;
    return host == '127.0.0.1' || host == 'localhost';
  }

  Future<bool> _probeBackend() async {
    final client = http.Client();
    try {
      final response = await client
          .get(_statusUri)
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  Uri get _statusUri {
    final normalizedBase = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    return Uri.parse('$normalizedBase/status');
  }

  (String host, int port) get _hostAndPort {
    final uri = Uri.tryParse(_baseUrl);
    if (uri == null) {
      return ('127.0.0.1', 8000);
    }
    final host = uri.host.isEmpty ? '127.0.0.1' : uri.host;
    final port = uri.hasPort
        ? uri.port
        : (uri.scheme == 'https' ? 443 : 8000);
    return (host, port);
  }

  Future<File?> _locateBackendExecutable() async {
    final envExecutable = Platform.environment['WX_AGENT_BACKEND_EXE'];
    if (envExecutable != null && envExecutable.trim().isNotEmpty) {
      final file = File(envExecutable.trim());
      if (await file.exists()) {
        return file;
      }
    }

    final directories = _candidateDirectories();
    const names = [
      'wx_agent_backend.exe',
      'wx_agent_server.exe',
      'wx_agent_cli.exe',
      'wx_agent.exe',
    ];

    for (final dir in directories) {
      for (final name in names) {
        final file = File(p.join(dir.path, name));
        if (file.existsSync()) {
          return file;
        }
      }
    }

    return null;
  }

  List<Directory> _candidateDirectories() {
    final seen = <String>{};
    final result = <Directory>[];

    void addIfExists(Directory dir) {
      final path = dir.path;
      if (seen.contains(path)) return;
      if (dir.existsSync()) {
        seen.add(path);
        result.add(dir);
      }
    }

    try {
      addIfExists(File(Platform.resolvedExecutable).parent);
      addIfExists(File(Platform.resolvedExecutable).parent.parent);
    } catch (_) {}

    addIfExists(Directory.current);

    try {
      addIfExists(File(Platform.script.toFilePath()).parent);
    } catch (_) {}

    final envDir = Platform.environment['WX_AGENT_BACKEND_DIR'];
    if (envDir != null && envDir.trim().isNotEmpty) {
      addIfExists(Directory(envDir.trim()));
    }

    final initial = List<Directory>.from(result);
    for (final dir in initial) {
      addIfExists(Directory(p.join(dir.path, 'backend')));
      addIfExists(Directory(p.join(dir.path, 'bin')));
    }

    return result;
  }

  Future<void> _startBackendProcess(File executable) async {
    final (host, port) = _hostAndPort;
    final args = ['--host', host, '--port', '$port'];
    try {
      final process = await Process.start(
        executable.path,
        args,
        workingDirectory: executable.parent.path,
      );
      _backendProcess = process;
      _managesBackend = true;
      _setBackendState(
        BackendState.starting,
        '已启动 ${p.basename(executable.path)}，等待服务就绪…',
      );

      unawaited(process.exitCode.then((code) {
        if (_managesBackend && _backendState == BackendState.running) {
          _setBackendState(
            BackendState.failed,
            '内置后端进程意外退出（exit $code）。',
          );
        }
      }));
    } catch (error) {
      _setBackendState(BackendState.failed, '无法启动后端：$error');
      rethrow;
    }
  }

  Future<bool> _waitForBackend(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _probeBackend()) {
        return true;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    return await _probeBackend();
  }

  Future<void> _stopManagedBackend() async {
    if (_backendProcess == null) {
      return;
    }
    try {
      _backendProcess!.kill();
      await _backendProcess!.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    } catch (_) {
      // Ignore errors when killing the child process.
    } finally {
      _backendProcess = null;
      _managesBackend = false;
    }
  }

  @override
  void dispose() {
    unawaited(_stopManagedBackend());
    _api.dispose();
    super.dispose();
  }
}

class NavigationController extends ChangeNotifier {
  WxAgentPage _page = WxAgentPage.welcome;

  WxAgentPage get page => _page;

  void goTo(WxAgentPage target) {
    if (target == _page) return;
    _page = target;
    notifyListeners();
  }
}

class WxAgentRoot extends StatelessWidget {
  const WxAgentRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppController()),
        ChangeNotifierProvider(create: (_) => NavigationController()),
      ],
      child: MaterialApp(
        title: 'WXAgent',
        theme: buildWxAgentTheme(),
        debugShowCheckedModeBanner: false,
        home: const WxAgentHome(),
      ),
    );
  }
}

class WxAgentHome extends StatelessWidget {
  const WxAgentHome({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationController>();
    final controller = context.watch<AppController>();

    return Scaffold(
      body: Row(
        children: [
          NavigationSidebar(current: nav.page, onSelect: nav.goTo),
          Expanded(
            child: Column(
              children: [
                const BackendStatusBanner(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildPage(nav.page, controller),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(WxAgentPage page, AppController controller) {
    switch (page) {
      case WxAgentPage.welcome:
        return WelcomePage(controller: controller);
      case WxAgentPage.key:
        return KeyAcquisitionPage(controller: controller);
      case WxAgentPage.data:
        return ChatDataPage(controller: controller);
      case WxAgentPage.analysis:
        return AnalysisPage(controller: controller);
      case WxAgentPage.summary:
        return SummaryPage(controller: controller);
      case WxAgentPage.settings:
        return SettingsPage(controller: controller);
    }
  }
}

class NavigationSidebar extends StatelessWidget {
  const NavigationSidebar({
    super.key,
    required this.current,
    required this.onSelect,
  });

  final WxAgentPage current;
  final ValueChanged<WxAgentPage> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: double.infinity,
      color: WxAgentColors.sidebar,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/wxagent_logo.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WXAgent',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'WeChat 数据助理',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: ListView.separated(
              itemCount: _navItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _navItems[index];
                final selected = item.page == current;
                return _SidebarButton(
                  icon: item.icon,
                  label: item.label,
                  description: item.description,
                  selected: selected,
                  onTap: () => onSelect(item.page),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '© 2025 WXAgent',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.white70),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (selected) const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.page, this.icon, this.label, this.description);
  final WxAgentPage page;
  final IconData icon;
  final String label;
  final String description;
}

const _navItems = [
  _NavItem(WxAgentPage.welcome, Icons.home_filled, '欢迎页', '新手指引与概览'),
  _NavItem(WxAgentPage.key, Icons.vpn_key_rounded, '密钥获取', '微信数据库密钥'),
  _NavItem(WxAgentPage.data, Icons.folder_zip_rounded, '聊天读取与导出', '解密与导出管理'),
  _NavItem(WxAgentPage.analysis, Icons.insights_rounded, '聊天记录分析', '多维度统计'),
  _NavItem(WxAgentPage.summary, Icons.auto_awesome, '聊天记录 AI 总结', '提示词与历史结果'),
  _NavItem(WxAgentPage.settings, Icons.settings_rounded, '设置', '路径与大模型配置'),
];

class BackendStatusBanner extends StatelessWidget {
  const BackendStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final state = controller.backendState;
    if (state == BackendState.running || state == BackendState.skipped) {
      return const SizedBox.shrink();
    }

    final palette = _paletteFor(state);
    final message = controller.backendMessage ?? _defaultMessage(state);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: palette.background,
      child: Row(
        children: [
          Icon(palette.icon, color: palette.foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: palette.foreground,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (state == BackendState.checking || state == BackendState.starting)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          if (state == BackendState.failed)
            TextButton(
              onPressed: controller.restartBackend,
              style: TextButton.styleFrom(foregroundColor: palette.foreground),
              child: const Text('重试启动'),
            ),
        ],
      ),
    );
  }

  _BackendPalette _paletteFor(BackendState state) {
    switch (state) {
      case BackendState.checking:
      case BackendState.starting:
        return const _BackendPalette(
          background: Color(0xFF1F3A5F),
          foreground: Colors.white,
          icon: Icons.sync,
        );
      case BackendState.failed:
        return const _BackendPalette(
          background: Color(0xFFB71C1C),
          foreground: Colors.white,
          icon: Icons.error_outline,
        );
      default:
        return const _BackendPalette(
          background: Color(0xFF1F3A5F),
          foreground: Colors.white,
          icon: Icons.info_outline,
        );
    }
  }

  String _defaultMessage(BackendState state) {
    switch (state) {
      case BackendState.checking:
        return '正在检测本地后端服务…';
      case BackendState.starting:
        return '正在启动内置后端…';
      case BackendState.failed:
        return '自动启动后端失败，请检查配置或重试。';
      case BackendState.idle:
      default:
        return '后端状态未知。';
    }
  }
}

class _BackendPalette {
  const _BackendPalette({
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final Color background;
  final Color foreground;
  final IconData icon;
}
