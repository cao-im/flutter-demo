import 'dart:async';

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
  final void Function(MessageModel)? onRecall;
  final void Function(MessageModel)? onDelete;
  final void Function(MessageModel)? onQuote;
  final void Function(MessageModel)? onForward;
  final void Function(MessageModel)? onFavorite;
  final void Function(MessageModel message, bool isMe)? onAvatarTap;

  const MessageListWidget({
    super.key,
    required this.scrollController,
    required this.onScrollToBottom,
    this.targetId = 0,
    this.isGroup = false,
    required this.onRetry,
    this.onRecall,
    this.onDelete,
    this.onQuote,
    this.onForward,
    this.onFavorite,
    this.onAvatarTap,
  });

  @override
  State<MessageListWidget> createState() => _MessageListWidgetState();
}

class _MessageListWidgetState extends State<MessageListWidget> {
  /// 上一次记录的消息数量，用于检测新消息并自动滚动
  int _lastMessageCount = 0;
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightKey;
  String? _pendingFocus;
  Timer? _highlightTimer;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  GlobalKey _keyFor(String id) {
    return _messageKeys.putIfAbsent(id, GlobalKey.new);
  }

  String _anchor(MessageModel message) => message.midKey ?? message.id;

  bool _matches(MessageModel item, String focus) {
    return item.midKey == focus || item.id == focus || 'l${item.id}' == focus;
  }

  void _scheduleFocus(String focus) {
    if (_pendingFocus == focus) return;
    final messages = context.read<ChatProvider>().messages;
    final dataIndex = messages.indexWhere((item) => _matches(item, focus));
    _pendingFocus = focus;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final chat = context.read<ChatProvider>();
      if (chat.focusMessageKey != focus) {
        _pendingFocus = null;
        return;
      }
      chat.clearFocusMessage();
      if (dataIndex < 0) {
        _pendingFocus = null;
        _showMissing('没有找到这条消息');
        return;
      }
      final current = chat.messages;
      final index = dataIndex < current.length && _matches(current[dataIndex], focus)
          ? dataIndex
          : current.indexWhere((item) => _matches(item, focus));
      if (index < 0) {
        _pendingFocus = null;
        _showMissing('没有找到这条消息');
        return;
      }
      await _reveal(current[index], index, current, missingText: '没有找到这条消息');
      _pendingFocus = null;
    });
  }

  Future<void> _jumpToQuoted(MessageModel message) async {
    final replyMid = message.replyMsgId;
    if (replyMid == null || replyMid <= 0) {
      _showMissing('原消息不在当前记录中');
      return;
    }
    final messages = context.read<ChatProvider>().messages;
    final dataIndex = messages.indexWhere((item) => item.mid == replyMid || item.midKey == '$replyMid');
    if (dataIndex < 0) {
      _showMissing('原消息不在当前记录中');
      return;
    }
    await _reveal(messages[dataIndex], dataIndex, messages, missingText: '原消息不在当前记录中');
  }

  Future<void> _reveal(
    MessageModel message,
    int dataIndex,
    List<MessageModel> messages, {
    required String missingText,
  }) async {
    final anchor = _anchor(message);
    setState(() => _highlightKey = anchor);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _highlightKey = null);
    });

    final key = _keyFor(anchor);
    for (var attempt = 0; attempt < 12; attempt++) {
      if (!mounted) return;
      final targetContext = key.currentContext;
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.35,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
        return;
      }
      if (!widget.scrollController.hasClients) return;
      final position = widget.scrollController.position;
      final visualIndex = messages.length - 1 - dataIndex;
      final average = messages.length <= 1 || position.maxScrollExtent <= 0
          ? 80.0
          : (position.maxScrollExtent + position.viewportDimension) / messages.length;
      final target = (visualIndex * average - position.viewportDimension * 0.35)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((position.pixels - target).abs() < 2 && attempt > 0) break;
      position.jumpTo(target);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || key.currentContext != null) return;
    _showMissing(missingText);
  }

  void _showMissing(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

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
                Text('暂无消息', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary(context))),
                const SizedBox(height: 8),
                Text('发送消息开始聊天吧~', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary(context))),
              ],
            ),
          );
        }

        // 消息数量变化时自动滚动到底部
        final focus = chatProvider.focusMessageKey;
        if (focus != null && focus.isNotEmpty) {
          _scheduleFocus(focus);
        }

        final currentMessageCount = chatProvider.messages.length;
        if (currentMessageCount > _lastMessageCount && _lastMessageCount > 0 && focus == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onScrollToBottom();
          });
        }
        _lastMessageCount = currentMessageCount;

        final currentUser = authProvider.user;
        final appUserId = currentUser?.id;
        final imUserId = currentUser?.imUserId;

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

                // senderId 存的是 IM 用户 ID，账号 id 对不上时不能把自己的消息画到左边。
                final senderId = message.senderId;
                final isMe = (senderId.isNotEmpty &&
                        (senderId == imUserId || senderId == appUserId)) ||
                    message.isSent;

                // 设置发送者头像和昵称
                // 群聊：优先使用消息自带的 senderInfo（每条消息的发送者可能不同）
                // 私聊：使用会话目标联系人信息
                String? senderAvatar;
                String? senderName;

                if (isMe) {
                  senderAvatar = currentUser?.avatar;
                  senderName = currentUser?.nickname ?? currentUser?.username;
                } else if (widget.isGroup) {
                  // 群聊：从消息自身的 senderInfo 获取
                  senderAvatar = message.senderDisplayAvatar;
                  senderName = message.senderDisplayName;
                } else {
                  // 私聊：使用会话目标的联系人信息
                  senderAvatar = contactAvatar;
                  senderName = contactName;
                }

                return Column(
                  children: [
                    if (showTimeSeparator)
                      TimeSeparator(time: message.timestamp),
                    if (message.type == MessageType.notice)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                        child: Text(
                          message.noticeText(imUserId ?? appUserId),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFFB2B2B2)),
                        ),
                      )
                    else
                    MessageBubble(
                      key: _keyFor(_anchor(message)),
                      message: message,
                      isMe: isMe,
                      senderAvatar: senderAvatar,
                      senderName: senderName,
                      showName: widget.isGroup && !isMe,
                      isGroup: widget.isGroup,
                      highlighted: _highlightKey != null && _anchor(message) == _highlightKey,
                      onRetry: () => widget.onRetry(message),
                      onRecall: widget.onRecall,
                      onDelete: widget.onDelete,
                      onQuote: widget.onQuote,
                      onForward: widget.onForward,
                      onFavorite: widget.onFavorite,
                      onAvatarTap: widget.onAvatarTap == null
                          ? null
                          : () => widget.onAvatarTap!(message, isMe),
                      onQuoteTap: message.replyMsgId == null
                          ? null
                          : () => _jumpToQuoted(message),
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
