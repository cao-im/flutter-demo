import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 呼叫等待音。去电是回铃，来电是铃声，接通后停止。
class CallRingtone {
  final AudioPlayer _player = AudioPlayer();
  _RingKind? _kind;

  static final Uint8List _outgoing = _wav(
    sampleRate: 8000,
    parts: const [(425, 380), (0, 1400)],
  );
  static final Uint8List _incoming = _wav(
    sampleRate: 8000,
    parts: const [(880, 160), (0, 70), (698, 220), (0, 1100)],
  );

  Future<void> playOutgoing() => _play(_RingKind.outgoing, _outgoing);

  Future<void> playIncoming() => _play(_RingKind.incoming, _incoming);

  Future<void> stop() async {
    if (_kind == null) return;
    _kind = null;
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('停止铃声失败: $e');
    }
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }

  Future<void> _play(_RingKind kind, Uint8List bytes) async {
    if (_kind == kind) return;
    _kind = kind;
    try {
      if (_kind != kind) return;
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await AudioPlayer.global.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              isSpeakerphoneOn: true,
              stayAwake: false,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.notificationRingtone,
              audioFocus: AndroidAudioFocus.gainTransient,
              audioMode: AndroidAudioMode.ringtone,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: const {AVAudioSessionOptions.defaultToSpeaker},
            ),
          ),
        );
      }
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1);
      await _player.stop();
      if (_kind != kind) return;
      await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
    } catch (e) {
      debugPrint('铃声播放失败: $e');
    }
  }
}

enum _RingKind { outgoing, incoming }

Uint8List _wav({
  required int sampleRate,
  required List<(int hz, int ms)> parts,
}) {
  final samples = <int>[];
  for (final (hz, ms) in parts) {
    final count = sampleRate * ms ~/ 1000;
    for (var i = 0; i < count; i++) {
      if (hz == 0) {
        samples.add(0);
        continue;
      }
      final edge = math.min(i, count - 1 - i).clamp(0, 80) / 80;
      final wave = math.sin(2 * math.pi * hz * i / sampleRate);
      samples.add((wave * edge * 0.55 * 32767).round());
    }
  }

  final data = ByteData(44 + samples.length * 2);
  void writeString(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  writeString(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}
