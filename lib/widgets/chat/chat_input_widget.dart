import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/chat_keyboard_provider.dart';
import '../../services/voice_recorder.dart';
import 'emoji_picker_panel.dart';
import 'chat_overlay_panel.dart';
import 'windows_ime_caret.dart';

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

  /// 录音结束且达到最短时长后回调本地文件路径和秒数。
  final Future<void> Function(String path, int durationSeconds)? onVoiceRecorded;

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
    this.onVoiceRecorded,
  });

  @override
  State<ChatInputWidget> createState() => _ChatInputWidgetState();
}

class _ChatInputWidgetState extends State<ChatInputWidget> {
  late final FocusNode _focusNode;

  /// 桌面端：表情按钮的 GlobalKey，用于锚点定位
  final GlobalKey _emojiButtonKey = GlobalKey();

  /// 桌面端输入框，用于测量真实光标位置（修正 Windows 输入法候选窗）
  final GlobalKey _desktopTextFieldKey = GlobalKey();

  WindowsImeCaret? _windowsImeCaret;

  /// 桌面端：当前显示的 OverlayEntry
  OverlayEntry? _overlayEntry;

  final VoiceRecorder _voiceRecorder = VoiceRecorder();
  Timer? _recordTicker;
  Timer? _waveTicker;
  DateTime? _recordStartedAt;
  bool _recording = false;
  bool _recordStopInFlight = false;
  bool _cancelArmed = false;
  bool _fingerDown = false;
  bool _voiceMode = false;
  int _recordSeconds = 0;
  Offset? _pointerDown;
  final List<double> _waveLevels = [];
  bool _samplingWave = false;

  static const int _maxRecordSeconds = 60;
  static const int _minRecordMillis = 800;

