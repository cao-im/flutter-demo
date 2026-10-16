import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../models/message_model.dart';
import '../../models/video_content.dart';

class VideoMessageContent extends StatelessWidget {
  final MessageModel message;

  const VideoMessageContent({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final video = VideoContent.tryParse(message.content);
    final label = video?.durationLabel ?? '';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _open(context, video),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 168,
            height: 126,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Cover(cover: video?.cover ?? ''),
                const ColoredBox(color: Color(0x33000000)),
                const Center(child: _PlayBadge()),
                if (label.isNotEmpty)
                  Positioned(
                    right: 6,
                    bottom: 4,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, VideoContent? video) async {
    final source = _playableSource(video);
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('视频无法播放')));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VideoPlayPage(source: source)),
    );
  }

  String? _playableSource(VideoContent? video) {
    final candidates = [video?.url ?? '', message.mediaUrl ?? ''];
    for (final raw in candidates) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      if (VideoContent.isRemote(value)) return value;
      if (!kIsWeb && File(value).existsSync()) return value;
    }
    return null;
  }
}

class _Cover extends StatelessWidget {
  final String cover;

  const _Cover({required this.cover});

  @override
  Widget build(BuildContext context) {
    final value = cover.trim();
    if (VideoContent.isRemote(value)) {
      return Image.network(
        value,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1C1C1E)),
      );
    }
    if (!kIsWeb && value.isNotEmpty && File(value).existsSync()) {
      return Image.file(
        File(value),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1C1C1E)),
      );
    }
    return const ColoredBox(color: Color(0xFF1C1C1E));
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
      child: const Icon(Icons.play_arrow, color: Colors.white, size: 22),
    );
  }
}

class VideoPlayPage extends StatefulWidget {
  final String source;

  const VideoPlayPage({super.key, required this.source});

  @override
  State<VideoPlayPage> createState() => _VideoPlayPageState();
}

class _VideoPlayPageState extends State<VideoPlayPage> {
  late final VideoPlayerController _controller;
  var _ready = false;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && !VideoContent.isRemote(widget.source)) {
      _controller = VideoPlayerController.file(File(widget.source));
    } else {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.source));
    }
    _controller.addListener(_onTick);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    }).catchError((Object e) {
      debugPrint('播放视频失败: $e');
      if (!mounted) return;
      setState(() => _failed = true);
    });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = _ready && _controller.value.aspectRatio > 0 ? _controller.value.aspectRatio : 16 / 9;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _failed
          ? Center(child: _failure())
          : !_ready
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    const labelHeight = 32.0;
                    final fitted = _fitVideo(
                      constraints.maxWidth,
                      constraints.maxHeight - labelHeight,
                      ratio,
                    );
                    return GestureDetector(
                      onTap: () {
                        if (_controller.value.isPlaying) {
                          _controller.pause();
                        } else {
                          _controller.play();
                        }
                      },
                      child: Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: SizedBox(
                                width: fitted.width,
                                height: fitted.height,
                                child: VideoPlayer(_controller),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: labelHeight,
                            child: Center(
                              child: Text(
                                '${_clock(_controller.value.position)} / ${_clock(_controller.value.duration)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _failure() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('无法播放这段视频', style: TextStyle(color: Colors.white70)),
        if (VideoContent.isRemote(widget.source))
          TextButton(
            onPressed: () {
              launchUrl(Uri.parse(widget.source), mode: LaunchMode.externalApplication);
            },
            child: const Text('用系统播放器打开'),
          ),
      ],
    );
  }

  Size _fitVideo(double maxWidth, double maxHeight, double ratio) {
    final width = maxWidth.isFinite && maxWidth > 0 ? maxWidth : 320.0;
    final height = maxHeight.isFinite && maxHeight > 0 ? maxHeight : 180.0;
    final safeRatio = ratio.isFinite && ratio > 0 ? ratio : 16 / 9;
    var videoWidth = width;
    var videoHeight = videoWidth / safeRatio;
    if (videoHeight > height) {
      videoHeight = height;
      videoWidth = videoHeight * safeRatio;
    }
    return Size(videoWidth, videoHeight);
  }

  String _clock(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
