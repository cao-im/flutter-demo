import 'dart:io';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class VideoInspect {
  final int durationSeconds;
  final String coverPath;

  const VideoInspect({required this.durationSeconds, this.coverPath = ''});

  /// 读取时长，并尽量截一帧做封面。失败时时长为 0、封面为空，不阻断发送。
  static Future<VideoInspect> inspect(String path) async {
    if (kIsWeb || path.isEmpty) {
      return const VideoInspect(durationSeconds: 0);
    }
    final duration = await _duration(path);
    final cover = await _cover(path);
    return VideoInspect(durationSeconds: duration, coverPath: cover);
  }

  static Future<int> _duration(String path) async {
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize().timeout(const Duration(seconds: 8));
      final seconds = controller.value.duration.inSeconds;
      return seconds < 0 ? 0 : seconds;
    } catch (e) {
      debugPrint('读取视频时长失败: $e');
      return 0;
    } finally {
      await controller.dispose();
    }
  }

  static Future<String> _cover(String path) async {
    try {
      final dir = await getTemporaryDirectory();
      final dest = '${dir.path}${Platform.pathSeparator}caoim_cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ok = await FcNativeVideoThumbnail().getVideoThumbnail(
        srcFile: path,
        destFile: dest,
        width: 480,
        height: 480,
        format: 'jpeg',
        quality: 80,
      );
      if (!ok || !File(dest).existsSync()) return '';
      return dest;
    } catch (e) {
      debugPrint('生成视频封面失败: $e');
      return '';
    }
  }
}
