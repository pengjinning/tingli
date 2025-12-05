import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/media_item.dart';

/// 目录服务 - 处理媒体文件目录加载
class CatalogService {
  static String? _baseUrl;

  /// 获取基础 URL
  static String get baseUrl => _baseUrl ?? '';

  /// 从 catalog.json 构建单元媒体项目列表
  static Future<Map<String, List<MediaItem>>>
  buildUnitItemsFromCatalog() async {
    final raw = await rootBundle.loadString('assets/waiyanshe/catalog.json');
    final data = json.decode(raw) as Map<String, dynamic>;
    _baseUrl = data['baseUrl'] as String;

    final result = <String, List<MediaItem>>{};
    final units = (data['units'] as Map<String, dynamic>);

    for (final entry in units.entries) {
      final unit = entry.key;
      final unitObj = entry.value as Map<String, dynamic>;

      for (final key in ['word', 'audio', 'video']) {
        if (!unitObj.containsKey(key)) continue;
        final list = (unitObj[key] as List).cast<Map<String, dynamic>>();

        for (final file in list) {
          final name = file['name'] as String;
          final category = file['category'] as String; // 与服务器路径一致
          final type = key == 'video'
              ? MediaType.video
              : (key == 'audio' ? MediaType.audio : MediaType.word);

          result.putIfAbsent(unit, () => []);
          result[unit]!.add(
            MediaItem(
              name: name,
              category: category,
              unit: unit,
              type: type,
              subtitleVtt: file['subtitleVtt'] as String?,
              subtitleSrt: file['subtitleSrt'] as String?,
            ),
          );
        }
      }
    }

    // Act it out
    if (data.containsKey('act')) {
      final actList = (data['act'] as List).cast<Map<String, dynamic>>();
      result['ACT'] = [
        for (final file in actList)
          MediaItem(
            name: file['name'] as String,
            category: file['category'] as String,
            unit: 'ACT',
            type: MediaType.audio,
          ),
      ];
    }

    return result;
  }
}
