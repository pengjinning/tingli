import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tingli/constants/urls.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';

/// 版本信息
class VersionInfo {
  final String version;
  final String downloadUrl;
  final List<String> updateLog;
  final String? apkSize;
  final DateTime? releaseDate;

  VersionInfo({
    required this.version,
    required this.downloadUrl,
    required this.updateLog,
    this.apkSize,
    this.releaseDate,
  });

  factory VersionInfo.fromJson(Map<String, dynamic> json) {
    // 兼容新旧两种 schema
    if (json.containsKey('versionName') || json.containsKey('versionCode')) {
      final vname = json['versionName'] as String? ?? '0.0.0';
      final vcode = (json['versionCode'] as num?)?.toInt() ?? 0;
      final url = json['downloadUrl'] as String? ?? '';
      final cl = json['changelog'];
      List<String> logs;
      if (cl is String) {
        logs = cl
            .split(RegExp(r'\r?\n'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (cl is List) {
        logs = cl.cast<String>();
      } else {
        logs = [];
      }
      String? apkSize;
      final sizeBytes = (json['sizeBytes'] as num?)?.toInt();
      if (sizeBytes != null) {
        final mb = sizeBytes / (1024 * 1024);
        apkSize = '${mb.toStringAsFixed(1)} MB';
      }
      final releasedAt = json['releasedAt'] as String?;
      return VersionInfo(
        version: '$vname+$vcode',
        downloadUrl: url,
        updateLog: logs,
        apkSize: apkSize,
        releaseDate: releasedAt != null ? DateTime.tryParse(releasedAt) : null,
      );
    }

    // 旧 schema 回退
    return VersionInfo(
      version: json['version'] as String,
      downloadUrl: json['downloadUrl'] as String,
      updateLog: (json['updateLog'] as List?)?.cast<String>() ?? [],
      apkSize: json['apkSize'] as String?,
      releaseDate: json['releaseDate'] != null
          ? DateTime.tryParse(json['releaseDate'] as String)
          : null,
    );
  }
}

/// 更新状态
enum UpdateStatus {
  idle, // 空闲
  checking, // 检查中
  available, // 有新版本
  downloading, // 下载中
  downloaded, // 下载完成
  installing, // 安装中
  failed, // 失败
  upToDate, // 已是最新
}

/// 应用更新服务
class UpdateService extends ChangeNotifier {
  static final String versionUrl = Urls.versionJson('tingli');

  String? _currentVersion;
  VersionInfo? _latestVersion;
  UpdateStatus _status = UpdateStatus.idle;
  double _downloadProgress = 0.0;
  String? _errorMessage;
  File? _downloadedApk;

  String? get currentVersion => _currentVersion;
  VersionInfo? get latestVersion => _latestVersion;
  UpdateStatus get status => _status;
  double get downloadProgress => _downloadProgress;
  String? get errorMessage => _errorMessage;
  bool get hasNewVersion =>
      _latestVersion != null &&
      _currentVersion != null &&
      _shouldUpdate(_currentVersion!, _latestVersion!.version);

  /// 初始化，获取当前版本
  Future<void> init() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;
      notifyListeners();
    } catch (e) {
      debugPrint('获取当前版本失败: $e');
    }
  }

  /// 检查更新
  Future<bool> checkForUpdate() async {
    if (_status == UpdateStatus.checking) {
      return false;
    }

    _status = UpdateStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await http
          .get(Uri.parse(versionUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final map = json.decode(response.body) as Map<String, dynamic>;
        _latestVersion = VersionInfo.fromJson(map);

        // 刷新当前版本
        final pkg = await PackageInfo.fromPlatform();
        _currentVersion = pkg.version;

        bool hasNew;
        if (map.containsKey('versionCode')) {
          final latestCode = (map['versionCode'] as num?)?.toInt() ?? 0;
          final currentCode = int.tryParse(pkg.buildNumber) ?? 0;
          hasNew = latestCode > currentCode;
        } else {
          hasNew = hasNewVersion; // 走旧版字符串比较
        }

        _status = hasNew ? UpdateStatus.available : UpdateStatus.upToDate;
        notifyListeners();
        return hasNew;
      } else {
        throw Exception('服务器返回错误: ${response.statusCode}');
      }
    } catch (e) {
      _status = UpdateStatus.failed;
      _errorMessage = '检查更新失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 下载APK（仅Android）
  Future<void> downloadApk() async {
    if (_latestVersion == null || !Platform.isAndroid) {
      return;
    }

    // 请求存储权限
    final permission = await _requestStoragePermission();
    if (!permission) {
      _status = UpdateStatus.failed;
      _errorMessage = '需要存储权限才能下载更新';
      notifyListeners();
      return;
    }

    _status = UpdateStatus.downloading;
    _downloadProgress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      // 获取下载目录
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        throw Exception('无法访问存储目录');
      }

      final fileName = '随睡听_${_latestVersion!.version}.apk';
      final savePath = '${dir.path}/$fileName';
      _downloadedApk = File(savePath);

      // 如果文件已存在，删除旧文件
      if (await _downloadedApk!.exists()) {
        await _downloadedApk!.delete();
      }

      // 下载文件
      final client = http.Client();
      final request = http.Request(
        'GET',
        Uri.parse(_latestVersion!.downloadUrl),
      );
      final response = await client.send(request);

      if (response.statusCode == 200) {
        final contentLength = response.contentLength ?? 0;
        var downloadedBytes = 0;

        final sink = _downloadedApk!.openWrite();

        await response.stream.forEach((chunk) {
          sink.add(chunk);
          downloadedBytes += chunk.length;

          if (contentLength > 0) {
            _downloadProgress = downloadedBytes / contentLength;
            notifyListeners();
          }
        });

        await sink.close();
        client.close();

        _status = UpdateStatus.downloaded;
        _downloadProgress = 1.0;
        notifyListeners();
      } else {
        throw Exception('下载失败: ${response.statusCode}');
      }
    } catch (e) {
      _status = UpdateStatus.failed;
      _errorMessage = '下载失败: $e';
      _downloadedApk = null;
      notifyListeners();
    }
  }

  /// 安装APK
  Future<void> installApk() async {
    if (_downloadedApk == null || !await _downloadedApk!.exists()) {
      _errorMessage = 'APK文件不存在';
      notifyListeners();
      return;
    }

    try {
      _status = UpdateStatus.installing;
      notifyListeners();

      // 使用 open_filex 打开APK文件进行安装
      final result = await OpenFilex.open(_downloadedApk!.path);

      if (result.type == ResultType.done) {
        debugPrint('安装成功');
      } else {
        debugPrint('安装结果: ${result.type} - ${result.message}');
        _errorMessage = '安装失败: ${result.message}';
        _status = UpdateStatus.failed;
        notifyListeners();
      }
    } catch (e) {
      _status = UpdateStatus.failed;
      _errorMessage = '安装失败: $e';
      notifyListeners();
    }
  }

  /// 下载并安装（一键更新）
  Future<void> downloadAndInstall() async {
    await downloadApk();
    if (_status == UpdateStatus.downloaded) {
      await installApk();
    }
  }

  /// 重置状态
  void reset() {
    _status = UpdateStatus.idle;
    _downloadProgress = 0.0;
    _errorMessage = null;
    _downloadedApk = null;
    notifyListeners();
  }

  /// 比较版本号
  bool _shouldUpdate(String current, String latest) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final latestParts = latest.split('.').map(int.parse).toList();

      for (
        var i = 0;
        i < 3 && i < currentParts.length && i < latestParts.length;
        i++
      ) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (e) {
      debugPrint('版本比较失败: $e');
      return false;
    }
  }

  /// 请求存储权限
  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      // Android 13+ 不需要存储权限，直接使用应用专属目录
      if (await Permission.storage.isGranted) {
        return true;
      }

      final status = await Permission.storage.request();
      return status.isGranted;
    }
    return true;
  }
}
