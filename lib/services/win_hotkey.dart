import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'key_chord.dart';

enum HotkeyRegisterResult { ok, conflict, failed, unsupported }

/// Windows 系统热键。其他平台没有对应通道，全局快捷键只在窗口前台生效。
class WinHotkey {
  static const MethodChannel _channel = MethodChannel('caoim/hotkey');
  static void Function(int id)? onPressed;
  static var _bound = false;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static void bind() {
    if (!supported || _bound) return;
    _bound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onHotKey' && call.arguments is int) {
        onPressed?.call(call.arguments as int);
      }
    });
  }

  static Future<HotkeyRegisterResult> register({
    required int id,
    required KeyChord chord,
  }) async {
    if (!supported) return HotkeyRegisterResult.unsupported;
    final vk = chord.virtualKey;
    if (vk == null) return HotkeyRegisterResult.failed;
    try {
      final value = await _channel.invokeMethod<String>('register', {
        'id': id,
        'modifiers': chord.winModifiers,
        'vk': vk,
      });
      return switch (value) {
        'ok' => HotkeyRegisterResult.ok,
        'conflict' => HotkeyRegisterResult.conflict,
        _ => HotkeyRegisterResult.failed,
      };
    } on MissingPluginException {
      return HotkeyRegisterResult.unsupported;
    } catch (error) {
      debugPrint('注册全局快捷键失败: $error');
      return HotkeyRegisterResult.failed;
    }
  }

  static Future<void> unregister(int id) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('unregister', {'id': id});
    } catch (error) {
      debugPrint('取消全局快捷键失败: $error');
    }
  }

  static Future<void> toggleWindow() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('toggleWindow');
    } catch (error) {
      debugPrint('切换窗口失败: $error');
    }
  }
}
