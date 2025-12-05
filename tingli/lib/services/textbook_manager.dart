import 'package:shared_preferences/shared_preferences.dart';

/// 教材配置模型
class TextbookConfig {
  final String publisher; // 出版社
  final String series; // 系列
  final String grade; // 年级
  final String semester; // 学期
  final String type; // 类型（课本听力、单词等）

  TextbookConfig({
    required this.publisher,
    required this.series,
    required this.grade,
    required this.semester,
    required this.type,
  });

  String get displayName => '$publisher-$series-$grade$semester$type';

  Map<String, String> toJson() => {
    'publisher': publisher,
    'series': series,
    'grade': grade,
    'semester': semester,
    'type': type,
  };

  factory TextbookConfig.fromJson(Map<String, dynamic> json) {
    return TextbookConfig(
      publisher: json['publisher'] ?? '外研社',
      series: json['series'] ?? '新版教材',
      grade: json['grade'] ?? '四上',
      semester: json['semester'] ?? '',
      type: json['type'] ?? '课本听力',
    );
  }

  // 默认配置
  static TextbookConfig get defaultConfig => TextbookConfig(
    publisher: '外研社',
    series: '新版教材',
    grade: '四',
    semester: '上',
    type: '课本听力',
  );
}

/// 教材管理服务
class TextbookManager {
  static const String _key = 'current_textbook';

  /// 获取当前教材配置
  static Future<TextbookConfig> getCurrentTextbook() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) {
      return TextbookConfig.defaultConfig;
    }

    try {
      final Map<String, dynamic> map = {};
      // 简单解析（假设格式为 key1:value1,key2:value2）
      final pairs = json.split(',');
      for (final pair in pairs) {
        final kv = pair.split(':');
        if (kv.length == 2) {
          map[kv[0]] = kv[1];
        }
      }
      return TextbookConfig.fromJson(map);
    } catch (e) {
      return TextbookConfig.defaultConfig;
    }
  }

  /// 保存教材配置
  static Future<void> saveTextbook(TextbookConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final json = config.toJson();
    final str = json.entries.map((e) => '${e.key}:${e.value}').join(',');
    await prefs.setString(_key, str);
  }

  /// 获取可用的教材列表（后期可扩展从服务器获取）
  static List<TextbookConfig> getAvailableTextbooks() {
    return [
      TextbookConfig(
        publisher: '外研社',
        series: '新版教材',
        grade: '四',
        semester: '上',
        type: '课本听力',
      ),
      TextbookConfig(
        publisher: '外研社',
        series: '新版教材',
        grade: '四',
        semester: '下',
        type: '课本听力',
      ),
      TextbookConfig(
        publisher: '外研社',
        series: '新版教材',
        grade: '五',
        semester: '上',
        type: '课本听力',
      ),
      TextbookConfig(
        publisher: '外研社',
        series: '新版教材',
        grade: '五',
        semester: '下',
        type: '课本听力',
      ),
      TextbookConfig(
        publisher: '外研社',
        series: '新版教材',
        grade: '六',
        semester: '上',
        type: '课本听力',
      ),
      TextbookConfig(
        publisher: '外研社',
        series: '新版教材',
        grade: '六',
        semester: '下',
        type: '课本听力',
      ),
    ];
  }
}
