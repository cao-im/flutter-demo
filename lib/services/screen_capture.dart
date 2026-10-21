import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一次框选截图的结果。取消时 [cancelled] 为 true，失败时两者都为空。
class ScreenShot {
  final Uint8List? bytes;
  final bool cancelled;

  const ScreenShot({this.bytes, this.cancelled = false});

  bool get ok => bytes != null && bytes!.isNotEmpty;
}

/// Windows 桌面框选截图。其他平台没有对应的全屏选取。
class ScreenCapture {
  static const MethodChannel _channel = MethodChannel('caoim/screenshot');
  static Completer<ScreenShot>? _pending;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static Future<ScreenShot> select() async {
    if (!supported) return const ScreenShot();
    final existing = _pending;
    if (existing != null) return existing.future;
    final completer = Completer<ScreenShot>();
    _pending = completer;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onResult') return;
      final pending = _pending;
      _pending = null;
      if (pending == null || pending.isCompleted) return;
      pending.complete(_read(call.arguments));
    });
    try {
      final opened = await _channel.invokeMethod<bool>('start');
      if (opened != true && !completer.isCompleted) {
        _pending = null;
        completer.complete(const ScreenShot());
      }
    } catch (error) {
      debugPrint('开始截图失败: $error');
      _pending = null;
      if (!completer.isCompleted) completer.complete(const ScreenShot());
    }
    return completer.future;
  }

  static ScreenShot _read(Object? arguments) {
    if (arguments is! Map) return const ScreenShot();
    if (arguments['cancelled'] == true) return const ScreenShot(cancelled: true);
    final raw = arguments['bytes'];
    if (raw is Uint8List && raw.isNotEmpty) return ScreenShot(bytes: raw);
    if (raw is List && raw.isNotEmpty) {
      return ScreenShot(bytes: Uint8List.fromList(raw.cast<int>()));
    }
    return const ScreenShot();
  }
}
