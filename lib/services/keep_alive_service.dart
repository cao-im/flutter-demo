import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 前台保活。应用退到后台后尽量保持连接，才能把新消息推到通知栏。
class KeepAliveService {
  static const MethodChannel _channel = MethodChannel('com.clb.caoim/keep_alive');

  static Future<void> start() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('startKeepAlive');
    } catch (e) {
      debugPrint('⚠️[KeepAlive] 启动失败: $e');
    }
  }

  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopKeepAlive');
    } catch (e) {
      debugPrint('⚠️[KeepAlive] 停止失败: $e');
    }
  }
}
