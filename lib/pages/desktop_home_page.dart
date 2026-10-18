import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/layout_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/contact_provider.dart';
import '../providers/auth_provider.dart';
import '../models/chat_model.dart';
import '../models/user_model.dart';
import '../widgets/desktop_navigation_rail.dart';
import '../widgets/profile_editor.dart';
import '../widgets/desktop_contacts_panel.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/qr_code_card.dart';
import '../theme/app_theme.dart';
import 'conversation_list_page.dart';
import 'chat_page.dart';
import 'favorites_page.dart';

class _NewConversationIntent extends Intent {
  const _NewConversationIntent();
}

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({super.key});

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

class _DesktopHomePageState extends State<DesktopHomePage> {
  static const double _middlePanelWidth = 320.0;
  static const double _minWindowWidth = 900.0;
  bool _initialized = false;
  bool _clearConversationScheduled = false;

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted && !_initialized) {
          setState(() => _initialized = true);

          debugPrint('🖥️ [DesktopHomePage] 初始化开始...');

          context.read<ChatProvider>().startListening();
          context.read<ContactProvider>().startListening();
          
          // ✅ 先同步联系人数据，确保会话列表能显示正确的姓名
          try {
            await context.read<ContactProvider>().syncContactsFromServer();
            debugPrint('✅ [DesktopHomePage] 联系人同步完成');
          } catch (e) {
            debugPrint('⚠️ [DesktopHomePage] 联系人同步失败: $e');
          }
          
          // 联系人数据就绪后再加载会话列表
          context.read<ChatProvider>().loadConversations();
          debugPrint('✅ [DesktopHomePage] 初始化完成');
        }
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
            const _NewConversationIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _NewConversationIntent: CallbackAction<_NewConversationIntent>(
            onInvoke: (_NewConversationIntent intent) => _showNewConversationHint(context),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Container(
            color: AppTheme.background(context),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < _minWindowWidth) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.desktop_windows_outlined, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text('窗口太小，请放大窗口', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                      ],
                    ),
                  );
                }

                return Consumer<LayoutProvider>(
                  builder: (context, layoutProvider, _) {
                    return Row(
                      children: [
                        DesktopNavigationRail(),
                        Container(width: 1, color: AppTheme.divider(context)),
                        _buildMiddlePanel(context, layoutProvider),
                        Container(width: 1, color: AppTheme.divider(context)),
                        _buildRightPanel(layoutProvider),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
      ),
    );
  }

  void _showNewConversationHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('新建会话功能开发中...'),
      duration: Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  Widget _buildMiddlePanel(BuildContext context, LayoutProvider layoutProvider) {
    switch (layoutProvider.selectedIndex) {
      case 0:
        return SizedBox(
          width: _middlePanelWidth,
          child: ConversationListPage(
            isEmbeddedMode: true,
            onConversationSelected: (id, name, isGroup) {
              layoutProvider.selectConversation(id, name, isGroup);
              
              // ✅ 同时设置ChatProvider的当前会话，确保发送消息时能正确获取
              final chatProvider = context.read<ChatProvider>();
              final conversation = chatProvider.conversations.firstWhere(
                (c) => c.id == id,
                orElse: () => ConversationModel(
                  id: id,
                  targetId: int.tryParse(id) ?? 0, // 尝试从 conversationId 解析
                  name: name,
                  isGroup: isGroup,
                  participantIds: [],
                ),
              );
              chatProvider.setCurrentConversation(conversation);
            },
          ),
        );

      case 1:
        return SizedBox(
          width: _middlePanelWidth,
          child: DesktopContactsPanel(),
        );

      case 2:
        return const SizedBox(
          width: _middlePanelWidth,
          child: FavoritesPage(embedded: true),
        );

      case 3:
        return SizedBox(
          width: _middlePanelWidth,
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.folder_outlined, size: 48, color: Colors.grey[400]),
            SizedBox(height: 12),
            Text('文件管理开发中...', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          ])),
        );

      case 4:
        return SizedBox(width: _middlePanelWidth, child: _buildSettingsPanel(context));

      default:
        return SizedBox(
          width: _middlePanelWidth,
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.construction_outlined, size: 48, color: Colors.grey[400]),
            SizedBox(height: 12),
            Text('功能开发中...', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          ])),
        );
    }
  }

  Widget _buildSettingsPanel(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final chatProvider = Provider.of<ChatProvider>(context);
    final user = authProvider.user;
    final avatarUrl = user?.avatar;
    final userName = user?.nickname ?? user?.username ?? '用户';

    return Material(
      color: AppTheme.surface(context),
      child: ListView(padding: EdgeInsets.zero, children: [
        Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.divider(context)))),
          child: Row(children: [
            AvatarWidget(imageUrl: avatarUrl, name: userName, size: 56),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(userName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
              SizedBox(height: 2),
              Text('在右侧修改头像、昵称、邮箱和手机号', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),

        Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text(
          '通用设置',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context), fontWeight: FontWeight.w500),
        )),

        _buildSettingsItem(
          icon: Icons.qr_code_2,
          iconColor: AppTheme.primaryColor,
          title: '我的二维码',
          subtitle: '扫码加我为好友',
          onTap: () => showMyQrCode(context),
        ),

        Divider(height: 1, indent: 20, endIndent: 20),

        _buildSettingsItem(icon: Icons.delete_sweep, iconColor: AppTheme.errorColor, title: '清空聊天记录', subtitle: '删除所有本地聊天数据', onTap: () => _showClearChatDataDialog(context, chatProvider)),

        Divider(height: 1, indent: 20, endIndent: 20),

        _buildSettingsItem(icon: Icons.logout, iconColor: AppTheme.errorColor, title: '退出登录', subtitle: '退出当前账号', onTap: () => _showLogoutDialog(context, authProvider)),

        SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildSettingsItem({required IconData icon, required Color iconColor, required String title, String? subtitle, required VoidCallback onTap}) {
    return InkWell(onTap: onTap, child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 20, color: iconColor)),
        SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 15, color: AppTheme.textPrimary(context))),
          if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context))),
        ])),
        Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
      ]),
    ));
  }

  Future<void> _showClearChatDataDialog(BuildContext context, ChatProvider chatProvider) async {
    final conversationCount = chatProvider.conversations.length;
    if (conversationCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('没有可清空的聊天记录'), duration: Duration(seconds: 2)));
      return;
    }

    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.orange[700]), SizedBox(width: 8), Text('清空聊天记录', style: TextStyle(fontWeight: FontWeight.bold))]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('此操作将永久删除所有本地聊天记录，包括：', style: TextStyle(fontSize: 14)),
        SizedBox(height: 12),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.withOpacity(0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildWarningItem(Icons.chat, '$conversationCount 个会话记录'),
            _buildWarningItem(Icons.message, '所有聊天消息内容'),
            _buildWarningItem(Icons.image, '已下载的图片和文件'),
            SizedBox(height: 4),
            Text('⚠️ 此操作不可恢复！删除后数据将无法找回。', style: TextStyle(fontSize: 12, color: AppTheme.errorColor, fontWeight: FontWeight.w500)),
          ]),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text('取消')),
        TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor), child: Text('确认清空', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
    ));

    if (confirmed == true && context.mounted) {
      try {
        await chatProvider.clearAllChatData();

        try { Provider.of<LayoutProvider>(context, listen: false).clearConversation(); } catch (_) {}

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ 聊天记录已全部清空'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            backgroundColor: AppTheme.successColor,
          ));

          Provider.of<LayoutProvider>(context, listen: false).selectNavigation(0);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ 清空失败: $e'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            backgroundColor: AppTheme.errorColor,
          ));
        }
      }
    }
  }

  Future<void> _showLogoutDialog(BuildContext context, AuthProvider authProvider) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('确认退出', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Text('确定要退出登录吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text('取消')),
        TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor), child: Text('退出', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
    ));

    if (confirmed == true && context.mounted) {
      await authProvider.logout(context);
      if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  Widget _buildWarningItem(IconData icon, String text) {
    return Padding(padding: EdgeInsets.symmetric(vertical: 2), child: Row(children: [
      Icon(icon, size: 16, color: AppTheme.textSecondary(context)),
      SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13))),
    ]));
  }

  /// 离开聊天面板、或没有选中会话时，清掉当前会话以恢复消息通知。
  /// 只在确实有内容可清时排队一次，避免 build → notifyListeners → build 死循环。
  void _scheduleClearCurrentConversationIfNeeded() {
    final chatProvider = context.read<ChatProvider>();
    if (chatProvider.currentConversation == null && chatProvider.messages.isEmpty) {
      return;
    }
    if (_clearConversationScheduled) return;
    _clearConversationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clearConversationScheduled = false;
      if (!mounted) return;
      context.read<ChatProvider>().clearCurrentConversation();
    });
  }

  Widget _buildRightPanel(LayoutProvider layoutProvider) {
    final conversationId = layoutProvider.currentConversationId ?? '';
    // 非消息面板，或消息面板但未选中会话：恢复通知
    if (layoutProvider.selectedIndex != 0 || conversationId.isEmpty) {
      _scheduleClearCurrentConversationIfNeeded();
    }

    switch (layoutProvider.selectedIndex) {
      case 0:
        // 消息：显示聊天面板
        final conversationName = layoutProvider.currentConversationName ?? '';
        final isGroup = layoutProvider.isGroup;

        return Expanded(
          key: ValueKey('chat_panel_$conversationId'),
          child: ChatPage(conversationId: conversationId, conversationName: conversationName, isGroup: isGroup, isPanelMode: true, targetId: int.tryParse(conversationId) ?? 0),
        );

      case 1:
        // 通讯录：显示联系人详情或空状态
        final selectedContact = layoutProvider.selectedContact;
        return Expanded(
          child: selectedContact != null
              ? _ContactDetailPanel(contact: selectedContact)
              : _ContactsEmptyPanel(),
        );

      case 2:
        return const Expanded(child: FavoriteDetailPane());

      case 3:
        // 文件：开发中占位
        return const Expanded(child: _PlaceholderPanel(icon: Icons.folder_outlined, title: '文件管理', subtitle: '此功能开发中...'));

      case 4:
        return const Expanded(child: _DesktopProfilePanel());

      default:
        return const Expanded(child: _PlaceholderPanel(icon: Icons.construction_outlined, title: '功能开发中', subtitle: '敬请期待'));
    }
  }

  /// 通讯录未选中联系人时的空状态面板
  Widget _ContactsEmptyPanel() {
    return Material(
      color: AppTheme.background(context),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 64, color: Colors.grey[300]),
            SizedBox(height: 16),
            Text(
              '选择一个联系人',
              style: TextStyle(fontSize: 15, color: Colors.grey[500]),
            ),
            SizedBox(height: 4),
            Text(
              '在左侧列表中选择联系人查看详情',
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopProfilePanel extends StatelessWidget {
  const _DesktopProfilePanel();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.background(context),
      child: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: const ProfileEditor(),
          ),
        ),
      ),
    );
  }
}

