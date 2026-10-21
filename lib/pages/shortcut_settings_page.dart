import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/key_chord.dart';
import '../services/shortcut_controller.dart';
import '../services/win_hotkey.dart';
import '../theme/app_theme.dart';

class ShortcutSettingsPage extends StatelessWidget {
  const ShortcutSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final shortcuts = context.watch<ShortcutController>();
    return Scaffold(
      appBar: AppBar(title: const Text('快捷键')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(
            WinHotkey.supported
                ? '全局快捷键如果已经被其他软件占用，会在这里提示。点击按键可以修改。'
                : '当前系统只能在本窗口处于前台时响应快捷键。点击按键可以修改。',
            style: TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textSecondary(context)),
          ),
          const SizedBox(height: 12),
          for (final spec in ShortcutController.specs) ...[
            _ShortcutRow(spec: spec),
            const Divider(height: 1),
          ],
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () => shortcuts.reset(),
              child: const Text('恢复默认快捷键'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final ShortcutSpec spec;

  const _ShortcutRow({required this.spec});

  @override
  Widget build(BuildContext context) {
    final shortcuts = context.watch<ShortcutController>();
    final conflict = shortcuts.conflictText(spec.id);
    return InkWell(
      onTap: () => _edit(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spec.title, style: TextStyle(fontSize: 15, color: AppTheme.textPrimary(context))),
                  const SizedBox(height: 4),
                  Text(
                    conflict ?? spec.detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: conflict == null ? AppTheme.textSecondary(context) : AppTheme.errorColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.inputFill(context),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: conflict == null ? AppTheme.divider(context) : AppTheme.errorColor),
              ),
              child: Text(shortcuts.chord(spec.id).label, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final shortcuts = context.read<ShortcutController>();
    final next = await showDialog<KeyChord>(
      context: context,
      builder: (context) => _CaptureDialog(spec: spec, current: shortcuts.chord(spec.id)),
    );
    if (next == null || !context.mounted) return;
    final message = await shortcuts.updateChord(spec.id, next);
    if (message != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _CaptureDialog extends StatefulWidget {
  final ShortcutSpec spec;
  final KeyChord current;

  const _CaptureDialog({required this.spec, required this.current});

  @override
  State<_CaptureDialog> createState() => _CaptureDialogState();
}

class _CaptureDialogState extends State<_CaptureDialog> {
  String? _hint;
  ShortcutController? _shortcuts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shortcuts ??= context.read<ShortcutController>()..setRecording(true);
  }

  @override
  void dispose() {
    _shortcuts?.setRecording(false);
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    final chord = KeyChord.fromEvent(event);
    if (chord == null) return KeyEventResult.handled;
    if (!widget.spec.allowBareKey && !chord.hasModifier) {
      setState(() => _hint = '请同时按下 Ctrl、Alt 或 Shift');
      return KeyEventResult.handled;
    }
    Navigator.pop(context, chord);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('修改${widget.spec.title}'),
      content: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('请按下新的快捷键。按 Esc 取消。'),
              const SizedBox(height: 8),
              Text('当前：${widget.current.label}', style: TextStyle(color: AppTheme.textSecondary(context))),
              if (_hint != null) ...[
                const SizedBox(height: 8),
                Text(_hint!, style: const TextStyle(color: AppTheme.errorColor)),
              ],
            ],
          ),
        ),
    );
  }
}
