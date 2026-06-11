import 'package:flutter/material.dart';

/// 聊天输入栏上方/下方的可扩展面板容器（类微信）
///
/// - 桌面端：以浮层弹窗形式展示在输入栏上方
/// - 移动端：以展开面板形式展示在输入栏下方
///
/// 可复用于表情、更多功能菜单等不同内容
class ChatOverlayPanel extends StatelessWidget {
  /// 面板内容构建器
  final WidgetBuilder contentBuilder;

  /// 是否显示面板
  final bool visible;

  /// 面板高度（移动端有效，桌面端自适应内容）
  final double height;

  /// 是否为桌面端样式
  final bool isDesktop;

  const ChatOverlayPanel({
    super.key,
    required this.contentBuilder,
    this.visible = false,
    this.height = 300,
    this.isDesktop = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    if (isDesktop) {
      return _DesktopPopupPanel(
        contentBuilder: contentBuilder,
      );
    }

    return _MobileExpandPanel(
      contentBuilder: contentBuilder,
      height: height,
    );
  }
}

// ==================== 桌面端：浮层弹窗 ====================

class _DesktopPopupPanel extends StatelessWidget {
  final WidgetBuilder contentBuilder;

  const _DesktopPopupPanel({required this.contentBuilder});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black26,
      child: Center(
        child: Container(
          width: 420,
          constraints: const BoxConstraints(maxHeight: 450),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: contentBuilder(context)),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== 移动端：底部展开面板 ====================

class _MobileExpandPanel extends StatelessWidget {
  final WidgetBuilder contentBuilder;
  final double height;

  const _MobileExpandPanel({
    required this.contentBuilder,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[50],
          border: Border(
            top: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        child: contentBuilder(context),
      ),
    );
  }
}
