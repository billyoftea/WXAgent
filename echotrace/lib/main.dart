import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'branding.dart';
import 'pages/home_page.dart';
import 'providers/app_state.dart';

void main() {
  runApp(const EchoTraceApp());
}

class EchoTraceApp extends StatelessWidget {
  const EchoTraceApp({
    super.key,
    this.branding = const EchoTraceBrandingData(),
  });

  final EchoTraceBrandingData branding;

  @override
  Widget build(BuildContext context) {
    return EchoTraceBranding(
      data: branding,
      child: ChangeNotifierProvider(
        create: (context) {
          final appState = AppState();
          // 异步初始化，避免阻塞界面渲染
          appState.initialize();
          return appState;
        },
        child: MaterialApp(
          title: '${branding.productName} - 微信数据库工作台',
          debugShowCheckedModeBanner: false,
          theme: _buildLightTheme(),
          themeMode: ThemeMode.light,
          home: const HomePage(),
        ),
      ),
    );
  }

  /// 构建浅色主题
  ThemeData _buildLightTheme() {
    const wechatGreen = Color(0xFF07C160);
    const backgroundColor = Color(0xFFF5F5F5); // 浅灰色背景

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
