import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 音频波形可视化 Widget
class AudioWaveform extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final double height;
  final int barCount;

  const AudioWaveform({
    super.key,
    required this.isPlaying,
    this.color = Colors.blue,
    this.height = 100,
    this.barCount = 50,
  });

  @override
  State<AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<AudioWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _barHeights = [];
  Timer? _updateTimer;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();

    // 初始化音柱高度
    for (int i = 0; i < widget.barCount; i++) {
      _barHeights.add(_random.nextDouble());
    }

    _startAnimation();
  }

  void _startAnimation() {
    _updateTimer?.cancel();
    if (widget.isPlaying) {
      _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted && widget.isPlaying) {
          setState(() {
            // 更新音柱高度，模拟音频波动
            for (int i = 0; i < _barHeights.length; i++) {
              // 使用正弦波和随机值的组合，创造更自然的波动
              final baseWave = math.sin(
                _controller.value * 2 * math.pi + i * 0.3,
              );
              final randomFactor = _random.nextDouble() * 0.5;
              _barHeights[i] = (baseWave.abs() * 0.7 + randomFactor * 0.3)
                  .clamp(0.1, 1.0);
            }
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(AudioWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _startAnimation();
      if (!widget.isPlaying) {
        // 暂停时，音柱逐渐降低
        setState(() {
          for (int i = 0; i < _barHeights.length; i++) {
            _barHeights[i] = 0.1;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(
          widget.barCount,
          (index) => Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
              height: widget.height * _barHeights[index],
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆形波纹动画 Widget
class CircularWaveform extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final double size;

  const CircularWaveform({
    super.key,
    required this.isPlaying,
    this.color = Colors.blue,
    this.size = 200,
  });

  @override
  State<CircularWaveform> createState() => _CircularWaveformState();
}

class _CircularWaveformState extends State<CircularWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(CircularWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _CircularWavePainter(
            animationValue: _controller.value,
            color: widget.color,
            isPlaying: widget.isPlaying,
          ),
        );
      },
    );
  }
}

class _CircularWavePainter extends CustomPainter {
  final double animationValue;
  final Color color;
  final bool isPlaying;

  _CircularWavePainter({
    required this.animationValue,
    required this.color,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isPlaying) return;

    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 3;

    // 绘制多个波纹圆环
    for (int i = 0; i < 3; i++) {
      final waveOffset = (animationValue + i * 0.33) % 1.0;
      final radius = baseRadius + (size.width / 6) * waveOffset;
      final opacity = (1.0 - waveOffset) * 0.5;

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      canvas.drawCircle(center, radius, paint);
    }

    // 绘制中心的脉动圆
    final pulseFactor = 0.9 + 0.1 * math.sin(animationValue * 2 * math.pi);
    final pulsePaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, baseRadius * pulseFactor, pulsePaint);
  }

  @override
  bool shouldRepaint(_CircularWavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isPlaying != isPlaying;
  }
}

/// 当前播放字幕显示 Widget
class CurrentSubtitleDisplay extends StatelessWidget {
  final String subtitle;
  final Color textColor;

  const CurrentSubtitleDisplay({
    super.key,
    required this.subtitle,
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    if (subtitle.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        subtitle,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: textColor,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
      ),
    );
  }
}
