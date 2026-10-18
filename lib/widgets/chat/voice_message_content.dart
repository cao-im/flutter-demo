import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/message_model.dart';
import '../../services/voice_player.dart';
import '../../theme/app_theme.dart';

class VoiceMessageContent extends StatefulWidget {
  final MessageModel message;
  final bool isMe;

  const VoiceMessageContent({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  State<VoiceMessageContent> createState() => _VoiceMessageContentState();
}

class _VoiceMessageContentState extends State<VoiceMessageContent> {
  Timer? _frameTimer;
  int _level = 3;

  VoicePlayer get _player => VoicePlayer.instance;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayer);
    _syncWave();
  }

  @override
  void didUpdateWidget(covariant VoiceMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWave();
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayer);
    _frameTimer?.cancel();
    super.dispose();
  }

  void _onPlayer() {
    if (!mounted) return;
    _syncWave();
    setState(() {});
  }

  void _syncWave() {
    final playing = _player.isPlaying(widget.message.id);
    if (playing) {
      _frameTimer ??= Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (!mounted) return;
        setState(() => _level = _level % 3 + 1);
      });
    } else {
      _frameTimer?.cancel();
      _frameTimer = null;
      _level = 3;
    }
  }

  Future<void> _toggle() async {
    final source = widget.message.voiceSource;
    if (source == null || source.isEmpty) {
      _tip('语音还没准备好');
      return;
    }
    try {
      await _player.toggle(widget.message.id, source);
    } catch (e) {
      _tip('播放失败');
    }
  }

  void _tip(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final playing = _player.isPlaying(widget.message.id);
    final played = _player.hasPlayed(widget.message.id);
    final duration = widget.message.voiceDuration;
    final width = (72 + duration * 2.6).clamp(88.0, 220.0);
    final color = widget.isMe ? Colors.white : AppTheme.textPrimary(context);
    final showDot = !widget.isMe && !played && !playing;
    final showRoute = playing && _player.canRouteToSpeaker;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: SizedBox(
            width: width,
            child: Row(
              children: widget.isMe
                  ? [
                      Text('$duration″', style: TextStyle(fontSize: 15, color: color)),
                      const Spacer(),
                      _WaveIcon(level: playing ? _level : 3, color: color, flip: true),
                    ]
                  : [
                      _WaveIcon(level: playing ? _level : 3, color: color),
                      const Spacer(),
                      Text('$duration″', style: TextStyle(fontSize: 15, color: color)),
                    ],
            ),
          ),
        ),
        if (showDot)
          const Positioned(
            right: -26,
            top: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFFFA5151), shape: BoxShape.circle),
              child: SizedBox(width: 8, height: 8),
            ),
          ),
        if (showRoute)
          Positioned(
            right: widget.isMe ? null : -22,
            left: widget.isMe ? -22 : null,
            bottom: -22,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: _player.speakerOn ? '听筒播放' : '扬声器播放',
              onPressed: () => _player.setSpeaker(!_player.speakerOn),
              icon: Icon(
                _player.speakerOn ? Icons.volume_up : Icons.hearing,
                size: 16,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ),
      ],
    );
  }
}

class _WaveIcon extends StatelessWidget {
  final int level;
  final Color color;
  final bool flip;

  const _WaveIcon({required this.level, required this.color, this.flip = false});

  @override
  Widget build(BuildContext context) {
    final icon = CustomPaint(
      size: const Size(18, 18),
      painter: _WavePainter(level: level, color: color),
    );
    if (!flip) return icon;
    return Transform.flip(flipX: true, child: icon);
  }
}

class _WavePainter extends CustomPainter {
  final int level;
  final Color color;

  _WavePainter({required this.level, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final origin = Offset(2, size.height / 2);
    canvas.drawCircle(origin, 1.6, Paint()..color = color);
    if (level >= 1) {
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: 5),
        -0.8,
        1.6,
        false,
        paint,
      );
    }
    if (level >= 2) {
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: 8.5),
        -0.8,
        1.6,
        false,
        paint,
      );
    }
    if (level >= 3) {
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: 12),
        -0.75,
        1.5,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.level != level || oldDelegate.color != color;
  }
}
