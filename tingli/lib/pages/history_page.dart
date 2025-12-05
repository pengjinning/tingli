import 'package:flutter/material.dart';

import '../models/play_history.dart';
import '../models/media_item.dart';
import '../services/history_manager.dart';
import '../services/player_service.dart';
import '../widgets/mini_player.dart';
import 'player_page.dart';

/// 播放历史记录页面
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  Map<String, List<PlayHistory>> _historyByDate = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final history = await HistoryManager.getHistoryByDate();
    setState(() {
      _historyByDate = history;
      _loading = false;
    });
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes分$secs秒';
  }

  /// 从播放历史创建 MediaItem
  MediaItem _createMediaItemFromHistory(PlayHistory history) {
    // 根据文件名推断类型和分类
    final fileName = history.fileName.toLowerCase();
    MediaType type;
    String category;

    if (fileName.contains('.mp4')) {
      type = MediaType.video;
      category = 'kewen-video';
    } else if (fileName.contains('word') || fileName.contains('单词')) {
      type = MediaType.word;
      category = 'word';
    } else {
      type = MediaType.audio;
      category = 'kewen-audio';
    }

    return MediaItem(
      name: history.fileName,
      category: category,
      unit: history.unit,
      type: type,
    );
  }

  /// 直接播放历史记录
  void _playHistory(PlayHistory history) {
    final playerService = PlayerService();
    final mediaItem = _createMediaItemFromHistory(history);

    // 检查是否是当前播放项
    final isCurrentItem =
        playerService.currentItem != null &&
        playerService.currentItem!.name == mediaItem.name &&
        playerService.currentItem!.unit == mediaItem.unit;

    if (isCurrentItem) {
      // 如果是当前播放项，切换播放/暂停状态
      playerService.togglePlayPause();
    } else {
      // 与首页一致：先下载（如需）再直接播放
      playerService.ensureCachedAndPlay(mediaItem);
    }
  }

  /// 打开播放器详情页面
  void _openPlayerPage(PlayHistory history) {
    final mediaItem = _createMediaItemFromHistory(history);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          items: [mediaItem], // 只播放这一个文件
          initial: mediaItem,
          onFinished: (duration) {
            // 播放结束回调
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('播放历史'),
        actions: [
          if (_historyByDate.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空历史',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('确认清空'),
                    content: const Text('确定要清空所有播放历史吗？此操作不可恢复。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await HistoryManager.clearHistory();
                  _loadHistory();
                }
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _historyByDate.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '暂无播放历史',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _historyByDate.length,
              itemBuilder: (context, index) {
                final dateKey = _historyByDate.keys.elementAt(index);
                final histories = _historyByDate[dateKey]!;
                final totalSeconds = histories.fold<int>(
                  0,
                  (sum, h) => sum + h.durationSeconds,
                );
                final totalMinutes = (totalSeconds / 60).floor();

                // 解析日期
                final date = DateTime.parse(dateKey);
                final now = DateTime.now();
                final isToday =
                    date.year == now.year &&
                    date.month == now.month &&
                    date.day == now.day;
                final dateLabel = isToday
                    ? '今天'
                    : '${date.year}年${date.month}月${date.day}日';

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ExpansionTile(
                    leading: const Icon(Icons.calendar_today),
                    title: Text(dateLabel),
                    subtitle: Text(
                      '播放 ${histories.length} 次，共 $totalMinutes 分钟',
                    ),
                    children: histories.map((history) {
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.audiotrack,
                          color: Theme.of(context).primaryColor,
                        ),
                        title: Text(
                          history.fileName,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          '${history.unit} • ${history.playTime.hour.toString().padLeft(2, '0')}:${history.playTime.minute.toString().padLeft(2, '0')} • ${_formatDuration(history.durationSeconds)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 播放按钮
                            ListenableBuilder(
                              listenable: PlayerService(),
                              builder: (context, _) {
                                final ps = PlayerService();
                                if (ps.isDownloadingFor(
                                  _createMediaItemFromHistory(history),
                                )) {
                                  return const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  );
                                }
                                return IconButton(
                                  icon: const Icon(
                                    Icons.play_circle_fill,
                                    size: 28,
                                  ),
                                  color: Colors.blue,
                                  tooltip: '播放',
                                  onPressed: () => _playHistory(history),
                                );
                              },
                            ),
                            // 详情按钮
                            IconButton(
                              icon: const Icon(Icons.info_outline, size: 24),
                              color: Colors.grey[600],
                              tooltip: '详情',
                              onPressed: () => _openPlayerPage(history),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}
