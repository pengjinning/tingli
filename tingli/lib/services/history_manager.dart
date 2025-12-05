import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/play_history.dart';

/// 播放历史管理服务
class HistoryManager {
  static const String _historyKey = 'play_history';
  static const int _maxHistoryItems = 1000; // 最多保存1000条记录

  /// 添加播放记录
  static Future<void> addHistory(PlayHistory history) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_historyKey) ?? [];
    historyJson.insert(0, json.encode(history.toJson()));

    // 限制记录数量
    if (historyJson.length > _maxHistoryItems) {
      historyJson.removeRange(_maxHistoryItems, historyJson.length);
    }

    await prefs.setStringList(_historyKey, historyJson);
  }

  /// 获取所有历史记录
  static Future<List<PlayHistory>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_historyKey) ?? [];
    return historyJson
        .map((str) => PlayHistory.fromJson(json.decode(str)))
        .toList();
  }

  /// 获取今日播放总时长（分钟）
  static Future<int> getTodayMinutes() async {
    final histories = await getHistory();
    final today = DateTime.now();
    final todayHistories = histories.where((h) {
      final playDate = h.playTime;
      return playDate.year == today.year &&
          playDate.month == today.month &&
          playDate.day == today.day;
    });

    final totalSeconds = todayHistories.fold<int>(
      0,
      (sum, h) => sum + h.durationSeconds,
    );
    return (totalSeconds / 60).floor();
  }

  /// 获取指定日期的播放总时长（分钟）
  static Future<int> getDateMinutes(DateTime date) async {
    final histories = await getHistory();
    final dateHistories = histories.where((h) {
      final playDate = h.playTime;
      return playDate.year == date.year &&
          playDate.month == date.month &&
          playDate.day == date.day;
    });

    final totalSeconds = dateHistories.fold<int>(
      0,
      (sum, h) => sum + h.durationSeconds,
    );
    return (totalSeconds / 60).floor();
  }

  /// 获取按日期分组的历史记录
  static Future<Map<String, List<PlayHistory>>> getHistoryByDate() async {
    final histories = await getHistory();
    final grouped = <String, List<PlayHistory>>{};

    for (final history in histories) {
      final date = history.playTime;
      final dateKey =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(history);
    }

    return grouped;
  }

  /// 清除所有历史记录
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}
