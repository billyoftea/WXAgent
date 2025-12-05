import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Go 解密库的 FFI 绑定
class GoDecryptFFI {
  late ffi.DynamicLibrary _dylib;
  late _ValidateKeyNative _validateKey;
  late _DecryptDatabaseNative _decryptDatabase;
  late _ForceUnlockFileNative _forceUnlockFile;
  late _CloseSelfFileHandlesNative _closeSelfFileHandles;
  late _FreeStringNative _freeString;

  /// 单例
  static final GoDecryptFFI _instance = GoDecryptFFI._internal();
  factory GoDecryptFFI() => _instance;

  GoDecryptFFI._internal() {
    _loadLibrary();
    _bindFunctions();
  }

  /// 加载动态库
  void _loadLibrary() {
    if (Platform.isWindows) {
      _dylib = _loadWindowsDLL();
    } else if (Platform.isMacOS) {
      _dylib = ffi.DynamicLibrary.open('libgo_decrypt.dylib');
    } else if (Platform.isLinux) {
      _dylib = ffi.DynamicLibrary.open('libgo_decrypt.so');
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  /// 加载 Windows DLL
  ffi.DynamicLibrary _loadWindowsDLL() {
    final searchRoots = _resolveWindowsSearchRoots();
    const relativeLocations = <String>[
      'go_decrypt.dll',
      'windows/runner/go_decrypt.dll',
      'build/windows/x64/runner/Release/go_decrypt.dll',
      'echotrace/windows/runner/go_decrypt.dll',
      'echotrace/build/windows/x64/runner/Release/go_decrypt.dll',
      'wx_agent/bin/echotrace/go_decrypt.dll',
      'bin/echotrace/go_decrypt.dll',
    ];

    final attempted = <String>{};
    final errors = <String>[];

    for (final root in searchRoots) {
      for (final relative in relativeLocations) {
        final candidate = root.isEmpty
            ? _normalizeWindowsPath(relative)
            : _joinWindowsPath(root, relative);
        final normalized = File(candidate).absolute.path;
        if (!attempted.add(normalized)) continue;
        try {
          if (!File(normalized).existsSync()) {
            errors.add('  - $normalized: File not found');
            continue;
          }
          return ffi.DynamicLibrary.open(normalized);
        } catch (e) {
          errors.add('  - $normalized: $e');
        }
      }
    }

    throw UnsupportedError(
      'Failed to load decrypt.dll\n'
      '\n'
      'Attempted locations:\n${errors.join('\n')}\n'
      '\n'
      'You can set WXAGENT_ROOT or WXAGENT_DLL_PATH to help locate go_decrypt.dll.',
    );
  }

  /// 绑定函数
  void _bindFunctions() {
    _validateKey = _dylib
        .lookup<ffi.NativeFunction<_ValidateKeyFFI>>('ValidateKey')
        .asFunction();
    _decryptDatabase = _dylib
        .lookup<ffi.NativeFunction<_DecryptDatabaseFFI>>('DecryptDatabase')
        .asFunction();
    _forceUnlockFile = _dylib
        .lookup<ffi.NativeFunction<_ForceUnlockFileFFI>>('ForceUnlockFile')
        .asFunction();
    _closeSelfFileHandles = _dylib
        .lookup<ffi.NativeFunction<_CloseSelfFileHandlesFFI>>(
          'CloseSelfFileHandles',
        )
        .asFunction();
    _freeString = _dylib
        .lookup<ffi.NativeFunction<_FreeStringFFI>>('FreeString')
        .asFunction();
  }

  List<String> _resolveWindowsSearchRoots() {
    final roots = <String>{''};
    try {
      roots.add(Directory.current.path);
      var current = Directory.current;
      for (var i = 0; i < 4; i++) {
        final parent = current.parent;
        if (parent.path == current.path) break;
        roots.add(parent.path);
        current = parent;
      }
    } catch (_) {}

    final exeDir = _safeExecutableDir();
    if (exeDir != null) roots.add(exeDir);
    final scriptDir = _scriptDirectory();
    if (scriptDir != null) roots.add(scriptDir);

    final envRoot = Platform.environment['WXAGENT_ROOT'];
    if (envRoot != null && envRoot.trim().isNotEmpty) {
      roots.add(envRoot.trim());
    }

    final envDll = Platform.environment['WXAGENT_DLL_PATH'];
    if (envDll != null && envDll.trim().isNotEmpty) {
      roots.add(envDll.trim());
    }

    return roots.toList();
  }

  String? _safeExecutableDir() {
    try {
      return File(Platform.resolvedExecutable).parent.path;
    } catch (_) {
      return null;
    }
  }

  String? _scriptDirectory() {
    try {
      final script = Platform.script;
      if (script.scheme == 'file') {
        return File.fromUri(script).parent.path;
      }
    } catch (_) {}
    return null;
  }

  String _normalizeWindowsPath(String value) {
    return value.replaceAll('/', '\\');
  }

  String _joinWindowsPath(String base, String relative) {
    final trimmedBase = base.replaceAll('/', '\\').replaceAll(RegExp(r'\\+$'), '');
    final normalizedRelative = _normalizeWindowsPath(relative);
    if (trimmedBase.isEmpty) {
      return normalizedRelative;
    }
    return '$trimmedBase\\$normalizedRelative';
  }

  /// 规范化文件路径（确保使用正确的路径分隔符，支持中文和空格）
  String _normalizePath(String path) {
    // 在 Windows 上，确保使用反斜杠
    // toNativeUtf8() 已经支持 UTF-8 编码，可以正确处理中文
    if (Platform.isWindows) {
      return path.replaceAll('/', '\\');
    }
    return path;
  }

  /// 验证密钥
  bool validateKey(String dbPath, String hexKey) {
    final normalizedPath = _normalizePath(dbPath);
    final dbPathPtr = normalizedPath.toNativeUtf8();
    final hexKeyPtr = hexKey.toNativeUtf8();

    try {
      final result = _validateKey(dbPathPtr.cast(), hexKeyPtr.cast());
      return result == 1;
    } finally {
      malloc.free(dbPathPtr);
      malloc.free(hexKeyPtr);
    }
  }

  /// 解密数据库
  /// 返回 null 表示成功，否则返回错误消息
  String? decryptDatabase(String inputPath, String outputPath, String hexKey) {
    final normalizedInputPath = _normalizePath(inputPath);
    final normalizedOutputPath = _normalizePath(outputPath);

    final inputPathPtr = normalizedInputPath.toNativeUtf8();
    final outputPathPtr = normalizedOutputPath.toNativeUtf8();
    final hexKeyPtr = hexKey.toNativeUtf8();

    try {
      final errorPtr = _decryptDatabase(
        inputPathPtr.cast(),
        outputPathPtr.cast(),
        hexKeyPtr.cast(),
      );

      if (errorPtr == ffi.nullptr) {
        return null; // 成功
      }

      // 读取错误消息
      final error = errorPtr.cast<Utf8>().toDartString();
      _freeString(errorPtr);
      return error;
    } finally {
      malloc.free(inputPathPtr);
      malloc.free(outputPathPtr);
      malloc.free(hexKeyPtr);
    }
  }

  /// 强制解锁文件（关闭所有占用该文件的句柄）
  /// 返回 null 表示成功，否则返回错误消息
  String? forceUnlockFile(String filePath) {
    final normalizedPath = _normalizePath(filePath);
    final filePathPtr = normalizedPath.toNativeUtf8();

    try {
      final errorPtr = _forceUnlockFile(filePathPtr.cast());

      if (errorPtr == ffi.nullptr) {
        return null; // 成功
      }

      // 读取错误消息
      final error = errorPtr.cast<Utf8>().toDartString();
      _freeString(errorPtr);
      return error;
    } finally {
      malloc.free(filePathPtr);
    }
  }

  /// 关闭当前进程中所有指向指定文件的句柄
  /// 返回 null 表示成功，否则返回错误消息
  String? closeSelfFileHandles(String filePath) {
    final normalizedPath = _normalizePath(filePath);
    final filePathPtr = normalizedPath.toNativeUtf8();

    try {
      final errorPtr = _closeSelfFileHandles(filePathPtr.cast());

      if (errorPtr == ffi.nullptr) {
        return null; // 成功
      }

      // 读取错误消息
      final error = errorPtr.cast<Utf8>().toDartString();
      _freeString(errorPtr);
      return error;
    } finally {
      malloc.free(filePathPtr);
    }
  }
}

// FFI 类型定义
typedef _ValidateKeyFFI =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Char> dbPath,
      ffi.Pointer<ffi.Char> hexKey,
    );
typedef _ValidateKeyNative =
    int Function(ffi.Pointer<ffi.Char> dbPath, ffi.Pointer<ffi.Char> hexKey);

typedef _DecryptDatabaseFFI =
    ffi.Pointer<ffi.Char> Function(
      ffi.Pointer<ffi.Char> inputPath,
      ffi.Pointer<ffi.Char> outputPath,
      ffi.Pointer<ffi.Char> hexKey,
    );
typedef _DecryptDatabaseNative =
    ffi.Pointer<ffi.Char> Function(
      ffi.Pointer<ffi.Char> inputPath,
      ffi.Pointer<ffi.Char> outputPath,
      ffi.Pointer<ffi.Char> hexKey,
    );

typedef _ForceUnlockFileFFI =
    ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char> filePath);
typedef _ForceUnlockFileNative =
    ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char> filePath);

typedef _CloseSelfFileHandlesFFI =
    ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char> filePath);
typedef _CloseSelfFileHandlesNative =
    ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char> filePath);

typedef _FreeStringFFI = ffi.Void Function(ffi.Pointer<ffi.Char> str);
typedef _FreeStringNative = void Function(ffi.Pointer<ffi.Char> str);
