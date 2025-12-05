import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class WxAgentApiClient {
  WxAgentApiClient({required this.baseUrl, http.Client? httpClient})
    : _client = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<KeyInfo> refreshKey({
    bool autoLaunch = false,
    int waitSeconds = 90,
    int pollInterval = 3,
  }) async {
    final response = await post(
      '/refresh-key',
      body: {
        'auto_launch': autoLaunch,
        'wait_seconds': waitSeconds,
        'poll_interval': pollInterval,
      },
    );
    return KeyInfo.fromJson(response);
  }

  Future<List<SessionMeta>> listSessions() async {
    final response = await get('/sessions');
    final list = response['data'] as List? ?? const [];
    return list
        .map(
          (item) => SessionMeta.fromJson((item as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<List<SessionMeta>> listExportStates() async {
    final response = await get('/export/states');
    final list = response['data'] as List? ?? const [];
    return list
        .map(
          (item) => SessionMeta.fromJson((item as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<bool> triggerExport({
    List<String>? extraArgs,
    bool silent = true,
  }) async {
    final response = await post(
      '/export',
      body: {'extra_args': extraArgs, 'silent': silent},
    );
    return response['success'] == true;
  }

  Future<Map<String, dynamic>> runFullRefresh({
    bool autoLaunchKey = true,
    int waitSeconds = 90,
    int pollInterval = 3,
    List<String>? exportArgs,
  }) {
    return post(
      '/full-refresh',
      body: {
        'auto_launch_key': autoLaunchKey,
        'wait_seconds': waitSeconds,
        'poll_interval': pollInterval,
        'export_args': exportArgs,
      },
    );
  }

  Future<AnalysisResult> analyzeSessions({
    String? startDate,
    String? endDate,
    int topN = 10,
    List<String>? sessionTypes,
  }) async {
    final response = await post(
      '/analysis/sessions',
      body: {
        'start_date': startDate,
        'end_date': endDate,
        'top_n': topN,
        'session_types': sessionTypes,
      },
    );
    return AnalysisResult.fromJson(response);
  }

  Future<SummaryRunResult> runSummary({
    String? startDate,
    String? endDate,
    bool incremental = true,
    List<String>? questions,
    bool saveMarkdown = true,
    String? summaryPrompt,
    List<String>? sessions,
  }) async {
    final sanitizedQuestions = questions
        ?.map((q) => q.trim())
        .where((q) => q.isNotEmpty)
        .toList();
    final sanitizedSessions = sessions
        ?.map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final body = <String, dynamic>{
      'start_date': startDate,
      'end_date': endDate,
      'incremental': incremental,
      'save_markdown': saveMarkdown,
      'summary_prompt': summaryPrompt,
    };
    if (sanitizedQuestions != null && sanitizedQuestions.isNotEmpty) {
      body['questions'] = sanitizedQuestions;
    }
    if (sanitizedSessions != null && sanitizedSessions.isNotEmpty) {
      body['sessions'] = sanitizedSessions;
    }
    final response = await post(
      '/summary/run',
      body: body,
    );
    return SummaryRunResult.fromJson(response);
  }

  Future<List<SummaryHistoryEntry>> listSummaryHistory({int? limit}) async {
    final response = await get('/summary/history', query: {'limit': limit});
    final list = response['data'] as List? ?? const [];
    return list
        .map(
          (item) => SummaryHistoryEntry.fromJson(
            (item as Map).cast<String, dynamic>(),
          ),
        )
        .toList();
  }

  Future<String> readSummaryHistory(String path) async {
    final response = await get(
      '/summary/history/content',
      query: {'path': path},
    );
    return response['content'] as String? ?? '';
  }

  Future<Map<String, dynamic>> fetchConfig() => get('/config');

  Future<Map<String, dynamic>> updateConfig(Map<String, dynamic> values) =>
      put('/config', body: {'values': values});

  Future<Map<String, dynamic>> reloadConfig() => post('/config/reload');

  Future<Map<String, dynamic>> getStatus() => get('/status');

  Future<Map<String, dynamic>> describeSession({
    required String file,
    String? startDate,
    String? endDate,
  }) => post(
    '/sessions/describe',
    body: {'file': file, 'start_date': startDate, 'end_date': endDate},
  );

  Future<Map<String, dynamic>> exportFiltered({
    List<String>? selected,
    List<String>? files,
    String? startDate,
    String? endDate,
    String? outputDir,
    bool singleFile = false,
  }) => post(
    '/summary/export',
    body: {
      'selected': selected,
      'files': files,
      'start_date': startDate,
      'end_date': endDate,
      'output_dir': outputDir,
      'single_file': singleFile,
    },
  );

  Future<Map<String, dynamic>> testLlm({
    String? baseUrl,
    String? model,
    String? apiKey,
  }) {
    final payload = <String, dynamic>{};

    void put(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        payload[key] = trimmed;
      }
    }

    put('base_url', baseUrl);
    put('model', model);
    put('api_key', apiKey);

    return post('/llm/test', body: payload.isEmpty ? null : payload);
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$normalizedBase$normalizedPath');
    if (query == null || query.isEmpty) {
      return uri;
    }
    final sanitized = <String, String>{};
    query.forEach((key, value) {
      if (value == null) return;
      if (value is Iterable) {
        final items = value
            .where((element) => element != null)
            .map((element) => element.toString())
            .where((element) => element.isNotEmpty)
            .toList();
        if (items.isEmpty) return;
        sanitized[key] = items.join(',');
        return;
      }
      final text = value.toString();
      if (text.isEmpty) {
        return;
      }
      sanitized[key] = text;
    });
    return uri.replace(queryParameters: sanitized);
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _client.get(_uri(path, query));
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    final response = await _client.post(
      _uri(path, query),
      headers: const {'Content-Type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    final response = await _client.put(
      _uri(path, query),
      headers: const {'Content-Type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode >= 400) {
      throw HttpException(response.statusCode, response.body);
    }
    if (response.body.isEmpty) {
      return const {};
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'data': decoded};
  }

  void dispose() {
    _client.close();
  }
}

class HttpException implements Exception {
  HttpException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'HTTP $statusCode: $body';
}
