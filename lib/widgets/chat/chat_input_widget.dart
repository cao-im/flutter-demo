import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/chat_keyboard_provider.dart';
import 'emoji_picker_panel.dart';
import 'chat_overlay_panel.dart';

/// 输入栏模式
enum ChatInputMode {
  text,
  publicAccount,
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

  bool get isDesktop => this == desktop;
}

/// 底部输入栏组件
class ChatInputWidget extends StatefulWidget {
  final ChatInputMode mode;
  final TextEditingController controller;
  final VoidCallback? onSend;
  final bool isSending;
  final VoidCallback? onMoreOptions;
  final ChatInputStyle style;
  final VoidCallback? onEmoji;
  final VoidCallback? onScreenshot;

  /// 外部传入的 FocusNode（用于页面级键盘高度监听）
  /// 如果不传则内部自动创建
  final FocusNode? externalFocusNode;

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
    this.externalFocusNode,
  });

  @override
  State<ChatInputWidget> createState() => _ChatInputWidgetState();
}

class _ChatInputWidgetState extends State<ChatInputWidget> {
  late final FocusNode _focusNode;

  /// 桌面端：表情按钮的 GlobalKey，用于锚点定位
  final GlobalKey _emojiButtonKey = GlobalKey();

  /// 桌面端：当前显示的 OverlayEntry
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    // 桌面端：创建带键盘事件处理的 FocusNode
    if (widget.style.isDesktop) {
      _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    } else {
      _focusNode = widget.externalFocusNode ?? FocusNode();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) return KeyEventResult.ignored;

