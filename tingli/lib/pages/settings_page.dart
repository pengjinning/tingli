import 'package:flutter/material.dart';
import 'cache_details_page.dart';
import 'calendar_page.dart';
import 'history_page.dart';
import 'dart:io';

import '../widgets/mini_player.dart';
import '../services/textbook_manager.dart';
import '../services/update_service.dart';
import '../services/notification_service.dart';
import '../services/cache_service.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  final int initialGoal;

  const SettingsPage({super.key, required this.initialGoal});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late int goal;
  TextbookConfig? _currentTextbook;
  final UpdateService _updateService = UpdateService();
  ReminderSettings? _reminderSettings;
  int? _cacheSizeBytes;

  @override
  void initState() {
    super.initState();
    goal = widget.initialGoal;
    _loadTextbook();
    _updateService.init();
    _loadReminderSettings();
    _loadCacheSize();
  }

  @override
  void dispose() {
    _updateService.dispose();
    super.dispose();
  }

  Future<void> _loadCacheSize() async {
    final size = await CacheService.getCacheSizeBytes();
    if (mounted) setState(() => _cacheSizeBytes = size);
  }

  Future<void> _loadTextbook() async {
    final textbook = await TextbookManager.getCurrentTextbook();
    setState(() => _currentTextbook = textbook);
  }

  Future<void> _loadReminderSettings() async {
    final settings = await NotificationService.getReminderSettings();
    setState(() => _reminderSettings = settings);
  }

  Future<void> _updateReminderSettings(ReminderSettings settings) async {
    await NotificationService.saveReminderSettings(settings);
    setState(() => _reminderSettings = settings);
  }

  Future<void> _selectReminderTime() async {
    final currentTime = TimeOfDay(
      hour: _reminderSettings?.hour ?? 19,
      minute: _reminderSettings?.minute ?? 0,
    );

    final time = await showTimePicker(
      context: context,
      initialTime: currentTime,
      helpText: '选择提醒时间（24小时制）',
      initialEntryMode: TimePickerEntryMode.input, // 使用输入模式，避免双圈表盘
      builder: (context, child) {
        // 强制 24 小时制显示
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (time != null && _reminderSettings != null) {
      await _updateReminderSettings(
        _reminderSettings!.copyWith(hour: time.hour, minute: time.minute),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 教材信息（禁用切换，仅显示）
          ListTile(
            leading: const Icon(Icons.book, color: Colors.blue),
            title: const Text('当前教材'),
            subtitle: Text(
              _currentTextbook?.displayName ?? '加载中...',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            // 移除 trailing 和 onTap，禁用点击
          ),
          const Divider(height: 1),
          // 更多功能入口：集中到设置页
          ListTile(
            leading: const Icon(Icons.calendar_month, color: Colors.indigo),
            title: const Text('打卡日历'),
            subtitle: const Text('查看每日打卡记录'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CalendarPage(dailyGoal: goal),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.brown),
            title: const Text('播放历史'),
            subtitle: const Text('查看详细播放记录'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryPage()),
              );
            },
          ),
          const Divider(height: 1),
          // 缓存管理
          ListTile(
            leading: const Icon(Icons.download, color: Colors.teal),
            title: const Text('缓存管理'),
            subtitle: Text(
              _cacheSizeBytes == null
                  ? '计算中...'
                  : '当前缓存: ${_fmtBytes(_cacheSizeBytes!)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CacheDetailsPage()),
              );
              // 从缓存详情页返回后刷新缓存大小
              _loadCacheSize();
            },
          ),
          const Divider(height: 1),
          // 每日播放目标
          ListTile(
            leading: const Icon(Icons.timer, color: Colors.orange),
            title: const Text('每日最少播放时长'),
            subtitle: Text('$goal 分钟'),
          ),
          // Slider不要分割线，直接紧跟在ListTile后面
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              value: goal.toDouble(),
              min: 5,
              max: 120,
              divisions: 23,
              label: '$goal',
              onChanged: (v) => setState(() => goal = v.round()),
            ),
          ),
          const Divider(height: 1),
          // 提醒设置
          ListTile(
            leading: const Icon(Icons.notifications, color: Colors.purple),
            title: const Text('打卡提醒'),
            subtitle: Text(
              _reminderSettings != null
                  ? '${_reminderSettings!.enabled ? "已启用" : "已关闭"} - ${_reminderSettings!.hour.toString().padLeft(2, "0")}:${_reminderSettings!.minute.toString().padLeft(2, "0")} 提醒'
                  : '加载中...',
            ),
            trailing: Switch(
              value: _reminderSettings?.enabled ?? false,
              onChanged: _reminderSettings != null
                  ? (enabled) async {
                      await _updateReminderSettings(
                        _reminderSettings!.copyWith(enabled: enabled),
                      );
                    }
                  : null,
            ),
            onTap: _reminderSettings?.enabled ?? false
                ? _selectReminderTime
                : null,
          ),
          const Divider(height: 1),
          // 应用更新
          ListenableBuilder(
            listenable: _updateService,
            builder: (context, child) {
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.system_update,
                      color: Colors.green,
                    ),
                    title: const Text('应用更新'),
                    subtitle: Text(
                      '当前版本: ${_updateService.currentVersion ?? "加载中..."}',
                    ),
                    trailing: _buildUpdateButton(),
                  ),
                  if (_updateService.status == UpdateStatus.downloading)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          LinearProgressIndicator(
                            value: _updateService.downloadProgress,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '下载中: ${(_updateService.downloadProgress * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  if (_updateService.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _updateService.errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              );
            },
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, goal),
              icon: const Icon(Icons.check),
              label: const Text('保存设置'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  String _fmtBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${units[i]}';
  }

  /// 构建更新按钮
  Widget _buildUpdateButton() {
    switch (_updateService.status) {
      case UpdateStatus.idle:
      case UpdateStatus.upToDate:
      case UpdateStatus.failed:
        return ElevatedButton(
          onPressed: _checkForUpdate,
          child: const Text('检查更新'),
        );
      case UpdateStatus.checking:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case UpdateStatus.available:
        return ElevatedButton(
          onPressed: _showUpdateDialog,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
          child: const Text('有新版本'),
        );
      case UpdateStatus.downloading:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case UpdateStatus.downloaded:
        return ElevatedButton(
          onPressed: () => _updateService.installApk(),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: const Text('立即安装'),
        );
      case UpdateStatus.installing:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
    }
  }

  /// 检查更新
  Future<void> _checkForUpdate() async {
    final hasUpdate = await _updateService.checkForUpdate();

    if (!mounted) return;

    if (_updateService.status == UpdateStatus.upToDate) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✅ 当前已是最新版本')));
    } else if (hasUpdate) {
      _showUpdateDialog();
    } else if (_updateService.status == UpdateStatus.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_updateService.errorMessage ?? '检查更新失败'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 显示更新对话框
  void _showUpdateDialog() {
    final version = _updateService.latestVersion;
    if (version == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.new_releases, color: Colors.orange),
            const SizedBox(width: 8),
            Text('发现新版本 ${version.version}'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (version.apkSize != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '安装包大小: ${version.apkSize}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              const Text(
                '更新内容：',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ...version.updateLog.map(
                (log) => Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontSize: 16)),
                      Expanded(child: Text(log)),
                    ],
                  ),
                ),
              ),
              if (Platform.isIOS) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '📱 iOS系统暂不支持应用内更新\n请前往App Store更新',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后更新'),
          ),
          if (Platform.isAndroid)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _updateService.downloadAndInstall();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('立即更新'),
            ),
        ],
      ),
    );
  }

  /// 显示提醒设置
}
