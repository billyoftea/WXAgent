import 'package:flutter/widgets.dart';

/// 数据结构，描述内嵌/独立模式下展示给用户的产品品牌信息。
class EchoTraceBrandingData {
  const EchoTraceBrandingData({
    this.productName = 'EchoTrace',
    this.tagline = '微信数据工作台',
    this.showVersionBadge = true,
  });

  final String productName;
  final String tagline;
  final bool showVersionBadge;

  EchoTraceBrandingData copyWith({
    String? productName,
    String? tagline,
    bool? showVersionBadge,
  }) {
    return EchoTraceBrandingData(
      productName: productName ?? this.productName,
      tagline: tagline ?? this.tagline,
      showVersionBadge: showVersionBadge ?? this.showVersionBadge,
    );
  }
}

/// InheritedWidget，便于在不同页面复用统一的品牌展示文案。
class EchoTraceBranding extends InheritedWidget {
  const EchoTraceBranding({
    super.key,
    required this.data,
    required super.child,
  });

  final EchoTraceBrandingData data;

  static EchoTraceBrandingData of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<EchoTraceBranding>();
    return widget?.data ?? const EchoTraceBrandingData();
  }

  @override
  bool updateShouldNotify(EchoTraceBranding oldWidget) {
    return oldWidget.data.productName != data.productName ||
        oldWidget.data.tagline != data.tagline ||
        oldWidget.data.showVersionBadge != data.showVersionBadge;
  }
}
