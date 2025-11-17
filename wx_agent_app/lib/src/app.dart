import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/pages.dart';
import 'services/wx_agent_api.dart';
import 'theme.dart';

enum WxAgentPage { welcome, key, data, analysis, summary, settings }

class AppController extends ChangeNotifier {
  AppController({String? baseUrl})
    : _baseUrl = baseUrl?.trim().isNotEmpty == true
          ? baseUrl!.trim()
          : 'http://127.0.0.1:8000' {
    _api = WxAgentApiClient(baseUrl: _baseUrl);
  }

  late WxAgentApiClient _api;
  String _baseUrl;

  WxAgentApiClient get api => _api;
  String get baseUrl => _baseUrl;

  void setBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == _baseUrl) {
      if (normalized.isEmpty) return;
      return;
    }
    _baseUrl = normalized;
    _api.dispose();
    _api = WxAgentApiClient(baseUrl: _baseUrl);
    notifyListeners();
  }

  @override
  void dispose() {
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildPage(nav.page, controller),
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
