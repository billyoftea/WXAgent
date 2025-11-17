import 'package:flutter/material.dart';

class WxAgentColors {
  static const Color primary = Color(0xFF3566F0);
  static const Color secondary = Color(0xFF6C7CFF);
  static const Color sidebar = Color(0xFF0F172A);
  static const Color background = Color(0xFFF4F6FB);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF101828);
  static const Color textSecondary = Color(0xFF475467);
  static const Color success = Color(0xFF12B76A);
  static const Color warning = Color(0xFFF79009);
  static const Color danger = Color(0xFFD92D20);
}

ThemeData buildWxAgentTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: WxAgentColors.primary,
      background: WxAgentColors.background,
    ),
    useMaterial3: true,
    fontFamily: 'Microsoft YaHei UI',
    fontFamilyFallback: const [
      'Microsoft YaHei',
      'PingFang SC',
      'Noto Sans CJK SC',
      'Heiti SC',
    ],
  );

  return base.copyWith(
    scaffoldBackgroundColor: WxAgentColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: WxAgentColors.sidebar,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: WxAgentColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: WxAgentColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: WxAgentColors.textPrimary,
      displayColor: WxAgentColors.textPrimary,
    ),
  );
}
