import 'dart:async';
// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'models/media_item.dart';
import 'services/catalog_service.dart';
import 'services/cache_service.dart';
import 'services/player_service.dart';
import 'pages/media_browser_page.dart';
import 'services/update_service.dart';

void main() {
  runApp(const TingLiApp());
}

class TingLiApp extends StatelessWidget {
  const TingLiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '睡前听力',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const Bootstrapper(),
    );
  }
}

class Bootstrapper extends StatefulWidget {
  const Bootstrapper({super.key});

  @override
  State<Bootstrapper> createState() => _BootstrapperState();
}

class _BootstrapperState extends State<Bootstrapper> {
  Map<String, List<MediaItem>>? _unitItems;
  String? _error;
  bool _isCheckingNetwork = true;

  @override
  void initState() {
    super.initState();
    _checkNetworkAndInit();
  }

  Future<void> _checkNetworkAndInit() async {
    // 检查网络连接状态
    final hasNetwork = await _checkNetworkConnection();

    if (!hasNetwork) {
      setState(() {
        _isCheckingNetwork = false;
        _error = 'network_error';
      });
      if (mounted) {
        _showNetworkErrorDialog();
      }
      return;
    }

    setState(() {
      _isCheckingNetwork = false;
    });

    _init();
  }

  Future<bool> _checkNetworkConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();

      // 检查是否有网络连接
      if (connectivityResult.contains(ConnectivityResult.none)) {
        return false;
      }

      // 到这里已基本确认有网络
      return true;
    } catch (e) {
      debugPrint('检查网络状态失败: $e');
      return false;
    }
  }

  void _showNetworkErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.wifi_off, color: Colors.orange),
            SizedBox(width: 8),
            Text('网络连接失败'),
          ],
        ),
        content: const Text(
          '随睡听 需要网络连接才能正常使用。\n\n'
          '请检查：\n'
          '• 是否已连接到 Wi-Fi 或移动数据\n'
          '• 是否允许应用使用网络\n'
          '• 网络连接是否正常',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _checkNetworkAndInit(); // 重新检查
            },
            child: const Text('重试'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // 在 iOS/Android 上可以打开设置
              // 这里简化处理，只是关闭对话框
            },
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _init() async {
    try {
      final unitItems = await CatalogService.buildUnitItemsFromCatalog();
      setState(() {
        _unitItems = unitItems;
        _error = null;
      });
      // 应用启动后，自动预取第一个音频，减少首次播放等待
      _autoPrefetchFirst(unitItems);

      // 🔥 恢复上次播放状态
      await _restoreLastPlaybackState();

      await _checkForUpdates();
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  void _autoPrefetchFirst(Map<String, List<MediaItem>> unitItems) {
    try {
      final order = ['U1', 'U2', 'U3', 'U4', 'U5', 'U6', 'ACT'];
      for (final u in order) {
        final list = (unitItems[u] ?? [])
            .where((e) => e.type != MediaType.video)
            .toList();
        if (list.isNotEmpty) {
          // 静默后台预取
          // 延迟到下一帧，避免阻塞 UI
          Future(() async {
            // 延迟少许，确保文档目录就绪
            await Future.delayed(const Duration(milliseconds: 100));
            await CacheService.prefetch(list.first);
          });
          break;
        }
      }
    } catch (_) {
      // 静默失败
    }
  }

  Future<void> _restoreLastPlaybackState() async {
    try {
      // 导入 PlayerService
      final playerService = PlayerService();
      await playerService.restoreAndInitialize();
      debugPrint('Restored last playback state');
    } catch (e) {
      debugPrint('Error restoring playback state: $e');
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final updater = UpdateService();
      await updater.init();
      final hasUpdate = await updater.checkForUpdate();
      if (!mounted || !hasUpdate || updater.latestVersion == null) return;

      final v = updater.latestVersion!;
      _showUpdateDialog(v.version, v.downloadUrl, v.updateLog);
    } catch (e) {
      debugPrint('检查更新失败: $e');
    }
  }

  // 版本比较已由 UpdateService 使用 versionCode 处理

  void _showUpdateDialog(
    String version,
    String downloadUrl,
    List<String> updateLog,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('发现新版本 $version'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '更新内容：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...updateLog.map(
                (log) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $log'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error == 'network_error') {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('网络连接失败', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              const Text('请检查网络设置后重试', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _isCheckingNetwork = true;
                  });
                  _checkNetworkAndInit();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重新检查'),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(body: Center(child: Text('加载失败: $_error')));
    }

    if (_unitItems == null || _isCheckingNetwork) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _isCheckingNetwork ? '正在检查网络连接...' : '正在加载...',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return MediaBrowserPage(unitItems: _unitItems!);
  }
}
