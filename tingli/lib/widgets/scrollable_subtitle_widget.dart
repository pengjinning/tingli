import 'package:flutter/material.dart';
import '../models/subtitle_cue.dart';

/// 可滚动的字幕组件
/// 以类似弹幕的形式从底部往上滚动显示字幕
class ScrollableSubtitleWidget extends StatefulWidget {
  final List<SubtitleCue> cues;
  final Duration currentPosition;
  final Function(Duration) onSeekTo;
  final Color textColor;
  final Color activeColor;
  final double fontSize;

  const ScrollableSubtitleWidget({
    super.key,
    required this.cues,
    required this.currentPosition,
    required this.onSeekTo,
    this.textColor = Colors.white70,
    this.activeColor = Colors.white,
    this.fontSize = 16.0,
  });

  @override
  State<ScrollableSubtitleWidget> createState() =>
      _ScrollableSubtitleWidgetState();
}

class _ScrollableSubtitleWidgetState extends State<ScrollableSubtitleWidget> {
  final ScrollController _scrollController = ScrollController();
  int _currentCueIndex = -1;
  bool _isUserScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 用户手动滚动时，暂停自动滚动
    if (_scrollController.position.isScrollingNotifier.value) {
      _isUserScrolling = true;
      // 3秒后恢复自动滚动
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isUserScrolling = false;
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(ScrollableSubtitleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 当播放位置改变时，找到当前字幕索引
    if (widget.currentPosition != oldWidget.currentPosition) {
      _updateCurrentCue();
    }
  }

  void _updateCurrentCue() {
    if (widget.cues.isEmpty) return;

    int newIndex = -1;
    for (int i = 0; i < widget.cues.length; i++) {
      final cue = widget.cues[i];
      final nextCue = i < widget.cues.length - 1 ? widget.cues[i + 1] : null;

      if (widget.currentPosition >= cue.start) {
        if (nextCue == null || widget.currentPosition < nextCue.start) {
          newIndex = i;
          break;
        }
      }
    }

    if (newIndex != _currentCueIndex) {
      setState(() {
        _currentCueIndex = newIndex;
      });

      // 如果不是用户手动滚动，则自动滚动到当前字幕
      if (!_isUserScrolling && newIndex >= 0) {
        _scrollToIndex(newIndex);
      }
    }
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;

    // 计算目标位置：让当前字幕显示在底部附近
    // 每个字幕项高度约为 60（48内容 + 12间距）
    const itemHeight = 60.0;
    final targetOffset = (index * itemHeight).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cues.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.subtitles_off, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              '暂无字幕',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.3),
            Colors.black.withValues(alpha: 0.6),
          ],
        ),
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: widget.cues.length,
        // 反向列表，从底部往上
        reverse: false,
        itemBuilder: (context, index) {
          final cue = widget.cues[index];
          final isActive = index == _currentCueIndex;

          return InkWell(
            onTap: () {
              // 点击字幕跳转到对应时间
              widget.onSeekTo(cue.start);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.blue.withValues(alpha: 0.3)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive
                      ? Colors.blue.withValues(alpha: 0.6)
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 时间标签
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.blue
                          : Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatTime(cue.start),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isActive ? Colors.white : Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 字幕文本
                  Expanded(
                    child: Text(
                      cue.text,
                      style: TextStyle(
                        fontSize: widget.fontSize,
                        fontWeight: isActive
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isActive ? widget.activeColor : widget.textColor,
                        height: 1.4,
                      ),
                    ),
                  ),
                  // 播放图标（仅在激活时显示）
                  if (isActive)
                    Icon(Icons.play_arrow, size: 20, color: widget.activeColor),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
