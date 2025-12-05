import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:async';
import 'package:better_player/better_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/media_item.dart';
import '../models/play_history.dart';
import 'history_manager.dart';
import 'catalog_service.dart';
import 'lockscreen_media_service.dart';
import 'cache_service.dart';

/// 全局播放器服务 - 单例模式
/// 用于在整个应用中共享播放状态
enum PlayerUiMode { mini, expandedVideo }

class PlayerService extends ChangeNotifier {
  static final PlayerService _instance = PlayerService._internal();
  factory PlayerService() => _instance;
  PlayerService._internal();

  // 全局 BetterPlayer 挂载用 key，确保在不同页面之间移动时不被 dispose
  static final GlobalKey globalBetterPlayerKey = GlobalKey(
    debugLabel: 'global_better_player',
  );

  // 播放器界面显示模式（用于单实例播放器在 Mini 与 视频详情页放大之间切换尺寸）
  final ValueNotifier<PlayerUiMode> uiMode = ValueNotifier<PlayerUiMode>(
    PlayerUiMode.mini,
  );

  // 指示 BetterPlayer 视图何时可安全挂载（控制器初始化/切换数据源期间应为 false）
  final ValueNotifier<bool> viewMountReady = ValueNotifier<bool>(false);

  void setUiMode(PlayerUiMode mode) {
    if (uiMode.value == mode) return;
    uiMode.value = mode;
  }

  // 当前播放的媒体项
  MediaItem? _currentItem;
  MediaItem? get currentItem => _currentItem;

  // 播放器控制器
  BetterPlayerController? _controller;
  BetterPlayerController? get controller => _controller;

  // 控制器当前是否被详情页挂载（为避免重复挂载）
  bool _hostedInPlayerPage = false;
  bool get hostedInPlayerPage => _hostedInPlayerPage;
  void setHostedInPlayerPage(bool hosted) {
    if (_hostedInPlayerPage == hosted) return;

    // 如果当前处于 frame 锁定阶段（如 dispose 过程中 finalizeTree），延迟到下一帧再通知，避免 setState locked 异常
    final phase = SchedulerBinding.instance.schedulerPhase;
    final isLockedPhase =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.postFrameCallbacks;
    if (isLockedPhase) {
      // 使用 addPostFrameCallback 确保在当前 frame 完成后再执行
      SchedulerBinding.instance.addPostFrameCallback((_) {
        // 二次校验，期间可能已经被设置
        if (_hostedInPlayerPage != hosted) {
          _hostedInPlayerPage = hosted;
          // 使用 microtask 再包一层，确保不与同一帧内其它 dispose 冲突
          scheduleMicrotask(() {
            try {
              notifyListeners();
            } catch (_) {}
          });
        }
      });
    } else {
      _hostedInPlayerPage = hosted;
      notifyListeners();
    }
  }

  // 避免重复监听
  bool _listenersSetup = false;

  // 播放状态
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  // 单曲循环
  bool _repeatOne = false;
  bool get repeatOne => _repeatOne;
  Future<void> toggleRepeatOne() async {
    _repeatOne = !_repeatOne;
    // 可选：持久化到本地，便于下次启动沿用
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('repeat_one_enabled', _repeatOne);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setRepeatOne(bool value) async {
    if (_repeatOne == value) return;
    _repeatOne = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('repeat_one_enabled', _repeatOne);
    } catch (_) {}
    notifyListeners();
  }

  // 播放进度
  Duration _currentPosition = Duration.zero;
  Duration get currentPosition => _currentPosition;

  Duration _totalDuration = Duration.zero;
  Duration get totalDuration => _totalDuration;

  // 当前字幕
  String _currentSubtitle = '';
  String get currentSubtitle => _currentSubtitle;

  // 多条目的下载进度跟踪：key -> progress(0~1)
  // key 规则："category/unit/name"
  final Map<String, double> _downloading = {};
  String _keyOf(MediaItem i) => '${i.category}/${i.unit}/${i.name}';
  double progressOf(MediaItem item) => _downloading[_keyOf(item)] ?? 0.0;
  bool isDownloadingFor(MediaItem item) {
    final p = progressOf(item);
    return p > 0 && p < 1.0;
  }

