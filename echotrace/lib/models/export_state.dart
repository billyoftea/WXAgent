import 'dart:convert';

/// 导出状态信息
class ExportState {
  /// 会话的 wxid
  final String sessionWxid;
  
  /// 会话的显示名称
  final String displayName;
  
  /// 文件路径
  final String filePath;
  
  /// 导出格式 (json/html/excel)
  final String format;
  
  /// 最后导出的消息 localId
  final int lastExportedLocalId;
  
  /// 最后导出的消息时间戳
  final int lastExportedTimestamp;
  
  /// 已导出的总消息数
  final int totalExportedCount;
  
  /// 首次导出时间
  final DateTime firstExportTime;
  
  /// 最后导出时间
  final DateTime lastExportTime;
  
  /// 导出历史（用于追踪每次导出的变化）
  final List<ExportHistory> history;

  ExportState({
    required this.sessionWxid,
    required this.displayName,
    required this.filePath,
    required this.format,
    this.lastExportedLocalId = 0,
    this.lastExportedTimestamp = 0,
    this.totalExportedCount = 0,
    DateTime? firstExportTime,
    DateTime? lastExportTime,
    this.history = const [],
  })  : firstExportTime = firstExportTime ?? DateTime.now(),
        lastExportTime = lastExportTime ?? DateTime.now();

  /// 从 JSON 反序列化
  factory ExportState.fromJson(Map<String, dynamic> json) {
    return ExportState(
      sessionWxid: json['sessionWxid'] as String,
      displayName: json['displayName'] as String,
      filePath: json['filePath'] as String,
      format: json['format'] as String,
      lastExportedLocalId: json['lastExportedLocalId'] as int? ?? 0,
      lastExportedTimestamp: json['lastExportedTimestamp'] as int? ?? 0,
      totalExportedCount: json['totalExportedCount'] as int? ?? 0,
      firstExportTime: json['firstExportTime'] != null
          ? DateTime.parse(json['firstExportTime'] as String)
          : null,
      lastExportTime: json['lastExportTime'] != null
          ? DateTime.parse(json['lastExportTime'] as String)
          : null,
      history: (json['history'] as List<dynamic>?)
              ?.map(
                (item) => ExportHistory.fromJson(
                  item as Map<String, dynamic>,
                ),
              )
              .toList() ??
          [],
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
        'sessionWxid': sessionWxid,
        'displayName': displayName,
        'filePath': filePath,
        'format': format,
        'lastExportedLocalId': lastExportedLocalId,
        'lastExportedTimestamp': lastExportedTimestamp,
        'totalExportedCount': totalExportedCount,
        'firstExportTime': firstExportTime.toIso8601String(),
        'lastExportTime': lastExportTime.toIso8601String(),
        'history': history.map((h) => h.toJson()).toList(),
      };

  /// 创建更新后的状态副本
  ExportState copyWith({
    String? sessionWxid,
    String? displayName,
    String? filePath,
    String? format,
    int? lastExportedLocalId,
    int? lastExportedTimestamp,
    int? totalExportedCount,
    DateTime? firstExportTime,
    DateTime? lastExportTime,
    List<ExportHistory>? history,
  }) {
    return ExportState(
      sessionWxid: sessionWxid ?? this.sessionWxid,
      displayName: displayName ?? this.displayName,
      filePath: filePath ?? this.filePath,
      format: format ?? this.format,
      lastExportedLocalId: lastExportedLocalId ?? this.lastExportedLocalId,
      lastExportedTimestamp: lastExportedTimestamp ?? this.lastExportedTimestamp,
      totalExportedCount: totalExportedCount ?? this.totalExportedCount,
      firstExportTime: firstExportTime ?? this.firstExportTime,
      lastExportTime: lastExportTime ?? this.lastExportTime,
      history: history ?? this.history,
    );
  }

  @override
  String toString() =>
      'ExportState(wxid=$sessionWxid, lastId=$lastExportedLocalId, '
      'exported=$totalExportedCount, lastTime=$lastExportTime)';
}

/// 单次导出的历史记录
class ExportHistory {
  /// 本次导出时间
  final DateTime exportTime;
  
  /// 本次新增的消息数
  final int addedCount;
  
  /// 本次导出后的总消息数
  final int totalCount;
  
  /// 本次导出的最后一条消息的 localId
  final int lastLocalId;

  ExportHistory({
    required this.exportTime,
    required this.addedCount,
    required this.totalCount,
    required this.lastLocalId,
  });

  factory ExportHistory.fromJson(Map<String, dynamic> json) {
    return ExportHistory(
      exportTime: DateTime.parse(json['exportTime'] as String),
      addedCount: json['addedCount'] as int,
      totalCount: json['totalCount'] as int,
      lastLocalId: json['lastLocalId'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'exportTime': exportTime.toIso8601String(),
        'addedCount': addedCount,
        'totalCount': totalCount,
        'lastLocalId': lastLocalId,
      };
}
