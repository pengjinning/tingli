import 'package:flutter/material.dart';
import 'package:better_player/better_player.dart';
import '../services/player_service.dart';
import '../services/lockscreen_media_service.dart';
import '../models/media_item.dart';
import '../pages/player_page_word.dart';
import '../pages/player_page_audio.dart';
import '../pages/player_page_video.dart';

/// 迷你播放器组件
/// 显示在应用底部，展示当前播放状态
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer>
    with SingleTickerProviderStateMixin {
  // 确保全局仅有一个 MiniPlayer 实例负责挂载隐藏 BetterPlayer，避免路由切换时卸载导致控制器被处置
  static Object? _mountOwner;
  final Object _token = Object();
  bool get _amOwner => identical(_mountOwner, _token);

  @override
  void initState() {
    super.initState();
    // 首个出现的 MiniPlayer 占用挂载权
    _mountOwner ??= _token;
  }

  @override
  void dispose() {
    // 若当前实例持有挂载权，释放给后续出现的 MiniPlayer（通常是根页面不会被销毁）
    if (_amOwner) {
      _mountOwner = null;
    }
    // 确保销毁时移除任何挂着的顶部视频 Overlay
    _removeVideoOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 确保锁屏媒体服务已初始化（多次调用会被内部忽略）
    // 不需要等待
    LockScreenMediaService().initialize();

    final ps = PlayerService();
    return ValueListenableBuilder<PlayerUiMode>(
      valueListenable: ps.uiMode,
      builder: (context, mode, _) {
        return ListenableBuilder(
          listenable: ps,
          builder: (context, child) {
            if (!ps.hasCurrentItem) return const SizedBox.shrink();
            final item = ps.currentItem!;
            return ValueListenableBuilder<bool>(
              valueListenable: ps.viewMountReady,
              builder: (context, ready, __) {
                final progress = ps.totalDuration.inMilliseconds > 0
                    ? ps.currentPosition.inMilliseconds /
                          ps.totalDuration.inMilliseconds
                    : 0.0;

                final mediaQuery = MediaQuery.of(context);
                final isExpanded =
                    mode == PlayerUiMode.expandedVideo &&
                    item.type == MediaType.video;
                final videoHeight = mediaQuery.size.width / (16 / 9);
                // 进度条(2) + 图标区(48) + 垂直内边距(16) + 底部安全区
                final baseBarHeight = 2 + 48 + 16 + mediaQuery.padding.bottom;

                // 展开模式下通过 Overlay 呈现视频，不再增加底部栏高度
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _updateVideoOverlay(isExpanded, videoHeight, ps);
                });

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOut,
                  width: double.infinity,
                  constraints: BoxConstraints(minHeight: baseBarHeight),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    left: false,
                    right: false,
                    bottom: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 仅在非视频或展开时挂载隐藏表面；视频在首页折叠时不挂载任何 BetterPlayer
                        if (_amOwner &&
                            ps.controller != null &&
                            ready &&
                            ps.hasCurrentItem &&
                            (item.type != MediaType.video || isExpanded))
                          _buildPlayerSurface(ps, isExpanded),
                        // 进度条
                        LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.grey[800],
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.blue,
                          ),
                          minHeight: 2,
                        ),
                        _buildControlBar(context, ps, item, isExpanded),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // 已移除固定高度，改为按内容 + 安全区动态计算

  Widget _buildPlayerSurface(PlayerService ps, bool isExpanded) {
    if (!isExpanded) {
      // 折叠状态：保持 BetterPlayer 存活但不参与布局
      return SizedBox(
        height: 0,
        width: 0,
        child: Stack(
          children: [
            Offstage(
              offstage: true,
              child: BetterPlayer(
                key: PlayerService.globalBetterPlayerKey,
                controller: ps.controller!,
              ),
            ),
            _AutoResumeWhenTopRoute(
              shouldBePlaying: ps.isPlaying,
              controller: ps.controller!,
            ),
          ],
        ),
      );
    }
    // 展开状态：由 Overlay 呈现，此处不占位
    return const SizedBox.shrink();
  }

  OverlayEntry? _videoOverlay;

  void _updateVideoOverlay(
    bool isExpanded,
    double videoHeight,
    PlayerService ps,
  ) {
    try {
      if (!mounted) return;
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      // 仅在控制器就绪且当前实例持有挂载权时才允许插入 Overlay
      if (_amOwner &&
          isExpanded &&
          ps.controller != null &&
          ps.viewMountReady.value) {
        if (_videoOverlay == null && overlay != null) {
          _videoOverlay = OverlayEntry(
            builder: (ctx) {
              final mq = MediaQuery.of(ctx);
              final double topOffset = mq.padding.top + kToolbarHeight;
              return Positioned(
                top: topOffset,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: videoHeight,
                  child: Stack(
                    children: [
                      BetterPlayer(
                        key: PlayerService.globalBetterPlayerKey,
                        controller: ps.controller!,
                      ),
                      _AutoResumeWhenTopRoute(
                        shouldBePlaying: ps.isPlaying,
                        controller: ps.controller!,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
          overlay.insert(_videoOverlay!);
        }
      } else {
        // 折叠或控制器缺失，移除 Overlay
        _removeVideoOverlay();
      }
    } catch (_) {
      // 忽略 overlay 操作异常
    }
  }

  void _removeVideoOverlay() {
    try {
      _videoOverlay?.remove();
    } catch (_) {}
    _videoOverlay = null;
  }

  Widget _buildControlBar(
    BuildContext context,
    PlayerService ps,
    MediaItem item,
    bool isExpanded,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openPlayerPage(context, item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (!isExpanded)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getMediaIcon(item.type.name),
                    color: Colors.blue,
                    size: 24,
                  ),
                ),
              if (!isExpanded) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getDisplayTitle(item),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ps.currentSubtitle.isNotEmpty
                          ? ps.currentSubtitle
                          : '${ps.formatDuration(ps.currentPosition)} / ${ps.formatDuration(ps.totalDuration)}',
                      style: TextStyle(
                        color: ps.currentSubtitle.isNotEmpty
                            ? Colors.blue[300]
                            : Colors.grey[400],
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '单曲循环',
                    icon: Icon(ps.repeatOne ? Icons.repeat_one : Icons.repeat),
                    color: ps.repeatOne ? Colors.orange : Colors.white,
                    iconSize: 24,
                    onPressed: () async => ps.toggleRepeatOne(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.replay_10),
                    color: Colors.white,
                    iconSize: 28,
                    onPressed: () => ps.seekBackward(),
                  ),
                  IconButton(
                    icon: Icon(
                      ps.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                    ),
                    color: Colors.blue,
                    iconSize: 40,
                    onPressed: () async => ps.togglePlayPause(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.forward_10),
                    color: Colors.white,
                    iconSize: 28,
                    onPressed: () => ps.seekForward(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开播放器详情页面
  void _openPlayerPage(BuildContext context, MediaItem item) {
    final playerService = PlayerService();

    final List<MediaItem> items = playerService.playlist.isNotEmpty
        ? playerService.playlist
        : <MediaItem>[item];

    final Widget page;
    switch (item.type) {
      case MediaType.word:
        page = PlayerPageWord(items: items, initial: item);
        break;
      case MediaType.audio:
        page = PlayerPageAudio(items: items, initial: item);
        break;
      case MediaType.video:
        page = PlayerPageVideo(items: items, initial: item);
        break;
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  /// 获取媒体类型对应的图标
  IconData _getMediaIcon(String typeName) {
    switch (typeName) {
      case 'audio':
        return Icons.audiotrack;
      case 'video':
        return Icons.videocam;
      case 'word':
        return Icons.text_fields;
      default:
        return Icons.music_note;
    }
  }

  /// 获取显示标题
  String _getDisplayTitle(dynamic item) {
    final name = item.name as String;
    // 移除扩展名
    return name.replaceAll(RegExp(r'\.(mp3|mp4)$', caseSensitive: false), '');
  }
}

/// 顶层路由时自动恢复播放的小部件（无 UI，仅产生副作用）
class _AutoResumeWhenTopRoute extends StatefulWidget {
  final bool shouldBePlaying;
  final BetterPlayerController controller;

  const _AutoResumeWhenTopRoute({
    required this.shouldBePlaying,
    required this.controller,
  });

  @override
  State<_AutoResumeWhenTopRoute> createState() =>
      _AutoResumeWhenTopRouteState();
}

class _AutoResumeWhenTopRouteState extends State<_AutoResumeWhenTopRoute> {
  @override
  void initState() {
    super.initState();
    // 使用下一帧检查与恢复，避免在 build 阶段直接副作用
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePlaying());
  }

  @override
  void didUpdateWidget(covariant _AutoResumeWhenTopRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shouldBePlaying != widget.shouldBePlaying ||
        oldWidget.controller != widget.controller) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePlaying());
    }
  }

  Future<void> _ensurePlaying() async {
    if (!mounted) return;
    try {
      // 仅当逻辑上应处于播放状态但控制器实际未播放时，才尝试恢复
      final actuallyPlaying = widget.controller.isPlaying() ?? false;
      if (widget.shouldBePlaying && !actuallyPlaying) {
        await widget.controller.play();
        // 避免静音情况
        try {
          await widget.controller.setVolume(1.0);
        } catch (_) {}
        PlayerService().updatePlayingState(true);
      }
    } catch (_) {
      // 忽略恢复失败
    }
  }

  @override
  Widget build(BuildContext context) {
    // 不渲染任何内容
    return const SizedBox.shrink();
  }
}
