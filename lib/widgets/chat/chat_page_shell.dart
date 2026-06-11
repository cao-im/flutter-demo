import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 聊天页面骨架 — 组装 Header + 消息列表 + 底部输入栏
///
/// 所有会话类型（私聊/群聊/公众号/系统通知）共用此骨架，
/// 通过传入不同的 Header/Input 组件实现差异化。
class ChatPageShell extends StatelessWidget {
  /// 顶部标题栏
  final Widget? header;

  /// 消息列表区域
  final Widget body;

  /// 底部输入栏/操作栏
  final Widget? bottomBar;

  /// 是否为面板模式（桌面端嵌入模式）
  final bool isPanelMode;

  /// 空状态占位（当 conversationId 为空时显示）
  final Widget? placeholder;

  const ChatPageShell({
    super.key,
    this.header,
    required this.body,
    this.bottomBar,
    this.isPanelMode = false,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    // 空状态：显示占位
    if (placeholder != null) return placeholder!;

    if (isPanelMode) {
      // 桌面端面板模式：Scaffold + Column 布局，正确处理 IME 插入
      return Scaffold(
        resizeToAvoidBottomInset: false,
        body: Material(
          color: AppTheme.surfaceColor,
          child: Column(
            children: [
              if (header != null) header!,
              Expanded(child: body),
              if (bottomBar != null) bottomBar!,
            ],
          ),
        ),
      );
    }

    // 移动端完整页面模式：Scaffold + AppBar
    return Scaffold(
      appBar: header is PreferredSizeWidget ? header as PreferredSizeWidget : null,
      body: Column(
        children: [
          Expanded(child: body),
          if (bottomBar != null) bottomBar!,
        ],
      ),
    );
  }
}