  void _setProgress(MediaItem item, double v) {
    final key = _keyOf(item);
    if (v <= 0 || v >= 1.0) {
      if (_downloading.containsKey(key)) {
        _downloading.remove(key);
        notifyListeners();
      }
      return;
    }
    _downloading[key] = v;
    notifyListeners();
  }

  // 播放列表
  List<MediaItem> _playlist = [];
  List<MediaItem> get playlist => _playlist;

  int _currentIndex = -1;
  int get currentIndex => _currentIndex;

  // 进度累加，每30秒写一条历史
  Duration _lastRecordedPosition = Duration.zero;
  int _accumulatedSeconds = 0;

  /// 设置播放列表
  void setPlaylist(List<MediaItem> items) {
    _playlist = items;
    notifyListeners();
  }

  /// 播放指定媒体项
  Future<void> play(
    MediaItem item, {
    BetterPlayerController? existingController,
  }) async {
    _currentItem = item;

    if (existingController != null) {
      // 如果当前已有不同的控制器，先安全释放
      if (_controller != null && !identical(_controller, existingController)) {
        try {
          _controller!.dispose();
        } catch (_) {}
        _listenersSetup = false;
      }
      _controller = existingController;
      _setupControllerListeners();
      // 已有控制器沿用时，允许挂载
      viewMountReady.value = true;
    }

    _currentIndex = _playlist.indexWhere(
      (e) =>
          e.name == item.name &&
          e.category == item.category &&
          e.unit == item.unit,
    );

    if (_controller != null) {
      _isPlaying = _controller!.isPlaying() ?? false;
    }

    _lastRecordedPosition = Duration.zero;
    _accumulatedSeconds = 0;

    await _addPlayHistory(item);
    notifyListeners();

    // 后台预取下一条，提升切换体验
    _prefetchNextIfAny();
  }

