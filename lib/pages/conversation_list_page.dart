import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/layout_provider.dart';
import '../providers/contact_provider.dart';
import '../models/chat_model.dart';
import '../models/user_model.dart';
import '../router/app_router.dart';
import '../theme/app_theme.dart';
import '../widgets/conversation_item.dart';
import '../widgets/avatar_widget.dart';

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
  final GlobalKey _addButtonKey = GlobalKey();
  final GlobalKey _appBarAddButtonKey = GlobalKey();

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

  /// 显示+号菜单（仿微信右上角下拉菜单）
  void _showCreateMenu(BuildContext context) {
    final RenderBox? button = _appBarAddButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) return;

    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonPosition.dx,
        buttonPosition.dy + button.size.height + 4,
        overlay.size.width - buttonPosition.dx - button.size.width,
        0,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'single_chat',
          height: 44,
          child: Row(children: [
            Icon(Icons.person_add, size: 20, color: AppTheme.textSecondaryColor),
            SizedBox(width: 12),
            Text('发起单聊', style: TextStyle(fontSize: 14, color: AppTheme.textPrimaryColor)),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'group_chat',
          height: 44,
          child: Row(children: [
            Icon(Icons.group_add, size: 20, color: AppTheme.textSecondaryColor),
            SizedBox(width: 12),
            Text('发起群聊', style: TextStyle(fontSize: 14, color: AppTheme.textPrimaryColor)),
          ]),
        ),
      ],
    ).then((value) {
      if (value == 'single_chat') {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          messenger.showSnackBar(const SnackBar(content: Text('功能开发中...')));
        }
      } else if (value == 'group_chat') {
        Navigator.pushNamed(context, AppRouter.groupCreate);
      }
    });
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
          IconButton(key: _appBarAddButtonKey, icon: const Icon(Icons.add), onPressed: () => _showCreateMenu(context)),
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
      child: Row(
        children: [
          Expanded(
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
          ),
          const SizedBox(width: 8),
          // + 号按钮，点击弹出菜单（仿微信）
          Material(
            key: _addButtonKey,
            color: Colors.white,
            shape: CircleBorder(side: BorderSide(color: Colors.grey[300]!)),
            child: InkWell(
              onTap: () => _showAddMenu(context),
              customBorder: const CircleBorder(),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                child: Icon(Icons.add, size: 20, color: AppTheme.primaryColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示+号菜单（定位在按钮下方）
  void _showAddMenu(BuildContext context) {
    final RenderBox? button = _addButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) return;

    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonPosition.dx,
        buttonPosition.dy + button.size.height + 4,
        overlay.size.width - buttonPosition.dx - button.size.width,
        0,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'add_friend',
          height: 44,
          child: Row(children: [
            Icon(Icons.person_add_outlined, size: 20, color: AppTheme.textSecondaryColor),
            SizedBox(width: 12),
            Text('添加好友', style: TextStyle(fontSize: 14, color: AppTheme.textPrimaryColor)),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'group_chat',
          height: 44,
          child: Row(children: [
            Icon(Icons.group_add_outlined, size: 20, color: AppTheme.textSecondaryColor),
            SizedBox(width: 12),
            Text('发起群聊', style: TextStyle(fontSize: 14, color: AppTheme.textPrimaryColor)),
          ]),
        ),
      ],
    ).then((value) {
      if (value == 'add_friend') {
        _showAddFriendDialog(context);
      } else if (value == 'group_chat') {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('发起群聊功能开发中'), duration: Duration(seconds: 2)),
        );
      }
    });
  }

  /// 添加好友弹窗
  void _showAddFriendDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _AddFriendDialog(),
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
                            'targetId': conversation.targetId,
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

/// 添加好友独立弹窗
class _AddFriendDialog extends StatefulWidget {
  const _AddFriendDialog();

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String? _errorMsg;
  List<UserModel> _searchResults = [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    setState(() { _isSearching = true; _errorMsg = null; _searchResults = []; });

    try {
      final contactProvider = context.read<ContactProvider>();
      await contactProvider.searchUsers(keyword);

      if (!mounted) return;

      setState(() {
        _isSearching = false;
        _searchResults = contactProvider.searchResults;
      });
    } catch (e) {
      if (mounted) setState(() { _isSearching = false; _errorMsg = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(horizontal: 80, vertical: 60),
      child: Container(
        width: 440,
        constraints: BoxConstraints(maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头部
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('添加朋友', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimaryColor)),
                IconButton(icon: Icon(Icons.close, size: 20, color: Colors.grey[500]), tooltip: '关闭', onPressed: () => Navigator.of(context).pop(), visualDensity: VisualDensity.compact),
              ]),
            ),

            // 搜索区域
            Padding(padding: const EdgeInsets.all(20), child: Row(children: [
              Expanded(child: TextField(controller: _searchController, autofocus: true, onSubmitted: (_) => _onSearch(), style: TextStyle(fontSize: 14), decoration: InputDecoration(hintText: '搜索微信号或手机号', hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14), prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey[500]), filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: AppTheme.primaryColor, width: 1)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)))),
              SizedBox(width: 10),
              ElevatedButton(onPressed: _isSearching ? null : _onSearch, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10)), child: _isSearching ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('搜索')),
            ])),

            // 错误提示
            if (_errorMsg != null)
              Padding(padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8), child: Text(_errorMsg!, style: TextStyle(fontSize: 13, color: AppTheme.errorColor))),

            // 搜索结果列表
            if (_searchResults.isNotEmpty || _isSearching)
              Expanded(child: Container(
                constraints: BoxConstraints(maxHeight: 280),
                child: _isSearching
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: CircularProgressIndicator()))
                    : ListView.separated(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _searchResults.length, separatorBuilder: (_, __) => Divider(height: 1, indent: 56, color: Colors.grey.shade100), itemBuilder: (ctx, i) => _buildSearchResultItem(_searchResults[i])),
              ))
            else if (!_isSearching && _searchResults.isEmpty && _searchController.text.isNotEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.search_off, size: 40, color: Colors.grey[300]),
                SizedBox(height: 8),
                Text('未找到该用户', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
              ])))
            else
              Padding(padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16), child: Align(alignment: Alignment.centerLeft, child: Text('输入对方的微信号或手机号进行搜索', style: TextStyle(fontSize: 12, color: Colors.grey[400])))),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultItem(UserModel user) {
    final displayName = user.nickname.isNotEmpty ? user.nickname : user.username;
    return InkWell(onTap: () async {
      try {
        await context.read<ContactProvider>().sendFriendRequest(int.tryParse(user.id) ?? 0);
        if (mounted) Navigator.of(context).pop();
      } catch (e) { debugPrint('发送好友请求失败: $e'); }
    }, borderRadius: BorderRadius.circular(8), child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
      AvatarWidget(imageUrl: user.avatar, name: displayName, size: 44),
      SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(displayName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        SizedBox(height: 2),
        Text(user.username, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      ])),
      if (user.friendStatus == 0)
        Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: AppTheme.primaryColor), child: Text('添加', style: TextStyle(fontSize: 12, color: Colors.white)))
      else if (user.friendStatus == 1)
        Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.orange.withOpacity(0.08)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.access_time, size: 13, color: Colors.orange), SizedBox(width: 4), Text('已请求', style: TextStyle(fontSize: 11, color: Colors.orange))]))
      else
        Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.green.withOpacity(0.08)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, size: 15, color: Colors.green), SizedBox(width: 4), Text('已是好友', style: TextStyle(fontSize: 11, color: Colors.green))])),
    ])));
  }
}
