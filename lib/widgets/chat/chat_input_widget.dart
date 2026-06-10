import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 输入栏模式
enum ChatInputMode {
  /// 文本输入模式（私聊/群聊）：显示输入框+发送按钮+附件
  text,
  /// 公众号模式：显示自定义底部菜单区域
  publicAccount,
  /// 禁用模式：不显示输入栏或显示提示文字
  disabled,
}

/// 输入栏样式（区分移动端/桌面端尺寸）
class ChatInputStyle {
  final double horizontalPadding;
  final double verticalPadding;
  final double bottomPadding;
  final double iconButtonSize;
  final double fontSize;
  final double inputHorizontalPadding;
  final double inputVerticalPadding;

  const ChatInputStyle({
    this.horizontalPadding = 8.0,
    this.verticalPadding = 8.0,
    this.bottomPadding = 8.0,
    this.iconButtonSize = 36.0,
    this.fontSize = 14.0,
    this.inputHorizontalPadding = 16.0,
    this.inputVerticalPadding = 10.0,
  });

  static const mobile = ChatInputStyle(
    horizontalPadding: 8.0,
    verticalPadding: 8.0,
    bottomPadding: 8.0,
    iconButtonSize: 36.0,
    fontSize: 14.0,
    inputHorizontalPadding: 16.0,
    inputVerticalPadding: 10.0,
  );

  static const desktop = ChatInputStyle(
    horizontalPadding: 20.0,
    verticalPadding: 12.0,
    bottomPadding: 12.0,
    iconButtonSize: 40.0,
    fontSize: 15.0,
    inputHorizontalPadding: 18.0,
    inputVerticalPadding: 11.0,
  );
}

/// 底部输入栏组件 — 支持多种模式（文本输入/公众号菜单/禁用）
class ChatInputWidget extends StatelessWidget {
  /// 输入模式
  final ChatInputMode mode;

  /// 输入控制器
  final TextEditingController controller;

  /// 发送按钮点击回调
  final VoidCallback? onSend;

  /// 是否正在发送
  final bool isSending;

  /// 更多选项按钮回调（+号/附件）
  final VoidCallback? onMoreOptions;

  /// 样式配置
  final ChatInputStyle style;

  const ChatInputWidget({
    super.key,
    this.mode = ChatInputMode.text,
    required this.controller,
    this.onSend,
    this.isSending = false,
    this.onMoreOptions,
    this.style = ChatInputStyle.mobile,
  });

  @override
  Widget build(BuildContext context) {
    if (mode == ChatInputMode.disabled) {
      return const SizedBox.shrink();
    }

    if (mode == ChatInputMode.publicAccount) {
      return _buildPublicAccountBar();
    }

    // === text 模式，完整复现原 _buildInputToolbar ===
    final hp = style.horizontalPadding;
    final vs = style.verticalPadding;
    final bp = style.bottomPadding;
    final ibs = style.iconButtonSize;

    return Container(
      padding: EdgeInsets.only(
        left: hp,
        right: hp,
        top: vs,
        bottom: MediaQuery.of(context).padding.bottom + bp,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // 1. 添加/更多按钮 (+ 圆形图标)
            SizedBox(
              width: ibs,
              height: ibs,
              child: IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 24),
                color: AppTheme.primaryColor,
                onPressed: onMoreOptions,
                tooltip: '更多',
              ),
            ),

            // 2. 附件按钮（仅桌面端 style==desktop 时显示）
            if (style == ChatInputStyle.desktop) ...[
              SizedBox(
                width: ibs,
                height: ibs,
                child: IconButton(
                  icon: const Icon(Icons.attach_file_outlined, size: 22),
                  color: AppTheme.textSecondaryColor,
                  onPressed: onMoreOptions,
                  tooltip: '发送文件',
                ),
              ),
              const SizedBox(width: 4),
            ],

            // 3. 文本输入框
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '输入消息...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: style.inputHorizontalPadding,
                    vertical: style.inputVerticalPadding,
                  ),
                  hintStyle: TextStyle(fontSize: style.fontSize),
                ),
                style: TextStyle(fontSize: style.fontSize),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend?.call(),
              ),
            ),

            // 4. 间距
            if (style == ChatInputStyle.desktop)
              const SizedBox(width: 10)
            else
              const SizedBox(width: 8),

            // 5. 发送按钮
            SizedBox(
              width: ibs,
              height: ibs,
              child: IconButton(
                icon: const Icon(Icons.send, size: 22),
                color: AppTheme.primaryColor,
                onPressed: (isSending || onSend == null)
                    ? null
                    : () => onSend!(),
                tooltip: '发送',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建公众号模式底部菜单栏
  Widget _buildPublicAccountBar() {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: 10,
        horizontal: style.horizontalPadding,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppTheme.dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildPAMenuItem(Icons.article_outlined, '文章'),
          _buildPAMenuItem(Icons.chat_bubble_outline, '消息'),
          _buildPAMenuItem(Icons.star_outline, '收藏'),
          _buildPAMenuItem(Icons.info_outline, '简介'),
        ],
      ),
    );
  }

  /// 构建公众号菜单项
  Widget _buildPAMenuItem(IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}
