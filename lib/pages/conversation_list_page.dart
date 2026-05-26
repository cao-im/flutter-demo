import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../models/chat_model.dart';
import '../router/app_router.dart';
import '../theme/app_theme.dart';
import '../widgets/conversation_item.dart';

class ConversationListPage extends StatefulWidget {
  const ConversationListPage({super.key});

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

  /// 智能加载：只在必要时加载，避免重复请求
  void _loadConversationsIfNeeded() {
    if (!_hasLoaded || mounted) {
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
    chatProvider.deleteConversation(conversationId);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('会话已删除'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showCreateDialog() {
    showModalBottomSheet(
      context: context,
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
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('功能开发中...')));
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
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    // ✅ 每次构建时检查是否需要加载数据（处理页面重新进入的情况）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadConversationsIfNeeded();
    });
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _showCreateDialog),
        ],
      ),
      body: Consumer<ChatProvider>(
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

          return RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppTheme.primaryColor,
            backgroundColor: Colors.white,
            edgeOffset: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
            child: ListView.builder(
              itemCount: chatProvider.conversations.length,
              itemBuilder: (context, index) {
                final conversation = chatProvider.conversations[index];
                return Dismissible(
                  key: Key(conversation.id.toString()),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (direction) => _confirmDelete(conversation),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: AppTheme.errorColor,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(Icons.delete, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          '删除',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  onDismissed: (direction) {
                    _handleDelete(conversation.id);
                  },
                  child: ConversationItem(
                    conversation: conversation,
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        AppRouter.chat,
                        arguments: {
                          'conversationId': conversation.id,
                          'conversationName': conversation.name,
                          'isGroup': conversation.isGroup,
                        },
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
