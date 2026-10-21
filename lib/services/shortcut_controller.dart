import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'key_chord.dart';
import 'screen_capture.dart';
import 'win_hotkey.dart';

enum ShortcutId { showWindow, search, send, previousChat, nextChat, screenshot }

class ShortcutSpec {
  final ShortcutId id;
  final String title;
  final String detail;
  final bool global;
  final bool allowBareKey;
  final KeyChord fallback;

  const ShortcutSpec({
    required this.id,
    required this.title,
    required this.detail,
    required this.global,
    required this.fallback,
    this.allowBareKey = false,
  });

  int get hotkeyId => id.index + 1;
}

class ShortcutController extends ChangeNotifier {
  static const _prefsKey = 'app_shortcuts_v1';

  static const specs = <ShortcutSpec>[
    ShortcutSpec(
      id: ShortcutId.showWindow,
      title: '显示/隐藏窗口',
      detail: '在其他软件前台时也能唤起本窗口',
      global: true,
      fallback: KeyChord(
        key: LogicalKeyboardKey.keyW,
        control: true,
        alt: true,
      ),
    ),
    ShortcutSpec(
      id: ShortcutId.screenshot,
      title: '截图',
      detail: '框选屏幕区域，发送到当前会话',
      global: true,
      fallback: KeyChord(key: LogicalKeyboardKey.keyA, alt: true),
    ),
    ShortcutSpec(
      id: ShortcutId.search,
      title: '搜索',
      detail: '定位到会话搜索框',
      global: false,
      fallback: KeyChord(key: LogicalKeyboardKey.keyF, control: true),
    ),
    ShortcutSpec(
      id: ShortcutId.send,
      title: '发送消息',
      detail: '输入框里使用。另一个 Enter 组合用来换行',
      global: false,
      allowBareKey: true,
      fallback: KeyChord(key: LogicalKeyboardKey.enter),
    ),
    ShortcutSpec(
      id: ShortcutId.previousChat,
      title: '上一条会话',
      detail: '在会话列表中向上切换',
      global: false,
      fallback: KeyChord(key: LogicalKeyboardKey.arrowUp, alt: true),
    ),
    ShortcutSpec(
      id: ShortcutId.nextChat,
      title: '下一条会话',
      detail: '在会话列表中向下切换',
      global: false,
      fallback: KeyChord(key: LogicalKeyboardKey.arrowDown, alt: true),
    ),
  ];

  final Map<ShortcutId, KeyChord> _chords = {
    for (final spec in specs) spec.id: spec.fallback,
  };
  final Set<ShortcutId> _systemConflicts = {};
  final FocusNode searchFocus = FocusNode(debugLabel: 'conversation-search');

  var _recording = false;
  var _handlerInstalled = false;
  VoidCallback? onSearch;
  VoidCallback? onPreviousChat;
  VoidCallback? onNextChat;
  VoidCallback? onScreenshot;

  KeyChord chord(ShortcutId id) => _chords[id] ?? _fallback(id);

  bool systemConflict(ShortcutId id) => _systemConflicts.contains(id);

  ShortcutId? internalConflictWith(ShortcutId id) {
    final mine = chord(id);
    for (final spec in specs) {
      if (spec.id == id) continue;
      if (chord(spec.id).sameAs(mine)) return spec.id;
    }
    return null;
  }

  bool get hasConflict => specs.any((spec) => conflictText(spec.id) != null);

  String? conflictText(ShortcutId id) {
    if (_systemConflicts.contains(id)) return '与其他软件冲突';
    final other = internalConflictWith(id);
    if (other != null) return '与「${_title(other)}」冲突';
    return null;
  }

  String subtitleForSettings() {
    final system = specs.where((spec) => systemConflict(spec.id)).map((spec) => spec.title).toList();
    if (system.isNotEmpty) return '${system.join('、')}与其他软件冲突';
    final names = specs.where((spec) => conflictText(spec.id) != null).map((spec) => spec.title).toList();
    if (names.isEmpty) return '发送、搜索、截图、切换会话和唤起窗口';
    return '${names.join('、')}与其他快捷键冲突';
  }

