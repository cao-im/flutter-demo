import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_keyboard_provider.dart';
import '../models/message_model.dart';
import '../models/chat_model.dart';
import '../theme/app_theme.dart';
import '../widgets/chat/chat_page_shell.dart';
import '../widgets/chat/chat_header_widget.dart';
import '../widgets/chat/message_list_widget.dart';
import '../widgets/chat/chat_input_widget.dart';

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

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode(); // 输入框焦点，用于键盘高度监听
  final ImagePicker _picker = ImagePicker();
  bool _isSending = false;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  ChatProvider? _chatProvider;
  int _lastMessageCount = 0;
  bool _currentConversationNotSetInInit = false; // 标记 initState 中是否成功设置会话
  int? _resolvedTargetId; // 解析后的 targetId（含兜底查询）

  /// 键盘防抖 Timer（避免 didChangeMetrics 频繁触发）
  Timer? _keyboardDebounceTimer;

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
    WidgetsBinding.instance.addObserver(this);
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

    WidgetsBinding.instance.removeObserver(this);
    _keyboardDebounceTimer?.cancel();
    _inputFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();

    // ✅ 退出聊天页面时清除当前会话状态，恢复消息通知功能
    // 使用延迟检查，避免在会话切换（A→B）时误清空新设置的会话
    Future.microtask(() {
      if (_chatProvider?.currentConversation != null &&
          _chatProvider?.currentConversation?.id == widget.conversationId) {
        debugPrint('🗑️[ChatPage] dispose: 确认清空当前会话，恢复通知');
        _chatProvider?.clearCurrentConversation();
      } else {
        debugPrint('🗑️[ChatPage] dispose: 当前会话已变更或为空，跳过清空');
      }
    });

    super.dispose();
  }

  // ==================== 键盘高度监听（丝滑切换核心） ====================

  /// 监听键盘/窗口尺寸变化，实时更新面板高度
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;

    final keyboardProvider = Provider.of<ChatKeyboardProvider>(context, listen: false);
    final currentKeyboardHeight = EdgeInsets.fromWindowPadding(
      WidgetsBinding.instance.window.viewInsets,
      WidgetsBinding.instance.window.devicePixelRatio,
    ).bottom;

    // 防抖：39ms 后更新，避免频繁触发导致闪烁
    _keyboardDebounceTimer?.cancel();
    _keyboardDebounceTimer = Timer(const Duration(milliseconds: 39), () {
      if (!mounted) return;
      keyboardProvider.updateKeyboardHeight(
        currentKeyboardHeight,
        hasFocus: _inputFocusNode.hasFocus,
      );
    });
  }

  void _scrollListener() {
    if (_scrollController.position.pixels <= 200) {
      _loadMoreMessages();
    }
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

  // ==================== 重构后的 UI 构建部分 ====================

  @override
  Widget build(BuildContext context) {
    // 空状态判断（保持原逻辑）
    if (widget.isPanelMode && widget.conversationId.isEmpty) {
      return _buildPlaceholder();
    }

    // 使用 ChatKeyboardProvider 管理键盘/面板高度，实现丝滑切换
    return ChangeNotifierProvider(
      create: (_) => ChatKeyboardProvider(),
      child: Builder(
        builder: (context) {
          // 使用 ChatPageShell 组装页面
          return ChatPageShell(
            isPanelMode: widget.isPanelMode,
            placeholder: (widget.isPanelMode && widget.conversationId.isEmpty)
                ? _buildPlaceholder()
                : null,

            // 标题栏：根据平台选择样式
            header: ChatHeaderWidget(
              title: widget.conversationName,
              subtitle: widget.isGroup ? '群聊' : '在线',
              style: widget.isPanelMode ? ChatHeaderStyle.panel : ChatHeaderStyle.appBar,
              showVoiceCall: widget.isPanelMode,
              showVideoCall: widget.isPanelMode,
              onMoreTap: () {},
            ),

            // 消息列表：使用提取的组件
            body: MessageListWidget(
              scrollController: _scrollController,
              onScrollToBottom: () => _scrollToBottom(),
              targetId: effectiveTargetId,
              isGroup: widget.isGroup,
              onRetry: (message) => _retryMessage(message),
            ),

            // 输入栏：使用提取的组件，传入动态面板高度
            bottomBar: ChatInputWidget(
              mode: ChatInputMode.text,
              controller: _messageController,
              onSend: _sendMessage,
              isSending: _isSending,
              onMoreOptions: _showMoreOptions,
              style: widget.isPanelMode ? ChatInputStyle.desktop : ChatInputStyle.mobile,
              externalFocusNode: _inputFocusNode,
            ),
          );
        },
      ),
    );
  }

  // 占位页面（保持原逻辑完全保留）
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
}
