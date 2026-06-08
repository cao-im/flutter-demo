/// Web 端音频播放 - 通过 HTML5 Audio API 播放 wav
///
/// 此文件仅在 Web 平台加载（通过条件导入）
/// 流程：从 Flutter assets 读取 wav 字节 → 创建 Blob URL → HTML5 Audio 播放
@JS()
library web_audio;

import 'dart:js_interop';
import 'dart:typed_data';

// ─── JS 全局函数绑定 ──────────────────────────────────────────

/// URL.createObjectURL(blob) → String
@JS('URL.createObjectURL')
external JSString _createObjectURL(_Blob blob);

/// URL.revokeObjectURL(url)
@JS('URL.revokeObjectURL')
external void _revokeObjectURL(JSString url);

// ─── JS 类型绑定（@staticInterop + external factory） ────────

@JS('Blob')
@staticInterop
class _Blob {
  external factory _Blob(JSArray<JSAny> parts, [_BlobOptions? options]);
}

@JS()
@anonymous
@staticInterop
class _BlobOptions {
  external factory _BlobOptions({String type});
}

@JS('Audio')
@staticInterop
class _Audio {
  external factory _Audio([JSString? src]);
}

extension _AudioExt on _Audio {
  external set volume(double v);
  external JSPromise play();
}

// ─── Dart 封装层 ─────────────────────────────────────────────

/// Web 音频播放器
class WebAudioPlayer {
  final String _blobUrl;

  WebAudioPlayer._(this._blobUrl);

  /// 播放音频
  void play() {
    final audio = _Audio(_blobUrl.toJS);
    audio.volume = 1.0;
    audio.play().toDart; // fire-and-forget
  }

  /// 释放资源
  void dispose() {
    if (_blobUrl.isNotEmpty) {
      _revokeObjectURL(_blobUrl.toJS);
    }
  }
}

/// 从 wav 字节数据创建播放器
///
/// [bytes] - wav 文件的字节数据（通过 rootBundle.load 获取）
WebAudioPlayer createWebAudio(Uint8List bytes) {
  // 1. Dart Uint8List → JS TypedArray → 装入 JS 数组
  final parts = <JSAny>[bytes.toJS].toJS;

  // 2. 创建 Blob { type: 'audio/wav' }
  final blob = _Blob(parts, _BlobOptions(type: 'audio/wav'));

  // 3. 创建 Object URL
  final url = _createObjectURL(blob).toDart;
  if (url.isEmpty) throw StateError('无法创建 Blob URL');

  return WebAudioPlayer._(url);
}
