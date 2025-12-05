import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';
import 'catalog_service.dart';

/// 媒体缓存服务：下载音频/视频到本地，统计缓存大小，清空缓存
class CacheService {
  // 进行中的下载，避免重复并发
  static final Set<String> _ongoing = <String>{};
  static Future<Directory> _cacheDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final cache = Directory(p.join(dir.path, 'media_cache'));
    if (!await cache.exists()) {
      await cache.create(recursive: true);
    }
    return cache;
  }

  /// 获取某个媒体文件的本地路径
  static Future<String> localPathOf(MediaItem item) async {
    final dir = await _cacheDir();
    final subdir = Directory(p.join(dir.path, item.category, item.unit));
    if (!await subdir.exists()) {
      await subdir.create(recursive: true);
    }
    return p.join(subdir.path, item.name);
  }

  /// 判断缓存是否存在
  static Future<bool> exists(MediaItem item) async {
    final path = await localPathOf(item);
    return File(path).exists();
  }

  /// 下载并保存到本地
  /// onProgress: 0.0 ~ 1.0
  static Future<String> download(
    MediaItem item, {
    void Function(double)? onProgress,
  }) async {
    final url = item.getUrl(CatalogService.baseUrl);
    final req = http.Request('GET', Uri.parse(url));
    final resp = await req.send();
    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode} when downloading $url');
    }
    final total = resp.contentLength ?? 0;
    final path = await localPathOf(item);
    final file = File(path);
    final sink = file.openWrite();
    int received = 0;
    await for (final chunk in resp.stream) {
      received += chunk.length;
      sink.add(chunk);
      if (total > 0 && onProgress != null) {
        onProgress(received / total);
      }
    }
    await sink.close();
    if (onProgress != null) onProgress(1.0);
    return path;
  }

  /// 预取：若不存在则在后台静默下载；若已存在或正在下载则直接返回
  static Future<void> prefetch(MediaItem item) async {
    try {
      if (await exists(item)) return;
      final key = '${item.category}/${item.unit}/${item.name}';
      if (_ongoing.contains(key)) return;
      _ongoing.add(key);
      await download(item, onProgress: null);
    } catch (_) {
      // 静默失败，无需抛出
    } finally {
      final key = '${item.category}/${item.unit}/${item.name}';
      _ongoing.remove(key);
    }
  }

  /// 统计缓存大小（字节）
  static Future<int> getCacheSizeBytes() async {
    final dir = await _cacheDir();
    int total = 0;
    if (!await dir.exists()) return 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  /// 清空缓存
  static Future<void> clearCache() async {
    final dir = await _cacheDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    // 重新创建目录，避免后续写入失败
    await _cacheDir();
  }

  /// 缓存项信息
  static Future<List<CacheEntry>> listEntries() async {
    final dir = await _cacheDir();
    final List<CacheEntry> list = [];
    if (!await dir.exists()) return list;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final stat = await entity.stat();
        final relPath = entity.path.substring(dir.path.length + 1);
        list.add(
          CacheEntry(
            file: entity,
            relativePath: relPath,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
          ),
        );
      }
    }
    // 按修改时间倒序
    list.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return list;
  }

  /// 删除某一条缓存项（相对路径，如: audio/U1/xxx.mp3）
  static Future<void> deleteEntry(String relativePath) async {
    final dir = await _cacheDir();
    final path = p.join(dir.path, relativePath);
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
  }
}

class CacheEntry {
  final File file;
  final String relativePath;
  final int sizeBytes;
  final DateTime modifiedAt;

  CacheEntry({
    required this.file,
    required this.relativePath,
    required this.sizeBytes,
    required this.modifiedAt,
  });
}