/// 通用占位面板（收藏、文件等开发中功能使用）
class _PlaceholderPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PlaceholderPanel({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.background(context),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey[300]),
            SizedBox(height: 16),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey[500])),
            SizedBox(height: 8),
            Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }
}

/// 桌面端设置面板（右侧完整展示）
class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel();

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, ChatProvider>(
      builder: (context, authProvider, chatProvider, _) {
        final user = authProvider.user;
        final avatarUrl = user?.avatar;
        final userName = user?.nickname ?? user?.username ?? '用户';

        return Material(
          color: AppTheme.background(context),
          child: ListView(padding: EdgeInsets.zero, children: [
            // 用户信息头部
            Container(
              padding: EdgeInsets.symmetric(horizontal: 40, vertical: 32),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.divider(context)))),
              child: Row(children: [
                AvatarWidget(imageUrl: avatarUrl, name: userName, size: 56),
                SizedBox(width: 20),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(userName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppTheme.textPrimary(context))),
                  SizedBox(height: 4),
                  Text(user?.email ?? '', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context))),
                ])),
              ]),
            ),

            // 设置项
            Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('通用设置', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context), fontWeight: FontWeight.w500))),

            _SettingsItem(
              icon: Icons.qr_code_2,
              iconColor: AppTheme.primaryColor,
              title: '我的二维码',
              subtitle: '扫码加我为好友',
              onTap: () => showMyQrCode(context),
            ),
            Divider(height: 1, indent: 40, endIndent: 40),
            _SettingsItem(icon: Icons.delete_sweep, iconColor: AppTheme.errorColor, title: '清空聊天记录', subtitle: '删除所有本地聊天数据'),
            Divider(height: 1, indent: 40, endIndent: 40),
            _SettingsItem(icon: Icons.logout, iconColor: AppTheme.errorColor, title: '退出登录', subtitle: '退出当前账号'),

            SizedBox(height: 32),
          ]),
        );
      },
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  final VoidCallback? onTap;

  const _SettingsItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(onTap: onTap, child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 40, vertical: 14),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 20, color: iconColor)),
        SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 15, color: AppTheme.textPrimary(context))),
          if (subtitle.isNotEmpty) Text(subtitle, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context))),
        ])),
        Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
      ]),
    ));
  }
}

