import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../models/export_state.dart';
import 'logger_service.dart';

/// 导出状态管理服务
/// 用于追踪每个会话的导出进度和元数据
class ExportStateService {
  static const String _stateFileName = '.export_state';

  /// 生成导出状态文件路径
  /// 状态文件与 JSON 文件在同一目录
  static String _getStateFilePath(String jsonFilePath) {
    final baseDir = File(jsonFilePath).parent.path;
    final baseName = File(jsonFilePath).path;
    return '$baseName$_stateFileName';
  }

  /// 读取导出状态
  /// 如果状态文件不存在，返回 null
  static Future<ExportState?> getExportState(String jsonFilePath) async {
    try {
      final stateFile = File(_getStateFilePath(jsonFilePath));
      if (!await stateFile.exists()) {
        return null;
      }

      final content = await stateFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return ExportState.fromJson(json);
    } catch (e) {
      await logger.error(
        'ExportStateService',
        '读取导出状态失败: $jsonFilePath',
        e,
      );
      return null;
    }
  }

  /// 保存导出状态
  static Future<bool> saveExportState(ExportState state) async {
    try {
      final stateFile = File(_getStateFilePath(state.filePath));
      
      // 确保目录存在
      final dir = stateFile.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final json = jsonEncode(state.toJson());
      await stateFile.writeAsString(json);
      
      await logger.info(
        'ExportStateService',
        '保存导出状态: wxid=${state.sessionWxid}, lastId=${state.lastExportedLocalId}',
      );
      return true;
    } catch (e) {
      await logger.error(
        'ExportStateService',
        '保存导出状态失败: ${state.filePath}',
        e,
      );
      return false;
    }
  }

  /// 删除导出状态（用于重新导出）
  static Future<bool> deleteExportState(String jsonFilePath) async {
    try {
      final stateFile = File(_getStateFilePath(jsonFilePath));
      if (await stateFile.exists()) {
        await stateFile.delete();
        await logger.info(
          'ExportStateService',
          '删除导出状态: $jsonFilePath',
        );
      }
      return true;
    } catch (e) {
      await logger.error(
        'ExportStateService',
        '删除导出状态失败: $jsonFilePath',
        e,
      );
      return false;
    }
  }

  /// 列出某个目录下所有的导出状态
  static Future<List<ExportState>> listExportStates(String directory) async {
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) {
        return [];
      }

      final states = <ExportState>[];
      
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith(_stateFileName)) {
          // 对应的 JSON 文件路径
          final jsonPath = entity.path.substring(
            0,
            entity.path.length - _stateFileName.length,
          );
          
          final state = await getExportState(jsonPath);
          if (state != null) {
            states.add(state);
          }
        }
      }

      return states;
    } catch (e) {
      await logger.error(
        'ExportStateService',
        '列出导出状态失败: $directory',
        e,
      );
      return [];
    }
  }

  /// 验证文件状态是否匹配
  /// 检查 JSON 文件是否存在且未被修改
  static Future<bool> validateExportState(ExportState state) async {
    try {
      final jsonFile = File(state.filePath);
      return await jsonFile.exists();
    } catch (e) {
      await logger.error(
        'ExportStateService',
        '验证导出状态失败: ${state.filePath}',
        e,
      );
      return false;
    }
  }
}
