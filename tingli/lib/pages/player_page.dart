import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:better_player/better_player.dart';
import '../widgets/mini_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../models/media_item.dart';
import '../models/subtitle_cue.dart';
import '../services/catalog_service.dart';
import '../services/player_service.dart';
import '../services/lockscreen_media_service.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/scrollable_subtitle_widget.dart';

/// 播放器页面（音频/视频）
class PlayerPage extends StatefulWidget {
  final List<MediaItem> items; // 顺序播放列表（仅音频）
  final MediaItem initial;
  final void Function(Duration played) onFinished;

  const PlayerPage({
    super.key,
    required this.items,
    required this.initial,
    required this.onFinished,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  // 🔥 不再持有局部控制器，使用全局 PlayerService 的控制器
  BetterPlayerController? get _controller => PlayerService().controller;

  int _index = 0;
  // 会话累计时长统计由历史记录统一汇总，移除本地累积字段
  Timer? _sleepTimer;
  int _sleepMinutes = 0; // 0 不启用
  List<SubtitleCue> _cues = const [];
  // 详情页不再提供倍速控制，交由 MiniPlayer 统一处理
  String _currentSubtitle = ''; // 当前字幕文本
  bool _showSubtitle = true; // 是否显示字幕（视频模式）

  // 锁屏媒体控制服务
  final _lockScreenService = LockScreenMediaService();

  // 监听 PlayerService 状态变化
  late final VoidCallback _playerServiceListener;

  @override
  void initState() {
    super.initState();
    _index = widget.items.indexWhere((e) => e.name == widget.initial.name);
    if (_index < 0) _index = 0;
    _initializeLockScreen();

    // 🔥 关键修复：延迟标记详情页作为挂载点
    // 先让 PlayerPage 的第一帧渲染完成（BetterPlayer 已挂载），再移除 MiniPlayer 的挂载点
    final ps = PlayerService();

    // 监听 PlayerService 状态变化，用于更新字幕和锁屏
    _playerServiceListener = () {
      if (!mounted) return;
      // 确保在 hostedInPlayerPage 等全局状态变化时触发重建，及时挂载 BetterPlayer
      setState(() {});
      _updateSubtitleAndLockScreen();
    };
    ps.addListener(_playerServiceListener);

    _setup();

    // 延迟设置挂载标记，确保 PlayerPage 的 BetterPlayer 已经渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ps.setHostedInPlayerPage(true);
      }
    });
  }

  Future<void> _initializeLockScreen() async {
    await _lockScreenService.initialize();
  }

  Future<void> _setup() async {
    final item = widget.items[_index];

    // 🔥 核心修复：使用全局 PlayerService，不再创建局部控制器
    // PlayerPage 只是全局控制器的显示容器，不拥有控制器的生命周期
    final playerService = PlayerService();
    playerService.setPlaylist(widget.items);

    // 使用 playDirect 创建/复用全局控制器
    await playerService.playDirect(item);

    // 等待控制器初始化完成
    await Future.delayed(const Duration(milliseconds: 500));

    // 恢复上次中断位置
    final last = await _readLastPosition(item);
    if (last != null && last > Duration.zero && _controller != null) {
      // 确保 video player 已经初始化
      final isInitialized = _controller!.isVideoInitialized() ?? false;
      if (isInitialized) {
        await _controller!.seekTo(last);
      }
    }

    // 预加载字幕以支持点击跳转
    _loadSubtitlesForClick(item);

    // 触发 UI 刷新
    if (mounted) setState(() {});

    // 更新锁屏媒体信息
    await _updateLockScreenMedia(item);
  }

  Future<void> _updateLockScreenMedia(MediaItem item) async {
    await _lockScreenService.updateMediaItem(
      title: item.name,
      album: item.unit,
      duration: _controller?.videoPlayerController?.value.duration,
    );

    // 更新播放状态
    final isPlaying = _controller?.isPlaying() ?? false;
    final position =
        _controller?.videoPlayerController?.value.position ?? Duration.zero;
    final duration =
        _controller?.videoPlayerController?.value.duration ?? Duration.zero;

    await _lockScreenService.updatePlaybackState(
      playing: isPlaying,
      position: position,
      bufferedPosition: duration,
    );
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();

    // 保存当前播放位置
    final item = widget.items[_index];
    final pos =
        _controller?.videoPlayerController?.value.position ?? Duration.zero;
    if (pos > Duration.zero) {
      _saveLastPosition(item, pos);
    }

    // 锁屏服务保持运行，不需要停止
    // _lockScreenService.stop(); // ❌ 不要调用这个

    final ps = PlayerService();

    // 移除监听器
    ps.removeListener(_playerServiceListener);

    // 🔥 核心修复：确保播放连续性
    // 不销毁全局控制器，只是标记详情页不再挂载，让 MiniPlayer 接管显示。
    ps.setHostedInPlayerPage(false);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    final isAudio = item.type == MediaType.audio || item.type == MediaType.word;

    return Scaffold(
      appBar: AppBar(
        title: Text('${item.unit} · ${item.name}'),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.timer),
            tooltip: '睡前定时',
            onSelected: (m) => _startSleepTimer(m),
            itemBuilder: (c) => const [
              PopupMenuItem(value: 0, child: Text('关闭定时')),
              PopupMenuItem(value: 10, child: Text('10 分钟')),
              PopupMenuItem(value: 20, child: Text('20 分钟')),
              PopupMenuItem(value: 30, child: Text('30 分钟')),
            ],
          ),
          // 视频模式下显示字幕切换按钮
          if (!isAudio && _cues.isNotEmpty)
            IconButton(
              tooltip: _showSubtitle ? '隐藏字幕' : '显示字幕',
              icon: Icon(_showSubtitle ? Icons.subtitles : Icons.subtitles_off),
              onPressed: () {
                setState(() => _showSubtitle = !_showSubtitle);
              },
            ),
          IconButton(
            tooltip: '字幕列表 (点击跳转)',
            icon: const Icon(Icons.list),
            onPressed: _cues.isEmpty ? null : () => _showSubtitleSheet(context),
          ),
        ],
      ),
      body: _controller == null
          ? const Center(child: CircularProgressIndicator())
          : isAudio
          ? _buildAudioPlayerUI(item)
          : _buildVideoPlayerUI(),
      // 在详情页底部也显示全局 MiniPlayer
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  Widget _buildVideoPlayerUI() {
    final playerService = PlayerService();

    return Column(
      children: [
        // 视频播放器（顶部）
        // 为避免与 MiniPlayer 的隐藏 BetterPlayer 重复挂载导致冲突，
        // 仅当本页被标记为挂载点时才渲染 BetterPlayer。
        if (PlayerService().hostedInPlayerPage)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: IgnorePointer(
              ignoring: true,
              child: BetterPlayer(controller: _controller!),
            ),
          ),
        // 字幕显示区域（视频下方）
        if (_showSubtitle && _cues.isNotEmpty)
          Expanded(
            child: ScrollableSubtitleWidget(
              cues: _cues,
              currentPosition: playerService.currentPosition,
              onSeekTo: (position) async {
                await _controller?.seekTo(position);
              },
            ),
          )
        else if (_showSubtitle)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.subtitles_off, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '暂无字幕',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          )
        else
          const Expanded(child: SizedBox()),
      ],
    );
  }

  Widget _buildAudioPlayerUI(MediaItem item) {
    final isPlaying = _controller?.isPlaying() ?? false;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.3),
            Theme.of(context).colorScheme.surface,
          ],
        ),
      ),
      child: Column(
        children: [
          const Spacer(),
          // 音频可视化波形 + 圆形唱片
          Stack(
            alignment: Alignment.center,
            children: [
              // 圆形波纹动画
              CircularWaveform(
                isPlaying: isPlaying,
                color: Theme.of(context).colorScheme.primary,
                size: 240,
              ),
              // 胶片/唱片风格的视觉元素
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primaryContainer,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.music_note,
                    size: 80,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          // 标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              item.name,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${item.unit} · ${item.category}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          // 当前字幕显示
          CurrentSubtitleDisplay(
            subtitle: _currentSubtitle,
            textColor: Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(height: 24),
          // 音频波形柱状图
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: AudioWaveform(
              isPlaying: isPlaying,
              color: Theme.of(context).colorScheme.primary,
              height: 60,
              barCount: 40,
            ),
          ),
          const SizedBox(height: 24),
          // 同上：避免重复挂载。仅当本页是挂载点时才渲染隐藏播放器。
          if (PlayerService().hostedInPlayerPage)
            SizedBox(
              height: 0,
              child: IgnorePointer(
                ignoring: true,
                child: BetterPlayer(controller: _controller!),
              ),
            ),
          // 播放进度显示（只读）
          _buildProgressDisplay(),
          const SizedBox(height: 16),
          // 详情页不再提供控制按钮和倍速选择，改由底部 MiniPlayer 统一控制
          const Spacer(),
        ],
      ),
    );
  }

  /// 构建播放进度显示
  Widget _buildProgressDisplay() {
    final playerService = PlayerService();
    final currentPos = playerService.currentPosition;
    final totalDur = playerService.totalDuration;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            playerService.formatDuration(currentPos),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          // 进度条
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LinearProgressIndicator(
                value: totalDur.inMilliseconds > 0
                    ? currentPos.inMilliseconds / totalDur.inMilliseconds
                    : 0.0,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
                minHeight: 4,
              ),
            ),
          ),
          Text(
            playerService.formatDuration(totalDur),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  // 详情页控制已移除，控制由底部 MiniPlayer 统一处理

  // 上/下一曲控制已移除，交由 MiniPlayer 统一处理

  /// 监听 PlayerService 状态变化，更新字幕和锁屏
  void _updateSubtitleAndLockScreen() async {
    if (!mounted) return;

    final playerService = PlayerService();
    final pos = playerService.currentPosition;
    final dur = playerService.totalDuration;
    final isPlaying = playerService.isPlaying;

    // 更新字幕
    _updateCurrentSubtitle(pos);

    // 更新锁屏播放状态
    try {
      await _lockScreenService.updatePlaybackState(
        playing: isPlaying,
        position: pos,
        bufferedPosition: dur,
      );
    } catch (e) {
      debugPrint('Update lock screen error: $e');
    }

    // 保存播放位置
    if (pos > Duration.zero) {
      await _saveLastPosition(widget.items[_index], pos);
    }
  }

  void _updateCurrentSubtitle(Duration position) {
    if (_cues.isEmpty) return;

    // 找到当前播放位置对应的字幕
    String newSubtitle = '';
    for (int i = 0; i < _cues.length; i++) {
      final cue = _cues[i];
      final nextCue = i < _cues.length - 1 ? _cues[i + 1] : null;

      if (position >= cue.start) {
        if (nextCue == null || position < nextCue.start) {
          newSubtitle = cue.text;
          break;
        }
      }
    }

    if (newSubtitle != _currentSubtitle) {
      setState(() {
        _currentSubtitle = newSubtitle;
      });
      // 同步到全局服务
      PlayerService().updateCurrentSubtitle(newSubtitle);
    }
  }

  // 上/下一曲控制已移除，交由 MiniPlayer 统一处理

  Future<void> _saveLastPosition(MediaItem item, Duration pos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pos_${item.unit}_${item.name}', pos.inMilliseconds);
  }

  Future<Duration?> _readLastPosition(MediaItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('pos_${item.unit}_${item.name}');
    if (ms == null) return null;
    return Duration(milliseconds: ms);
  }

  void _startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepMinutes = minutes;
    if (minutes <= 0) return;
    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      await _controller?.pause();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已到设置的$_sleepMinutes分钟，自动暂停播放')));
      }
    });
  }

  Future<void> _loadSubtitlesForClick(MediaItem item) async {
    try {
      final baseUrl = CatalogService.baseUrl;
      // 优先 VTT
      final vtt = await http
          .get(Uri.parse(item.getVttUrl(baseUrl)))
          .timeout(const Duration(seconds: 5));
      if (vtt.statusCode == 200) {
        final text = utf8.decode(vtt.bodyBytes);
        setState(() => _cues = _parseVtt(text));
        return;
      }
      // 退回 SRT
      final srt = await http
          .get(Uri.parse(item.getSrtUrl(baseUrl)))
          .timeout(const Duration(seconds: 5));
      if (srt.statusCode == 200) {
        final text = utf8.decode(srt.bodyBytes);
        setState(() => _cues = _parseSrt(text));
      }
    } catch (_) {
      // ignore
    }
  }

  void _showSubtitleSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) {
        return SafeArea(
          child: _cues.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('未加载到字幕'),
                )
              : ListView.separated(
                  itemCount: _cues.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final cue = _cues[i];
                    return ListTile(
                      dense: true,
                      title: Text(cue.text),
                      subtitle: Text(_fmtDuration(cue.start)),
                      onTap: () async {
                        Navigator.pop(context);
                        await _controller?.seekTo(cue.start);
                      },
                    );
                  },
                ),
        );
      },
    );
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return [
      if (h > 0) h.toString().padLeft(2, '0'),
      m.toString().padLeft(2, '0'),
      s.toString().padLeft(2, '0'),
    ].join(':');
  }

  List<SubtitleCue> _parseVtt(String text) {
    final lines = const LineSplitter().convert(text);
    final cues = <SubtitleCue>[];
    Duration? start;
    final buffer = StringBuffer();
    for (final raw in lines) {
      final l = raw.trimRight();
      if (l.contains('-->')) {
        if (start != null && buffer.isNotEmpty) {
          cues.add(SubtitleCue(start, buffer.toString().trim()));
          buffer.clear();
        }
        final parts = l.split('-->');
        start = _parseTimestamp(parts.first.trim());
      } else if (l.isEmpty) {
        if (start != null && buffer.isNotEmpty) {
          cues.add(SubtitleCue(start, buffer.toString().trim()));
          start = null;
          buffer.clear();
        }
      } else if (!l.startsWith('WEBVTT')) {
        buffer.writeln(l);
      }
    }
    if (start != null && buffer.isNotEmpty) {
      cues.add(SubtitleCue(start, buffer.toString().trim()));
    }
    return cues;
  }

  List<SubtitleCue> _parseSrt(String text) {
    final lines = const LineSplitter().convert(text);
    final cues = <SubtitleCue>[];
    Duration? start;
    final buffer = StringBuffer();
    for (final raw in lines) {
      final l = raw.trimRight();
      if (RegExp(r'^\d+\s*$').hasMatch(l)) {
        continue; // index 行
      } else if (l.contains('-->')) {
        if (start != null && buffer.isNotEmpty) {
          cues.add(SubtitleCue(start, buffer.toString().trim()));
          buffer.clear();
        }
        final parts = l.split('-->');
        start = _parseTimestamp(parts.first.trim());
      } else if (l.isEmpty) {
        if (start != null && buffer.isNotEmpty) {
          cues.add(SubtitleCue(start, buffer.toString().trim()));
          start = null;
          buffer.clear();
        }
      } else {
        buffer.writeln(l);
      }
    }
    if (start != null && buffer.isNotEmpty) {
      cues.add(SubtitleCue(start, buffer.toString().trim()));
    }
    return cues;
  }

  Duration _parseTimestamp(String s) {
    final cleaned = s.replaceAll(',', '.');
    final parts = cleaned.split(':');
    int h = 0, m = 0;
    double sec = 0;
    if (parts.length == 3) {
      h = int.tryParse(parts[0]) ?? 0;
      m = int.tryParse(parts[1]) ?? 0;
      sec = double.tryParse(parts[2]) ?? 0;
    } else if (parts.length == 2) {
      m = int.tryParse(parts[0]) ?? 0;
      sec = double.tryParse(parts[1]) ?? 0;
    }
    final ms = (sec * 1000).round();
    return Duration(hours: h, minutes: m, milliseconds: ms);
  }
}
