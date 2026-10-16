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

  /// 聊天区域右侧抽屉，例如群资料。宽屏并排，窄屏覆盖在消息上方。
  final Widget? sidePanel;

  /// 点击遮罩时关闭抽屉
  final VoidCallback? onSidePanelDismissed;

  const ChatPageShell({
    super.key,
    this.header,
    required this.body,
    this.bottomBar,
    this.isPanelMode = false,
    this.placeholder,
    this.sidePanel,
    this.onSidePanelDismissed,
  });

  @override
  Widget build(BuildContext context) {
    if (placeholder != null) return placeholder!;

    final chat = Column(
      children: [
        if (header != null && (isPanelMode || header is! PreferredSizeWidget)) header!,
        Expanded(child: body),
        if (bottomBar != null) bottomBar!,
      ],
    );
    final content = _withSidePanel(chat);

    if (isPanelMode) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        body: Material(
          color: AppTheme.surfaceColor,
          child: content,
        ),
      );
    }

    return Scaffold(
      appBar: header is PreferredSizeWidget ? header as PreferredSizeWidget : null,
      body: content,
    );
  }

  Widget _withSidePanel(Widget chat) {
    final panel = sidePanel;
    if (panel == null) return chat;
    return LayoutBuilder(
      builder: (context, constraints) {
        final overlay = constraints.maxWidth < 760;
        final width = overlay ? (constraints.maxWidth * 0.86).clamp(260.0, 320.0) : 300.0;
        final drawer = SizedBox(width: width, child: panel);
        if (overlay) {
          return Stack(
            children: [
              chat,
              Positioned.fill(
                child: GestureDetector(
                  onTap: onSidePanelDismissed,
                  child: const ColoredBox(color: Color(0x33000000)),
                ),
              ),
              Positioned(top: 0, right: 0, bottom: 0, child: drawer),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: chat),
            drawer,
          ],
        );
      },
    );
  }
}
