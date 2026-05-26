import 'package:flutter/foundation.dart';
import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart' as sdk;
import 'package:cao_im_sdk_flutter/event/event_bus.dart';
import 'package:cao_im_sdk_flutter/event/im_event.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../sdk/im_sdk_manager.dart';

class ChatProvider with ChangeNotifier {
  final IMSdkManager _sdkManager = IMSdkManager();
  final EventBus _eventBus = EventBus();
  
  ConversationModel? _currentConversation;
  List<MessageModel> _messages = [];
  List<ConversationModel> _conversations = [];
  bool _isLoading = false;
  bool _isListening = false;
  bool _isEventListening = false;

  ConversationModel? get currentConversation => _currentConversation;
  List<MessageModel> get messages => _messages;
  List<ConversationModel> get conversations => _conversations;
  bool get isLoading => _isLoading;

  void startListening() {
    if (_isListening) return;
    _sdkManager.client.addMessageListener(_ChatMessageListener(this));
    _isListening = true;
    
    // ✅ 开始监听事件总线
    startEventListening();
  }

  void stopListening() {
    _sdkManager.client.removeMessageListener(_ChatMessageListener(this));
    _isListening = false;
    
    // ✅ 停止监听事件总线
    stopEventListening();
  }

  /// ✅ 开始监听 EventBus 事件（自动刷新会话列表）
  void startEventListening() {
    if (_isEventListening) return;
    _isEventListening = true;

    // 监听消息发送成功 → 刷新会话列表
    _eventBus.on<MessageSentEvent>().listen((event) {
      debugPrint('📍[ChatProvider] 📢 收到 MessageSentEvent, 自动刷新会话列表');
      loadConversations();
    });

    // 监听收到新消息 → 刷新会话列表
    _eventBus.on<MessageReceivedEvent>().listen((event) {
      debugPrint('📍[ChatProvider] 📢 收到 MessageReceivedEvent, 自动刷新会话列表');

      // 判断当前是否在该会话的聊天页面
      bool isInCurrentConversation = false;
      if (_currentConversation != null) {
        final msgTargetId = event.message.toId;
        final convParts = _currentConversation!.id.split('_');
        final convTargetId = int.tryParse(convParts.last ?? '0') ?? 0;

        if (msgTargetId == convTargetId || event.message.fromId == convTargetId) {
          isInCurrentConversation = true;
          debugPrint('📍[ChatProvider] 消息属于当前会话，刷新消息列表但不增加未读数');
          loadMessages(_currentConversation!.id);
        }
      }

      // 如果不在当前会话，正常加载会话列表（包含未读数）
      if (!isInCurrentConversation) {
        loadConversations();
      } else {
        // 在当前会话时，加载会话列表但清零该会话未读数
        _loadConversationsAndClearUnread();
      }
    });

    // 监听会话更新 → 刷新会话列表
    _eventBus.on<ConversationUpdatedEvent>().listen((event) {
      debugPrint('📍[ChatProvider] 📢 收到 ConversationUpdatedEvent, 自动刷新会话列表');
      loadConversations();
    });

    // 监听消息撤回 → 刷新相关数据
    _eventBus.on<MessageRecalledEvent>().listen((event) {
      debugPrint('📍[ChatProvider] 📢 收到 MessageRecalledEvent');
      loadConversations();
      if (_currentConversation != null) {
        loadMessages(_currentConversation!.id);
      }
    });

    debugPrint('✅[ChatProvider] 已开始监听 EventBus 事件（自动刷新）');
  }

  /// 停止监听事件
  void stopEventListening() {
    _isEventListening = false;
    // EventBus 的监听器会在 Provider 销毁时自动清理
    debugPrint('[ChatProvider] 已停止监听 EventBus 事件');
  }

  void setCurrentConversation(ConversationModel conversation) {
    _currentConversation = conversation;
    notifyListeners();
  }

