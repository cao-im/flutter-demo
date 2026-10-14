import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecording {
  final String path;
  final int durationMillis;

  const VoiceRecording({required this.path, required this.durationMillis});
}

/// 跨端录音。Windows / Linux 用 wav，手机用 aac。
class VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;
  DateTime? _started;

  Future<void> start() async {
    if (kIsWeb) {
      throw StateError('当前平台不支持录音');
    }
    final allowed = await _recorder.hasPermission();
    if (!allowed) {
      throw StateError('没有麦克风权限，请在系统设置中允许后重试');
    }

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final base = '${dir.path}${Platform.pathSeparator}voice_$stamp';
    final attempts = Platform.isWindows || Platform.isLinux
        ? <_Attempt>[
            _Attempt(AudioEncoder.wav, '$base.wav', 16000),
            _Attempt(AudioEncoder.wav, '$base.wav', 44100),
          ]
        : <_Attempt>[
            _Attempt(AudioEncoder.aacLc, '$base.m4a', 16000),
            _Attempt(AudioEncoder.wav, '$base.wav', 16000),
          ];

    Object? lastError;
    for (final attempt in attempts) {
      try {
        await _recorder.start(
          RecordConfig(
            encoder: attempt.encoder,
            numChannels: 1,
            sampleRate: attempt.sampleRate,
            bitRate: 32000,
          ),
          path: attempt.path,
        );
        _path = attempt.path;
        _started = DateTime.now();
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('无法开始录音${lastError == null ? '' : ': $lastError'}');
  }

  /// 当前输入音量，0 接近静音，1 为较大声。
  Future<double> readLevel() async {
    try {
      final amplitude = await _recorder.getAmplitude();
      final db = amplitude.current;
      if (db.isNaN || db <= -48) return 0.06;
      final linear = ((db + 48) / 48).clamp(0.0, 1.0);
      return (0.06 + 0.94 * math.sqrt(linear)).clamp(0.06, 1.0);
    } catch (_) {
      return 0.06;
    }
  }

  Future<VoiceRecording?> stop() async {
    final started = _started;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _path;
    }
    _started = null;
    _path = null;
    final resolved = path;
    if (resolved == null || resolved.isEmpty || started == null) return null;
    return VoiceRecording(
      path: resolved,
      durationMillis: DateTime.now().difference(started).inMilliseconds,
    );
  }

  Future<void> cancel() async {
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _path;
    }
    _started = null;
    _path = null;
    final target = path;
    if (target == null || target.isEmpty) return;
    try {
      await File(target).delete();
    } catch (_) {}
  }

  Future<void> dispose() => _recorder.dispose();
}

class _Attempt {
  final AudioEncoder encoder;
  final String path;
  final int sampleRate;

  const _Attempt(this.encoder, this.path, this.sampleRate);
}
