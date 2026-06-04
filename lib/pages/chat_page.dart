import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../models/message_model.dart';
import '../models/chat_model.dart';
import '../models/contact_info_model.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';
import '../widgets/time_separator.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final String conversationName;
  final bool isGroup;
  final bool isPanelMode;
  final int targetId; // 聊天对象的真实用户ID（对应服务端 contactUserId）

  const ChatPage({
    super.key,
    required this.conversationId,
    required this.conversationName,
    this.isGroup = false,
    this.isPanelMode = false,
    this.targetId = 0, // 默认0，由调用方传入正确值
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  bool _isSending = false;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  ChatProvider? _chatProvider;
  int _lastMessageCount = 0;
  bool _currentConversationNotSetInInit = false; // 标记 initState 中是否成功设置会话
  int? _resolvedTargetId; // 解析后的 targetId（含兜底查询）

  /// 获取 targetId：优先使用传入值，为0时从已加载的会话列表中查找兜底
  int get effectiveTargetId {
    if (widget.targetId > 0) return widget.targetId;
    if (_resolvedTargetId != null && _resolvedTargetId! > 0) return _resolvedTargetId!;
    // 最后兜底：直接解析 conversationId（新格式是纯数字 targetId）
    return int.tryParse(widget.conversationId) ?? 0;
  }

  /// 从 ChatProvider 已加载的会话列表中查找匹配的 targetId
  void _resolveTargetIdFromConversations() {
    if (widget.targetId > 0) {
      _resolvedTargetId = widget.targetId;
      return;
    }
    if (_chatProvider == null) return;
    // 在已有会话列表中按 id 匹配
    final match = _chatProvider!.conversations.firstWhere(
      (c) => c.id == widget.conversationId,
      orElse: () => ConversationModel(
        id: '', targetId: 0, name: '', participantIds: [],
      ),
    );
    if (match.targetId > 0) {
      _resolvedTargetId = match.targetId;
      debugPrint('🔄[ChatPage] 从会话列表查找到 targetId=${_resolvedTargetId} (conversationId=${widget.conversationId})');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // 尝试从已加载的会话列表中解析 targetId（兜底逻辑）
    _resolveTargetIdFromConversations();

    // ✅ 备用逻辑：如果 initState 中设置会话失败，在这里重试
    // 原因：某些情况下 initState 中可能无法访问 InheritedWidget
    if (widget.conversationId.isNotEmpty && _currentConversationNotSetInInit) {
      debugPrint('🔄[ChatPage] didChangeDependencies: 重试设置当前会话 ${widget.conversationId}');
      _chatProvider?.setCurrentConversation(
        ConversationModel(
          id: widget.conversationId,
          targetId: effectiveTargetId,
          name: widget.conversationName,
          participantIds: [],
          isGroup: widget.isGroup,
        ),
      );
      _currentConversationNotSetInInit = false;
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('🔄[ChatPage] initState 被调用: conversationId=${widget.conversationId}, conversationName=${widget.conversationName}');
    _scrollController.addListener(_scrollListener);
    _lastMessageCount = 0;

    if (widget.conversationId.isNotEmpty) {
      // ✅ 同步设置当前会话（不使用 postFrameCallback）
      // 注意：必须使用 Provider.of 直接获取，不能使用 _chatProvider 字段
      // 原因：initState() 在 didChangeDependencies() 之前执行，此时 _chatProvider 还是 null
      debugPrint('🔄[ChatPage] initState: 同步设置当前会话 ${widget.conversationId}');
      try {
        final chatProvider = Provider.of<ChatProvider>(context, listen: false);
        chatProvider.setCurrentConversation(
          ConversationModel(
            id: widget.conversationId,
            targetId: effectiveTargetId,
            name: widget.conversationName,
            participantIds: [],
            isGroup: widget.isGroup,
          ),
        );
        debugPrint('✅[ChatPage] initState: 成功设置当前会话');
        _currentConversationNotSetInInit = false;
      } catch (e) {
        debugPrint('⚠️[ChatPage] initState: 设置当前会话失败（可能 context 未就绪）: $e');
        // 如果在 initState 中无法获取 Provider，将在 didChangeDependencies 中重试
        _currentConversationNotSetInInit = true;
      }

      // 异步操作（加载消息、标记已读）仍然使用 postFrameCallback
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        debugPrint('🔄[ChatPage] initState postFrameCallback 执行: 加载消息');
        await _chatProvider?.loadMessages(widget.conversationId);

        _scrollToBottom(animate: false);  // 首次加载使用无动画跳转

        // 使用 effectiveTargetId（含兜底查询后的真实用户ID）
        final targetId = effectiveTargetId;

        await _chatProvider?.markConversationAsRead(
          targetId: targetId,
          isGroup: widget.isGroup,
          dbId: _chatProvider?.currentConversation?.dbId,
        );
      });
    } else {
      debugPrint('⚠️[ChatPage] initState: conversationId 为空，不设置当前会话');
    }
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    debugPrint('🔄[ChatPage] didUpdateWidget 被调用: oldId=${oldWidget.conversationId}, newId=${widget.conversationId}');

    if (oldWidget.conversationId != widget.conversationId) {
      debugPrint('🔄[ChatPage] 会话ID发生变化，调用 _onConversationChanged');
      _onConversationChanged();
    }
  }

  void _onConversationChanged() {
    debugPrint('🔄[ChatPage] _onConversationChanged 被调用: conversationId=${widget.conversationId}');
    _currentPage = 1;
    _hasMore = true;
    _lastMessageCount = 0;
    // 会话切换时重新解析 targetId
    _resolvedTargetId = null;
    _resolveTargetIdFromConversations();

    if (widget.conversationId.isNotEmpty) {
      // ✅ 同步设置当前会话（不使用 postFrameCallback）
      // 原因：避免时序问题，确保会话切换时立即生效
      debugPrint('🔄[ChatPage] _onConversationChanged: 同步设置当前会话 ${widget.conversationId}');
      _chatProvider?.setCurrentConversation(
        ConversationModel(
          id: widget.conversationId,
          targetId: effectiveTargetId,
          name: widget.conversationName,
          participantIds: [],
          isGroup: widget.isGroup,
        ),
      );

      // 异步操作（加载消息、标记已读）仍然使用 postFrameCallback
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        debugPrint('🔄[ChatPage] _onConversationChanged postFrameCallback 执行: 加载消息');
        await _chatProvider?.loadMessages(widget.conversationId);

        _scrollToBottom(animate: false);  // 切换会话时也使用无动画跳转

        // 使用 effectiveTargetId（含兜底查询后的真实用户ID）
        final targetId = effectiveTargetId;

        await _chatProvider?.markConversationAsRead(
          targetId: targetId,
          isGroup: widget.isGroup,
          dbId: _chatProvider?.currentConversation?.dbId,
        );
      });
    } else {
      debugPrint('⚠️[ChatPage] _onConversationChanged: conversationId 为空，清空当前会话');
      _chatProvider?.clearCurrentConversation();
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    debugPrint('🗑️[ChatPage] dispose 被调用: conversationId=${widget.conversationId}');
    final shouldClear = widget.conversationId.isEmpty;
    debugPrint('🗑️[ChatPage] dispose: shouldClear=$shouldClear');

    _messageController.dispose();
    _scrollController.dispose();

    // ✅ 改进的清理逻辑：
    // 1. 只在占位符页面（conversationId 为空）销毁时才考虑清空
    // 2. 使用延迟检查，避免在会话切换时误清空新设置的会话
    if (shouldClear) {
      Future.microtask(() {
        // 再次检查：如果当前会话已经被新 Widget 设置过，就不清空
        if (_chatProvider?.currentConversation != null) {
          debugPrint('🗑️[ChatPage] dispose microtask: 当前已有会话 ${_chatProvider?.currentConversation?.id}，跳过清空');
          return;
        }
        debugPrint('🗑️[ChatPage] dispose microtask: 确认清空当前会话');
        _chatProvider?.clearCurrentConversation();
      });
    } else {
      debugPrint('🗑️[ChatPage] dispose: 聊天页面被销毁，不清空会话');
    }

    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels <= 200) {
      _loadMoreMessages();
    }
  }

  bool _isMessageFromMe(MessageModel message, BuildContext context) {
    final authUserId = Provider.of<AuthProvider>(
      context,
      listen: false,
    )?.user?.id;
    return message.isSent || message.senderId == authUserId;
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;

    _currentPage++;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    try {
      final targetId = effectiveTargetId;
      final sdkMessages = await chatProvider.loadMoreHistoryMessages(
        targetId: targetId,
        page: _currentPage,
        pageSize: 20,
      );

      if (sdkMessages == null || sdkMessages.length < 20) {
        _hasMore = false;
      }
    } catch (e) {
      debugPrint('加载更多消息失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isSending) return;

    setState(() => _isSending = true);
    final content = _messageController.text.trim();

    await Provider.of<ChatProvider>(
      context,
      listen: false,
    ).sendMessage(content);

    _messageController.clear();
    setState(() => _isSending = false);

    _scrollToBottom();
  }

  Future<void> _retryMessage(MessageModel message) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    await chatProvider.retrySendMessage(message);
    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        await Provider.of<ChatProvider>(
          context,
          listen: false,
        ).sendMessage(image.path, type: 'image');
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('选择图片失败: $e');
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      if (!animate) {
        _scrollController.jumpTo(0);
        return;
      }

      final currentOffset = _scrollController.offset;
      
      if (currentOffset <= 1) {
        return; 
      }

      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _showMoreOptions() {
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildOptionItem(Icons.photo_library, '图片', _pickImage),
                    _buildOptionItem(Icons.camera_alt, '拍照', () async {
                      try {
                        final XFile? photo = await _picker.pickImage(
                          source: ImageSource.camera,
                        );
                        if (photo != null) {
                          await Provider.of<ChatProvider>(
                            context,
                            listen: false,
                          ).sendMessage(photo.path, type: 'image');
                          _scrollToBottom();
                        }
                      } catch (e) {
                        debugPrint('拍照失败: $e');
                      }
                    }),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('显示底部弹窗失败: $e');
    }
  }

  Widget _buildOptionItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 28, color: AppTheme.primaryColor),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPanelMode && widget.conversationId.isEmpty) {
      return _buildPlaceholder();
    }
    
    if (widget.isPanelMode) {
      return _buildPanelLayout();
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.conversationName),
            if (widget.isGroup)
              const Text(
                '群聊',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              )
            else
              const Text(
                '在线',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildInputToolbar(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return Consumer2<ChatProvider, AuthProvider>(
      builder: (context, chatProvider, authProvider, _) {
        if (chatProvider.isLoading && chatProvider.messages.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (chatProvider.messages.isEmpty) {
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
                  '暂无消息',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '发送消息开始聊天吧~',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        final currentMessageCount = chatProvider.messages.length;
        if (currentMessageCount > _lastMessageCount && _lastMessageCount > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
        }
        _lastMessageCount = currentMessageCount;

        final currentUser = authProvider.user;

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
              controller: _scrollController,
              reverse: true,
              itemCount: chatProvider.messages.length,
              itemBuilder: (context, index) {
                final reversedIndex = chatProvider.messages.length - 1 - index;
                final message = chatProvider.messages[reversedIndex];
                final previousMessage = (reversedIndex > 0)
                    ? chatProvider.messages[reversedIndex - 1]
                    : null;

                final showTimeSeparator = shouldShowTimeSeparator(
                  message.timestamp,
                  previousMessage?.timestamp,
                );

                final isMe = _isMessageFromMe(message, context);

                String? senderAvatar;
                String? senderName;

                if (isMe) {
                  senderAvatar = currentUser?.avatar;
                  senderName = currentUser?.nickname ?? currentUser?.username;
                } else {
                  senderAvatar = contactAvatar;
                  senderName = contactName;
                }

                return Column(
                  children: [
                    if (showTimeSeparator)
                      TimeSeparator(time: message.timestamp),
                    MessageBubble(
                      message: message,
                      isMe: isMe,
                      senderAvatar: senderAvatar,
                      senderName: senderName,
                      showName: widget.isGroup && !isMe,
                      onRetry: () => _retryMessage(message),
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

  Future<ContactInfo?> _getContactInfo(ChatProvider chatProvider) async {
    try {
      final targetId = effectiveTargetId;

      if (targetId <= 0) return null;

      return await chatProvider.getContactInfoById(targetId);
    } catch (e) {
      debugPrint('获取联系人信息失败: $e');
      return null;
    }
  }

  Widget _buildInputToolbar() {
    final horizontalPadding = widget.isPanelMode ? 20.0 : 8.0;
    final iconButtonSize = widget.isPanelMode ? 40.0 : 36.0;

    return Container(
      padding: EdgeInsets.only(
        left: horizontalPadding,
        right: horizontalPadding,
        top: widget.isPanelMode ? 12 : 8,
        bottom: MediaQuery.of(context).padding.bottom + (widget.isPanelMode ? 12 : 8),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            SizedBox(
              width: iconButtonSize,
              height: iconButtonSize,
              child: IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 24),
                color: AppTheme.primaryColor,
                onPressed: _showMoreOptions,
                tooltip: '更多',
              ),
            ),
            if (widget.isPanelMode) ...[
              SizedBox(
                width: iconButtonSize,
                height: iconButtonSize,
                child: IconButton(
                  icon: const Icon(Icons.attach_file_outlined, size: 22),
                  color: AppTheme.textSecondaryColor,
                  onPressed: _showMoreOptions,
                  tooltip: '发送文件',
                ),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: '输入消息...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: widget.isPanelMode ? 18 : 16,
                    vertical: widget.isPanelMode ? 11 : 10,
                  ),
                  hintStyle: TextStyle(
                    fontSize: widget.isPanelMode ? 15 : 14,
                  ),
                ),
                style: TextStyle(
                  fontSize: widget.isPanelMode ? 15 : 14,
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            if (widget.isPanelMode) const SizedBox(width: 10) else const SizedBox(width: 8),
            SizedBox(
              width: iconButtonSize,
              height: iconButtonSize,
              child: IconButton(
                icon: const Icon(Icons.send, size: 22),
                color: AppTheme.primaryColor,
                onPressed: _isSending ? null : _sendMessage,
                tooltip: '发送',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 96,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 20),
          Text(
            '选择一个会话开始聊天',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '在左侧列表中选择联系人或群组',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeader() {
    final fontSize = widget.isPanelMode ? 17.0 : 16.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isPanelMode ? 20 : 16,
        vertical: widget.isPanelMode ? 14 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppTheme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.conversationName,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimaryColor,
              ),
            ),
          ),
          if (widget.isPanelMode) ...[
            _buildPanelActionButton(Icons.phone_outlined, '语音通话'),
            const SizedBox(width: 4),
            _buildPanelActionButton(Icons.videocam_outlined, '视频通话'),
            const SizedBox(width: 4),
          ],
          _buildPanelActionButton(Icons.more_vert, '更多'),
        ],
      ),
    );
  }

  Widget _buildPanelActionButton(IconData icon, String tooltip) {
    final buttonSize = widget.isPanelMode ? 36.0 : 32.0;
    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: IconButton(
        icon: Icon(icon, size: widget.isPanelMode ? 22 : 20),
        tooltip: tooltip,
        onPressed: () {},
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildPanelLayout() {
    return Material(
      color: AppTheme.surfaceColor,
      child: Column(
        children: [
          _buildPanelHeader(),
          Expanded(child: _buildMessageList()),
          _buildInputToolbar(),
        ],
      ),
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _isLoadingMore
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                '- 没有更多了 -',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
      ),
    );
  }
}
