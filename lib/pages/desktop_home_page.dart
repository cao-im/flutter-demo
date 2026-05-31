import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/layout_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/contact_provider.dart';
import '../providers/auth_provider.dart';
import '../models/chat_model.dart';
import '../widgets/desktop_navigation_rail.dart';
import '../widgets/desktop_contacts_panel.dart';
import '../theme/app_theme.dart';
import 'conversation_list_page.dart';
import 'chat_page.dart';

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

    return Shortcuts(
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
            color: AppTheme.backgroundColor,
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
                        Container(width: 1, color: AppTheme.dividerColor),
                        _buildMiddlePanel(context, layoutProvider),
                        Container(width: 1, color: AppTheme.dividerColor),
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
        return SizedBox(
          width: _middlePanelWidth,
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.star_outline, size: 48, color: Colors.grey[400]),
            SizedBox(height: 12),
            Text('收藏夹开发中...', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          ])),
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
      color: AppTheme.surfaceColor,
      child: ListView(padding: EdgeInsets.zero, children: [
        Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.dividerColor))),
          child: Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Text(userName.isNotEmpty ? userName[0] : '?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primaryColor))
                  : null,
            ),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(userName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimaryColor), maxLines: 1, overflow: TextOverflow.ellipsis),
              SizedBox(height: 2),
              Text(user?.email ?? '', style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),

        Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text(
          '通用设置',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor, fontWeight: FontWeight.w500),
        )),

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
          Text(title, style: TextStyle(fontSize: 15, color: AppTheme.textPrimaryColor)),
          if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
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
      Icon(icon, size: 16, color: AppTheme.textSecondaryColor),
      SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13))),
    ]));
  }

  Widget _buildRightPanel(LayoutProvider layoutProvider) {
    final conversationId = layoutProvider.currentConversationId ?? '';
    final conversationName = layoutProvider.currentConversationName ?? '';
    final isGroup = layoutProvider.isGroup;

    return Expanded(key: ValueKey('chat_panel_$conversationId'), child: ChatPage(conversationId: conversationId, conversationName: conversationName, isGroup: isGroup, isPanelMode: true));
  }
}
