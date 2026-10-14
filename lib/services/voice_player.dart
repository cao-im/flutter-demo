import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 全局只播放一条语音。手机默认走听筒，可切到扬声器。
class VoicePlayer extends ChangeNotifier {
  VoicePlayer._() {
    _player.onPlayerComplete.listen((_) {
      _playing = false;
      notifyListeners();
    });
  }

  static final VoicePlayer instance = VoicePlayer._();

  final AudioPlayer _player = AudioPlayer();
  final Set<String> _played = {};
  String? _messageId;
  String? _source;
  bool _playing = false;
  bool speakerOn = false;

  bool get playing => _playing;
  String? get messageId => _messageId;

  bool isPlaying(String id) => _playing && _messageId == id;

  bool hasPlayed(String id) => _played.contains(id);

  bool get canRouteToSpeaker =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> toggle(String messageId, String source) async {
    if (isPlaying(messageId)) {
      await stop();
      return;
    }
    await _player.stop();
    _played.add(messageId);
    _messageId = messageId;
    _source = source;
    _playing = true;
    notifyListeners();
    try {
      if (canRouteToSpeaker) {
        await AudioPlayer.global.setAudioContext(_audioContext(speakerOn));
      }
      await _player.play(_playable(source));
    } catch (e) {
      _playing = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setSpeaker(bool enabled) async {
    if (!canRouteToSpeaker || speakerOn == enabled) return;
    speakerOn = enabled;
    notifyListeners();
    final source = _source;
    if (!_playing || source == null) return;
    final position = await _player.getCurrentPosition();
    await AudioPlayer.global.setAudioContext(_audioContext(speakerOn));
    await _player.stop();
    await _player.play(_playable(source));
    if (position != null && position > Duration.zero) {
      await _player.seek(position);
    }
  }

  Source _playable(String source) {
    if (source.startsWith('http://') || source.startsWith('https://')) {
      return UrlSource(source);
    }
    return DeviceFileSource(source);
  }

  Future<void> stop() async {
    _playing = false;
    await _player.stop();
    notifyListeners();
  }

  AudioContext _audioContext(bool speaker) {
    if (speaker) {
      return AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          audioMode: AndroidAudioMode.normal,
          stayAwake: false,
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playAndRecord,
          options: const {AVAudioSessionOptions.defaultToSpeaker},
        ),
      );
    }
    return AudioContext(
      android: const AudioContextAndroid(
        isSpeakerphoneOn: false,
        audioMode: AndroidAudioMode.inCommunication,
        stayAwake: false,
        contentType: AndroidContentType.speech,
        usageType: AndroidUsageType.voiceCommunication,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playAndRecord,
        options: const {AVAudioSessionOptions.allowBluetooth},
      ),
    );
  }
}
