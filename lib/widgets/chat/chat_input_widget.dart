import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
class ChatInputWidget extends StatefulWidget {
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

  /// 表情按钮回调
  final VoidCallback? onEmoji;

  /// 截图按钮回调
  final VoidCallback? onScreenshot;

  const ChatInputWidget({
    super.key,
    this.mode = ChatInputMode.text,
    required this.controller,
    this.onSend,
    this.isSending = false,
    this.onMoreOptions,
    this.style = ChatInputStyle.mobile,
    this.onEmoji,
    this.onScreenshot,
  });

  @override
  State<ChatInputWidget> createState() => _ChatInputWidgetState();
}

class _ChatInputWidgetState extends State<ChatInputWidget> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      onKeyEvent: _handleKeyEvent,
    );
  }

  /// 桌面端键盘事件处理：回车发送，Shift+回车换行
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final isDesktop = widget.style == ChatInputStyle.desktop;
    if (!isDesktop) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    // Shift + Enter → 手动插入换行
    if (HardwareKeyboard.instance.isShiftPressed) {
      final cursorPos = widget.controller.selection.baseOffset;
      final text = widget.controller.text;
      widget.controller.text =
          text.substring(0, cursorPos) +
              '\n' +
          text.substring(cursorPos);
      widget.controller.selection = TextSelection(
        baseOffset: cursorPos + 1,
        extentOffset: cursorPos + 1,
      );
      return KeyEventResult.handled;
    }
    // Enter → 发送消息
    widget.onSend?.call();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == ChatInputMode.disabled) {
      return const SizedBox.shrink();
    }

    if (widget.mode == ChatInputMode.publicAccount) {
      return _buildPublicAccountBar();
    }

    // === text 模式 ===
    final hp = widget.style.horizontalPadding;
    final vs = widget.style.verticalPadding;
    final bp = widget.style.bottomPadding;
    final isDesktop = widget.style == ChatInputStyle.desktop;

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
        child: isDesktop ? _buildDesktopInput() : _buildMobileInput(),
      ),
    );
  }

  /// 桌面端输入区域 — 微信风格：一个边框容器内含 输入框 + 工具栏+发送按钮
  Widget _buildDesktopInput() {
    final inputHeight = widget.style.fontSize * 1.8 * 5 +
        widget.style.inputVerticalPadding * 2 + 16;
    return Container(
      constraints: BoxConstraints(
        minHeight: inputHeight + 40,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E5E5), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 上半部分：输入框（独占一行，固定5行高度）
          SizedBox(
            height: inputHeight,
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: true,
              maxLines: null,
              expands: true,
              textInputAction: TextInputAction.newline,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: '输入消息...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: true,
                fillColor: Colors.white,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: widget.style.inputHorizontalPadding,
                  vertical: widget.style.inputVerticalPadding + 4,
                ),
                hintStyle: TextStyle(
                  fontSize: widget.style.fontSize,
                  color: Colors.grey[400],
                ),
                isDense: true,
              ),
              style: TextStyle(fontSize: widget.style.fontSize),
            ),
          ),

          // 分隔线
          Divider(height: 1, thickness: 1, color: const Color(0xFFE5E5E5)),

          // 下半部分：工具栏图标 + 发送按钮（同一行，在边框内部）
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              children: [
                _buildToolbarIcon(Icons.sentiment_satisfied_alt_outlined, '表情', widget.onEmoji),
                const SizedBox(width: 16),
                _buildToolbarIcon(Icons.attach_file_outlined, '发送文件', widget.onMoreOptions),
                const SizedBox(width: 16),
                _buildToolbarIcon(Icons.crop_outlined, '截图', widget.onScreenshot),
                const Spacer(),
                // 发送按钮 — 文字按钮，和工具栏同行
                TextButton(
                  onPressed:
                      (widget.isSending || widget.onSend == null)
                          ? null
                          : () => widget.onSend!(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    minimumSize: const Size(50, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: TextStyle(
                      fontSize: widget.style.fontSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('发送'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 移动端输入区域 — 保持原有样式
  Widget _buildMobileInput() {
    final ibs = widget.style.iconButtonSize;
    return Row(
      children: [
        SizedBox(
          width: ibs,
          height: ibs,
          child: IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 24),
            color: AppTheme.primaryColor,
            onPressed: widget.onMoreOptions,
            tooltip: '更多',
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '输入消息...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey[100],
              contentPadding: EdgeInsets.symmetric(
                horizontal: widget.style.inputHorizontalPadding,
                vertical: widget.style.inputVerticalPadding,
              ),
              hintStyle: TextStyle(fontSize: widget.style.fontSize),
            ),
            style: TextStyle(fontSize: widget.style.fontSize),
            maxLines: null,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => widget.onSend?.call(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: ibs,
          height: ibs,
          child: IconButton(
            icon: const Icon(Icons.send, size: 22),
            color: AppTheme.primaryColor,
            onPressed: (widget.isSending || widget.onSend == null)
                ? null
                : () => widget.onSend!(),
            tooltip: '发送',
          ),
        ),
      ],
    );
  }

  /// 构建工具栏图标按钮
  Widget _buildToolbarIcon(IconData icon, String tooltip, VoidCallback? onPressed) {
    return SizedBox(
      width: widget.style.iconButtonSize,
      height: widget.style.iconButtonSize,
      child: IconButton(
        icon: Icon(icon, size: 22),
        color: AppTheme.textSecondaryColor,
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }

  /// 构建公众号模式底部菜单栏
  Widget _buildPublicAccountBar() {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: 10,
        horizontal: widget.style.horizontalPadding,
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
