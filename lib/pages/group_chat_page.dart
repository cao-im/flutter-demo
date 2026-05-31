import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';
import '../models/message_model.dart';

class GroupChatPage extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupChatPage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<MessageModel> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMockMessages();
  }

  void _loadMockMessages() async {
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _messages = [
        MessageModel(
          id: '1',
          conversationId: widget.groupId,
          senderId: 'user1',
          receiverId: widget.groupId,
          type: MessageType.text,
          content: '大家好，欢迎加入群聊！',
          timestamp: DateTime.now().subtract(const Duration(minutes: 30)),
        ),
        MessageModel(
          id: '2',
          conversationId: widget.groupId,
          senderId: 'user2',
          receiverId: widget.groupId,
          type: MessageType.text,
          content: '谢谢！很高兴认识大家',
          timestamp: DateTime.now().subtract(const Duration(minutes: 25)),
        ),
        MessageModel(
          id: '3',
          conversationId: widget.groupId,
          senderId: 'me',
          receiverId: widget.groupId,
          type: MessageType.text,
          content: '大家好~',
          timestamp: DateTime.now().subtract(const Duration(minutes: 20)),
        ),
      ];
      _isLoading = false;
    });
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    final message = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: widget.groupId,
      senderId: 'me',
      receiverId: widget.groupId,
      type: MessageType.text,
      content: _messageController.text.trim(),
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.insert(0, message);
    });

    _messageController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.groupName),
            Text(
              '${_messages.length}条消息',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.people_outline), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isMe = message.senderId == 'me';
                      return MessageBubble(
                        message: message,
                        isMe: isMe,
                        showName: !isMe,
                        senderName: isMe ? '我' : '用户${message.senderId}',
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
                    onPressed: () {},
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
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: AppTheme.primaryColor,
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
