import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/chat_provider.dart';
import '../providers/contact_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_keyboard_provider.dart';
import '../providers/layout_provider.dart';
import '../models/message_model.dart';
import '../models/file_content.dart';
import '../models/chat_model.dart';
import '../models/user_model.dart';
import '../theme/app_theme.dart';
import '../widgets/chat/chat_page_shell.dart';
import '../widgets/chat/chat_header_widget.dart';
import '../widgets/chat/message_list_widget.dart';
import '../widgets/chat/chat_input_widget.dart';
import 'user_profile_page.dart';
import 'profile_page.dart';
import 'group_info_page.dart';
import '../services/apis/group_api.dart';

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
  String _announcement = '';
  bool _showGroupDrawer = false;
  int _memberCount = 0;
  String? _groupNameOverride;

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
    if (widget.isGroup) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadGroupMeta());
    }

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
    _showGroupDrawer = false;
    _memberCount = 0;
    _groupNameOverride = null;
    _announcement = '';
    // 会话切换时重新解析 targetId
    _resolvedTargetId = null;
    _resolveTargetIdFromConversations();
    if (widget.isGroup) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadGroupMeta());
    }

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

    try {
      await Provider.of<ChatProvider>(
        context,
        listen: false,
      ).sendMessage(content);
      if (!mounted) return;
      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendVoice(String path, int seconds) async {
    try {
      await Provider.of<ChatProvider>(context, listen: false).sendVoiceFile(path, seconds);
      if (!mounted) return;
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _retryMessage(MessageModel message) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    await chatProvider.retrySendMessage(message);
    _scrollToBottom();
  }

  Future<void> _deleteMessage(MessageModel message) async {
    await Provider.of<ChatProvider>(context, listen: false).deleteMessage(message);
  }

  void _quoteMessage(MessageModel message) {
    context.read<ChatProvider>().setReplyingTo(message);
    _inputFocusNode.requestFocus();
  }

  Future<void> _forwardMessage(MessageModel message) async {
    final chat = context.read<ChatProvider>();
    final targets = chat.conversations.where((item) => item.targetId > 0).toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可转发的会话')),
      );
      return;
    }
    final picked = await showDialog<ConversationModel>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('转发给'),
          content: SizedBox(
            width: 320,
            height: 360,
            child: ListView.builder(
              itemCount: targets.length,
              itemBuilder: (_, index) {
                final item = targets[index];
                return ListTile(
                  title: Text(item.name.isEmpty ? '未命名会话' : item.name),
                  subtitle: Text(item.isGroup ? '群聊' : '私聊'),
                  onTap: () => Navigator.pop(dialogContext, item),
                );
              },
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    try {
      await context.read<ChatProvider>().forwardMessage(message, picked);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已转发给 ${picked.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('转发失败：$e')),
      );
    }
  }

  Future<void> _recallMessage(MessageModel message) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤回消息'),
        content: const Text('确定要撤回这条消息吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await chatProvider.recallMessage(message);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('消息已撤回'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('撤回失败: $e'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();
        await Provider.of<ChatProvider>(
          context,
          listen: false,
        ).sendImage(bytes, image.name);
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('选择图片失败: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: FileContent.allowedExtensions,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.single;
      await context.read<ChatProvider>().sendFile(
        name: file.name,
        size: file.size,
        path: file.path,
        bytes: file.bytes,
      );
      if (!mounted) return;
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
                    _buildOptionItem(Icons.insert_drive_file_outlined, '文件', _pickFile),
                    if (widget.isGroup)
                      _buildOptionItem(Icons.alternate_email, '提及', () {
                        Navigator.pop(context);
                        _mentionMember();
                      }),
                    _buildOptionItem(Icons.camera_alt, '拍照', () async {
                      try {
                        final XFile? photo = await _picker.pickImage(
                          source: ImageSource.camera,
                        );
                        if (photo != null) {
                          final bytes = await photo.readAsBytes();
                          await Provider.of<ChatProvider>(
                            context,
                            listen: false,
                          ).sendImage(bytes, photo.name);
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
            sidePanel: widget.isGroup && _showGroupDrawer && _useSideGroupPanel()
                ? GroupInfoDrawer(
                    groupId: effectiveTargetId,
                    groupName: _groupNameOverride ?? widget.conversationName,
                    onClose: () => _setGroupDrawer(false),
                    onMemberCount: (count) {
                      if (!mounted || count == _memberCount) return;
                      setState(() => _memberCount = count);
                    },
                    onAnnouncementChanged: (text) {
                      if (!mounted || text == _announcement) return;
                      setState(() => _announcement = text);
                    },
                    onNameChanged: (name) => _applyGroupName(name),
                    onMemberTap: (userId, name, avatar) => _openUserProfile(
                      context,
                      userId: userId,
                      nickname: name,
                      avatar: avatar,
                    ),
                  )
                : null,
            onSidePanelDismissed: () => _setGroupDrawer(false),

            // 标题栏：根据平台选择样式
            header: ChatHeaderWidget(
              title: _headerTitle(context.watch<ChatProvider>()),
              subtitle: widget.isGroup ? null : '在线',
              style: widget.isPanelMode ? ChatHeaderStyle.panel : ChatHeaderStyle.appBar,
              showVoiceCall: widget.isPanelMode,
              showVideoCall: widget.isPanelMode,
              onTitleTap: widget.isGroup ? () => _openGroupSurface() : () => _openPeerProfile(context),
              onMoreTap: widget.isGroup ? () => _openGroupSurface() : () {},
            ),

            // 消息列表：使用提取的组件
            body: Column(
              children: [
                if (widget.isGroup && _announcement.isNotEmpty)
                  Material(
                    color: const Color(0xFFFFF7E8),
                    child: InkWell(
                      onTap: () => _openGroupSurface(toggle: false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.campaign_outlined, size: 18, color: Color(0xFFB26A00)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _announcement,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF8A5A00)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: MessageListWidget(
              scrollController: _scrollController,
              onScrollToBottom: () => _scrollToBottom(),
              targetId: effectiveTargetId,
              isGroup: widget.isGroup,
              onRetry: (message) => _retryMessage(message),
              onRecall: (message) => _recallMessage(message),
              onDelete: (message) => _deleteMessage(message),
              onQuote: _quoteMessage,
              onForward: _forwardMessage,
              onAvatarTap: (message, isMe) => _openSenderProfile(context, message, isMe),
            ),
                ),
              ],
            ),

            // 输入栏：使用提取的组件，传入动态面板高度
            bottomBar: Builder(
              builder: (context) {
                final reply = context.watch<ChatProvider>().replyingTo;
                return ChatInputWidget(
                  mode: ChatInputMode.text,
                  controller: _messageController,
                  onSend: _sendMessage,
                  isSending: _isSending,
                  onMoreOptions: _showMoreOptions,
                  onAttachFile: _pickFile,
                  onVoiceRecorded: _sendVoice,
                  style: widget.isPanelMode ? ChatInputStyle.desktop : ChatInputStyle.mobile,
                  externalFocusNode: _inputFocusNode,
                  quoteTitle: reply?.senderDisplayName,
                  quotePreview: reply?.quoteText,
                  onClearQuote: () => context.read<ChatProvider>().clearReply(),
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _liveConversationName(ChatProvider chatProvider) {
    for (final conversation in chatProvider.conversations) {
      if (conversation.isGroup == widget.isGroup &&
          conversation.targetId == effectiveTargetId &&
          conversation.name.isNotEmpty) {
        return conversation.name;
      }
    }
    if (_groupNameOverride != null && _groupNameOverride!.isNotEmpty) {
      return _groupNameOverride!;
    }
    return widget.conversationName;
  }

  String _headerTitle(ChatProvider chatProvider) {
    final name = _liveConversationName(chatProvider);
    if (widget.isGroup && _memberCount > 0) return '$name ($_memberCount)';
    return name;
  }

  bool _useSideGroupPanel() {
    final phone = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return !phone;
  }

  void _openGroupSurface({bool toggle = true}) {
    if (effectiveTargetId <= 0) return;
    if (_useSideGroupPanel()) {
      _setGroupDrawer(toggle ? !_showGroupDrawer : true);
      return;
    }
    _openGroupInfoPage();
  }

  Future<void> _openGroupInfoPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupInfoPage(
          groupId: effectiveTargetId,
          groupName: _groupNameOverride ?? widget.conversationName,
          onMemberCount: (count) {
            if (!mounted || count == _memberCount) return;
            setState(() => _memberCount = count);
          },
          onAnnouncementChanged: (text) {
            if (!mounted || text == _announcement) return;
            setState(() => _announcement = text);
          },
          onNameChanged: _applyGroupName,
          onMemberTap: (userId, name, avatar) {
            if (!mounted) return;
            _openUserProfile(
              context,
              userId: userId,
              nickname: name,
              avatar: avatar,
            );
          },
        ),
      ),
    );
  }

  void _applyGroupName(String name) {
    if (!mounted || name.isEmpty) return;
    context.read<ChatProvider>().renameGroup(effectiveTargetId, name);
    final layout = context.read<LayoutProvider>();
    layout.renameConversationIfOpen(widget.conversationId, name);
    layout.renameConversationIfOpen('$effectiveTargetId', name);
    if (name == _groupNameOverride) return;
    setState(() => _groupNameOverride = name);
  }

  void _setGroupDrawer(bool open) {
    if (open && effectiveTargetId <= 0) return;
    setState(() => _showGroupDrawer = open);
  }

  Future<void> _loadGroupMeta() async {
    if (!widget.isGroup || effectiveTargetId <= 0) return;
    try {
      final group = await GroupApi().getGroupInfo(effectiveTargetId);
      final text = group['introduction']?.toString() ?? '';
      final name = group['name']?.toString() ?? '';
      if (!mounted) return;
      if (name.isNotEmpty) _applyGroupName(name);
      setState(() {
        if (text != _announcement) _announcement = text;
      });
    } catch (e) {
      debugPrint('加载群公告失败: $e');
    }
    try {
      final members = await GroupApi().fetchMembers(effectiveTargetId);
      if (!mounted) return;
      setState(() => _memberCount = members.length);
    } catch (e) {
      debugPrint('加载群成员数失败: $e');
    }
  }

  Future<void> _mentionMember() async {
    if (effectiveTargetId <= 0) return;
    try {
      final members = await GroupApi().fetchMembers(effectiveTargetId);
      if (!mounted) return;
      final me = context.read<AuthProvider>().user;
      final myId = int.tryParse(me?.imUserId ?? '') ?? int.tryParse(me?.id ?? '') ?? 0;
      final picked = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('选择要提及的成员')),
              for (final raw in members.whereType<Map>())
                if (_asMentionId(raw['userId']) != myId)
                  ListTile(
                    title: Text(_mentionName(raw)),
                    onTap: () => Navigator.pop(sheetContext, Map<String, dynamic>.from(raw)),
                  ),
            ],
          ),
        ),
      );
      if (picked == null || !mounted) return;
      final name = _mentionName(picked);
      final userId = _asMentionId(picked['userId']);
      final text = _messageController.text;
      final spacer = text.isEmpty || text.endsWith(' ') ? '' : ' ';
      _messageController.text = '$text$spacer@$name ';
      _messageController.selection = TextSelection.collapsed(offset: _messageController.text.length);
      context.read<ChatProvider>().addMention(userId, name);
      _inputFocusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法加载成员：$e')));
    }
  }

  String _mentionName(Map raw) {
    final groupNick = raw['groupNickname']?.toString() ?? '';
    if (groupNick.isNotEmpty) return groupNick;
    final name = raw['nickname']?.toString() ?? '';
    if (name.isNotEmpty) return name;
    return '用户${raw['userId']}';
  }

  int _asMentionId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _openPeerProfile(BuildContext context) {
    final userId = effectiveTargetId;
    if (userId <= 0) return;
    _openUserProfile(
      context,
      userId: userId,
      nickname: widget.conversationName,
    );
  }

  void _openSenderProfile(BuildContext context, MessageModel message, bool isMe) {
    if (isMe) {
      if (widget.isPanelMode) {
        context.read<LayoutProvider>().selectNavigation(4);
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfilePage()),
        );
      }
      return;
    }
    final userId = int.tryParse(message.senderId) ?? message.senderInfo?.userId ?? 0;
    if (!widget.isGroup && userId <= 0) {
      _openPeerProfile(context);
      return;
    }
    final nickname = !widget.isGroup &&
            (message.senderInfo == null || message.senderInfo!.nickname.isEmpty)
        ? widget.conversationName
        : message.senderDisplayName;
    _openUserProfile(
      context,
      userId: userId,
      nickname: nickname,
      avatar: message.senderDisplayAvatar,
    );
  }

  void _openUserProfile(
    BuildContext context, {
    required int userId,
    required String nickname,
    String? avatar,
  }) {
    if (userId <= 0) return;
    final contacts = context.read<ContactProvider>();
    final conversation = context.read<ChatProvider>().privateConversation(userId);
    final contact = contacts.mergeRelationState(
      UserModel(
        id: '$userId',
        username: '',
        nickname: nickname,
        avatar: avatar,
        imUserId: '$userId',
      ),
      isTop: conversation?.isTop,
      isMute: conversation?.isMute,
    );
    if (widget.isPanelMode) {
      final layout = context.read<LayoutProvider>();
      layout.selectNavigation(1);
      layout.selectContact(contact);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfilePage(contact: contact)),
    );
  }

  Widget _buildPlaceholder() {
    return const Material(
      color: AppTheme.backgroundColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChatEmptyMark(),
            SizedBox(height: 28),
            Text(
              '选择一个会话开始聊天',
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4E5964),
              ),
            ),
            SizedBox(height: 6),
            Text(
              '在左侧列表中选择联系人或群组',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF9AA3AB),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 未选中会话时的占位插画：浅色底盘上的两条对话气泡。
