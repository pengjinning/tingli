/// 媒体类型枚举
enum MediaType { word, audio, video }

/// 媒体项目数据模型
class MediaItem {
  final String name; // 文件名（含扩展名）
  final String category; // 'kewen-audio' | 'kewen-video' | 'word'
  final String unit; // 'U1'..'U6' 或 'ACT'
  final MediaType type;
  final String? subtitleVtt; // 可选：覆盖字幕路径（相对 baseUrl）
  final String? subtitleSrt; // 可选：覆盖字幕路径（相对 baseUrl）

  const MediaItem({
    required this.name,
    required this.category,
    required this.unit,
    required this.type,
    this.subtitleVtt,
    this.subtitleSrt,
  });

  /// 获取媒体文件完整 URL
  String getUrl(String baseUrl) => '$baseUrl/$category/$name';

  /// 获取 VTT 字幕 URL
  String getVttUrl(String baseUrl) => subtitleVtt != null
      ? '$baseUrl/$subtitleVtt'
      : getUrl(
          baseUrl,
        ).replaceAll(RegExp(r'\.(mp3|mp4)$', caseSensitive: false), '.vtt');

  /// 获取 SRT 字幕 URL
  String getSrtUrl(String baseUrl) => subtitleSrt != null
      ? '$baseUrl/$subtitleSrt'
      : getUrl(
          baseUrl,
        ).replaceAll(RegExp(r'\.(mp3|mp4)$', caseSensitive: false), '.srt');
}
