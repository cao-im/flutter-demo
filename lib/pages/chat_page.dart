import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../models/message_model.dart';
import '../models/chat_model.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';
import '../widgets/time_separator.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final String conversationName;
  final bool isGroup;
  final bool isPanelMode;

  const ChatPage({
    super.key,
    required this.conversationId,
    required this.conversationName,
    this.isGroup = false,
    this.isPanelMode = false,
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatProvider = Provider.of<ChatProvider>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    
    if (widget.conversationId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _chatProvider?.setCurrentConversation(
          ConversationModel(
            id: widget.conversationId,
            name: widget.conversationName,
            participantIds: [],
            isGroup: widget.isGroup,
          ),
        );

        await _chatProvider?.loadMessages(widget.conversationId);

        _scrollToBottom();

        final parts = widget.conversationId.split('_');
        final targetId = int.tryParse(parts.last ?? '0') ?? 0;
        final isGroup = parts.first == '2';

        await _chatProvider?.markConversationAsRead(
          targetId: targetId,
          isGroup: isGroup,
        );
      });
    }
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.conversationId != widget.conversationId) {
      _onConversationChanged();
    }
  }

  void _onConversationChanged() {
    _currentPage = 1;
    _hasMore = true;

    if (widget.conversationId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _chatProvider?.setCurrentConversation(
          ConversationModel(
            id: widget.conversationId,
            name: widget.conversationName,
            participantIds: [],
            isGroup: widget.isGroup,
          ),
        );

        await _chatProvider?.loadMessages(widget.conversationId);

        _scrollToBottom();

        final parts = widget.conversationId.split('_');
        final targetId = int.tryParse(parts.last ?? '0') ?? 0;
        final isGroup = parts.first == '2';

        await _chatProvider?.markConversationAsRead(
          targetId: targetId,
          isGroup: isGroup,
        );
      });
    } else {
      _chatProvider?.clearCurrentConversation();
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    Future.microtask(() {
      _chatProvider?.clearCurrentConversation();
    });
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
      final parts = widget.conversationId.split('_');
      final targetId = int.tryParse(parts.last ?? '0') ?? 0;
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
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
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
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

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollToBottom();
          }
        });

        return ListView.builder(
          controller: _scrollController,
          itemCount: chatProvider.messages.length,
          itemBuilder: (context, index) {
            final message = chatProvider.messages[index];
            final previousMessage = index > 0
                ? chatProvider.messages[index - 1]
                : null;

            final showTimeSeparator = shouldShowTimeSeparator(
              message.timestamp,
              previousMessage?.timestamp,
            );

            return Column(
              children: [
                if (showTimeSeparator)
                  TimeSeparator(time: message.timestamp),
                MessageBubble(
                  message: message,
                  isMe: _isMessageFromMe(message, context),
                  onRetry: () => _retryMessage(message),
                ),
              ],
            );
          },
        );
      },
    );
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
