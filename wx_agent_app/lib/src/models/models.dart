class KeyInfo {
  KeyInfo({
    this.dbKey,
    this.imageXorKey,
    this.imageAesKey,
    this.timestamp,
    this.raw = const {},
  });

  factory KeyInfo.fromJson(Map<String, dynamic> json) {
    return KeyInfo(
      dbKey: json['db_key'] as String?,
      imageXorKey: _toInt(json['image_xor_key']),
      imageAesKey: json['image_aes_key'] as String?,
      timestamp: json['timestamp'] as String?,
      raw: Map<String, dynamic>.from(json['raw'] as Map? ?? const {}),
    );
  }

  final String? dbKey;
  final int? imageXorKey;
  final String? imageAesKey;
  final String? timestamp;
  final Map<String, dynamic> raw;
}

class SessionMeta {
  SessionMeta({
    required this.sessionId,
    required this.displayName,
    this.sessionType,
    this.category,
    this.messages = 0,
    this.file,
    this.stateFile,
    this.stateFileExists = false,
    this.lastExportTime,
    this.totalExported = 0,
    this.lastAddedCount,
    this.firstTimestamp,
    this.lastTimestamp,
    this.sentMessages,
    this.receivedMessages,
  });

  factory SessionMeta.fromJson(Map<String, dynamic> json) {
    return SessionMeta(
      sessionId: _asString(
        json['session_id'] ?? json['sessionId'],
        fallback: '',
      ),
      displayName: _asString(
        json['display_name'] ?? json['displayName'],
        fallback: '未命名会话',
      ),
      sessionType: json['session_type'] as String?,
      category: json['category'] as String?,
      messages: _toInt(json['messages']) ?? 0,
      file: _asNullableString(json['file']),
      stateFile: _asNullableString(json['state_file']),
      stateFileExists: json['state_file_exists'] == true,
      lastExportTime: _asNullableString(json['last_export_time']),
      totalExported: _toInt(json['total_exported']) ?? 0,
      lastAddedCount: _toInt(json['last_added_count']),
      firstTimestamp: _asNullableString(json['first_timestamp']),
      lastTimestamp: _asNullableString(json['last_timestamp']),
      sentMessages: _toInt(json['sent_messages']),
      receivedMessages: _toInt(json['received_messages']),
    );
  }

  final String sessionId;
  final String displayName;
  final String? sessionType;
  final String? category;
  final int messages;
  final String? file;
  final String? stateFile;
  final bool stateFileExists;
  final String? lastExportTime;
  final int totalExported;
  final int? lastAddedCount;
  final String? firstTimestamp;
  final String? lastTimestamp;
  final int? sentMessages;
  final int? receivedMessages;
}

class AnalysisResult {
  AnalysisResult({
    required this.top,
    required this.breakdown,
    required this.totalMessages,
    required this.sessionCount,
    this.windowStart,
    this.windowEnd,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final topList = (json['top'] as List? ?? [])
        .map((e) => SessionMeta.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final window =
        (json['window'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AnalysisResult(
      top: topList,
      breakdown: Map<String, dynamic>.from(
        json['breakdown'] as Map? ?? const {},
      ),
      totalMessages: _toInt(json['total_messages']) ?? 0,
      sessionCount: _toInt(json['session_count']) ?? topList.length,
      windowStart: window['start'] as String?,
      windowEnd: window['end'] as String?,
    );
  }

  final List<SessionMeta> top;
  final Map<String, dynamic> breakdown;
  final int totalMessages;
  final int sessionCount;
  final String? windowStart;
  final String? windowEnd;
}

class SummaryHistoryEntry {
  SummaryHistoryEntry({
    required this.name,
    required this.path,
    this.modified,
    this.sizeBytes,
  });

  factory SummaryHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SummaryHistoryEntry(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      modified: json['modified'] as String?,
      sizeBytes: _toInt(json['size']),
    );
  }

  final String name;
  final String path;
  final String? modified;
  final int? sizeBytes;
}

class ExportHistoryRecord {
  ExportHistoryRecord({
    required this.exportTime,
    this.filePath,
    this.addedCount,
  });

  factory ExportHistoryRecord.fromJson(Map<String, dynamic> json) {
    return ExportHistoryRecord(
      exportTime: json['exportTime'] as String? ?? '',
      filePath: json['filePath'] as String?,
      addedCount: _toInt(json['addedCount']),
    );
  }

  final String exportTime;
  final String? filePath;
  final int? addedCount;
}

class SummaryRunResult {
  SummaryRunResult({
    required this.messages,
    required this.sessions,
    required this.outputPath,
    required this.durationSeconds,
    required this.content,
  });

  factory SummaryRunResult.fromJson(Map<String, dynamic> json) {
    return SummaryRunResult(
      messages: _toInt(json['messages']) ?? 0,
      sessions: _toInt(json['sessions']) ?? 0,
      outputPath:
          (json['summary_file'] ??
                  json['summary_output'] ??
                  json['output_path'] ??
                  json['path'])
              as String?,
      durationSeconds: _toInt(json['duration']) ?? 0,
      content: json['summary'] as String? ?? json['content'] as String? ?? '',
    );
  }

  final int messages;
  final int sessions;
  final String? outputPath;
  final int durationSeconds;
  final String content;
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

String _asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

String? _asNullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}
