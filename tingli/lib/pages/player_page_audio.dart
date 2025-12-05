import 'dart:async';

import 'package:flutter/material.dart';
import 'package:better_player/better_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_item.dart';
import '../models/subtitle_cue.dart';
import '../services/catalog_service.dart';
import '../services/player_service.dart';
import '../services/lockscreen_media_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/scrollable_subtitle_widget.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// 课文音频详情页面：中间显示字幕
class PlayerPageAudio extends StatefulWidget {
  final List<MediaItem> items;
  final MediaItem initial;

  const PlayerPageAudio({
    super.key,
    required this.items,
    required this.initial,
  });

  @override
  State<PlayerPageAudio> createState() => _PlayerPageAudioState();
}

class _PlayerPageAudioState extends State<PlayerPageAudio> {
  BetterPlayerController? get _controller => PlayerService().controller;
  int _index = 0;
  final _lockScreen = LockScreenMediaService();
  late final VoidCallback _listener;
  List<SubtitleCue> _cues = const [];

  @override
  void initState() {
    super.initState();
    _index = widget.items.indexWhere((e) => e.name == widget.initial.name);
    if (_index < 0) _index = 0;

    _listener = () {
      if (!mounted) return;
      setState(() {});
      _updateLockscreen();
    };
    PlayerService().addListener(_listener);

    _setup();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PlayerService().setHostedInPlayerPage(true);
    });
  }

  Future<void> _setup() async {
    await _lockScreen.initialize();
    final item = widget.items[_index];
    final ps = PlayerService();
    ps.setPlaylist(widget.items);
    await ps.playDirect(item);

    // 恢复位置
    await Future.delayed(const Duration(milliseconds: 200));
    final last = await _readLastPosition(item);
    if (last != null && (_controller?.isVideoInitialized() ?? false)) {
      await _controller!.seekTo(last);
    }

    // 加载字幕
    await _loadSubtitles(item);
    await _updateLockscreen();
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
    PlayerService().removeListener(_listener);
    PlayerService().setHostedInPlayerPage(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    return Scaffold(
      appBar: AppBar(title: Text('${item.unit} · ${item.name}')),
      body: Column(
        children: [
          // 隐藏挂载点
          // （已移除本地 BetterPlayer 挂载，统一由 MiniPlayer 持续挂载）
          // 字幕区域
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
          ),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  Future<void> _updateLockscreen() async {
    final item = widget.items[_index];
    await _lockScreen.updateMediaItem(
      title: item.name,
      album: item.unit,
      duration: _controller?.videoPlayerController?.value.duration,
    );
    await _lockScreen.updatePlaybackState(
      playing: _controller?.isPlaying() ?? false,
      position:
          _controller?.videoPlayerController?.value.position ?? Duration.zero,
      bufferedPosition:
          _controller?.videoPlayerController?.value.duration ?? Duration.zero,
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
    return Duration(hours: h, minutes: m, milliseconds: (sec * 1000).round());
  }
}
