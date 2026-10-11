import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import '../models/message_model.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final String? senderAvatar;
  final String? senderName;
  final bool showName;
  final VoidCallback? onRetry;
  final VoidCallback? onImageTap;
  final Function(MessageModel)? onRecall;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.senderAvatar,
    this.senderName,
    this.showName = false,
    this.onRetry,
    this.onImageTap,
    this.onRecall,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bubbleMaxWidth = constraints.maxWidth * 0.6;
        return Padding(
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
                    GestureDetector(
                      onLongPress: () => _showMessageContextMenu(context),
                      child: _isImageMessage
                          ? _buildImageBubble(context, bubbleMaxWidth / 4)
                          : Container(
                              constraints:
                                  BoxConstraints(maxWidth: bubbleMaxWidth),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: message.status == MessageStatus.recalled
                                    ? Colors.grey[200]
                                    : isMe
                                        ? AppTheme.primaryColor
                                        : Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                                  bottomRight: Radius.circular(isMe ? 4 : 16),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: _buildContent(context),
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
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  bool get _isImageMessage =>
      message.type == MessageType.image &&
      message.status != MessageStatus.recalled;

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
          child: Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
        );
      case MessageStatus.recalled:
        return const SizedBox.shrink();
    }
  }

  Widget _buildContent(BuildContext context) {
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

    switch (message.type) {
      case MessageType.image:
        // 图片气泡由外层单独渲染，避免套上文字消息的蓝色背景
        return _buildImageContent(context, maxWidth: 220);
      case MessageType.text:
      default:
        return SelectableText(
          message.content,
          style: TextStyle(
            fontSize: 15,
            color: isMe ? Colors.white : AppTheme.textPrimaryColor,
            height: 1.4,
          ),
        );
    }
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
    final source = message.imageSource;
    if (source == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Center(
                child: source.startsWith('http')
                    ? PhotoView(
                        imageProvider: NetworkImage(source),
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: PhotoViewComputedScale.covered * 3,
                      )
                    : PhotoView(
                        imageProvider: FileImage(File(source)),
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

  void _showMessageContextMenu(BuildContext context) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        overlay.size.width * 0.25,
        overlay.size.height * 0.4,
        overlay.size.width * 0.25,
        overlay.size.height * 0.4,
      ),
      items: [
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
        if (message.canRecall)
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
      ],
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('消息已删除'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        break;
      case 'forward':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('转发功能开发中...'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        break;
    }
  }
}