class _ChatEmptyMark extends StatelessWidget {
  const _ChatEmptyMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 168,
      height: 168,
      child: CustomPaint(painter: _ChatEmptyMarkPainter()),
    );
  }
}

class _ChatEmptyMarkPainter extends CustomPainter {
  const _ChatEmptyMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(
      center,
      76,
      Paint()..color = AppTheme.primaryColor.withValues(alpha: 0.06),
    );

    canvas.drawCircle(
      center.translate(0, 4),
      56,
      Paint()
        ..color = const Color(0x141A3A5C)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(center, 58, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      58,
      Paint()
        ..color = const Color(0xFFE3EDF5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final incoming = RRect.fromRectAndRadius(
      Rect.fromLTWH(center.dx - 42, center.dy - 36, 68, 44),
      const Radius.circular(14),
    );
    canvas.drawRRect(incoming, Paint()..color = const Color(0xFFF3F7FB));
    canvas.drawRRect(
      incoming,
      Paint()
        ..color = const Color(0xFFD5E3EE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final line = Paint()
      ..color = const Color(0xFFC5D3DE)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    canvas.drawLine(
      Offset(center.dx - 28, center.dy - 22),
      Offset(center.dx + 14, center.dy - 22),
      line,
    );
    canvas.drawLine(
      Offset(center.dx - 28, center.dy - 10),
      Offset(center.dx + 4, center.dy - 10),
      line,
    );

    final outgoing = RRect.fromRectAndRadius(
      Rect.fromLTWH(center.dx - 6, center.dy + 4, 54, 38),
      const Radius.circular(14),
    );
    canvas.drawRRect(
      outgoing,
      Paint()..color = AppTheme.primaryColor.withValues(alpha: 0.16),
    );

    final outLine = Paint()
      ..color = AppTheme.primaryColor.withValues(alpha: 0.55)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    canvas.drawLine(
      Offset(center.dx + 6, center.dy + 18),
      Offset(center.dx + 36, center.dy + 18),
      outLine,
    );
    canvas.drawLine(
      Offset(center.dx + 6, center.dy + 28),
      Offset(center.dx + 24, center.dy + 28),
      outLine,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