    if (HardwareKeyboard.instance.isShiftPressed) {
      // Shift+Enter: 插入换行，让 TextField 处理
      return KeyEventResult.ignored;
    }
    // Enter: 发送消息
    widget.onSend?.call();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _removeDesktopOverlay();
    // 仅在 FocusNode 是内部创建时才释放
    if (widget.externalFocusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  // ==================== 表情面板切换 ====================

  void _toggleEmojiPanel() {
    if (widget.style.isDesktop) {
      _toggleDesktopEmojiPopup();
    } else {
      // 移动端：通过 Provider 管理面板状态，实现丝滑切换
      final provider = Provider.of<ChatKeyboardProvider>(context, listen: false);
      final willShow = !provider.showEmojiPanel;

      // 先强制隐藏输入法，再切换面板状态
      _hideKeyboard().then((_) {
        if (!mounted) return;
        provider.toggleEmojiPanel(willShow);
        if (willShow) _focusNode.unfocus();
      });
    }
  }

  /// 强制隐藏系统输入法（解决输入法与表情面板共存的问题）
  Future<void> _hideKeyboard() async {
    _focusNode.unfocus();
    await SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  void _closeEmojiPanel() {
    final provider = Provider.of<ChatKeyboardProvider>(context, listen: false);
    if (provider.showEmojiPanel) {
      provider.toggleEmojiPanel(false);
    }
  }

  // ==================== 桌面端：锚点弹窗 ====================

  void _toggleDesktopEmojiPopup() {
    if (_overlayEntry != null) {
      _removeDesktopOverlay();
      return;
    }
    _showDesktopAnchoredPopup();
  }

  void _showDesktopAnchoredPopup() {
    final renderBox = _emojiButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => _AnchoredEmojiPopup(
        anchorOffset: offset,
        anchorSize: size,
        onEmojiSelected: _insertEmoji,
        onClose: _removeDesktopOverlay,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeDesktopOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // ==================== 表情插入 ====================

  void _insertEmoji(String emoji) {
    final text = widget.controller.text;
    final cursorPos = widget.controller.selection.baseOffset;
    final newText = '${text.substring(0, cursorPos)}$emoji${text.substring(cursorPos)}';
    widget.controller.text = newText;
    widget.controller.selection = TextSelection(
      baseOffset: cursorPos + emoji.length,
      extentOffset: cursorPos + emoji.length,
    );
  }

  // ==================== 构建 ====================

  @override
  Widget build(BuildContext context) {
    if (widget.mode == ChatInputMode.disabled) return const SizedBox.shrink();
    if (widget.mode == ChatInputMode.publicAccount) return _buildPublicAccountBar();

    final hp = widget.style.horizontalPadding;
    final vs = widget.style.verticalPadding;
    final bp = widget.style.bottomPadding;
    final isDesktop = widget.style.isDesktop;

    // 使用 Consumer 监听面板状态变化，实现动态高度
    return Consumer<ChatKeyboardProvider>(
      builder: (context, keyboardProvider, _) {
        final showEmojiPanel = keyboardProvider.showEmojiPanel;
        final panelHeight = keyboardProvider.panelHeight;
        final bottomInset = MediaQuery.of(context).padding.bottom;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 输入栏主体（始终在最上方）
            Container(
              padding: EdgeInsets.only(
                left: hp,
                right: hp,
                top: vs,
                // 移动端表情面板显示时，不加底部安全区（由面板承担）；否则正常加
                bottom: (!isDesktop && showEmojiPanel) ? bp : bottomInset + bp,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                bottom: isDesktop || !showEmojiPanel,
                child: isDesktop ? _buildDesktopInput() : _buildMobileInput(showEmojiPanel),
              ),
            ),

            // 移动端：表情面板在输入框下方展开，使用 Provider 动态高度
            if (!isDesktop)
              ChatOverlayPanel(
                visible: showEmojiPanel,
                height: panelHeight > 0 ? panelHeight : 260.0,
                isDesktop: false,
                contentBuilder: (_) => SafeArea(
                  top: false,
                  bottom: true,
                  child: EmojiPickerPanel(
                    onEmojiSelected: _insertEmoji,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ==================== 桌面端输入区域 ====================

  Widget _buildDesktopInput() {
    final inputHeight = widget.style.fontSize * 1.8 * 5 +
        widget.style.inputVerticalPadding * 2 + 16;
    return Container(
      constraints: BoxConstraints(minHeight: inputHeight + 40),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E5E5), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
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
                hintStyle: TextStyle(fontSize: widget.style.fontSize, color: Colors.grey[400]),
                isDense: true,
              ),
              style: TextStyle(fontSize: widget.style.fontSize),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E5E5)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              children: [
                // 表情按钮 — 带 GlobalKey 用于锚点定位
                _buildToolbarIconWithKey(
                  Icons.sentiment_satisfied_alt_outlined,
                  '表情',
                  _toggleEmojiPanel,
                  key: _emojiButtonKey,
                ),
                const SizedBox(width: 16),
                _buildToolbarIcon(Icons.attach_file_outlined, '发送文件', widget.onMoreOptions),
                const SizedBox(width: 16),
                _buildToolbarIcon(Icons.crop_outlined, '截图', widget.onScreenshot),
                const Spacer(),
                TextButton(
                  onPressed: (widget.isSending || widget.onSend == null) ? null : () => widget.onSend!(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    minimumSize: const Size(50, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: TextStyle(fontSize: widget.style.fontSize, fontWeight: FontWeight.w500),
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

  // ==================== 移动端输入区域 ====================

  Widget _buildMobileInput(bool showEmojiPanel) {
    final ibs = widget.style.iconButtonSize;
    return Row(
      children: [
        SizedBox(
          width: ibs,
          height: ibs,
          child: IconButton(
            icon: Icon(
              showEmojiPanel ? Icons.keyboard_outlined : Icons.sentiment_satisfied_alt_outlined,
              size: 24,
            ),
            color: AppTheme.primaryColor,
            onPressed: _toggleEmojiPanel,
            tooltip: showEmojiPanel ? '键盘' : '表情',
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
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
            onTap: () => _closeEmojiPanel(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: ibs,
          height: ibs,
          child: IconButton(icon: const Icon(Icons.add_circle_outline, size: 24), color: AppTheme.primaryColor, onPressed: widget.onMoreOptions, tooltip: '更多'),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: ibs,
          height: ibs,
          child: IconButton(icon: const Icon(Icons.send, size: 22), color: AppTheme.primaryColor, onPressed: (widget.isSending || widget.onSend == null) ? null : () => widget.onSend!(), tooltip: '发送'),
        ),
      ],
    );
  }

  // ==================== 工具方法 ====================

  Widget _buildToolbarIcon(IconData icon, String tooltip, VoidCallback? onPressed) {
    return SizedBox(
      width: widget.style.iconButtonSize,
      height: widget.style.iconButtonSize,
      child: IconButton(icon: Icon(icon, size: 22), color: AppTheme.textSecondaryColor, onPressed: onPressed, tooltip: tooltip),
    );
  }

  /// 带 GlobalKey 的工具栏图标（桌面端表情按钮用）
  Widget _buildToolbarIconWithKey(IconData icon, String tooltip, VoidCallback? onPressed, {required Key key}) {
    return SizedBox(
      key: key,
      width: widget.style.iconButtonSize,
      height: widget.style.iconButtonSize,
      child: IconButton(icon: Icon(icon, size: 22), color: AppTheme.textSecondaryColor, onPressed: onPressed, tooltip: tooltip),
    );
  }

  Widget _buildPublicAccountBar() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10, horizontal: widget.style.horizontalPadding),
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppTheme.dividerColor))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _buildPAMenuItem(Icons.article_outlined, '文章'),
        _buildPAMenuItem(Icons.chat_bubble_outline, '消息'),
        _buildPAMenuItem(Icons.star_outline, '收藏'),
        _buildPAMenuItem(Icons.info_outline, '简介'),
      ]),
    );
  }

  Widget _buildPAMenuItem(IconData icon, String label) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 24, color: Colors.grey[600]),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
    ]);
  }
}

// ==================== 桌面端锚点浮层弹窗 ====================

/// 桌面端表情选择弹窗 — 锚定在表情按钮上方，带小箭头
class _AnchoredEmojiPopup extends StatelessWidget {
  final Offset anchorOffset;
  final Size anchorSize;
  final void Function(String emoji) onEmojiSelected;
  final VoidCallback onClose;

  const _AnchoredEmojiPopup({
    required this.anchorOffset,
    required this.anchorSize,
    required this.onEmojiSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    const popupWidth = 380.0;
    const popupHeight = 360.0;
    const arrowSize = 10.0;       // 箭头高度
    const arrowWidth = 18.0;     // 箭头底部宽度
    const bottomGap = 6.0;       // 弹窗底部与工具栏的间距

    // 弹窗位置：居中对齐到按钮上方
    final left = anchorOffset.dx + anchorSize.width / 2 - popupWidth / 2;
    final top = anchorOffset.dy - popupHeight - arrowSize - bottomGap;

    return GestureDetector(
      onTap: onClose,
      behavior: HitTestBehavior.opaque,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 小箭头（向下指向按钮）— 用 ClipPath 确保不溢出
                  ClipPath(
                    clipper: _ArrowClipper(),
                    child: Container(
                      width: arrowWidth,
                      height: arrowSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 表情面板内容卡片
                  Container(
                    width: popupWidth,
                    height: popupHeight,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: EmojiPickerPanel(
                      onEmojiSelected: (emoji) {
                        onEmojiSelected(emoji);
                        onClose();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 箭头裁剪器 — 向下三角形的形状
class _ArrowClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _ArrowClipper oldClipper) => false;
}
