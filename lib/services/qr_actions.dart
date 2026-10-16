import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/contact_provider.dart';
import '../providers/layout_provider.dart';
import '../router/app_router.dart';
import '../utils/qr_payload.dart';
import '../widgets/adaptive_layout.dart';
import 'apis/group_api.dart';

class QrActions {
  static Future<void> handle(BuildContext context, String raw) async {
    final payload = QrPayload.parse(raw);
    if (payload == null) {
      _toast(context, '无法识别这个二维码');
      return;
    }
    if (payload.isUser) {
      await _addFriend(context, payload.id);
    } else {
      await _joinGroup(context, payload.id);
    }
  }

  static Future<void> _addFriend(BuildContext context, int userId) async {
    final me = _myId(context);
    if (me != null && me == userId) {
      _toast(context, '这是你自己的二维码');
      return;
    }
    try {
      await context.read<ContactProvider>().sendFriendRequest(userId, source: 2);
      if (!context.mounted) return;
      _toast(context, '已发送好友申请');
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!context.mounted) return;
      _toast(context, _message(e));
    }
  }

  static Future<void> _joinGroup(BuildContext context, int groupId) async {
    try {
      final status = await GroupApi().join(groupId);
      if (!context.mounted) return;
      if (status == 'pending') {
        _toast(context, '已提交入群申请，等待管理员验证');
        Navigator.of(context).maybePop();
        return;
      }
      var name = '群聊';
      try {
        final info = await GroupApi().getGroupInfo(groupId);
        final rawName = info['name']?.toString().trim() ?? '';
        if (rawName.isNotEmpty) name = rawName;
      } catch (_) {}
      if (!context.mounted) return;
      _toast(context, '已加入群聊');
      _openGroup(context, groupId, name);
    } catch (e) {
      if (!context.mounted) return;
      _toast(context, _message(e));
    }
  }

  static void _openGroup(BuildContext context, int groupId, String name) {
    final id = '$groupId';
    if (AdaptiveLayout.isDesktopPlatform) {
      final layout = context.read<LayoutProvider>();
      layout.selectNavigation(0);
      layout.selectConversation(id, name, true);
      context.read<ChatProvider>().setCurrentConversation(
        ConversationModel(id: id, targetId: groupId, name: name, isGroup: true, participantIds: []),
      );
      Navigator.of(context).maybePop();
      return;
    }
    Navigator.of(context).pushReplacementNamed(
      AppRouter.chat,
      arguments: {
        'conversationId': id,
        'conversationName': name,
        'isGroup': true,
        'targetId': groupId,
      },
    );
  }

  static int? _myId(BuildContext context) {
    final user = context.read<AuthProvider>().user;
    return int.tryParse(user?.imUserId ?? user?.id ?? '');
  }

  static void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  static String _message(Object error) {
    return error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
  }
}
