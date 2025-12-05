import 'package:audio_service/audio_service.dart';
import 'player_service.dart';

/// 锁屏媒体控制服务
/// 集成audio_service实现锁屏和通知栏控制
class LockScreenMediaService {
  static final LockScreenMediaService _instance =
      LockScreenMediaService._internal();
  factory LockScreenMediaService() => _instance;
  LockScreenMediaService._internal();

  AudioHandler? _audioHandler;
  bool _isInitialized = false;

  /// 初始化音频服务
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _audioHandler = await AudioService.init(
        builder: () => MediaPlayerHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.weiyuai.tingli.audio',
          androidNotificationChannelName: '随睡听音频播放',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: true,
          androidNotificationIcon: 'mipmap/ic_launcher',
        ),
      );
      _isInitialized = true;
    } catch (e) {
      print('Failed to initialize AudioService: $e');
    }
  }

  /// 更新媒体信息
  Future<void> updateMediaItem({
    required String title,
    required String album,
    Duration? duration,
    String? artUri,
  }) async {
    if (_audioHandler == null) return;

    final mediaItem = MediaItem(
      id: title,
      title: title,
      album: album,
      duration: duration,
      artUri: artUri != null ? Uri.parse(artUri) : null,
    );

    await _audioHandler!.updateQueue([mediaItem]);
    await _audioHandler!.updateMediaItem(mediaItem);
  }

  /// 更新播放状态
  Future<void> updatePlaybackState({
    required bool playing,
    Duration? position,
    Duration? bufferedPosition,
    double speed = 1.0,
  }) async {
    if (_audioHandler == null) return;

    // 使用 BaseAudioHandler 的方法来更新播放状态
    if (_audioHandler is BaseAudioHandler) {
      final handler = _audioHandler as BaseAudioHandler;
      handler.playbackState.add(
        PlaybackState(
          controls: [
            MediaControl.skipToPrevious,
            MediaControl.rewind,
            playing ? MediaControl.pause : MediaControl.play,
            MediaControl.fastForward,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 2, 4],
          processingState: AudioProcessingState.ready,
          playing: playing,
          updatePosition: position ?? Duration.zero,
          bufferedPosition: bufferedPosition ?? Duration.zero,
          speed: speed,
          queueIndex: 0,
        ),
      );
    }
  }

  /// 停止服务
  Future<void> stop() async {
    if (_audioHandler != null) {
      await _audioHandler!.stop();
    }
  }
}

/// 媒体播放处理器
class MediaPlayerHandler extends BaseAudioHandler {
  final PlayerService _playerService = PlayerService();

  MediaPlayerHandler() {
    // 监听播放器状态变化
    _playerService.addListener(_onPlayerStateChanged);
  }

  void _onPlayerStateChanged() {
    // 同步播放状态到锁屏控制
    LockScreenMediaService().updatePlaybackState(
      playing: _playerService.isPlaying,
      position: _playerService.currentPosition,
      bufferedPosition: _playerService.totalDuration,
    );

    // 同步媒体信息（当切换曲目时）
    final item = _playerService.currentItem;
    if (item != null) {
      LockScreenMediaService().updateMediaItem(
        title: item.name,
        album: item.unit,
        duration: _playerService.totalDuration,
      );
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    // 系统移除任务时，保持状态一致
    await stop();
  }

  @override
  Future<void> play() async {
    await _playerService.togglePlayPause();
  }

  @override
  Future<void> pause() async {
    await _playerService.togglePlayPause();
  }

  @override
  Future<void> stop() async {
    await _playerService.controller?.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _playerService.controller?.seekTo(position);
  }

  @override
  Future<void> skipToNext() async {
    _playerService.playNext();
  }

  @override
  Future<void> skipToPrevious() async {
    _playerService.playPrevious();
  }

  @override
  Future<void> fastForward() async {
    _playerService.seekForward();
  }

  @override
  Future<void> rewind() async {
    _playerService.seekBackward();
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    // 支持自定义操作
    switch (name) {
      case 'setSpeed':
        final speed = extras?['speed'] as double? ?? 1.0;
        await _playerService.controller?.setSpeed(speed);
        break;
    }
  }
}