  @override
  void initState() {
    super.initState();
    // 桌面端：创建带键盘事件处理的 FocusNode
    if (widget.style.isDesktop) {
      _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
      if (WindowsImeCaret.supported) {
        _windowsImeCaret = WindowsImeCaret(
          controller: widget.controller,
          focusNode: _focusNode,
          textFieldKey: _desktopTextFieldKey,
        )..bind();
      }
    } else {
      _focusNode = widget.externalFocusNode ?? FocusNode();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_recording && event.logicalKey == LogicalKeyboardKey.escape) {
      _finishRecord(send: false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey != LogicalKeyboardKey.enter) return KeyEventResult.ignored;
    if (_recording) {
      _finishRecord(send: true);
      return KeyEventResult.handled;
    }

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
    _recordTicker?.cancel();
    _waveTicker?.cancel();
    _voiceRecorder.dispose();
    _removeDesktopOverlay();
    _windowsImeCaret?.dispose();
    _windowsImeCaret = null;
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
            if (_recording && !isDesktop) _buildHoldBanner(),
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
    // 不要用 expands:true 撑满固定高度：Windows 上这样上报的光标矩形会偏，
    // 候选窗容易盖住输入文字。改成跟 Web textarea 一样按内容增高，候选窗随光标走。
    final lineHeight = widget.style.fontSize * 1.8;
    final verticalPad = widget.style.inputVerticalPadding + 4;
    final minHeight = lineHeight * 5 + verticalPad * 2;
    final maxHeight = lineHeight * 8 + verticalPad * 2;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E5E5), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight, maxHeight: maxHeight),
            child: _recording
                ? _buildDesktopRecordingPanel()
                : TextField(
              key: _desktopTextFieldKey,
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: true,
              keyboardType: TextInputType.multiline,
              maxLines: null,
              minLines: 5,
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
                  vertical: verticalPad,
                ),
                hintStyle: TextStyle(fontSize: widget.style.fontSize, color: Colors.grey[400]),
                isDense: true,
              ),
              style: TextStyle(fontSize: widget.style.fontSize, height: 1.8),
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
                _buildToolbarIcon(
                  _recording ? Icons.mic : Icons.mic_none_outlined,
                  _recording ? '结束并发送' : '语音',
                  _onDesktopMic,
                  color: _recording ? const Color(0xFFFA5151) : null,
                ),
                const SizedBox(width: 16),
                _buildToolbarIcon(Icons.crop_outlined, '截图', widget.onScreenshot),
                const Spacer(),
                if (_recording) ...[
                  TextButton(
                    onPressed: () => _finishRecord(send: false),
                    style: _toolbarTextButtonStyle(AppTheme.textSecondaryColor),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => _finishRecord(send: true),
                    style: _toolbarTextButtonStyle(AppTheme.primaryColor),
                    child: const Text('发送'),
                  ),
                ] else
                  TextButton(
                    onPressed: (widget.isSending || widget.onSend == null) ? null : () => widget.onSend!(),
                    style: _toolbarTextButtonStyle(AppTheme.primaryColor),
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
              _voiceMode ? Icons.keyboard_outlined : Icons.mic_none_outlined,
              size: 24,
            ),
            color: AppTheme.primaryColor,
            onPressed: _toggleVoiceMode,
            tooltip: _voiceMode ? '键盘' : '语音',
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _voiceMode ? _buildHoldToTalk() : TextField(
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
        if (!_voiceMode)
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
        SizedBox(
          width: ibs,
          height: ibs,
          child: IconButton(icon: const Icon(Icons.add_circle_outline, size: 24), color: AppTheme.primaryColor, onPressed: widget.onMoreOptions, tooltip: '更多'),
        ),
        if (!_voiceMode) ...[
          const SizedBox(width: 4),
          SizedBox(
            width: ibs,
            height: ibs,
            child: IconButton(icon: const Icon(Icons.send, size: 22), color: AppTheme.primaryColor, onPressed: (widget.isSending || widget.onSend == null) ? null : () => widget.onSend!(), tooltip: '发送'),
          ),
        ],
      ],
    );
  }

  Widget _buildHoldToTalk() {
    final label = _recording
        ? (_cancelArmed ? '松开 取消' : '松开 结束')
        : '按住 说话';
    final bg = _recording
        ? (_cancelArmed ? const Color(0xFFFA5151) : const Color(0xFFD6D6D6))
        : const Color(0xFFF2F2F2);
    return Listener(
      onPointerDown: (event) {
        _pointerDown = event.position;
        _fingerDown = true;
        _beginRecord(hold: true);
      },
      onPointerMove: (event) {
        final origin = _pointerDown;
        if (origin == null) return;
        final cancel = event.position.dy < origin.dy - 56;
        if (cancel != _cancelArmed && mounted) {
          setState(() => _cancelArmed = cancel);
        }
      },
      onPointerUp: (_) {
        _fingerDown = false;
        _pointerDown = null;
        _finishRecord(send: !_cancelArmed);
      },
      onPointerCancel: (_) {
        _fingerDown = false;
        _pointerDown = null;
        _finishRecord(send: false);
      },
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: widget.style.fontSize,
            fontWeight: FontWeight.w600,
            color: _cancelArmed ? Colors.white : const Color(0xFF4E5964),
          ),
        ),
      ),
    );
  }

  Widget _buildHoldBanner() {
    final cancel = _cancelArmed;
    final ss = _recordSeconds.toString().padLeft(2, '0');
    return Material(
      color: cancel ? const Color(0xFFFA5151) : const Color(0xFF07C160),
      child: SizedBox(
        height: cancel ? 72 : 108,
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(cancel ? Icons.undo : Icons.mic, color: Colors.white, size: 22),
            const SizedBox(height: 6),
            if (!cancel)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: _RecordWaveform(
                  levels: _waveLevels,
                  color: Colors.white,
                  height: 22,
                  barCount: 28,
                ),
              ),
            if (!cancel) const SizedBox(height: 4),
            Text(
              cancel ? '松开手指，取消发送' : '手指上滑，取消发送  0:$ss',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopRecordingPanel() {
    final ss = _recordSeconds.toString().padLeft(2, '0');
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _finishRecord(send: false);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          _finishRecord(send: true);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ColoredBox(
        color: const Color(0xFFFFF8F8),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mic, color: Color(0xFFFA5151), size: 28),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: _RecordWaveform(
                  levels: _waveLevels,
                  color: const Color(0xFFFA5151),
                  height: 36,
                  barCount: 42,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '正在录音 0:$ss',
                style: const TextStyle(fontSize: 16, color: Color(0xFF4E5964), fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter 发送，Esc 取消 · 最长 $_maxRecordSeconds 秒',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle _toolbarTextButtonStyle(Color color) {
    return TextButton.styleFrom(
      foregroundColor: color,
      minimumSize: const Size(50, 32),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: TextStyle(
        inherit: false,
        fontSize: widget.style.fontSize,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  void _onDesktopMic() {
    if (widget.onVoiceRecorded == null) return;
    if (_recording) {
      _finishRecord(send: true);
      return;
    }
    _removeDesktopOverlay();
    _focusNode.unfocus();
    _beginRecord(hold: false);
  }

  void _toggleVoiceMode() {
    if (_recording) return;
    setState(() => _voiceMode = !_voiceMode);
    if (_voiceMode) {
      _focusNode.unfocus();
      Provider.of<ChatKeyboardProvider>(context, listen: false).toggleEmojiPanel(false);
    } else {
      _focusNode.requestFocus();
    }
  }

  Future<void> _beginRecord({required bool hold}) async {
    if (_recording || _recordStopInFlight || widget.onVoiceRecorded == null) return;
    try {
      await _voiceRecorder.start();
    } catch (e) {
      _showTip(e.toString().replaceFirst('Bad state: ', ''));
      return;
    }
    if (!mounted) {
      await _voiceRecorder.cancel();
      return;
    }
    HapticFeedback.mediumImpact();
    _recordStartedAt = DateTime.now();
    _waveLevels
      ..clear()
      ..addAll(List.filled(24, 0.06));
    _recordTicker?.cancel();
    _recordTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _recordStartedAt == null) return;
      final elapsed = DateTime.now().difference(_recordStartedAt!).inSeconds;
      setState(() => _recordSeconds = elapsed);
      if (elapsed >= _maxRecordSeconds) {
        _finishRecord(send: true);
      }
    });
    _waveTicker?.cancel();
    _waveTicker = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _sampleWave();
    });
    setState(() {
      _recording = true;
      _recordSeconds = 0;
    });
    if (hold && !_fingerDown) {
      await _finishRecord(send: !_cancelArmed);
    }
  }

  Future<void> _finishRecord({required bool send}) async {
    if (!_recording || _recordStopInFlight) return;
    _recordStopInFlight = true;
    _recordTicker?.cancel();
    _recordTicker = null;
    _waveTicker?.cancel();
    _waveTicker = null;
    final started = _recordStartedAt;
    final discard = !send || _cancelArmed;
    setState(() {
      _recording = false;
      _cancelArmed = false;
    });
    try {
      if (discard) {
        await _voiceRecorder.cancel();
        return;
      }
      final result = await _voiceRecorder.stop();
      if (result == null || started == null) return;
      if (result.durationMillis < _minRecordMillis) {
        try {
          await File(result.path).delete();
        } catch (_) {}
        _showTip('说话时间太短');
        return;
      }
      final seconds = (result.durationMillis / 1000).ceil().clamp(1, _maxRecordSeconds);
      await widget.onVoiceRecorded?.call(result.path, seconds);
    } catch (e) {
      _showTip(e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      _recordStopInFlight = false;
      _recordStartedAt = null;
    }
  }

  Future<void> _sampleWave() async {
    if (_samplingWave || !_recording || !mounted) return;
    _samplingWave = true;
    try {
      final level = await _voiceRecorder.readLevel();
      if (!_recording || !mounted) return;
      setState(() {
        _waveLevels.add(level);
        if (_waveLevels.length > 64) {
          _waveLevels.removeAt(0);
        }
      });
    } finally {
      _samplingWave = false;
    }
  }

  void _showTip(String text) {
    if (!mounted || text.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ==================== 工具方法 ====================

  Widget _buildToolbarIcon(IconData icon, String tooltip, VoidCallback? onPressed, {Color? color}) {
    return SizedBox(
      width: widget.style.iconButtonSize,
      height: widget.style.iconButtonSize,
      child: IconButton(
        icon: Icon(icon, size: 22),
        color: color ?? AppTheme.textSecondaryColor,
        onPressed: onPressed,
        tooltip: tooltip,
      ),
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

class _RecordWaveform extends StatelessWidget {
  final List<double> levels;
  final Color color;
  final double height;
  final int barCount;

  const _RecordWaveform({
    required this.levels,
    required this.color,
    required this.height,
    required this.barCount,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _RecordWavePainter(
          levels: levels,
          color: color,
          barCount: barCount,
        ),
      ),
    );
  }
}

class _RecordWavePainter extends CustomPainter {
  final List<double> levels;
  final Color color;
  final int barCount;

  _RecordWavePainter({
    required this.levels,
    required this.color,
    required this.barCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final samples = levels.length >= barCount
        ? levels.sublist(levels.length - barCount)
        : <double>[
            ...List.filled(barCount - levels.length, 0.06),
            ...levels,
          ];
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round;
    final gap = 3.0;
    final barWidth = ((size.width - gap * (barCount - 1)) / barCount).clamp(2.0, 5.0);
    final step = barWidth + gap;
    final midY = size.height / 2;
    for (var i = 0; i < samples.length; i++) {
      final level = samples[i].clamp(0.06, 1.0);
      final barHeight = (size.height * level).clamp(2.0, size.height);
      final x = i * step;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + barWidth / 2, midY),
            width: barWidth,
            height: barHeight,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RecordWavePainter oldDelegate) => true;
}
