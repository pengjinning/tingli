import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:better_player/better_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../models/media_item.dart';
import '../models/subtitle_cue.dart';
import '../services/catalog_service.dart';
import '../services/player_service.dart';
import '../services/lockscreen_media_service.dart';
import '../widgets/scrollable_subtitle_widget.dart';
import '../widgets/mini_player.dart';

/// 课文视频详情页面：顶部视频 + 下方字幕列表
class PlayerPageVideo extends StatefulWidget {
  final List<MediaItem> items;
  final MediaItem initial;

  const PlayerPageVideo({
    super.key,
    required this.items,
    required this.initial,
  });

  @override
  State<PlayerPageVideo> createState() => _PlayerPageVideoState();
}

class _PlayerPageVideoState extends State<PlayerPageVideo> {
  BetterPlayerController? get _controller => PlayerService().controller;
  int _index = 0;
  final _lockScreen = LockScreenMediaService();
  late final VoidCallback _listener;
  List<SubtitleCue> _cues = const [];
  bool _showSubtitle = true;

  @override
  void initState() {
    super.initState();
    _index = widget.items.indexWhere((e) => e.name == widget.initial.name);
    if (_index < 0) _index = 0;
    _listener = () {
      if (mounted) setState(() {});
    };
    PlayerService().addListener(_listener);
    _setup();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PlayerService().setHostedInPlayerPage(true); // 兼容旧逻辑（后续可移除）
        PlayerService().setUiMode(PlayerUiMode.expandedVideo);
      }
    });
  }

  Future<void> _setup() async {
    await _lockScreen.initialize();
    final item = widget.items[_index];
    final ps = PlayerService();
    ps.setPlaylist(widget.items);
    await ps.playDirect(item);
    await Future.delayed(const Duration(milliseconds: 200));
    final last = await _readLastPosition(item);
    if (last != null && (_controller?.isVideoInitialized() ?? false)) {
      await _controller!.seekTo(last);
    }
    await _loadSubtitles(item);
    if (mounted) setState(() {});
  }

  Future<void> _loadSubtitles(MediaItem item) async {
    try {
      final baseUrl = CatalogService.baseUrl;
      final vtt = await http
          .get(Uri.parse(item.getVttUrl(baseUrl)))
          .timeout(const Duration(seconds: 5));
      if (vtt.statusCode == 200) {
        final text = utf8.decode(vtt.bodyBytes);
        setState(() => _cues = _parseVtt(text));
        return;
      }
      final srt = await http
          .get(Uri.parse(item.getSrtUrl(baseUrl)))
          .timeout(const Duration(seconds: 5));
      if (srt.statusCode == 200) {
        final text = utf8.decode(srt.bodyBytes);
        setState(() => _cues = _parseSrt(text));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    final item = widget.items[_index];
    final pos =
        _controller?.videoPlayerController?.value.position ?? Duration.zero;
    if (pos > Duration.zero) {
      _saveLastPosition(item, pos);
    }
    final ps = PlayerService();
    ps.removeListener(_listener);
    ps.setHostedInPlayerPage(false);
    // 先切换到 mini 模式以移除顶部 Overlay，再停止视频播放并隐藏 MiniPlayer
    ps.setUiMode(PlayerUiMode.mini);
    if (ps.currentItem?.type == MediaType.video) {
      ps.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('${item.unit} · ${item.name}'),
        actions: [
          if (_cues.isNotEmpty)
            IconButton(
              tooltip: _showSubtitle ? '隐藏字幕' : '显示字幕',
              icon: Icon(_showSubtitle ? Icons.subtitles : Icons.subtitles_off),
              onPressed: () => setState(() => _showSubtitle = !_showSubtitle),
            ),
        ],
      ),
      body: Column(
        children: [
          // 顶部区域由 MiniPlayer 展开占据，此处占位防止下方字幕立即顶上；
          // 也可以使用 Sliver/CustomScrollView 更灵活，这里简化处理。
          SizedBox(height: MediaQuery.of(context).size.width / (16 / 9)),
          if (_showSubtitle)
            Expanded(
              child: _cues.isEmpty
                  ? Center(
                      child: Text(
                        '暂无字幕',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : ScrollableSubtitleWidget(
                      cues: _cues,
                      currentPosition: PlayerService().currentPosition,
                      onSeekTo: (p) async => _controller?.seekTo(p),
                    ),
            )
          else
            const Expanded(child: SizedBox()),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

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
        continue;
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
    return Duration(hours: h, minutes: m, milliseconds: (sec * 1000).round());
  }
}
