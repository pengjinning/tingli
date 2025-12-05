import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_item.dart';
import '../services/history_manager.dart';
import '../services/player_service.dart';
import '../widgets/mini_player.dart';
// 详情入口由 MiniPlayer 提供，此处不再直接引用 PlayerPage
import 'settings_page.dart';
// import 'favorite_page.dart'; // 收藏功能已隐藏
// import 'subtitle_search_page.dart'; // 字幕搜索已隐藏

/// 媒体浏览页面（主页）
class MediaBrowserPage extends StatefulWidget {
  final Map<String, List<MediaItem>> unitItems;

  const MediaBrowserPage({super.key, required this.unitItems});

  @override
  State<MediaBrowserPage> createState() => _MediaBrowserPageState();
}

class _MediaBrowserPageState extends State<MediaBrowserPage> {
  String search = '';
  String filter = 'ALL'; // ALL, U1..U6, ACT
  int _dailyGoalMinutes = 20; // 设置页可配
  int _todayMinutes = 0; // 今日已播放时长
  bool _isSearching = false; // 搜索框是否展开
  final TextEditingController _searchController = TextEditingController();
  Timer? _todayTimer;

  @override
  void initState() {
    super.initState();
    _init();
    // 每15秒刷新一次今日播放时长，实时反映播放增加
    _todayTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshTodayMinutes();
    });
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _dailyGoalMinutes = prefs.getInt('dailyGoalMinutes') ?? 20;
    _todayMinutes = await HistoryManager.getTodayMinutes();
    // 恢复用户上次选择的单元过滤器
    filter = prefs.getString('unitFilter') ?? 'ALL';
    setState(() {});
  }

  Future<void> _refreshTodayMinutes() async {
    final minutes = await HistoryManager.getTodayMinutes();
    setState(() => _todayMinutes = minutes);
  }

  @override
  void dispose() {
    _todayTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final units = ['U1', 'U2', 'U3', 'U4', 'U5', 'U6'];
    final filteredUnits = filter == 'ALL'
        ? units
        : units.where((u) => u == filter).toList();

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: '搜索文件名、单元或类型…',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (v) =>
                    setState(() => search = v.trim().toLowerCase()),
              )
            : const Text('🎓 睡前听力'),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  search = '';
                  _isSearching = false;
                });
              },
              tooltip: '清除搜索',
            )
          else ...[
            // 搜索按钮 - 已隐藏
            // IconButton(
            //   icon: const Icon(Icons.search),
            //   onPressed: () {
            //     setState(() => _isSearching = true);
            //   },
            //   tooltip: '搜索文件',
            // ),
            // 字幕搜索按钮 - 已隐藏
            // IconButton(
            //   icon: const Icon(Icons.subtitles),
            //   onPressed: () {
            //     Navigator.push(
            //       context,
            //       MaterialPageRoute(
            //         builder: (_) =>
            //             SubtitleSearchPage(unitItems: widget.unitItems),
            //       ),
            //     );
            //   },
            //   tooltip: '搜索字幕',
            // ),
            // 仅保留一个设置按钮，其它入口迁移到设置页
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '设置',
              onPressed: () async {
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SettingsPage(initialGoal: _dailyGoalMinutes),
                  ),
                );
                if (res is int) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('dailyGoalMinutes', res);
                  setState(() => _dailyGoalMinutes = res);
                }
                _refreshTodayMinutes();
              },
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // 今日播放统计卡片
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  Theme.of(context).primaryColor.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _todayMinutes >= _dailyGoalMinutes
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: _todayMinutes >= _dailyGoalMinutes
                          ? Colors.green
                          : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '今日播放',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$_todayMinutes / $_dailyGoalMinutes 分钟',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _todayMinutes / _dailyGoalMinutes,
                    minHeight: 8,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _todayMinutes >= _dailyGoalMinutes
                          ? Colors.green
                          : Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                if (_todayMinutes >= _dailyGoalMinutes)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '🎉 太棒了！已达成今日目标',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                else if (_todayMinutes > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '还差 ${_dailyGoalMinutes - _todayMinutes} 分钟达成目标，加油！',
                      style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _chip('ALL', '全部'),
                for (final u in ['U1', 'U2', 'U3', 'U4', 'U5', 'U6'])
                  _chip(u, u),
                _chip('ACT', 'Act it out'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // 普通单元
                for (final unit in filteredUnits) _buildUnitSection(unit),
                // Act it out 区域（仅在 ALL 或 ACT 过滤时显示）
                if (filter == 'ALL' || filter == 'ACT') _buildActSection(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  Widget _chip(String key, String label) {
    final selected = filter == key;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) async {
          setState(() => filter = key);
          // 保存用户选择到本地
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('unitFilter', key);
        },
      ),
    );
  }

  Widget _buildUnitSection(String unit) {
    final items = widget.unitItems[unit] ?? [];
    final matched = items
        .where((e) => e.name.toLowerCase().contains(search))
        .toList();
    if (matched.isEmpty && search.isNotEmpty) return const SizedBox.shrink();

    final word = matched.where((e) => e.type == MediaType.word).toList();
    final audios = matched.where((e) => e.type == MediaType.audio).toList();
    final videos = matched.where((e) => e.type == MediaType.video).toList();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Text('📖', style: TextStyle(fontSize: 22)),
              title: Text(
                '$unit 单元',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (word.isNotEmpty) _buildCategory('📝 单词发音', word),
            if (audios.isNotEmpty) _buildCategory('🎵 课文音频', audios),
            if (videos.isNotEmpty) _buildCategory('🎬 课文视频', videos),
          ],
        ),
      ),
    );
  }

  Widget _buildActSection() {
    final actItems = (widget.unitItems['ACT'] ?? [])
        .where((e) => e.name.toLowerCase().contains(search))
        .toList();
    if (actItems.isEmpty && search.isNotEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              leading: Text('🎭', style: TextStyle(fontSize: 22)),
              title: Text(
                'Act it out',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            _buildCategory('🎵 表演音频', actItems),
          ],
        ),
      ),
    );
  }

  Widget _buildCategory(String title, List<MediaItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        ...items.map(_buildItemTile),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildItemTile(MediaItem item) {
    final isVideo = item.type == MediaType.video;
    final leading = isVideo
        ? const Text('🎬', style: TextStyle(fontSize: 18))
        : const Text('🎵', style: TextStyle(fontSize: 18));

    return ListenableBuilder(
      listenable: PlayerService(),
      builder: (context, child) {
        final playerService = PlayerService();
        // 检查当前item是否正在播放
        // 是否当前播放仅用于渲染高亮时可考虑使用，此处移除不用
        // 控制由 MiniPlayer 统一处理，不再在列表尾部展示播放/暂停按钮

        final downloading = playerService.isDownloadingFor(item);
        final progress = playerService.progressOf(item);

        return ListTile(
          leading: leading,
          title: Text(item.name),
          subtitle: downloading
              ? Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: progress > 0 && progress < 1 ? progress : null,
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                    ),
                  ],
                )
              : Text('${item.unit} · ${item.category}'),
          // 去掉尾部播放/详情按钮，统一由底部 MiniPlayer 控制。
          // 下载中时在 subtitle 后显示一个轻量的进度指示。
          trailing: downloading
              ? SizedBox(
                  width: 32,
                  height: 32,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 3,
                        value: progress > 0 && progress < 1 ? progress : null,
                      ),
                      Text(
                        '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                )
              : null,
          // 点击列表项直接播放
          onTap: () => _playDirectly(item),
        );
      },
    );
  }

  /// 直接播放（不进入详情页）
  Future<void> _playDirectly(MediaItem item) async {
    final playerService = PlayerService();

    // 更新播放列表（视频仅播放当前项；音频/单词顺播）
    final items = item.type == MediaType.video
        ? [item]
        : _flatListInOrder(startFrom: item);
    playerService.setPlaylist(items);

    // 如果点击的是当前播放项，则切换播放/暂停；否则直接开始播放（不跳转）
    final isCurrentItem =
        playerService.currentItem != null &&
        playerService.currentItem!.name == item.name &&
        playerService.currentItem!.unit == item.unit &&
        playerService.currentItem!.category == item.category;

    if (isCurrentItem) {
      await playerService.togglePlayPause();
    } else {
      // 首次点击时先下载缓存（若需要），并显示进度
      await playerService.ensureCachedAndPlay(item);
    }

    if (mounted) setState(() {});
  }

  // 列表不再提供“详情”入口，若需进入详情可通过 MiniPlayer 点击进入

  List<MediaItem> _flatListInOrder({MediaItem? startFrom}) {
    final order = ['U1', 'U2', 'U3', 'U4', 'U5', 'U6', 'ACT'];
    final all = <MediaItem>[];
    for (final u in order) {
      final list = widget.unitItems[u] ?? [];
      all.addAll(list.where((e) => e.type != MediaType.video)); // 仅音频顺播
    }
    if (startFrom == null) return all;
    final idx = all.indexWhere(
      (e) => e.unit == startFrom.unit && e.name == startFrom.name,
    );
    if (idx <= 0) return all;
    return [...all.sublist(idx), ...all.sublist(0, idx)];
  }

  // 播放完成事件由 PlayerPage 负责，这里无需处理
}
