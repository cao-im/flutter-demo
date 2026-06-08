/// 非 Web 平台的音频播放 stub
///
/// Web 端使用 notification_service_web.dart（HTML5 Audio API）
/// 其他平台此文件不会实际被调用，返回空实现
import 'dart:typed_data';

/// Stub: 返回一个空实现，非 Web 平台不会真正调用
dynamic createWebAudio(Uint8List bytes) => _StubAudioPlayer();

class _StubAudioPlayer {
  void play() {}
  void dispose() {}
}
