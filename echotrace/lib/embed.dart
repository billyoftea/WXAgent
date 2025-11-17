import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'providers/app_state.dart';
import 'branding.dart';

export 'branding.dart';

/// 适合在其他应用中嵌入使用的界面封装。
class EchoTraceEmbeddedView extends StatefulWidget {
  const EchoTraceEmbeddedView({
    super.key,
    this.branding = const EchoTraceBrandingData(),
    this.theme,
  });

  final EchoTraceBrandingData branding;
  final ThemeData? theme;

  @override
  State<EchoTraceEmbeddedView> createState() => _EchoTraceEmbeddedViewState();
}

class _EchoTraceEmbeddedViewState extends State<EchoTraceEmbeddedView> {
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = AppState()..initialize();
  }

  @override
  void dispose() {
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? _buildEmbeddedTheme();
    return EchoTraceBranding(
      data: widget.branding,
      child: ChangeNotifierProvider<AppState>.value(
        value: _appState,
        child: Theme(
          data: theme,
          child: const HomePage(),
        ),
      ),
    );
  }

  ThemeData _buildEmbeddedTheme() {
    const wechatGreen = Color(0xFF07C160);
    const backgroundColor = Color(0xFFF5F5F5);
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'HarmonyOS Sans SC',
      colorScheme: ColorScheme.fromSeed(
        seedColor: wechatGreen,
        brightness: Brightness.light,
        primary: wechatGreen,
        secondary: wechatGreen,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: backgroundColor,
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.withValues(alpha: 0.1), width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: wechatGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: wechatGreen,
          side: const BorderSide(color: wechatGreen),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: wechatGreen, width: 2),
        ),
      ),
    );
  }
}