  Future<void> init() async {
    await _load();
    WinHotkey.bind();
    WinHotkey.onPressed = _onGlobalHotKey;
    if (!_handlerInstalled) {
      HardwareKeyboard.instance.addHandler(_onKey);
      _handlerInstalled = true;
    }
    await _syncGlobal();
    notifyListeners();
  }

  void setRecording(bool value) {
    _recording = value;
  }

  Future<String?> updateChord(ShortcutId id, KeyChord chord) async {
    final spec = _spec(id);
    if (!spec.allowBareKey && !chord.hasModifier) {
      return '请包含 Ctrl、Alt 或 Shift';
    }
    if (spec.global && chord.virtualKey == null) {
      return '这个按键不能注册成全局快捷键';
    }
    for (final other in specs) {
      if (other.id == id) continue;
      if (this.chord(other.id).sameAs(chord)) {
        return '已用于「${other.title}」';
      }
    }
    _chords[id] = chord;
    await _save();
    await _syncGlobal();
    notifyListeners();
    if (_systemConflicts.contains(id)) {
      return '与其他软件冲突，这个快捷键暂时不会生效';
    }
    return null;
  }

  Future<void> reset() async {
    for (final spec in specs) {
      _chords[spec.id] = spec.fallback;
    }
    await _save();
    await _syncGlobal();
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final spec in specs) {
        final value = decoded[spec.id.name];
        if (value is! String) continue;
        final chord = KeyChord.decode(value);
        if (chord != null) _chords[spec.id] = chord;
      }
    } catch (error) {
      debugPrint('读取快捷键失败: $error');
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {for (final spec in specs) spec.id.name: chord(spec.id).encode()};
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }

  Future<void> _syncGlobal() async {
    _systemConflicts.clear();
    for (final spec in specs) {
      if (!spec.global) continue;
      final result = await WinHotkey.register(id: spec.hotkeyId, chord: chord(spec.id));
      if (result == HotkeyRegisterResult.conflict) {
        _systemConflicts.add(spec.id);
      }
    }
  }

  void _onGlobalHotKey(int id) {
    for (final spec in specs) {
      if (spec.hotkeyId != id) continue;
      if (spec.id == ShortcutId.showWindow) {
        WinHotkey.toggleWindow();
      } else if (spec.id == ShortcutId.screenshot) {
        onScreenshot?.call();
      }
    }
  }

  bool _onKey(KeyEvent event) {
    if (_recording || event is! KeyDownEvent) return false;
    final pressed = KeyChord.fromEvent(event);
    if (pressed == null) return false;
    if (pressed.sameAs(chord(ShortcutId.search))) {
      onSearch?.call();
      return onSearch != null;
    }
    if (pressed.sameAs(chord(ShortcutId.previousChat))) {
      onPreviousChat?.call();
      return onPreviousChat != null;
    }
    if (pressed.sameAs(chord(ShortcutId.nextChat))) {
      onNextChat?.call();
      return onNextChat != null;
    }
    if (!WinHotkey.supported && pressed.sameAs(chord(ShortcutId.showWindow))) {
      return false;
    }
    if (pressed.sameAs(chord(ShortcutId.screenshot))) {
      if (!ScreenCapture.supported) return false;
      if (WinHotkey.supported && !systemConflict(ShortcutId.screenshot)) return false;
      onScreenshot?.call();
      return onScreenshot != null;
    }
    return false;
  }

  ShortcutSpec _spec(ShortcutId id) => specs.firstWhere((spec) => spec.id == id);

  KeyChord _fallback(ShortcutId id) => _spec(id).fallback;

  String _title(ShortcutId id) => _spec(id).title;

  @override
  void dispose() {
    if (_handlerInstalled) {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    searchFocus.dispose();
    super.dispose();
  }
}
