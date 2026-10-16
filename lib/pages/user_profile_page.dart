import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_model.dart';
import '../models/user_model.dart';
import '../providers/chat_provider.dart';
import '../providers/contact_provider.dart';
import '../providers/layout_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_widget.dart';

/// 查看对方资料。打开时向服务器拉取最新昵称和头像。
class UserProfilePage extends StatefulWidget {
  final UserModel contact;

  const UserProfilePage({super.key, required this.contact});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late UserModel _contact;
  bool _loading = true;
  bool _busy = false;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  int get _imUserId =>
      int.tryParse(_contact.imUserId ?? '') ?? int.tryParse(_contact.id) ?? 0;

  Future<void> _refresh() async {
    if (_imUserId <= 0) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final contactProvider = context.read<ContactProvider>();
    final chatProvider = context.read<ChatProvider>();
    final conversation = chatProvider.privateConversation(_imUserId);
    if (conversation != null && mounted) {
      setState(() {
        _contact = _contact.copyWith(
          isTop: conversation.isTop,
          isMute: conversation.isMute,
        );
      });
    }
    final updated = await contactProvider.refreshContactFromServer(_imUserId);
    final blocked = await contactProvider.isBlocked(_imUserId);
    if (!mounted) return;
    final live = chatProvider.privateConversation(_imUserId);
    setState(() {
      final base = updated ?? _contact;
      _contact = contactProvider.mergeRelationState(
        base.copyWith(
          remark: _contact.remark.isNotEmpty ? _contact.remark : base.remark,
        ),
        isTop: live?.isTop,
        isMute: live?.isMute,
      );
      _blocked = blocked;
      _loading = false;
    });
  }

  Future<void> _toggleBlock() async {
    final contactProvider = context.read<ContactProvider>();
    final next = !_blocked;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(next ? '加入黑名单' : '解除拉黑'),
        content: Text(next
            ? '拉黑后对方将无法给你发消息或加好友。'
            : '解除后对方可以再次给你发消息。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(next ? '拉黑' : '解除', style: TextStyle(color: next ? AppTheme.errorColor : null)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (next) {
        await contactProvider.blockUser(_imUserId);
      } else {
        await contactProvider.unblockUser(_imUserId);
      }
      if (mounted) setState(() => _blocked = next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editRemark() async {
    final controller = TextEditingController(text: _contact.remark);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置备注'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(
            hintText: '备注名',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final updated =
          await context.read<ContactProvider>().updateRemark(_imUserId, result);
      if (!mounted) return;
      if (updated != null) {
        setState(() => _contact = updated);
        _renameOpenConversation(updated.displayName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备注保存失败: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _renameOpenConversation(String name) {
    try {
      final layout = context.read<LayoutProvider>();
      layout.renameConversationIfOpen(_contact.id, name);
      layout.renameConversationIfOpen('$_imUserId', name);
    } catch (_) {}
  }

  ConversationModel? _findPrivateConversation(ChatProvider chat) {
    return chat.conversations
        .where((c) => !c.isGroup && c.targetId == _imUserId)
        .firstOrNull;
  }

  Future<void> _toggleTop() async {
    final chat = context.read<ChatProvider>();
    final contact = context.read<ContactProvider>();
    final conv = _findPrivateConversation(chat);
    setState(() => _busy = true);
    try {
      final next = !_contact.isTop;
      if (conv != null) {
        await chat.setConversationTop(
          conv,
          next,
          syncContact: (id, isTop) => contact.setContactTop(id, isTop).then((_) {}),
        );
      } else {
        await contact.setContactTop(_imUserId, next);
      }
      if (mounted) setState(() => _contact = _contact.copyWith(isTop: next));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('置顶失败: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMute() async {
    final chat = context.read<ChatProvider>();
    final contact = context.read<ContactProvider>();
    final conv = _findPrivateConversation(chat);
    setState(() => _busy = true);
    try {
      final next = !_contact.isMute;
      if (conv != null) {
        await chat.setConversationMute(
          conv,
          next,
          syncContact: (id, isMute) => contact.setContactMute(id, isMute).then((_) {}),
        );
      } else {
        await contact.setContactMute(_imUserId, next);
      }
      if (mounted) setState(() => _contact = _contact.copyWith(isMute: next));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('免打扰设置失败: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _contact.displayName;
    return Scaffold(
      appBar: AppBar(title: const Text('个人资料')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            children: [
              Center(
                child: AvatarWidget(
                  imageUrl: _contact.avatar,
                  name: name.isNotEmpty ? name : '用户',
                  size: 88,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  name.isNotEmpty ? name : '用户',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
              ),
              if (_contact.username.isNotEmpty) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    '用户名 ${_contact.username}',
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor),
                  ),
                ),
              ],
              if (_loading) ...[
                const SizedBox(height: 24),
                const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppTheme.dividerColor),
                ),
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('备注'),
                      subtitle: Text(
                        _contact.remark.isEmpty ? '添加备注名' : _contact.remark,
                        style: TextStyle(
                          color: _contact.remark.isEmpty
                              ? AppTheme.textSecondaryColor
                              : AppTheme.textPrimaryColor,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy ? null : _editRemark,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('置顶聊天'),
                      value: _contact.isTop,
                      onChanged: _busy ? null : (_) => _toggleTop(),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('消息免打扰'),
                      value: _contact.isMute,
                      onChanged: _busy ? null : (_) => _toggleMute(),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: Text(
                        _blocked ? '解除拉黑' : '加入黑名单',
                        style: TextStyle(
                          color: _blocked ? AppTheme.primaryColor : AppTheme.errorColor,
                        ),
                      ),
                      onTap: _busy ? null : _toggleBlock,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x22000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
