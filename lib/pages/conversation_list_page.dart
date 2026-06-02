import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/layout_provider.dart';
import '../models/chat_model.dart';
import '../router/app_router.dart';
import '../theme/app_theme.dart';
import '../widgets/conversation_item.dart';

class ConversationListPage extends StatefulWidget {
  final bool isEmbeddedMode;
  final void Function(String conversationId, String conversationName, bool isGroup)? onConversationSelected;

  const ConversationListPage({
    super.key,
    this.isEmbeddedMode = false,
    this.onConversationSelected,
  });

  @override
  State<ConversationListPage> createState() => _ConversationListPageState();
}

class _ConversationListPageState extends State<ConversationListPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    // ✅ 延迟加载，确保 IMClient 已初始化
    Future.delayed(Duration(milliseconds: 500), () {
      if (mounted) {
        _loadConversationsIfNeeded();
      }
    });
  }

  /// 智能加载：只在首次加载时执行，避免重复请求
  void _loadConversationsIfNeeded() {
    if (!_hasLoaded) {
      _hasLoaded = true;
      Provider.of<ChatProvider>(context, listen: false).loadConversations();
    }
  }

  Future<void> _onRefresh() async {
    await Provider.of<ChatProvider>(context, listen: false).loadConversations();
  }

  Future<bool> _confirmDelete(ConversationModel conversation) async {
    final result =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('删除会话'),
            content: Text('确定要删除与 ${conversation.name} 的聊天记录吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  '删除',
                  style: TextStyle(color: AppTheme.errorColor),
                ),
              ),
            ],
          ),
        ) ??
        false;
    return result;
  }

  void _handleDelete(String conversationId) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    await chatProvider.deleteConversation(conversationId);

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('会话已删除'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  void _showContextMenu(ConversationModel conversation, Offset position) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        MediaQuery.of(context).size.width - position.dx,
        MediaQuery.of(context).size.height - position.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete, color: AppTheme.errorColor, size: 20),
              SizedBox(width: 8),
              Text('删除会话', style: TextStyle(color: AppTheme.errorColor)),
            ],
          ),
        ),
      ],
    );

    if (result == 'delete') {
      _confirmAndDelete(conversation);
    }
  }

  Future<void> _confirmAndDelete(ConversationModel conversation) async {
    final confirmed = await _confirmDelete(conversation);
    if (confirmed) {
      _handleDelete(conversation.id);
    }
  }

  void _showCreateDialog() {
    try {
      showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.person_add,
                    color: AppTheme.primaryColor,
                  ),
                  title: const Text('发起单聊'),
                  onTap: () {
                    Navigator.pop(context);
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    if (messenger != null) {
                      messenger.showSnackBar(const SnackBar(content: Text('功能开发中...')));
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.group_add,
                    color: AppTheme.primaryColor,
                  ),
                  title: const Text('发起群聊'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, AppRouter.groupCreate);
                  },
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('显示底部弹窗失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    // ✅ 只在首次build时延迟加载，避免死循环
    
    if (widget.isEmbeddedMode) {
      return _buildEmbeddedBody();
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _showCreateDialog),
        ],
      ),
      body: Column(
        children: [
          Consumer<ConnectionProvider>(
            builder: (context, connectionProvider, _) {
              final state = connectionProvider.state;
              final error = connectionProvider.errorMessage;

              if (connectionProvider.isConnected) {
                return const SizedBox.shrink();
              }

              if (state == ImConnectionState.connecting ||
                  state == ImConnectionState.reconnecting) {
                return Container(
                  color: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        state == ImConnectionState.connecting
                            ? '正在连接...'
                            : '正在重连...',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }

              if (error != null && error.isNotEmpty) {
                return Container(
                  color: Colors.red[400],
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          error.length > 50 ? '${error.substring(0, 47)}...' : error,
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Container(
                color: Colors.grey[400],
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    const Text('未连接', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmbeddedBody() {
    return Material(
      color: AppTheme.surfaceColor,
      child: Column(
        children: [
          Consumer<ConnectionProvider>(
            builder: (context, connectionProvider, _) {
              final state = connectionProvider.state;
              final error = connectionProvider.errorMessage;

              if (connectionProvider.isConnected) {
                return const SizedBox.shrink();
              }

              if (state == ImConnectionState.connecting ||
                  state == ImConnectionState.reconnecting) {
                return Container(
                  color: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        state == ImConnectionState.connecting
                            ? '正在连接...'
                            : '正在重连...',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }

              if (error != null && error.isNotEmpty) {
                return Container(
                  color: Colors.red[400],
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          error.length > 50 ? '${error.substring(0, 47)}...' : error,
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Container(
                color: Colors.grey[400],
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    const Text('未连接', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              );
            },
          ),
          _buildEmbeddedSearchBox(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildEmbeddedSearchBox() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        decoration: InputDecoration(
          hintText: '搜索',
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        if (chatProvider.isLoading && chatProvider.conversations.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (chatProvider.conversations.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无会话',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  '点击右上角 + 发起聊天',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        if (widget.isEmbeddedMode) {
          return Consumer<LayoutProvider>(
            builder: (context, layoutProvider, _) {
              final selectedId = layoutProvider.currentConversationId;

              return ListView.builder(
                itemCount: chatProvider.conversations.length,
                itemBuilder: (context, index) {
                  final conversation = chatProvider.conversations[index];
                  final isSelected = conversation.id == selectedId;

                  return ConversationItem(
                    conversation: conversation,
                    isSelected: isSelected,
                    onTap: () {
                      if (widget.onConversationSelected != null) {
                        layoutProvider.selectConversation(
                          conversation.id,
                          conversation.name,
                          conversation.isGroup,
                        );
                        widget.onConversationSelected!(
                          conversation.id,
                          conversation.name,
                          conversation.isGroup,
                        );
                      }
                    },
                    onLongPress: (position) => _showContextMenu(conversation, position),
                  );
                },
              );
            },
          );
        }

        return RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppTheme.primaryColor,
          backgroundColor: Colors.white,
          edgeOffset: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
          child: Consumer<LayoutProvider>(
            builder: (context, layoutProvider, _) {
              final selectedId = layoutProvider.currentConversationId;

              return ListView.builder(
                itemCount: chatProvider.conversations.length,
                itemBuilder: (context, index) {
                  final conversation = chatProvider.conversations[index];
                  final isSelected = widget.isEmbeddedMode && conversation.id == selectedId;

                  return ConversationItem(
                    conversation: conversation,
                    isSelected: isSelected,
                    onTap: () {
                      if (widget.isEmbeddedMode && widget.onConversationSelected != null) {
                        layoutProvider.selectConversation(
                          conversation.id,
                          conversation.name,
                          conversation.isGroup,
                        );
                        widget.onConversationSelected!(
                          conversation.id,
                          conversation.name,
                          conversation.isGroup,
                        );
                      } else {
                        Navigator.pushNamed(
                          context,
                          AppRouter.chat,
                          arguments: {
                            'conversationId': conversation.id,
                            'conversationName': conversation.name,
                            'isGroup': conversation.isGroup,
                          },
                        );
                      }
                    },
                    onLongPress: (position) => _showContextMenu(conversation, position),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