/// 联系人详情面板（桌面端右侧展示）
class _ContactDetailPanel extends StatefulWidget {
  final UserModel contact;
  const _ContactDetailPanel({required this.contact});

  @override
  State<_ContactDetailPanel> createState() => _ContactDetailPanelState();
}

class _ContactDetailPanelState extends State<_ContactDetailPanel> {
  late UserModel _contact;
  bool _busy = false;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshProfile());
  }

  @override
  void didUpdateWidget(covariant _ContactDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contact.id != widget.contact.id ||
        oldWidget.contact.imUserId != widget.contact.imUserId) {
      _contact = widget.contact;
      _refreshProfile();
    } else if (widget.contact.nickname != _contact.nickname ||
        widget.contact.avatar != _contact.avatar ||
        widget.contact.remark != _contact.remark ||
        widget.contact.isTop != _contact.isTop ||
        widget.contact.isMute != _contact.isMute) {
      _contact = widget.contact;
    }
  }

  int get _imUserId =>
      int.tryParse(_contact.imUserId ?? '') ?? int.tryParse(_contact.id) ?? 0;

  Future<void> _refreshProfile() async {
    final imUserId = _imUserId;
    if (imUserId <= 0 || !mounted) return;
    final contactProvider = context.read<ContactProvider>();
    final chatProvider = context.read<ChatProvider>();
    final conversation = chatProvider.privateConversation(imUserId);
    if (conversation != null && mounted) {
      setState(() {
        _contact = _contact.copyWith(
          isTop: conversation.isTop,
          isMute: conversation.isMute,
        );
      });
    }
    final updated = await contactProvider.refreshContactFromServer(imUserId);
    final blocked = await contactProvider.isBlocked(imUserId);
    if (!mounted) return;
    final live = chatProvider.privateConversation(imUserId);
    if (updated != null) {
      final merged = contactProvider.mergeRelationState(
        updated.copyWith(
          remark: _contact.remark.isNotEmpty ? _contact.remark : updated.remark,
        ),
        isTop: live?.isTop,
        isMute: live?.isMute,
      );
      setState(() {
        _contact = merged;
        _blocked = blocked;
      });
      final layout = context.read<LayoutProvider>();
      layout.replaceSelectedContact(merged);
      layout.renameConversationIfOpen(merged.id, merged.displayName);
      layout.renameConversationIfOpen('$imUserId', merged.displayName);
    } else {
      setState(() => _blocked = blocked);
    }
  }

  Future<void> _toggleBlock() async {
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
      final contactProvider = context.read<ContactProvider>();
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

  ConversationModel? _findPrivateConversation() {
    return context
        .read<ChatProvider>()
        .conversations
        .where((c) => !c.isGroup && c.targetId == _imUserId)
        .firstOrNull;
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
          decoration: const InputDecoration(hintText: '备注名', border: OutlineInputBorder()),
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
      final updated = await context.read<ContactProvider>().updateRemark(_imUserId, result);
      if (!mounted || updated == null) return;
      setState(() => _contact = updated);
      final layout = context.read<LayoutProvider>();
      layout.replaceSelectedContact(updated);
      layout.renameConversationIfOpen(updated.id, updated.displayName);
      layout.renameConversationIfOpen('$_imUserId', updated.displayName);
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

  Future<void> _toggleTop(bool next) async {
    setState(() => _busy = true);
    try {
      final chat = context.read<ChatProvider>();
      final contact = context.read<ContactProvider>();
      final conv = _findPrivateConversation();
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

  Future<void> _toggleMute(bool next) async {
    setState(() => _busy = true);
    try {
      final chat = context.read<ChatProvider>();
      final contact = context.read<ContactProvider>();
      final conv = _findPrivateConversation();
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
    final contact = _contact;
    final displayName = contact.displayName;
    final avatarUrl = contact.avatar;

    return Material(
      color: AppTheme.background(context),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.divider(context))),
            ),
            child: Row(
              children: [
                AvatarWidget(
                  imageUrl: avatarUrl,
                  name: displayName,
                  size: 56,
                ),
                SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '用户名: ${contact.username}',
                        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: 20),
              children: [
                _buildDetailSection(title: '好友资料', children: [
                  _buildDetailItem(
                    label: '备注',
                    value: contact.remark.isEmpty ? '添加备注名' : contact.remark,
                    onTap: _busy ? null : _editRemark,
                  ),
                  if (contact.phone != null && contact.phone!.isNotEmpty)
                    _buildDetailItem(label: '手机号', value: contact.phone!),
                  if (contact.email != null && contact.email!.isNotEmpty)
                    _buildDetailItem(label: '邮箱', value: contact.email!),
                ]),
                _buildDetailSection(title: '聊天设置', children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 32),
                    title: const Text('置顶聊天', style: TextStyle(fontSize: 14)),
                    value: contact.isTop,
                    onChanged: _busy ? null : _toggleTop,
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 32),
                    title: const Text('消息免打扰', style: TextStyle(fontSize: 14)),
                    value: contact.isMute,
                    onChanged: _busy ? null : _toggleMute,
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 32),
                    title: Text(
                      _blocked ? '解除拉黑' : '加入黑名单',
                      style: TextStyle(
                        fontSize: 14,
                        color: _blocked ? AppTheme.primaryColor : AppTheme.errorColor,
                      ),
                    ),
                    onTap: _busy ? null : _toggleBlock,
                  ),
                ]),
              ],
            ),
          ),

          Container(
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.divider(context))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(icon: Icons.chat_bubble_outline, label: '发消息', onTap: () {
                  final layoutProvider = context.read<LayoutProvider>();
                  layoutProvider.selectNavigation(0);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    layoutProvider.selectConversation(contact.id, displayName, false);
                  });
                }),
                _buildActionButton(icon: Icons.call_outlined, label: '语音通话', onTap: () {}),
                _buildActionButton(icon: Icons.videocam_outlined, label: '视频通话', onTap: () {}),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 8),
          child: Text(
            title,
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context), fontWeight: FontWeight.w500),
          ),
        ),
        ...children,
        Divider(height: 1, indent: 32, endIndent: 32),
      ],
    );
  }

  Widget _buildDetailItem({
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        child: Row(
          children: [
            SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 14, color: AppTheme.textSecondary(context)))),
            Expanded(child: Text(value, style: TextStyle(fontSize: 14, color: AppTheme.textPrimary(context)))),
            if (onTap != null) Icon(Icons.chevron_right, size: 18, color: AppTheme.textSecondary(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: AppTheme.primaryColor),
            SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: AppTheme.primaryColor)),
          ],
        ),
      ),
    );
  }
}
