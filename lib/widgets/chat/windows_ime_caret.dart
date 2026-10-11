import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Keeps the Windows IME candidate window aligned with the real caret.
///
/// Flutter Windows reports composing-rect fallback at offset 0, which parks the
/// candidate window on the left of a multiline field. This helper measures the
/// actual caret and pushes it to the native runner.
class WindowsImeCaret {
  WindowsImeCaret({
    required this.controller,
    required this.focusNode,
    required this.textFieldKey,
  });

  static const MethodChannel _channel = MethodChannel('caoim/ime');

  final TextEditingController controller;
  final FocusNode focusNode;
  final GlobalKey textFieldKey;

  bool _bound = false;
  bool _frameScheduled = false;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  void bind() {
    if (!supported || _bound) return;
    _bound = true;
    controller.addListener(_scheduleUpdate);
    focusNode.addListener(_onFocusChanged);
    if (focusNode.hasFocus) {
      _scheduleUpdate();
    }
  }

  void dispose() {
    if (!_bound) return;
    _bound = false;
    controller.removeListener(_scheduleUpdate);
    focusNode.removeListener(_onFocusChanged);
    unawaited(_clear());
  }

  void _onFocusChanged() {
    if (focusNode.hasFocus) {
      _scheduleUpdate();
    } else {
      unawaited(_clear());
    }
  }

  void _scheduleUpdate() {
    if (!_bound || !focusNode.hasFocus || _frameScheduled) return;
    _frameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameScheduled = false;
      _pushCaret();
    });
  }

  Future<void> _clear() async {
    try {
      await _channel.invokeMethod<void>('clearCaret');
    } catch (_) {}
  }

  void _pushCaret() {
    if (!_bound || !focusNode.hasFocus) return;

    final context = textFieldKey.currentContext;
    final editable = _findRenderEditable(context);
    if (context == null || editable == null || !editable.attached) return;

    final value = controller.value;
    final int offset;
    if (value.composing.isValid) {
      offset = value.composing.end;
    } else if (value.selection.isValid) {
      offset = value.selection.extentOffset;
    } else {
      offset = value.text.length;
    }

    final caret = editable.getLocalRectForCaret(TextPosition(offset: offset));
    final transform = editable.getTransformTo(null);
    final global = MatrixUtils.transformRect(transform, caret);
    final dpr = MediaQuery.devicePixelRatioOf(context);

    unawaited(
      _channel.invokeMethod<void>('updateCaret', <String, int>{
        'left': (global.left * dpr).round(),
        'top': (global.top * dpr).round(),
        'right': (global.right * dpr).round(),
        'bottom': (global.bottom * dpr).round(),
      }).then<void>((_) {}, onError: (_) {}),
    );
  }

  static RenderEditable? _findRenderEditable(BuildContext? context) {
    final root = context?.findRenderObject();
    if (root == null) return null;

    RenderEditable? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderEditable) {
        found = object;
        return;
      }
      object.visitChildren(visit);
    }

    visit(root);
    return found;
  }
}
