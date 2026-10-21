import 'package:flutter/services.dart';

/// 一组快捷键。用逻辑键的 keyId 保存，避免受键盘布局影响。
class KeyChord {
  final LogicalKeyboardKey key;
  final bool control;
  final bool alt;
  final bool shift;
  final bool meta;

  const KeyChord({
    required this.key,
    this.control = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  bool get hasModifier => control || alt || shift || meta;

  String encode() {
    final parts = <String>[
      if (control) 'ctrl',
      if (alt) 'alt',
      if (shift) 'shift',
      if (meta) 'meta',
      key.keyId.toRadixString(16),
    ];
    return parts.join('+');
  }

  String get label {
    final parts = <String>[
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      if (meta) 'Win',
      _keyName(key),
    ];
    return parts.join(' + ');
  }

  /// Windows RegisterHotKey 使用的修饰符。带 MOD_NOREPEAT，避免按住连发。
  int get winModifiers {
    var value = 0x4000;
    if (alt) value |= 0x0001;
    if (control) value |= 0x0002;
    if (shift) value |= 0x0004;
    if (meta) value |= 0x0008;
    return value;
  }

  /// 能注册成系统热键时返回虚拟键码。
  int? get virtualKey {
    final named = <LogicalKeyboardKey, int>{
      LogicalKeyboardKey.enter: 0x0D,
      LogicalKeyboardKey.tab: 0x09,
      LogicalKeyboardKey.space: 0x20,
      LogicalKeyboardKey.arrowUp: 0x26,
      LogicalKeyboardKey.arrowDown: 0x28,
      LogicalKeyboardKey.arrowLeft: 0x25,
      LogicalKeyboardKey.arrowRight: 0x27,
      LogicalKeyboardKey.f1: 0x70,
      LogicalKeyboardKey.f2: 0x71,
      LogicalKeyboardKey.f3: 0x72,
      LogicalKeyboardKey.f4: 0x73,
      LogicalKeyboardKey.f5: 0x74,
      LogicalKeyboardKey.f6: 0x75,
      LogicalKeyboardKey.f7: 0x76,
      LogicalKeyboardKey.f8: 0x77,
      LogicalKeyboardKey.f9: 0x78,
      LogicalKeyboardKey.f10: 0x79,
      LogicalKeyboardKey.f11: 0x7A,
      LogicalKeyboardKey.f12: 0x7B,
    };
    final known = named[key];
    if (known != null) return known;
    final text = key.keyLabel;
    if (text.length != 1) return null;
    final unit = text.toUpperCase().codeUnitAt(0);
    if (unit >= 0x30 && unit <= 0x39) return unit;
    if (unit >= 0x41 && unit <= 0x5A) return unit;
    return null;
  }

  static bool isModifier(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  static KeyChord? fromEvent(KeyEvent event) {
    final key = event.logicalKey;
    if (isModifier(key)) return null;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    bool down(LogicalKeyboardKey left, LogicalKeyboardKey right) =>
        pressed.contains(left) || pressed.contains(right);
    return KeyChord(
      key: key,
      control: down(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight),
      alt: down(LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight),
      shift: down(LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight),
      meta: down(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight),
    );
  }

  static KeyChord? decode(String raw) {
    final bits = raw.split('+');
    if (bits.isEmpty) return null;
    final id = int.tryParse(bits.last, radix: 16);
    if (id == null) return null;
    final key = LogicalKeyboardKey.findKeyByKeyId(id);
    if (key == null) return null;
    return KeyChord(
      key: key,
      control: bits.contains('ctrl'),
      alt: bits.contains('alt'),
      shift: bits.contains('shift'),
      meta: bits.contains('meta'),
    );
  }

  bool sameAs(KeyChord other) => encode() == other.encode();

  static String _keyName(LogicalKeyboardKey key) {
    final named = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.enter: 'Enter',
      LogicalKeyboardKey.tab: 'Tab',
      LogicalKeyboardKey.space: 'Space',
      LogicalKeyboardKey.arrowUp: '↑',
      LogicalKeyboardKey.arrowDown: '↓',
      LogicalKeyboardKey.arrowLeft: '←',
      LogicalKeyboardKey.arrowRight: '→',
      LogicalKeyboardKey.escape: 'Esc',
    };
    final text = named[key];
    if (text != null) return text;
    final label = key.keyLabel;
    if (label.length == 1) return label.toUpperCase();
    return label;
  }
}
