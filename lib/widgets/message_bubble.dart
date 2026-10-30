import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import '../navigation/app_route.dart';
import '../models/message_model.dart';
import '../providers/chat_provider.dart';
import '../services/media_store.dart';
import '../pages/full_text_page.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';
import 'chat/voice_message_content.dart';
import 'chat/file_message_content.dart';
import 'chat/video_message_content.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final String? senderAvatar;
  final String? senderName;
  final bool showName;
  final bool isGroup;
  final VoidCallback? onRetry;
  final VoidCallback? onImageTap;
  final Function(MessageModel)? onRecall;
  final void Function(MessageModel)? onDelete;
  final void Function(MessageModel)? onQuote;
  final void Function(MessageModel)? onForward;
  final void Function(MessageModel)? onFavorite;
  final VoidCallback? onQuoteTap;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onTap;
  final bool highlighted;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.senderAvatar,
    this.senderName,
    this.showName = false,
    this.isGroup = false,
    this.onRetry,
    this.onImageTap,
    this.onRecall,
    this.onDelete,
    this.onQuote,
    this.onForward,
    this.onFavorite,
    this.onQuoteTap,
    this.onAvatarTap,
    this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bubbleMaxWidth = constraints.maxWidth * 0.6;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          color: highlighted
              ? AppTheme.primaryColor.withValues(alpha: 0.12)
              : Colors.transparent,
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe) ...[
                AvatarWidget(
                  imageUrl: senderAvatar,
                  name: senderName,
                  size: 40,
                  onTap: onAvatarTap,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment:
                      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showName && !isMe && senderName != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          senderName!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (message.replyPreview != null &&
                        message.replyPreview!.isNotEmpty)
                      _buildQuoteStrip(context, bubbleMaxWidth),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (isMe && message.status == MessageStatus.failed) ...[
                          _buildStatusIcon(),
                          const SizedBox(width: 6),
                        ],
                        Builder(
                          builder: (bubbleContext) {
                            return _MessageMenuTarget(
                          desktop: _rightClickMenu,
                          onTap: onTap,
                          onOpen: (globalPosition) => _showMessageContextMenu(
                            bubbleContext,
                            globalPosition: globalPosition,
                          ),
                          child: _isImageMessage
                              ? _buildImageBubble(context, bubbleMaxWidth / 4)
                              : _isFileMessage
                                  ? FileMessageContent(message: message)
                                  : _isVideoMessage
                                      ? VideoMessageContent(message: message)
                                      : Container(
                                  constraints: BoxConstraints(
                                    maxWidth: bubbleMaxWidth,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: message.status ==
                                            MessageStatus.recalled
                                        ? AppTheme.inputFill(context)
                                        : isMe
                                            ? AppTheme.primaryColor
                                            : AppTheme.bubbleIncoming(context),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft:
                                          Radius.circular(isMe ? 16 : 4),
                                      bottomRight:
                                          Radius.circular(isMe ? 4 : 16),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: _buildContent(
                                    context,
                                    maxTextWidth: bubbleMaxWidth - 32,
                                  ),
                                ),
                            );
                          },
                        ),
                      ],
                    ),
                    if (isMe &&
                        message.readCount != null &&
                        message.status != MessageStatus.recalled)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _readLabel(),
                          style: TextStyle(
                            fontSize: 11,
                            color: message.readCount! > 0
                                ? const Color(0xFF07C160)
                                : const Color(0xFFB2B2B2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 8),
                AvatarWidget(
                  imageUrl: senderAvatar,
                  name: senderName,
                  size: 40,
                  onTap: onAvatarTap,
                ),
              ],
            ],
          ),
        ),
        );
      },
    );
  }

  bool get _rightClickMenu {
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  bool get _isImageMessage =>
      message.type == MessageType.image &&
      message.status != MessageStatus.recalled;

  bool get _isFileMessage =>
      message.type == MessageType.file &&
      message.status != MessageStatus.recalled;

  bool get _isVideoMessage =>
      message.type == MessageType.video &&
      message.status != MessageStatus.recalled;

  String _readLabel() {
    final count = message.readCount ?? 0;
    if (!isGroup) return count > 0 ? '已读' : '未读';
    return count > 0 ? '已读 $count' : '未读';
  }

  Widget _buildStatusIcon() {
    switch (message.status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
          ),
        );
      case MessageStatus.sent:
        return Icon(Icons.check, size: 14, color: Colors.white70);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 14, color: Colors.white70);
      case MessageStatus.read:
        return Icon(Icons.done_all, size: 14, color: Colors.blueAccent);
      case MessageStatus.failed:
        return GestureDetector(
          onTap: onRetry,
          child: const Icon(Icons.error_outline, size: 20, color: Colors.redAccent),
        );
      case MessageStatus.recalled:
        return const SizedBox.shrink();
    }
  }

  static const int _foldMaxLines = 6;

  Widget _buildQuoteStrip(BuildContext context, double maxWidth) {
    final name = message.replySenderName;
    final preview = message.replyPreview ?? '';
    final strip = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.isDark(context)
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: AppTheme.primaryColor, width: 3),
        ),
      ),
      child: Text(
        name == null || name.isEmpty ? preview : '$name：$preview',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context), height: 1.3),
      ),
    );
    if (onQuoteTap == null) return strip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onQuoteTap,
        child: strip,
      ),
    );
  }

  Widget _buildContent(BuildContext context, {required double maxTextWidth}) {
    if (message.status == MessageStatus.recalled) {
      return Text(
        '已撤回',
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[500],
          fontStyle: FontStyle.italic,
        ),
      );
    }

    if (message.isCallRecord) {
      return _buildCallRecord(context);
    }

    switch (message.type) {
      case MessageType.image:
        // 图片气泡由外层单独渲染，避免套上文字消息的蓝色背景
        return _buildImageContent(context, maxWidth: 220);
      case MessageType.audio:
        return VoiceMessageContent(message: message, isMe: isMe);
      case MessageType.file:
        return FileMessageContent(message: message);
      case MessageType.video:
        return VideoMessageContent(message: message);
      case MessageType.text:
      default:
        return _buildFoldableText(context, maxTextWidth);
    }
  }

  Widget _buildCallRecord(BuildContext context) {
    final color = isMe ? Colors.white : AppTheme.textPrimary(context);
    final icon = Icon(
      message.callWithVideo ? Icons.videocam : Icons.phone,
      size: 18,
      color: color,
    );
    final label = Text(
      message.content,
      style: TextStyle(fontSize: 15, color: color, height: 1.4),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: isMe
          ? [label, const SizedBox(width: 6), icon]
          : [icon, const SizedBox(width: 6), label],
    );
  }

  Widget _buildFoldableText(BuildContext context, double maxTextWidth) {
    final style = TextStyle(
      fontSize: 15,
      color: isMe ? Colors.white : AppTheme.textPrimary(context),
      height: 1.4,
    );
    final exceeds = _textExceedsMaxLines(
      message.content,
      style,
      maxTextWidth,
      _foldMaxLines,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _mentionText(
          message.content,
          style,
          maxLines: exceeds ? _foldMaxLines : null,
          overflow: exceeds ? TextOverflow.ellipsis : TextOverflow.visible,
        ),
        if (exceeds)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  AppRoute(
                    builder: (_) => FullTextPage(content: message.content),
                  ),
                );
              },
              child: Text(
                '全文',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isMe
                      ? Colors.white.withValues(alpha: 0.92)
                      : AppTheme.primaryColor,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _mentionText(
    String content,
    TextStyle style, {
    int? maxLines,
    TextOverflow overflow = TextOverflow.clip,
  }) {
    final pattern = RegExp(r'@[^\s@]+');
    if (!pattern.hasMatch(content)) {
      return Text(content, style: style, maxLines: maxLines, overflow: overflow);
    }
    final mentionStyle = style.copyWith(
      color: isMe ? const Color(0xFFFFE08A) : AppTheme.primaryColor,
      fontWeight: FontWeight.w600,
    );
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in pattern.allMatches(content)) {
      if (match.start > start) {
        spans.add(TextSpan(text: content.substring(start, match.start), style: style));
      }
      spans.add(TextSpan(text: match.group(0), style: mentionStyle));
      start = match.end;
    }
    if (start < content.length) {
      spans.add(TextSpan(text: content.substring(start), style: style));
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  bool _textExceedsMaxLines(
    String text,
    TextStyle style,
    double maxWidth,
    int maxLines,
  ) {
    if (text.isEmpty) return false;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth > 0 ? maxWidth : 240);
    return painter.didExceedMaxLines;
  }

  /// 图片消息：无彩色气泡底，仅圆角 + 轻阴影，收发两端一致
  Widget _buildImageBubble(BuildContext context, double maxWidth) {
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _buildImageContent(context, maxWidth: maxWidth),
    );
  }

  /// 按原图比例缩放：限制最大宽高，不强制裁成方图
  Widget _buildImageContent(BuildContext context, {required double maxWidth}) {
    final source = message.imageSource;
    final maxHeight = maxWidth * 1.6;

    return GestureDetector(
      onTap: () => _showImageViewer(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: source == null
            ? _buildImagePlaceholder(maxWidth)
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: maxHeight,
                ),
                child: source.startsWith('http')
                    ? Image.network(
                        source,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildImagePlaceholder(maxWidth),
                      )
                    : Image.file(
                        File(source),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildImagePlaceholder(maxWidth),
                      ),
              ),
      ),
    );
  }

  Widget _buildImagePlaceholder(double width) {
    return Container(
      width: width,
      height: width * 0.75,
      color: Colors.grey[300],
      child: const Icon(Icons.image, size: 48),
    );
  }

  Future<void> _showImageViewer(BuildContext context) async {
    var source = message.imageSource;
    if (source == null) return;
    if (source.startsWith('http://') || source.startsWith('https://')) {
      final name = Uri.tryParse(source)?.path.split('/').last;
      try {
        final saved = await MediaStore.ensure(
          knownPath: message.localPath,
          remoteUrl: source,
          name: (name == null || name.isEmpty) ? 'image.jpg' : name,
        );
        if (saved.path.isNotEmpty) {
          source = saved.path;
          final key = message.midKey;
          if (key != null && key.isNotEmpty && context.mounted) {
            await context.read<ChatProvider>().rememberMediaPath(key, saved.path);
          }
        }
      } catch (error) {
        debugPrint('保存图片失败: $error');
      }
    }
    final resolved = source;
    if (!context.mounted || resolved == null || resolved.isEmpty) return;
    final display = resolved;

    Navigator.push(
      context,
      AppRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Center(
                child: display.startsWith('http')
                    ? PhotoView(
                        imageProvider: NetworkImage(display),
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: PhotoViewComputedScale.covered * 3,
                      )
                    : PhotoView(
                        imageProvider: FileImage(File(display)),
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: PhotoViewComputedScale.covered * 3,
                      ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: SafeArea(
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessageContextMenu(BuildContext context, {Offset? globalPosition}) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null || !overlay.hasSize) return;

    final RelativeRect position;
    if (globalPosition != null) {
      final local = overlay.globalToLocal(globalPosition);
      position = RelativeRect.fromRect(
        Rect.fromLTWH(local.dx, local.dy, 0, 0),
        Offset.zero & overlay.size,
      );
    } else {
      final bubble = context.findRenderObject() as RenderBox?;
      if (bubble == null || !bubble.hasSize) return;
      final offset = bubble.localToGlobal(Offset.zero, ancestor: overlay);
      position = RelativeRect.fromRect(
        Rect.fromLTWH(offset.dx, offset.dy, bubble.size.width, bubble.size.height),
        Offset.zero & overlay.size,
      );
    }

    final items = <PopupMenuEntry<String>>[
        if (!message.isCallRecord)
          PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 20),
              const SizedBox(width: 8),
              const Text('复制'),
            ],
          ),
        ),
        if (onQuote != null && !message.isCallRecord && message.status != MessageStatus.recalled)
          PopupMenuItem(
            value: 'quote',
            child: Row(
              children: [
                const Icon(Icons.format_quote, size: 20),
                const SizedBox(width: 8),
                const Text('引用'),
              ],
            ),
          ),
        if (message.canRecall && !message.isCallRecord)
          PopupMenuItem(
            value: 'recall',
            child: Row(
              children: [
                const Icon(Icons.undo, size: 20),
                const SizedBox(width: 8),
                const Text('撤回'),
              ],
            ),
          ),
        if (onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete, size: 20, color: AppTheme.errorColor),
                const SizedBox(width: 8),
                const Text('删除'),
              ],
            ),
          ),
        if (onFavorite != null && message.type != MessageType.notice && message.status != MessageStatus.recalled)
          PopupMenuItem(
            value: 'favorite',
            child: Row(
              children: [
                const Icon(Icons.star_outline, size: 20),
                const SizedBox(width: 8),
                const Text('收藏'),
              ],
            ),
          ),
        if (!message.isCallRecord)
          PopupMenuItem(
          value: 'forward',
          child: Row(
            children: [
              const Icon(Icons.forward, size: 20),
              const SizedBox(width: 8),
              const Text('转发'),
            ],
          ),
        ),
      ];
    if (items.isEmpty) return;

    showMenu(
      context: context,
      position: position,
      items: items,
    ).then((value) {
      if (value != null && context.mounted) {
        _handleMenuAction(value, context);
      }
    });
  }

  void _handleMenuAction(String action, BuildContext context) {
    switch (action) {
      case 'copy':
        Clipboard.setData(ClipboardData(text: message.content));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已复制到剪贴板'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        break;
      case 'recall':
        if (onRecall != null) {
          onRecall!(message);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('撤回消息: ${message.displayText}'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
        break;
      case 'delete':
        onDelete?.call(message);
        break;
      case 'quote':
        onQuote?.call(message);
        break;
      case 'favorite':
        onFavorite?.call(message);
        break;
      case 'forward':
        if (onForward != null) {
          onForward!(message);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('转发功能开发中...'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
        break;
    }
  }
}

class _MessageMenuTarget extends StatelessWidget {
  final bool desktop;
  final Widget child;
  final VoidCallback? onTap;
  final void Function(Offset? globalPosition) onOpen;

  const _MessageMenuTarget({
    required this.desktop,
    required this.child,
    required this.onOpen,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (kIsWeb && desktop) BrowserContextMenu.disableContextMenu();
      },
      onExit: (_) {
        if (kIsWeb && desktop) BrowserContextMenu.enableContextMenu();
      },
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: desktop ? null : () => onOpen(null),
        onSecondaryTapDown: desktop ? (details) => onOpen(details.globalPosition) : null,
        child: child,
      ),
    );
  }
}
