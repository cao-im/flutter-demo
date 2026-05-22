import 'package:flutter/foundation.dart';
import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart' as sdk;
import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../sdk/im_sdk_manager.dart';

class ChatProvider with ChangeNotifier {
  final IMSdkManager _sdkManager = IMSdkManager();
  ConversationModel? _currentConversation;
  List<MessageModel> _messages = [];
  List<ConversationModel> _conversations = [];
  bool _isLoading = false;
  bool _isListening = false;

  ConversationModel? get currentConversation => _currentConversation;
  List<MessageModel> get messages => _messages;
  List<ConversationModel> get conversations => _conversations;
  bool get isLoading => _isLoading;

  void startListening() {
    if (_isListening) return;
    _sdkManager.client.addMessageListener(_ChatMessageListener(this));
    _isListening = true;
  }

  void stopListening() {
    _sdkManager.client.removeMessageListener(_ChatMessageListener(this));
    _isListening = false;
  }

  void setCurrentConversation(ConversationModel conversation) {
    _currentConversation = conversation;
    notifyListeners();
  }

  Future<void> loadConversations() async {
    _isLoading = true;
    notifyListeners();

    try {
      final sdkConversations = await _sdkManager.client.getConversationList();
      _conversations = sdkConversations.map((conv) {
        return ConversationModel(
          id: conv.id?.toString() ?? conv.conversationId,
          name: conv.isPrivate ? '用户 ${conv.targetId}' : '群组 ${conv.targetId}',
          participantIds: [conv.targetId.toString(), conv.userId.toString()],
          lastMessage: conv.lastMessage != null
              ? _convertSdkMessageToModel(conv.lastMessage!)
              : null,
          unreadCount: conv.unreadCount,
          isGroup: conv.isGroup,
        );
      }).toList();
    } catch (e) {
      debugPrint('加载会话列表失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMessages(String conversationId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final parts = conversationId.split('_');
      final targetId = int.tryParse(parts.last ?? '0') ?? 0;

      final sdkMessages = await _sdkManager.client.getHistoryMessages(
        targetId: targetId,
      );
      _messages = sdkMessages
          .map((msg) => _convertSdkMessageToModel(msg))
          .toList();
    } catch (e) {
      debugPrint('加载消息失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<MessageModel>?> loadMoreHistoryMessages({
    required int targetId,
    required int page,
    required int pageSize,
  }) async {
    try {
      final sdkMessages = await _sdkManager.client.getHistoryMessages(
        targetId: targetId,
        page: page,
        size: pageSize,
      );
      if (sdkMessages.isEmpty) return null;

      final newMessages = sdkMessages
          .map((msg) => _convertSdkMessageToModel(msg))
          .toList();
      _messages.addAll(newMessages);
      notifyListeners();
      return newMessages;
    } catch (e) {
      debugPrint('加载更多消息失败: $e');
      return null;
    }
  }

  Future<void> sendMessage(String content, {String type = 'text'}) async {
    if (_currentConversation == null) return;

    final tempMessage = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: _currentConversation!.id,
      senderId: '',
      receiverId: '',
      type: type == 'image' ? MessageType.image : MessageType.text,
      content: content,
      timestamp: DateTime.now(),
      isSending: true,
      status: MessageStatus.sending,
    );

    _messages.insert(0, tempMessage);
    notifyListeners();

    try {
      final parts = _currentConversation!.id.split('_');
      final targetId = int.tryParse(parts.last ?? '0') ?? 0;
      final isGroup = parts.first == '2';

      sdk.Message sentMessage;
      if (isGroup) {
        sentMessage = await _sdkManager.client.sendGroupMessage(
          groupId: targetId,
          content: content,
          msgType: type == 'image' ? 1 : 0,
        );
      } else {
        sentMessage = await _sdkManager.client.sendMessage(
          toId: targetId,
          content: content,
          msgType: type == 'image' ? 1 : 0,
        );
      }

      final index = _messages.indexWhere((m) => m.id == tempMessage.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          isSending: false,
          isSent: true,
          status: MessageStatus.sent,
          id: sentMessage.id?.toString() ?? tempMessage.id,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('发送消息失败: $e');
      final index = _messages.indexWhere((m) => m.id == tempMessage.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          isSending: false,
          status: MessageStatus.failed,
        );
        notifyListeners();
      }
    }
  }

  Future<void> retrySendMessage(MessageModel message) async {
    if (_currentConversation == null) return;

    final retryIndex = _messages.indexWhere((m) => m.id == message.id);
    if (retryIndex != -1) {
      _messages[retryIndex] = _messages[retryIndex].copyWith(
        isSending: true,
        status: MessageStatus.sending,
      );
      notifyListeners();
    }

    try {
      final parts = _currentConversation!.id.split('_');
      final targetId = int.tryParse(parts.last ?? '0') ?? 0;
      final isGroup = parts.first == '2';

      sdk.Message sentMessage;
      if (isGroup) {
        sentMessage = await _sdkManager.client.sendGroupMessage(
          groupId: targetId,
          content: message.content,
          msgType: message.type == MessageType.image ? 1 : 0,
        );
      } else {
        sentMessage = await _sdkManager.client.sendMessage(
          toId: targetId,
          content: message.content,
          msgType: message.type == MessageType.image ? 1 : 0,
        );
      }

      if (retryIndex != -1) {
        _messages[retryIndex] = _messages[retryIndex].copyWith(
          isSending: false,
          isSent: true,
          status: MessageStatus.sent,
          id: sentMessage.id?.toString() ?? message.id,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('重发消息失败: $e');
      if (retryIndex != -1) {
        _messages[retryIndex] = _messages[retryIndex].copyWith(
          isSending: false,
          status: MessageStatus.failed,
        );
        notifyListeners();
      }
    }
  }

  void receiveMessage(MessageModel message) {
    _messages.insert(0, message);
    notifyListeners();
  }

  void deleteConversation(String conversationId) {
    _conversations.removeWhere((c) => c.id == conversationId);
    notifyListeners();
  }

  void clearCurrentConversation() {
    _currentConversation = null;
    _messages = [];
    notifyListeners();
  }

  MessageModel _convertSdkMessageToModel(sdk.Message msg) {
    return MessageModel(
      id: msg.id?.toString() ?? msg.timestamp.toString(),
      conversationId: '',
      senderId: msg.fromId.toString(),
      receiverId: msg.toId.toString(),
      type: msg.msgType == sdk.MessageType.image
          ? MessageType.image
          : MessageType.text,
      content: msg.content,
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.timestamp),
      isSent: false,
      status: MessageStatus.delivered,
    );
  }
}

class _ChatMessageListener implements sdk.MessageListener {
  final ChatProvider _provider;
  _ChatMessageListener(this._provider);

  @override
  void onMessageReceived(sdk.Message message) {
    final model = MessageModel(
      id: message.id?.toString() ?? message.timestamp.toString(),
      conversationId: '',
      senderId: message.fromId.toString(),
      receiverId: message.toId.toString(),
      type: message.msgType == sdk.MessageType.image
          ? MessageType.image
          : MessageType.text,
      content: message.content,
      timestamp: DateTime.fromMillisecondsSinceEpoch(message.timestamp),
      status: MessageStatus.delivered,
    );
    _provider.receiveMessage(model);
  }

  @override
  void onMessageSent(sdk.Message message) {}

  @override
  void onMessageRecalled(sdk.Message message) {}
}