  Future<void> loadConversations() async {
    _isLoading = true;
    notifyListeners();

    try {
      debugPrint('📍[ChatProvider] 开始加载会话列表...');
      final sdkConversations = await _sdkManager.client.getConversationList();
      debugPrint('📍[ChatProvider] 获取到 ${sdkConversations.length} 个会话');

      final List<ConversationModel> conversationModels = [];

      for (final conv in sdkConversations) {
        final displayId = (conv.id != null && conv.id! > 0)
            ? '${conv.targetType.value}_${conv.targetId}'
            : conv.conversationId;

        String displayName;
        DateTime? lastActiveTime;

        if (conv.isGroup) {
          try {
            final group = await _sdkManager.client.getGroup(conv.targetId);
            displayName = group.name.isNotEmpty ? group.name : '群组 ${conv.targetId}';
          } catch (e) {
            debugPrint('⚠️[ChatProvider] 获取群组名称失败: $e');
            displayName = '群组 ${conv.targetId}';
          }
        } else {
          displayName = '用户${conv.targetId}';
        }

        if (conv.lastMessage != null) {
          lastActiveTime = DateTime.fromMillisecondsSinceEpoch(conv.lastMessage!.timestamp);
        } else if (conv.updateTime != null) {
          lastActiveTime = DateTime.fromMillisecondsSinceEpoch(conv.updateTime);
        }

        conversationModels.add(ConversationModel(
          id: displayId,
          name: displayName,
          participantIds: [conv.targetId.toString(), conv.userId.toString()],
          lastMessage: conv.lastMessage != null
              ? _convertSdkMessageToModel(conv.lastMessage!)
              : null,
          unreadCount: conv.unreadCount,
          isGroup: conv.isGroup,
          lastActiveTime: lastActiveTime,
        ));
      }

      _conversations = conversationModels;

      debugPrint('📍[ChatProvider] 会话列表转换完成, 数量: ${_conversations.length}');
      if (_conversations.isNotEmpty) {
        debugPrint('📍[ChatProvider] 第一个会话: id=${_conversations[0].id}, name=${_conversations[0].name}');
      }
    } catch (e, stackTrace) {
      debugPrint('❌[ChatProvider] 加载会话列表失败: $e');
      debugPrint('❌[ChatProvider] 堆栈: $stackTrace');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadConversationsAndClearUnread() async {
    try {
      final sdkConversations = await _sdkManager.client.getConversationList();

      final List<ConversationModel> conversationModels = [];

      for (final conv in sdkConversations) {
        final displayId = (conv.id != null && conv.id! > 0)
            ? '${conv.targetType.value}_${conv.targetId}'
            : conv.conversationId;

        String displayName;
        DateTime? lastActiveTime;

        if (conv.isGroup) {
          try {
            final group = await _sdkManager.client.getGroup(conv.targetId);
            displayName = group.name.isNotEmpty ? group.name : '群组 ${conv.targetId}';
          } catch (e) {
            displayName = '群组 ${conv.targetId}';
          }
        } else {
          displayName = '用户${conv.targetId}';
        }

        if (conv.lastMessage != null) {
          lastActiveTime = DateTime.fromMillisecondsSinceEpoch(conv.lastMessage!.timestamp);
        } else if (conv.updateTime != null) {
          lastActiveTime = DateTime.fromMillisecondsSinceEpoch(conv.updateTime);
        }

        // 如果是当前会话，清零未读数
        int unreadCount = conv.unreadCount;
        if (_currentConversation != null && displayId == _currentConversation!.id) {
          unreadCount = 0;
          debugPrint('📍[ChatProvider] 当前会话未读数已清零: $displayId');
        }

        conversationModels.add(ConversationModel(
          id: displayId,
          name: displayName,
          participantIds: [conv.targetId.toString(), conv.userId.toString()],
          lastMessage: conv.lastMessage != null
              ? _convertSdkMessageToModel(conv.lastMessage!)
              : null,
          unreadCount: unreadCount,
          isGroup: conv.isGroup,
          lastActiveTime: lastActiveTime,
        ));
      }

      _conversations = conversationModels;
      notifyListeners();
    } catch (e) {
      debugPrint('❌[ChatProvider] 加载会话列表(清零未读)失败: $e');
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

      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
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
      _messages.insertAll(0, newMessages);
      notifyListeners();
      return newMessages;
    } catch (e) {
      debugPrint('加载更多消息失败: $e');
      return null;
    }
  }

  Future<void> sendMessage(String content, {String type = 'text'}) async {
    if (_currentConversation == null) {
      debugPrint('❌[ChatProvider] sendMessage 失败: _currentConversation 为空');
      return;
    }

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

    _messages.add(tempMessage);
    notifyListeners();

    try {
      final parts = _currentConversation!.id.split('_');
      final targetId = int.tryParse(parts.last ?? '0') ?? 0;
      final isGroup = parts.first == '2';
      
      debugPrint('📍[ChatProvider] 发送消息: conversationId=${_currentConversation!.id}, targetId=$targetId, isGroup=$isGroup');
      
      if (targetId <= 0) {
        debugPrint('❌[ChatProvider] ⚠️ targetId 无效 ($targetId)，取消发送');
        return;
      }

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
      
      // ✅ 发送成功后也主动刷新一次会话列表（双重保障）
      debugPrint('📍[ChatProvider] 发送成功，主动刷新会话列表');
      loadConversations();
      
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
    _messages.add(message);
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    notifyListeners();
  }

  Future<void> markConversationAsRead({
    required int targetId,
    required bool isGroup,
  }) async {
    try {
      debugPrint('📍[ChatProvider] 标记会话已读: targetId=$targetId, isGroup=$isGroup');

      await _sdkManager.client.markConversationAsRead(targetId);

      final convIndex = _conversations.indexWhere(
        (c) => c.id.contains(targetId.toString()),
      );

      if (convIndex != -1 && _conversations[convIndex].unreadCount > 0) {
        final updatedConv = _conversations[convIndex].copyWith(
          unreadCount: 0,
        );
        _conversations[convIndex] = updatedConv;
        debugPrint('✅[ChatProvider] 会话已读标记成功, 未读数已清零');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌[ChatProvider] 标记会话已读失败: $e');
    }
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
    final currentUserId = _sdkManager.client.currentUserId;
    final isFromMe = currentUserId != null && msg.fromId == currentUserId;

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
      isSent: isFromMe,
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
