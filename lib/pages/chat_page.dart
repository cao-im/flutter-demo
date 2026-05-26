import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../models/message_model.dart';
import '../models/chat_model.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final String conversationName;
  final bool isGroup;

  const ChatPage({
    super.key,
    required this.conversationId,
    required this.conversationName,
    this.isGroup = false,
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChatProvider>(context, listen: false).setCurrentConversation(
        ConversationModel(
          id: widget.conversationId,
          name: widget.conversationName,
          participantIds: [],
          isGroup: widget.isGroup,
        ),
      );
      Provider.of<ChatProvider>(
        context,
        listen: false,
      ).loadMessages(widget.conversationId);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    Provider.of<ChatProvider>(
      context,
      listen: false,
    ).clearCurrentConversation();
    super.dispose();
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
    showModalBottomSheet(
      context: context,
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
          Expanded(
            child: Consumer<ChatProvider>(
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

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: chatProvider.messages.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_hasMore && index == chatProvider.messages.length) {
                      return _buildLoadingMoreIndicator();
                    }

                    final message = chatProvider.messages[index];
                    // 优先使用 isSent 字段判断，其次通过 senderId 比较
                    final authUserId = Provider.of<AuthProvider>(
                      context,
                      listen: false,
                    )?.user?.id;
                    final isMe = message.isSent || message.senderId == authUserId;
                    return MessageBubble(
                      message: message,
                      isMe: isMe,
                      onRetry: () => _retryMessage(message),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 8,
              right: 8,
              top: 8,
              bottom: MediaQuery.of(context).padding.bottom + 8,
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
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    color: AppTheme.primaryColor,
                    onPressed: _showMoreOptions,
                  ),
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: AppTheme.primaryColor,
                    onPressed: _isSending ? null : _sendMessage,
                  ),
                ],
              ),
            ),
          ),
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
