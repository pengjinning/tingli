import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

/// 收藏项数据模型
class FavoriteItem {
  final String fileName;
  final String category;
  final String unit;
  final String type; // 'word', 'audio', 'video'
  final DateTime addedTime;

  FavoriteItem({
    required this.fileName,
    required this.category,
    required this.unit,
    required this.type,
    required this.addedTime,
  });

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'category': category,
    'unit': unit,
    'type': type,
    'addedTime': addedTime.toIso8601String(),
  };

  /// 从 JSON 创建
  factory FavoriteItem.fromJson(Map<String, dynamic> json) => FavoriteItem(
    fileName: json['fileName'] as String,
    category: json['category'] as String,
    unit: json['unit'] as String,
    type: json['type'] as String,
    addedTime: DateTime.parse(json['addedTime'] as String),
  );

  /// 从 MediaItem 创建
  factory FavoriteItem.fromMediaItem(MediaItem item) => FavoriteItem(
    fileName: item.name,
    category: item.category,
    unit: item.unit,
    type: item.type.name,
    addedTime: DateTime.now(),
  );

  /// 转换为 MediaItem
  MediaItem toMediaItem() {
    MediaType mediaType;
    switch (type) {
      case 'video':
        mediaType = MediaType.video;
        break;
      case 'word':
        mediaType = MediaType.word;
        break;
      default:
        mediaType = MediaType.audio;
    }

    return MediaItem(
      name: fileName,
      category: category,
      unit: unit,
      type: mediaType,
    );
  }
}

/// 收藏管理器
class FavoriteManager {
  static const String _key = 'favorites';

  /// 获取所有收藏
  static Future<List<FavoriteItem>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null) return [];

    try {
      final List<dynamic> jsonList = json.decode(jsonStr);
      return jsonList.map((j) => FavoriteItem.fromJson(j)).toList();
    } catch (e) {
      return [];
    }
  }

  /// 添加收藏
  static Future<void> addFavorite(MediaItem item) async {
    final favorites = await getFavorites();

    // 检查是否已存在
    final exists = favorites.any(
      (f) =>
          f.fileName == item.name &&
          f.unit == item.unit &&
          f.category == item.category,
    );

    if (exists) return;

    // 添加新收藏
    favorites.add(FavoriteItem.fromMediaItem(item));
    await _saveFavorites(favorites);
  }

  /// 移除收藏
  static Future<void> removeFavorite(MediaItem item) async {
    final favorites = await getFavorites();
    favorites.removeWhere(
      (f) =>
          f.fileName == item.name &&
          f.unit == item.unit &&
          f.category == item.category,
    );
    await _saveFavorites(favorites);
  }

  /// 检查是否已收藏
  static Future<bool> isFavorite(MediaItem item) async {
    final favorites = await getFavorites();
    return favorites.any(
      (f) =>
          f.fileName == item.name &&
          f.unit == item.unit &&
          f.category == item.category,
    );
  }

  /// 切换收藏状态
  static Future<bool> toggleFavorite(MediaItem item) async {
    final isFav = await isFavorite(item);
    if (isFav) {
      await removeFavorite(item);
      return false;
    } else {
      await addFavorite(item);
      return true;
    }
  }

  /// 清空所有收藏
  static Future<void> clearFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// 保存收藏列表
  static Future<void> _saveFavorites(List<FavoriteItem> favorites) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(favorites.map((f) => f.toJson()).toList());
    await prefs.setString(_key, jsonStr);
  }

  /// 按单元分组获取收藏
  static Future<Map<String, List<FavoriteItem>>> getFavoritesByUnit() async {
    final favorites = await getFavorites();
    final Map<String, List<FavoriteItem>> grouped = {};

    for (final favorite in favorites) {
      if (!grouped.containsKey(favorite.unit)) {
        grouped[favorite.unit] = [];
      }
      grouped[favorite.unit]!.add(favorite);
    }

    return grouped;
  }
}
