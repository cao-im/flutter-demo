import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/layout_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/contact_provider.dart';
import '../widgets/desktop_navigation_rail.dart';
import '../theme/app_theme.dart';
import 'conversation_list_page.dart';
import 'chat_page.dart';

class _NewConversationIntent extends Intent {
  const _NewConversationIntent();
}

class DesktopHomePage extends StatelessWidget {
  const DesktopHomePage({super.key});

  static const double _middlePanelWidth = 320.0;
  static const double _minWindowWidth = 900.0;

  @override
  Widget build(BuildContext context) {
    _initData(context);

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
                        Icon(
                          Icons.desktop_windows_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '窗口太小，请放大窗口',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Consumer<LayoutProvider>(
                  builder: (context, layoutProvider, _) {
                    return Row(
                      children: [
                        const DesktopNavigationRail(),
                        Container(width: 1, color: AppTheme.dividerColor),
                        _buildMiddlePanel(layoutProvider),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('新建会话功能开发中...'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _initData(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadConversations();
      context.read<ContactProvider>().startListening();
    });
  }

  Widget _buildMiddlePanel(LayoutProvider layoutProvider) {
    switch (layoutProvider.selectedIndex) {
      case 0:
        return SizedBox(
          width: _middlePanelWidth,
          child: ConversationListPage(
            isEmbeddedMode: true,
            onConversationSelected: (id, name, isGroup) {
              layoutProvider.selectConversation(id, name, isGroup);
            },
          ),
        );
      default:
        return SizedBox(
          width: _middlePanelWidth,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.construction_outlined,
                  size: 48,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 12),
                Text(
                  '功能开发中...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildRightPanel(LayoutProvider layoutProvider) {
    final conversationId = layoutProvider.currentConversationId ?? '';
    final conversationName = layoutProvider.currentConversationName ?? '';
    final isGroup = layoutProvider.isGroup;

    return Expanded(
      key: ValueKey('chat_panel_$conversationId'),
      child: ChatPage(
        conversationId: conversationId,
        conversationName: conversationName,
        isGroup: isGroup,
        isPanelMode: true,
      ),
    );
  }
}
