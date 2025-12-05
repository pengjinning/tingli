import 'package:flutter/material.dart';

// import '../models/media_item.dart';
import '../services/favorite_manager.dart';
import '../services/player_service.dart';
import '../widgets/mini_player.dart';
import 'player_page.dart';

/// 收藏页面
class FavoritePage extends StatefulWidget {
  const FavoritePage({super.key});

  @override
  State<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends State<FavoritePage> {
  Map<String, List<FavoriteItem>> _favoritesByUnit = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _loading = true);
    final favorites = await FavoriteManager.getFavoritesByUnit();
    setState(() {
      _favoritesByUnit = favorites;
      _loading = false;
    });
  }

  /// 直接播放收藏项
  void _playFavorite(FavoriteItem favorite) {
    final playerService = PlayerService();
    final mediaItem = favorite.toMediaItem();

    // 检查是否是当前播放项
    final isCurrentItem =
        playerService.currentItem != null &&
        playerService.currentItem!.name == mediaItem.name &&
        playerService.currentItem!.unit == mediaItem.unit;

    if (isCurrentItem) {
      // 如果是当前播放项，切换播放/暂停状态
      playerService.togglePlayPause();
    } else {
      // 如果是新的项目，打开播放页面开始播放
      _openPlayerPage(favorite);
    }
  }

  /// 打开播放器详情页面
  void _openPlayerPage(FavoriteItem favorite) {
    final mediaItem = favorite.toMediaItem();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          items: [mediaItem],
          initial: mediaItem,
          onFinished: (duration) {},
        ),
      ),
    ).then((_) => _loadFavorites()); // 返回时刷新列表
  }

  /// 取消收藏
  Future<void> _removeFavorite(FavoriteItem favorite) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消收藏'),
        content: Text('确定要取消收藏《${favorite.fileName}》吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await FavoriteManager.removeFavorite(favorite.toMediaItem());
      _loadFavorites();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已取消收藏')));
      }
    }
  }

  IconData _getMediaIcon(String type) {
    switch (type) {
      case 'video':
        return Icons.videocam;
      case 'word':
        return Icons.text_fields;
      default:
        return Icons.audiotrack;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 按照 U1-U6, ACT 的顺序排序
    final unitOrder = ['U1', 'U2', 'U3', 'U4', 'U5', 'U6', 'ACT'];
    final sortedUnits = _favoritesByUnit.keys.toList()
      ..sort((a, b) {
        final aIndex = unitOrder.indexOf(a);
        final bIndex = unitOrder.indexOf(b);
        if (aIndex == -1 && bIndex == -1) return a.compareTo(b);
        if (aIndex == -1) return 1;
        if (bIndex == -1) return -1;
        return aIndex.compareTo(bIndex);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        actions: [
          if (_favoritesByUnit.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空收藏',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('确认清空'),
                    content: const Text('确定要清空所有收藏吗？此操作不可恢复。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text(
                          '清空',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await FavoriteManager.clearFavorites();
                  _loadFavorites();
                }
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _favoritesByUnit.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无收藏',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击首页或播放页的 ❤️ 按钮添加收藏',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: sortedUnits.length,
              itemBuilder: (context, index) {
                final unit = sortedUnits[index];
                final favorites = _favoritesByUnit[unit]!;

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ExpansionTile(
                    leading: const Icon(Icons.folder_special),
                    title: Text('$unit 单元'),
                    subtitle: Text('${favorites.length} 个收藏'),
                    initiallyExpanded: false,
                    children: favorites.map((favorite) {
                      return ListenableBuilder(
                        listenable: PlayerService(),
                        builder: (context, child) {
                          final playerService = PlayerService();
                          final mediaItem = favorite.toMediaItem();
                          final isCurrentlyPlaying =
                              playerService.currentItem != null &&
                              playerService.currentItem!.name ==
                                  mediaItem.name &&
                              playerService.currentItem!.unit == mediaItem.unit;
                          final showPauseIcon =
                              isCurrentlyPlaying && playerService.isPlaying;

                          return ListTile(
                            dense: true,
                            leading: Icon(
                              _getMediaIcon(favorite.type),
                              color: Theme.of(context).primaryColor,
                            ),
                            title: Text(
                              favorite.fileName,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              '${favorite.unit} • ${favorite.addedTime.month}月${favorite.addedTime.day}日',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 播放/暂停按钮
                                IconButton(
                                  icon: Icon(
                                    showPauseIcon
                                        ? Icons.pause_circle_filled
                                        : Icons.play_circle_fill,
                                    size: 28,
                                  ),
                                  color: isCurrentlyPlaying
                                      ? Colors.orange
                                      : Colors.blue,
                                  tooltip: showPauseIcon ? '暂停' : '播放',
                                  onPressed: () => _playFavorite(favorite),
                                ),
                                // 详情按钮
                                IconButton(
                                  icon: const Icon(
                                    Icons.info_outline,
                                    size: 24,
                                  ),
                                  color: Colors.grey[600],
                                  tooltip: '详情',
                                  onPressed: () => _openPlayerPage(favorite),
                                ),
                                // 取消收藏按钮
                                IconButton(
                                  icon: const Icon(Icons.favorite, size: 24),
                                  color: Colors.red,
                                  tooltip: '取消收藏',
                                  onPressed: () => _removeFavorite(favorite),
                                ),
                              ],
                            ),
                          );
                        },
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
