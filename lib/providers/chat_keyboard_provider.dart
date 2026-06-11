import 'package:flutter/material.dart';

/// 聊天键盘/面板高度管理器
///
/// 核心原理：记录键盘最大高度，当表情面板显示时，
/// 用 (maxKeyboardHeight - currentKeyboardHeight) 作为面板高度，
/// 使键盘收缩距离 = 面板上升距离，保持输入框位置稳定
class ChatKeyboardProvider extends ChangeNotifier {
  /// 键盘最大高度（输入框底部到屏幕底部的距离）
  double _maxKeyboardHeight = 0.0;

  /// 当前键盘实时高度
  double _currentKeyboardHeight = 0.0;

  /// 表情面板是否显示
  bool _showEmojiPanel = false;

  // ==================== Getters ====================

  double get maxKeyboardHeight => _maxKeyboardHeight;

  double get currentKeyboardHeight => _currentKeyboardHeight;

  bool get showEmojiPanel => _showEmojiPanel;

  /// 表情/更多面板的动态高度（核心公式）
  ///
  /// 当键盘收起时，面板高度 = maxKeyboardHeight - currentKeyboardHeight
  /// 这样面板上升量恰好填补键盘收缩量，输入框不动
  double get panelHeight {
    if (!_showEmojiPanel) return 0.0;
    final height = _maxKeyboardHeight - _currentKeyboardHeight;
    return height > 0 ? height : 260.0; // 兜底最小值
  }

  // ==================== Setters / Updates ====================

  /// 更新键盘实时高度（由 didChangeMetrics 调用）
  void updateKeyboardHeight(double height, {bool hasFocus = false}) {
    _currentKeyboardHeight = height;

    // 键盘弹出且有焦点时，记录最大高度
    if (height > 0 && hasFocus && height > _maxKeyboardHeight) {
      _maxKeyboardHeight = height;
    }

    notifyListeners();
  }

  /// 切换表情面板显示状态
  void toggleEmojiPanel(bool show) {
    if (_showEmojiPanel == show) return;
    _showEmojiPanel = show;
    notifyListeners();
  }

  /// 重置状态（页面退出时调用）
  void reset() {
    _maxKeyboardHeight = 0.0;
    _currentKeyboardHeight = 0.0;
    _showEmojiPanel = false;
    notifyListeners();
  }
}
