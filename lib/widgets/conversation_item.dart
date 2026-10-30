import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'avatar_widget.dart';
import 'group_avatar.dart';

class ConversationItem extends StatelessWidget {
  final ConversationModel conversation;
  final VoidCallback onTap;
  final void Function(Offset position)? onLongPress;
  final VoidCallback? onDelete;
  final bool isSelected;

  const ConversationItem({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onLongPress,
    this.onDelete,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (details) {
        if (onLongPress != null) {
          onLongPress!(details.globalPosition);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blue.withOpacity(0.1)
              : (conversation.isTop
                  ? AppTheme.divider(context).withOpacity(0.35)
                  : Colors.transparent),
          border: Border(
            bottom: BorderSide(color: AppTheme.divider(context), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                conversation.isGroup
                    ? GroupAvatar(
                        groupId: conversation.targetId,
                        size: 50,
                        fallbackName: conversation.name,
                      )
                    : AvatarWidget(
                        imageUrl: conversation.avatar,
                        name: conversation.name,
                        size: 50,
                      ),
                if (conversation.unreadCount > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: conversation.isMute
                        ? Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 18,
                            ),
                            child: Text(
                              conversation.unreadCount > 99
                                  ? '99+'
                                  : '${conversation.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          children: [
                            if (conversation.isTop)
                              Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(Icons.push_pin, size: 14, color: AppTheme.textSecondary(context)),
                              ),
                            Flexible(
                              child: Text(
                                conversation.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatTime(conversation.lastActiveTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _previewLine(context),
                      ),
                      if (conversation.isMute)
                        Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.notifications_off_outlined, size: 16, color: AppTheme.textSecondary(context)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewLine(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      color: conversation.unreadCount > 0 && !conversation.isMute
          ? AppTheme.textPrimary(context)
          : AppTheme.textSecondary(context),
      fontWeight: conversation.unreadCount > 0 && !conversation.isMute
          ? FontWeight.w500
          : FontWeight.normal,
    );
    final mentioned = conversation.mentionMessageKey != null &&
        conversation.mentionMessageKey!.isNotEmpty;
    final text = _preview(context);
    if (!mentioned) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(
            text: '[有人@我] ',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFFFA5151),
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: text, style: style),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _preview(BuildContext context) {
    final message = conversation.lastMessage;
    if (message == null) return '暂无消息';
    if (message.type == MessageType.notice) {
      final user = context.read<AuthProvider>().user;
      return message.noticeText(user?.imUserId ?? user?.id);
    }
    return message.displayText;
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays == 0) {
      return DateFormat('HH:mm').format(time);
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return DateFormat('EEEE', 'zh_CN').format(time);
    } else {
      return DateFormat('MM/dd').format(time);
    }
  }
}
