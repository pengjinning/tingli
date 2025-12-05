import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'history_manager.dart';

/// 提醒设置模型
class ReminderSettings {
  final bool enabled; // 是否启用
  final int hour; // 小时 (0-23)
  final int minute; // 分钟 (0-59)
  final int maxReminders; // 每日最多提醒次数

  ReminderSettings({
    this.enabled = true,
    this.hour = 19, // 默认晚上7点
    this.minute = 0,
    this.maxReminders = 1,
  });

  ReminderSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    int? maxReminders,
  }) {
    return ReminderSettings(
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      maxReminders: maxReminders ?? this.maxReminders,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'maxReminders': maxReminders,
  };

  factory ReminderSettings.fromJson(Map<String, dynamic> json) {
    return ReminderSettings(
      enabled: json['enabled'] ?? true,
      hour: json['hour'] ?? 19,
      minute: json['minute'] ?? 0,
      maxReminders: json['maxReminders'] ?? 1,
    );
  }
}

/// 通知服务
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const String _settingsKey = 'reminder_settings';
  static const int _dailyReminderID = 1;

  /// 初始化通知服务
  static Future<void> initialize() async {
    if (_initialized) return;

    // 初始化时区数据
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));

    // Android 初始化设置
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // iOS 初始化设置
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
  }

  /// 通知点击回调
  static void _onNotificationTapped(NotificationResponse response) {
    // 可以在这里处理通知点击事件，例如跳转到特定页面
    print('Notification tapped: ${response.payload}');
  }

  /// 请求通知权限
  static Future<bool> requestPermission() async {
    if (!_initialized) await initialize();

    // Android 13+ 需要请求通知权限
    final androidPermission = await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    // iOS 请求权限
    final iosPermission = await _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    return androidPermission ?? iosPermission ?? true;
  }

  /// 获取提醒设置
  static Future<ReminderSettings> getReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_settingsKey);
    if (json == null) {
      return ReminderSettings();
    }

    try {
      final Map<String, dynamic> map = {};
      final pairs = json.split(',');
      for (final pair in pairs) {
        final kv = pair.split(':');
        if (kv.length == 2) {
          final key = kv[0];
          final value = kv[1];
          if (key == 'enabled') {
            map[key] = value == 'true';
          } else {
            map[key] = int.tryParse(value) ?? 0;
          }
        }
      }
      return ReminderSettings.fromJson(map);
    } catch (e) {
      return ReminderSettings();
    }
  }

  /// 保存提醒设置
  static Future<void> saveReminderSettings(ReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final json = settings.toJson();
    final str = json.entries.map((e) => '${e.key}:${e.value}').join(',');
    await prefs.setString(_settingsKey, str);

    // 重新调度通知
    if (settings.enabled) {
      await scheduleDailyReminder(settings);
    } else {
      await cancelDailyReminder();
    }
  }

  /// 调度每日提醒
  static Future<void> scheduleDailyReminder(ReminderSettings settings) async {
    if (!_initialized) await initialize();
    if (!settings.enabled) return;

    // 取消现有的提醒
    await _notifications.cancel(_dailyReminderID);

    // 设置提醒时间
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      settings.hour,
      settings.minute,
    );

    // 如果今天的时间已过，调度到明天
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    // Android 通知详情
    const androidDetails = AndroidNotificationDetails(
      'daily_reminder', // 渠道 ID
      '每日打卡提醒', // 渠道名称
      channelDescription: '提醒用户完成每日播放目标',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );

    // iOS 通知详情
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // 调度每日重复通知
    await _notifications.zonedSchedule(
      _dailyReminderID,
      '📚 随睡听 打卡提醒',
      '今天还没完成播放目标哦，加油！',
      scheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // 每天同一时间重复
    );
  }

  /// 检查并发送提醒（由应用在后台任务中调用）
  static Future<void> checkAndSendReminder(int dailyGoalMinutes) async {
    final settings = await getReminderSettings();
    if (!settings.enabled) return;

    // 检查今日播放时长
    final todayMinutes = await HistoryManager.getTodayMinutes();

    // 如果未完成目标，发送提醒
    if (todayMinutes < dailyGoalMinutes) {
      await sendImmediateReminder(
        '还差 ${dailyGoalMinutes - todayMinutes} 分钟达成今日目标',
      );
    }
  }

  /// 立即发送提醒
  static Future<void> sendImmediateReminder(String message) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'daily_reminder',
      '每日打卡提醒',
      channelDescription: '提醒用户完成每日播放目标',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      _dailyReminderID,
      '📚 随睡听 打卡提醒',
      message,
      notificationDetails,
    );
  }

  /// 取消每日提醒
  static Future<void> cancelDailyReminder() async {
    if (!_initialized) await initialize();
    await _notifications.cancel(_dailyReminderID);
  }

  /// 取消所有通知
  static Future<void> cancelAllNotifications() async {
    if (!_initialized) await initialize();
    await _notifications.cancelAll();
  }

  /// 获取待处理的通知列表
  static Future<List<PendingNotificationRequest>>
  getPendingNotifications() async {
    if (!_initialized) await initialize();
    return await _notifications.pendingNotificationRequests();
  }
}
