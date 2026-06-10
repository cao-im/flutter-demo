import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/message_model.dart';
import '../../models/contact_info_model.dart';
import '../message_bubble.dart';
import '../time_separator.dart';
import '../../theme/app_theme.dart';

/// 消息列表组件 — 所有会话类型共用（私聊/群聊/公众号/系统通知）
class MessageListWidget extends StatefulWidget {
  final ScrollController scrollController;
  final VoidCallback onScrollToBottom;
  final int targetId;
  final bool isGroup;
  final void Function(MessageModel) onRetry;

  const MessageListWidget({
    super.key,
    required this.scrollController,
    required this.onScrollToBottom,
    this.targetId = 0,
    this.isGroup = false,
    required this.onRetry,
  });

  @override
  State<MessageListWidget> createState() => _MessageListWidgetState();
}

class _MessageListWidgetState extends State<MessageListWidget> {
  /// 上一次记录的消息数量，用于检测新消息并自动滚动
  int _lastMessageCount = 0;

  /// 获取联系人信息
  Future<ContactInfo?> _getContactInfo(ChatProvider chatProvider) async {
    try {
      if (widget.targetId <= 0) return null;
      return await chatProvider.getContactInfoById(widget.targetId);
    } catch (e) {
      debugPrint('获取联系人信息失败: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ChatProvider, AuthProvider>(
      builder: (context, chatProvider, authProvider, _) {
        // 加载中状态
        if (chatProvider.isLoading && chatProvider.messages.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        // 空状态
        if (chatProvider.messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('暂无消息', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                const SizedBox(height: 8),
                Text('发送消息开始聊天吧~', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
              ],
            ),
          );
        }

        // 消息数量变化时自动滚动到底部
        final currentMessageCount = chatProvider.messages.length;
        if (currentMessageCount > _lastMessageCount && _lastMessageCount > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onScrollToBottom();
          });
        }
        _lastMessageCount = currentMessageCount;

        final currentUser = authProvider.user;
        final authUserId = currentUser?.id;

        // 异步获取联系人头像和昵称
        return FutureBuilder<ContactInfo?>(
          future: _getContactInfo(chatProvider),
          builder: (context, snapshot) {
            String? contactAvatar;
            String? contactName;

            if (snapshot.hasData && snapshot.data != null) {
              contactAvatar = snapshot.data!.avatar.isNotEmpty ? snapshot.data!.avatar : null;
              contactName = snapshot.data!.nickname.isNotEmpty ? snapshot.data!.nickname : snapshot.data!.username;
            }

            return ListView.builder(
              controller: widget.scrollController,
              reverse: true,
              itemCount: chatProvider.messages.length,
              itemBuilder: (context, index) {
                final reversedIndex = chatProvider.messages.length - 1 - index;
                final message = chatProvider.messages[reversedIndex];
                final previousMessage = (reversedIndex > 0)
                    ? chatProvider.messages[reversedIndex - 1]
                    : null;

                // 时间分割线判断
                final showTimeSeparator = shouldShowTimeSeparator(
                  message.timestamp,
                  previousMessage?.timestamp,
                );

                // 判断消息是否来自自己
                final isMe = message.isSent || message.senderId == authUserId;

                // 设置发送者头像和昵称
                String? senderAvatar;
                String? senderName;

                if (isMe) {
                  senderAvatar = currentUser?.avatar;
                  senderName = currentUser?.nickname ?? currentUser?.username;
                } else {
                  senderAvatar = contactAvatar;
                  senderName = contactName;
                }

                return Column(
                  children: [
                    if (showTimeSeparator)
                      TimeSeparator(time: message.timestamp),
                    MessageBubble(
                      message: message,
                      isMe: isMe,
                      senderAvatar: senderAvatar,
                      senderName: senderName,
                      showName: widget.isGroup && !isMe,
                      onRetry: () => widget.onRetry(message),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
