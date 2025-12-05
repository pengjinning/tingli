/// 播放历史记录数据模型
class PlayHistory {
  final String fileName; // 文件名
  final String unit; // 单元名称 (U1-U6, ACT)
  final DateTime playTime; // 播放时间
  final int durationSeconds; // 播放时长（秒）

  PlayHistory({
    required this.fileName,
    required this.unit,
    required this.playTime,
    required this.durationSeconds,
  });

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'unit': unit,
    'playTime': playTime.toIso8601String(),
    'durationSeconds': durationSeconds,
  };

  /// 从 JSON 创建
  factory PlayHistory.fromJson(Map<String, dynamic> json) => PlayHistory(
    fileName: json['fileName'] as String,
    unit: json['unit'] as String,
    playTime: DateTime.parse(json['playTime'] as String),
    durationSeconds: json['durationSeconds'] as int,
  );
}
