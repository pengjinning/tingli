import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/subtitle_cue.dart';
import '../models/media_item.dart';
import '../services/catalog_service.dart';

/// 字幕搜索结果
class SubtitleSearchResult {
  final MediaItem mediaItem;
  final SubtitleCue cue;
  final String matchText; // 匹配的文本片段

  SubtitleSearchResult({
    required this.mediaItem,
    required this.cue,
    required this.matchText,
  });
}

/// 字幕搜索服务
class SubtitleSearchService {
  static final SubtitleSearchService _instance =
      SubtitleSearchService._internal();
  factory SubtitleSearchService() => _instance;
  SubtitleSearchService._internal();

  // 缓存已加载的字幕
  final Map<String, List<SubtitleCue>> _subtitleCache = {};

  /// 搜索所有媒体项的字幕
  Future<List<SubtitleSearchResult>> searchSubtitles(
    Map<String, List<MediaItem>> unitItems,
    String query,
  ) async {
    if (query.trim().isEmpty) return [];

    final results = <SubtitleSearchResult>[];
    final lowerQuery = query.toLowerCase();

    // 遍历所有单元的所有媒体项
    for (final entry in unitItems.entries) {
      for (final item in entry.value) {
        // 加载字幕
        final cues = await _loadSubtitlesForItem(item);
        if (cues.isEmpty) continue;

        // 搜索字幕文本
        for (final cue in cues) {
          if (cue.text.toLowerCase().contains(lowerQuery)) {
            results.add(
              SubtitleSearchResult(
                mediaItem: item,
                cue: cue,
                matchText: _extractMatchText(cue.text, query),
              ),
            );
          }
        }
      }
    }

    return results;
  }

  /// 提取匹配文本（高亮前后文）
  String _extractMatchText(String fullText, String query) {
    final lowerText = fullText.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);

    if (index == -1) return fullText;

    // 提取前后文，最多显示50个字符
    final start = (index - 20).clamp(0, fullText.length);
    final end = (index + query.length + 20).clamp(0, fullText.length);

    String result = fullText.substring(start, end);
    if (start > 0) result = '...$result';
    if (end < fullText.length) result = '$result...';

    return result;
  }

  /// 加载媒体项的字幕
  Future<List<SubtitleCue>> _loadSubtitlesForItem(MediaItem item) async {
    final cacheKey = '${item.unit}_${item.name}';

    // 检查缓存
    if (_subtitleCache.containsKey(cacheKey)) {
      return _subtitleCache[cacheKey]!;
    }

    try {
      final baseUrl = CatalogService.baseUrl;
      final baseName = item.name.replaceAll(RegExp(r'\.(mp3|mp4)$'), '');

      // 尝试加载 VTT 或 SRT 字幕
      String? subtitleText;
      String? subtitleUrl;

      // 优先尝试 VTT
      subtitleUrl = '$baseUrl/${item.unit}/$baseName.vtt';
      try {
        final vttResp = await http.get(Uri.parse(subtitleUrl));
        if (vttResp.statusCode == 200) {
          subtitleText = utf8.decode(vttResp.bodyBytes);
        }
      } catch (_) {
        // VTT 不存在，尝试 SRT
        subtitleUrl = '$baseUrl/${item.unit}/$baseName.srt';
        try {
          final srtResp = await http.get(Uri.parse(subtitleUrl));
          if (srtResp.statusCode == 200) {
            subtitleText = utf8.decode(srtResp.bodyBytes);
          }
        } catch (_) {
          // SRT 也不存在
        }
      }

      if (subtitleText == null) {
        _subtitleCache[cacheKey] = [];
        return [];
      }

      // 解析字幕
      final cues = subtitleUrl.endsWith('.vtt')
          ? _parseVtt(subtitleText)
          : _parseSrt(subtitleText);

      _subtitleCache[cacheKey] = cues;
      return cues;
    } catch (e) {
      _subtitleCache[cacheKey] = [];
      return [];
    }
  }

  /// 解析 VTT 字幕
  List<SubtitleCue> _parseVtt(String text) {
    final cues = <SubtitleCue>[];
    Duration? start;
    final buffer = StringBuffer();

    for (final line in text.split('\n')) {
      if (line.contains('-->')) {
        final parts = line.split('-->');
        start = _parseTime(parts[0].trim());
      } else if (line.trim().isEmpty && start != null) {
        if (buffer.isNotEmpty) {
          cues.add(SubtitleCue(start, buffer.toString().trim()));
          buffer.clear();
        }
        start = null;
      } else if (start != null && line.trim().isNotEmpty) {
        buffer.writeln(line);
      }
    }

    if (start != null && buffer.isNotEmpty) {
      cues.add(SubtitleCue(start, buffer.toString().trim()));
    }

    return cues;
  }

  /// 解析 SRT 字幕
  List<SubtitleCue> _parseSrt(String text) {
    final cues = <SubtitleCue>[];
    Duration? start;
    final buffer = StringBuffer();
    int state = 0; // 0=index, 1=time, 2=text

    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (start != null && buffer.isNotEmpty) {
          cues.add(SubtitleCue(start, buffer.toString().trim()));
          buffer.clear();
          start = null;
        }
        state = 0;
      } else if (state == 0 && RegExp(r'^\d+$').hasMatch(trimmed)) {
        state = 1;
      } else if (state == 1 && trimmed.contains('-->')) {
        final parts = trimmed.split('-->');
        start = _parseTime(parts[0].trim());
        state = 2;
      } else if (state == 2) {
        buffer.writeln(trimmed);
      }
    }

    if (start != null && buffer.isNotEmpty) {
      cues.add(SubtitleCue(start, buffer.toString().trim()));
    }

    return cues;
  }

  /// 解析时间字符串
  Duration _parseTime(String time) {
    final parts = time.replaceAll(',', '.').split(':');
    if (parts.length != 3) return Duration.zero;

    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    final seconds = double.tryParse(parts[2]) ?? 0.0;

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds.floor(),
      milliseconds: ((seconds - seconds.floor()) * 1000).round(),
    );
  }

  /// 清除缓存
  void clearCache() {
    _subtitleCache.clear();
  }
}