  /// 直接播放：用于首页点击列表项时，不进入详情页也能开始播放
  /// - 如果已有控制器且有效，则复用控制器并切换数据源
  /// - 如果是同一个音频且正在播放，则不做任何操作，保持播放状态
  /// - 如果没有控制器或控制器无效，则新建一个隐藏使用的控制器（由 MiniPlayer 作为挂载点）
  Future<void> playDirect(MediaItem item) async {
    // 🔥 检查是否是同一个音频
    final isSameItem =
        _currentItem != null &&
        _currentItem!.name == item.name &&
        _currentItem!.category == item.category &&
        _currentItem!.unit == item.unit;

    // 如果是同一个音频且控制器有效，确保正在播放
    if (isSameItem && _controller != null && _isControllerValid) {
      debugPrint('playDirect: Same item, ensuring playback');

      // 更新索引
      _currentIndex = _playlist.indexWhere(
        (e) =>
            e.name == item.name &&
            e.category == item.category &&
            e.unit == item.unit,
      );

      // 🔥 关键修复：检查播放状态，如果没有在播放则开始播放
      try {
        final isActuallyPlaying = _controller!.isPlaying() ?? false;
        if (!isActuallyPlaying) {
          debugPrint(
            'playDirect: Controller exists but not playing, starting playback',
          );
          await _controller!.play();
          // 显式恢复音量，防止在视图重新挂载后出现静音/音量为0的情况
          try {
            await _controller!.setVolume(1.0);
          } catch (_) {}
          _isPlaying = true;
        } else {
          // 已在播放，确保音量不是0
          try {
            await _controller!.setVolume(1.0);
          } catch (_) {}
          debugPrint('playDirect: Already playing, keeping current state');
        }
      } catch (e) {
        debugPrint('playDirect: Error checking/starting playback: $e');
      }

      notifyListeners();
      return;
    }

    _currentItem = item;

    // 更新当前索引（基于现有播放列表）
    _currentIndex = _playlist.indexWhere(
      (e) =>
          e.name == item.name &&
          e.category == item.category &&
          e.unit == item.unit,
    );

    final baseUrl = CatalogService.baseUrl;
    // 如果已有缓存，优先使用本地文件；否则走网络
    final hasCache = await CacheService.exists(item);
    final dataSourceType = hasCache
        ? BetterPlayerDataSourceType.file
        : BetterPlayerDataSourceType.network;
    final urlOrPath = hasCache
        ? await CacheService.localPathOf(item)
        : item.getUrl(baseUrl);

    final ds = BetterPlayerDataSource(
      dataSourceType,
      urlOrPath,
      subtitles: [
        // 优先 VTT，其次 SRT
        BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.network,
          urls: [item.getVttUrl(baseUrl)],
          name: '字幕 (VTT)',
          selectedByDefault: true,
        ),
        BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.network,
          urls: [item.getSrtUrl(baseUrl)],
          name: '字幕 (SRT)',
        ),
      ],
    );

    // 检查现有控制器是否有效可用
    final hasValidController = _controller != null && _isControllerValid;
    final isVideo = item.type == MediaType.video;

    if (!hasValidController || isVideo) {
      // 如果控制器无效，先清理再重建
      if (_controller != null) {
        debugPrint('playDirect: Disposing invalid controller before recreate');
        try {
          _controller?.dispose();
        } catch (e) {
          debugPrint('playDirect: Error disposing old controller: $e');
        }
        _controller = null;
        _listenersSetup = false;
      }
      // 重建期间不允许挂载
      viewMountReady.value = false;

      // 创建一个新的控制器（隐藏使用，MiniPlayer 中有 0 高度挂载点）
      debugPrint('playDirect: Creating new controller for ${item.name}');
      _controller = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: true,
          handleLifecycle: false,
          controlsConfiguration: const BetterPlayerControlsConfiguration(
            enableSubtitles: true,
            enableQualities: false,
          ),
          subtitlesConfiguration: const BetterPlayerSubtitlesConfiguration(
            backgroundColor: Colors.transparent,
            fontColor: Colors.white,
            outlineEnabled: false,
            fontSize: 16,
          ),
        ),
        betterPlayerDataSource: ds,
      );
      _listenersSetup = false;
      _setupControllerListeners();
      // 等待初始化事件后再置为 true（在 initialized 事件中完成）
    } else {
      // 复用已有有效控制器，切换数据源并播放；如失败则重建控制器
      debugPrint('playDirect: Reusing existing controller for ${item.name}');
      bool needRecreate = false;
      try {
        // 切换数据源期间不允许挂载，避免使用到旧的 VPC
        viewMountReady.value = false;
        try {
          await _controller!.pause();
        } catch (e) {
          debugPrint('playDirect: pause error (non-critical): $e');
        }
        await _controller!.setupDataSource(ds);
        try {
          await _controller!.play();
        } catch (e) {
          debugPrint('playDirect: play error: $e');
          needRecreate = true;
        }
      } catch (e) {
        debugPrint(
          'playDirect: setupDataSource failed, will recreate controller. Error: $e',
        );
        needRecreate = true;
      }

      if (needRecreate) {
        debugPrint('playDirect: Recreating controller due to error');
        try {
          _controller?.dispose();
        } catch (e) {
          debugPrint('playDirect: Error disposing controller: $e');
        }
        _listenersSetup = false;
        viewMountReady.value = false;
        _controller = BetterPlayerController(
          BetterPlayerConfiguration(
            autoPlay: true,
            handleLifecycle: false,
            controlsConfiguration: const BetterPlayerControlsConfiguration(
              enableSubtitles: true,
              enableQualities: false,
            ),
            subtitlesConfiguration: const BetterPlayerSubtitlesConfiguration(
              backgroundColor: Colors.transparent,
              fontColor: Colors.white,
              outlineEnabled: false,
              fontSize: 16,
            ),
          ),
          betterPlayerDataSource: ds,
        );
        _setupControllerListeners();
        // 等待 initialized 事件恢复 viewMountReady
      }
    }

    _isPlaying = true;
    _lastRecordedPosition = Duration.zero;
    _accumulatedSeconds = 0;

    // 写入一条开始播放的历史（时长 0，后续进度事件会累计）
    await _addPlayHistory(item);

    // 更新锁屏媒体信息
    try {
      await LockScreenMediaService().initialize();
      await LockScreenMediaService().updateMediaItem(
        title: item.name,
        album: item.unit,
        duration: _controller?.videoPlayerController?.value.duration,
      );
      await LockScreenMediaService().updatePlaybackState(
        playing: true,
        position:
            _controller?.videoPlayerController?.value.position ?? Duration.zero,
        bufferedPosition:
            _controller?.videoPlayerController?.value.duration ?? Duration.zero,
      );
    } catch (_) {}

    notifyListeners();

    // 保存当前播放状态
    await saveCurrentPlaybackState();

    // 后台预取下一条，提升切换体验
    _prefetchNextIfAny();
  }

  /// 首次点击播放时，如果无缓存，先显示下载进度，下载完成后自动播放本地文件
  Future<void> ensureCachedAndPlay(MediaItem item) async {
    // 如果已经有缓存，直接走 playDirect
    if (await CacheService.exists(item)) {
      return playDirect(item);
    }

    // 下载并上报进度
    _setProgress(item, 0.0001); // 触发UI显示
    try {
      await CacheService.download(
        item,
        onProgress: (p) {
          _setProgress(item, p);
        },
      );
      _setProgress(item, 1.0);
      // 下载完成后播放本地缓存
      await playDirect(item);
      // 短暂延时后重置进度条与下载标记
      Future.delayed(const Duration(milliseconds: 300), () {
        _setProgress(item, 0.0);
      });
      return;
    } catch (e) {
      // 下载失败，回退使用网络播放
      _setProgress(item, 0.0);
      notifyListeners();
      return playDirect(item);
    }
  }

  /// 预取下一条音频（仅音频/单词类型）
  void _prefetchNextIfAny() {
    if (_playlist.isEmpty || _currentIndex < 0) return;
    final nextIdx = _currentIndex + 1;
    if (nextIdx >= _playlist.length) return;
    final nextItem = _playlist[nextIdx];
    if (nextItem.type == MediaType.video) return; // 暂不预取视频
    // 异步静默预取
    Future(() => CacheService.prefetch(nextItem));
  }

  /// 播放/暂停切换（同时同步锁屏状态）
  Future<void> togglePlayPause() async {
    if (!_isControllerValid) return;
    try {
      final playing = _controller!.isPlaying() ?? false;
      if (playing) {
        await _controller!.pause();
        _isPlaying = false;
      } else {
        await _controller!.play();
        _isPlaying = true;
      }
      try {
        await LockScreenMediaService().updatePlaybackState(
          playing: _isPlaying,
          position:
              _controller?.videoPlayerController?.value.position ??
              Duration.zero,
          bufferedPosition:
              _controller?.videoPlayerController?.value.duration ??
              Duration.zero,
        );
      } catch (_) {}
      notifyListeners();
    } catch (e) {
      debugPrint('togglePlayPause error: $e');
    }
  }

  Future<void> _addPlayHistory(MediaItem item) async {
    try {
      final history = PlayHistory(
        fileName: item.name,
        unit: item.unit,
        playTime: DateTime.now(),
        durationSeconds: 0,
      );
      await HistoryManager.addHistory(history);
    } catch (_) {}
  }

  void _safeNotifyListeners() {
    try {
      notifyListeners();
    } catch (_) {}
  }

  void _setupControllerListeners() {
    if (_controller == null) return;
    if (_listenersSetup) {
      debugPrint('Controller listeners already setup, skipping');
      return;
    }
    _listenersSetup = true;

    _controller!.addEventsListener((event) async {
      switch (event.betterPlayerEventType) {
        case BetterPlayerEventType.play:
          _isPlaying = true;
          _safeNotifyListeners();
          break;
        case BetterPlayerEventType.pause:
          _isPlaying = false;
          // 暂停时也记录累积的播放时长（即使小于1秒）
          if (_accumulatedSeconds > 0 && _currentItem != null) {
            try {
              final history = PlayHistory(
                fileName: _currentItem!.name,
                unit: _currentItem!.unit,
                playTime: DateTime.now(),
                durationSeconds: _accumulatedSeconds,
              );
              await HistoryManager.addHistory(history);
            } catch (_) {}
            _accumulatedSeconds = 0;
          }
          _safeNotifyListeners();
          break;
        case BetterPlayerEventType.progress:
          try {
            final progress =
                (event.parameters?['progress'] as Duration?) ??
                _controller?.videoPlayerController?.value.position ??
                Duration.zero;
            final total =
                _controller?.videoPlayerController?.value.duration ??
                _totalDuration;
            _currentPosition = progress;
            _totalDuration = total;

            // 每累计 >=1 秒，追加一次历史（加快统计频率）
            final diff = progress.inSeconds - _lastRecordedPosition.inSeconds;
            if (diff > 0 && _isPlaying && _currentItem != null) {
              _accumulatedSeconds += diff;
              if (_accumulatedSeconds >= 1) {
                try {
                  final history = PlayHistory(
                    fileName: _currentItem!.name,
                    unit: _currentItem!.unit,
                    playTime: DateTime.now(),
                    durationSeconds: _accumulatedSeconds,
                  );
                  await HistoryManager.addHistory(history);
                } catch (_) {}
                _accumulatedSeconds = 0;
              }
            }
            _lastRecordedPosition = progress;

            _safeNotifyListeners();
          } catch (_) {}
          break;
        case BetterPlayerEventType.initialized:
          try {
            final duration =
                (event.parameters?['duration'] as Duration?) ??
                _controller?.videoPlayerController?.value.duration ??
                Duration.zero;
            _totalDuration = duration;
            // 初始化完成，允许视图挂载
            viewMountReady.value = true;
            _safeNotifyListeners();
          } catch (_) {}
          break;
        case BetterPlayerEventType.finished:
          // 完成一遍播放
          _isPlaying = false;
          if (_accumulatedSeconds > 0 && _currentItem != null) {
            try {
              final history = PlayHistory(
                fileName: _currentItem!.name,
                unit: _currentItem!.unit,
                playTime: DateTime.now(),
                durationSeconds: _accumulatedSeconds,
              );
              await HistoryManager.addHistory(history);
            } catch (_) {}
            _accumulatedSeconds = 0;
          }

          // 如果开启单曲循环，则回到开头并继续播放
          if (_repeatOne && _isControllerValid) {
            try {
              await _controller!.seekTo(Duration.zero);
              await _controller!.play();
              try {
                await _controller!.setVolume(1.0);
              } catch (_) {}
              _isPlaying = true;
              _lastRecordedPosition = Duration.zero;
              _safeNotifyListeners();
              break; // 不继续到下一首
            } catch (_) {
              // 若重播异常，则退回到默认的下一首逻辑
            }
          }

          // 默认：进入下一首（仅更新索引/当前项，由上层控制是否开始播放）
          playNext();
          break;
        default:
          break;
      }
    });
  }

  bool get _isControllerValid {
    if (_controller == null) return false;
    try {
      _controller!.isPlaying();
      return true;
    } catch (_) {
      return false;
    }
  }

  void playNext() {
    if (_playlist.isEmpty || _currentIndex < 0) return;
    final nextIndex = _currentIndex + 1;
    if (nextIndex < _playlist.length) {
      _currentIndex = nextIndex;
      _currentItem = _playlist[nextIndex];
      notifyListeners();
    }
  }

  void playPrevious() {
    if (_playlist.isEmpty || _currentIndex < 0) return;
    final prevIndex = _currentIndex - 1;
    if (prevIndex >= 0) {
      _currentIndex = prevIndex;
      _currentItem = _playlist[prevIndex];
      notifyListeners();
    }
  }

  void seekForward() {
    if (!_isControllerValid) return;
    try {
      final newPosition = _currentPosition + const Duration(seconds: 10);
      final maxPosition = _totalDuration;
      if (newPosition < maxPosition) {
        _controller!.seekTo(newPosition);
      } else {
        _controller!.seekTo(maxPosition);
      }
    } catch (_) {}
  }

  void seekBackward() {
    if (!_isControllerValid) return;
    try {
      final newPosition = _currentPosition - const Duration(seconds: 10);
      if (newPosition > Duration.zero) {
        _controller!.seekTo(newPosition);
      } else {
        _controller!.seekTo(Duration.zero);
      }
    } catch (_) {}
  }

  void stop() {
    // 停止时立即标记为不可挂载，确保 UI 立刻卸载 BetterPlayer
    viewMountReady.value = false;
    _controller?.pause();
    _currentItem = null;
    _controller = null;
    _isPlaying = false;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    _currentIndex = -1;
    _listenersSetup = false;
    _accumulatedSeconds = 0;
    _lastRecordedPosition = Duration.zero;
    notifyListeners();
  }

  void updatePlayingState(bool playing) {
    if (_isPlaying != playing) {
      _isPlaying = playing;
      notifyListeners();
    }
  }

  void updateProgress(Duration position, Duration total) {
    _currentPosition = position;
    _totalDuration = total;
    notifyListeners();
  }

  void updateCurrentSubtitle(String subtitle) {
    if (_currentSubtitle != subtitle) {
      _currentSubtitle = subtitle;
      notifyListeners();
    }
  }

  bool get hasActivePlayer => _currentItem != null && _isControllerValid;
  bool get hasCurrentItem => _currentItem != null;

  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  /// 保存当前播放状态到本地存储
  Future<void> saveCurrentPlaybackState() async {
    if (_currentItem == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // 保存当前播放的音频信息
      final stateMap = {
        'name': _currentItem!.name,
        'category': _currentItem!.category,
        'unit': _currentItem!.unit,
        'type': _currentItem!.type.name,
        'position': _currentPosition.inMilliseconds,
        'isPlaying': _isPlaying,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await prefs.setString('last_playback_state', jsonEncode(stateMap));
      debugPrint('Saved playback state: ${_currentItem!.name}');
    } catch (e) {
      debugPrint('Error saving playback state: $e');
    }
  }

  /// 从本地存储恢复上次播放状态
  /// 返回恢复的 MediaItem，如果没有则返回 null
  Future<MediaItem?> restoreLastPlaybackState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateJson = prefs.getString('last_playback_state');

      if (stateJson == null) {
        debugPrint('No saved playback state found');
        return null;
      }

      final stateMap = jsonDecode(stateJson) as Map<String, dynamic>;

      // 检查保存时间，如果超过7天则不恢复
      final timestamp = stateMap['timestamp'] as int;
      final savedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      if (now.difference(savedTime).inDays > 7) {
        debugPrint('Saved state too old, ignoring');
        await prefs.remove('last_playback_state');
        return null;
      }

      // 重建 MediaItem
      final item = MediaItem(
        name: stateMap['name'] as String,
        category: stateMap['category'] as String,
        unit: stateMap['unit'] as String,
        type: MediaType.values.firstWhere(
          (t) => t.name == stateMap['type'],
          orElse: () => MediaType.audio,
        ),
      );

      debugPrint('Restored playback state: ${item.name}');
      return item;
    } catch (e) {
      debugPrint('Error restoring playback state: $e');
      return null;
    }
  }

  /// 应用启动时恢复上次播放状态
  /// 将在 MiniPlayer 中显示，但不自动播放
  Future<void> restoreAndInitialize() async {
    final item = await restoreLastPlaybackState();
    if (item == null) return;

    try {
      // 仅初始化 UI 状态，不自动播放
      _currentItem = item;
      // 恢复单曲循环设置（可选）
      try {
        final prefs = await SharedPreferences.getInstance();
        _repeatOne = prefs.getBool('repeat_one_enabled') ?? false;
      } catch (_) {}
      notifyListeners();

      debugPrint('Initialized UI with last item: ${item.name}');
    } catch (e) {
      debugPrint('Error initializing with last item: $e');
    }
  }
}
