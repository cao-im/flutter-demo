import 'package:flutter/foundation.dart';
import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart' as sdk;
import 'package:cao_im_sdk_flutter/event/event_bus.dart';
import 'package:cao_im_sdk_flutter/event/im_event.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../models/contact_info_model.dart';
import '../models/sender_info_model.dart';
import '../services/contact_database_service.dart';
import '../services/notification_service.dart';
import '../utils/display_name_helper.dart';
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

  // 联系人信息本地缓存（避免重复查询数据库）
  final Map<int, ContactInfo> _contactInfoCache = {};

  ConversationModel? get currentConversation => _currentConversation;
  List<MessageModel> get messages => _messages;
  List<ConversationModel> get conversations => _conversations;
  bool get isLoading => _isLoading;

  int get totalUnreadCount {
    return _conversations.fold(0, (sum, conv) => sum + conv.unreadCount);
  }

  void startListening() {
    if (_isListening) return;
    _sdkManager.client.addMessageListener(_ChatMessageListener(this));
    _isListening = true;

    // ✅ 开始监听事件总线
    startEventListening();

    // ✅ 初始化通知服务
    _initNotificationService();
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
        final convTargetId = _currentConversation!.targetId;

        // 群聊消息：用 groupId 匹配；私聊消息：用 fromId 或 toId 匹配
        final message = event.message;
        if (message.groupId != null && message.groupId! > 0) {
          // 群聊消息
          if (message.groupId == convTargetId) {
            isInCurrentConversation = true;
            debugPrint('📍[ChatProvider] 群聊消息属于当前会话(groupId=${message.groupId})，消息已由 onMessageReceived 增量添加，无需全量刷新');
          }
        } else {
          // 私聊消息
          if (message.toId == convTargetId || message.fromId == convTargetId) {
            isInCurrentConversation = true;
            debugPrint('📍[ChatProvider] 私聊消息属于当前会话，消息已由 onMessageReceived 增量添加，无需全量刷新');
          }
        }
      }

      // 如果不在当前会话，正常加载会话列表（包含未读数）并触发通知
      if (!isInCurrentConversation) {
        loadConversations();
        // ✅ 触发消息通知（通知服务内部会判断是否需要显示）
        _triggerMessageNotification(event.message);
      } else {
        // 在当前会话时：消息已由 receiveMessage() 增量添加到列表，
        // 只需刷新会话列表以更新 lastMessage/unreadCount
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

    // 监听联系人数据变更 → 刷新会话列表
    _eventBus.on<ContactDataChangedEvent>().listen((event) {
      debugPrint('📍[ChatProvider] 📢 收到 ContactDataChangedEvent, changeType=${event.changeType}, contactId=${event.contactId}, 刷新会话列表');

      // 清空联系人信息缓存，确保获取最新数据
      _clearContactInfoCache();

      loadConversations();
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
    debugPrint('🔧[ChatProvider] setCurrentConversation 被调用: id=${conversation.id}, name=${conversation.name}');
    debugPrint('🔧[ChatProvider] 设置前 _currentConversation: ${_currentConversation?.id ?? "null"}');
    _currentConversation = conversation;
    debugPrint('🔧[ChatProvider] 设置后 _currentConversation: ${_currentConversation?.id ?? "null"}');

    // ✅ 同步当前聊天会话到通知服务（用于判断是否需要显示通知）
    NotificationService().currentChatTargetId = conversation.targetId;

    // 延迟通知，避免在 initState 等 build 期间调用 notifyListeners 导致报错
    Future.microtask(() => notifyListeners());
  }

  Future<void> loadConversations() async {
    _isLoading = true;
    notifyListeners();

    try {
      debugPrint('📍[ChatProvider] 开始加载会话列表...');
      final sdkConversations = await _sdkManager.client.getConversationList();
      debugPrint('📍[ChatProvider] 获取到 ${sdkConversations.length} 个会话');

      // 性能优化：收集所有私聊会话的targetId，一次性批量查询
      final privateTargetIds = sdkConversations
          .where((c) => !c.isGroup)
          .map((c) => c.targetId)
          .toSet()
          .toList();

      // 批量预加载所有联系人信息到缓存
      if (privateTargetIds.isNotEmpty) {
        await _batchPreloadContacts(privateTargetIds);
      }

      final List<ConversationModel> conversationModels = [];

      for (final conv in sdkConversations) {
        final displayId = (conv.id != null && conv.id! > 0)
            ? '${conv.targetId}'
            : conv.conversationId;

        String displayName;
        String? displayAvatar;
        DateTime? lastActiveTime;

        if (conv.isGroup) {
          try {
            final group = await _sdkManager.client.getGroup(conv.targetId);
            displayName = group.name.isNotEmpty ? group.name : '群组 ${conv.targetId}';
            
            // 如果最后一条消息有groupInfo，优先使用
            if (conv.lastMessage?.groupInfo != null) {
              displayName = conv.lastMessage!.groupInfo!.groupName;
            }
          } catch (e) {
            debugPrint('⚠️[ChatProvider] 获取群组名称失败: $e');
            
            // 尝试从最后一条消息的groupInfo获取
            if (conv.lastMessage?.groupInfo != null) {
              displayName = conv.lastMessage!.groupInfo!.groupName;
            } else {
              displayName = '群组 ${conv.targetId}';
            }
          }
        } else {
          // 优先从最后一条消息的senderInfo获取（新方案）
          if (conv.lastMessage?.senderInfo != null) {
            final lastMsgSenderInfo = conv.lastMessage!.senderInfo!;
            displayName = lastMsgSenderInfo.nickname.isNotEmpty 
                ? lastMsgSenderInfo.nickname 
                : '用户${conv.targetId}';
            displayAvatar = lastMsgSenderInfo.avatar.isNotEmpty 
                ? lastMsgSenderInfo.avatar 
                : null;
          } else {
            // fallback到本地缓存（原有方案）
            final contactInfo = _contactInfoCache[conv.targetId];
            displayName = DisplayNameHelper.getDisplayNameOrDefault(contactInfo, conv.targetId);
            displayAvatar = DisplayNameHelper.getDisplayAvatar(contactInfo);
          }
        }

        if (conv.lastMessage != null) {
          lastActiveTime = DateTime.fromMillisecondsSinceEpoch(conv.lastMessage!.timestamp);
        } else if (conv.updateTime != null) {
          lastActiveTime = DateTime.fromMillisecondsSinceEpoch(conv.updateTime);
        }

        conversationModels.add(ConversationModel(
          id: displayId,
          dbId: conv.id,
          targetId: conv.targetId,
          name: displayName,
          avatar: displayAvatar,
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

  /// 批量预加载联系人信息到缓存（性能优化）
  Future<void> _batchPreloadContacts(List<int> targetIds) async {
    if (targetIds.isEmpty) return;

    // 过滤出缓存中不存在的ID
    final uncachedIds = targetIds.where((id) => !_contactInfoCache.containsKey(id)).toList();
    if (uncachedIds.isEmpty) {
      debugPrint('📍[ChatProvider] 💾 批量预加载: 全部命中缓存 (${targetIds.length}/${targetIds.length})');
      return;
    }

    final hitCount = targetIds.length - uncachedIds.length;
    debugPrint('📍[ChatProvider] 📥 批量预加载联系人: 总数=${targetIds.length}, 缓存命中=$hitCount, 需查询=${uncachedIds.length}');

    try {
      final contactService = ContactDatabaseService();
      await contactService.init(userId: _sdkManager.client.currentUserId ?? 0);
      final contactsMap = await contactService.getContactsByIds(uncachedIds);

      // 将查询结果加入缓存
      for (final entry in contactsMap.entries) {
        _contactInfoCache[entry.key] = entry.value;
      }

      debugPrint('📍[ChatProvider] ✅ 批量预加载完成: 成功加载 ${contactsMap.length} 个联系人到缓存');
    } catch (e) {
      debugPrint('⚠️[ChatProvider] 批量预加载联系人失败: $e');
    }
  }

  Future<void> _loadConversationsAndClearUnread() async {
    try {
      final sdkConversations = await _sdkManager.client.getConversationList();

      // 性能优化：批量预加载联系人信息
      final privateTargetIds = sdkConversations
          .where((c) => !c.isGroup)
          .map((c) => c.targetId)
          .toSet()
          .toList();

      if (privateTargetIds.isNotEmpty) {
        await _batchPreloadContacts(privateTargetIds);
      }

      final List<ConversationModel> conversationModels = [];

      for (final conv in sdkConversations) {
        final displayId = (conv.id != null && conv.id! > 0)
            ? '${conv.targetId}'
            : conv.conversationId;

        String displayName;
        String? displayAvatar;
        DateTime? lastActiveTime;

        if (conv.isGroup) {
          try {
            final group = await _sdkManager.client.getGroup(conv.targetId);
            displayName = group.name.isNotEmpty ? group.name : '群组 ${conv.targetId}';
            
            // 如果最后一条消息有groupInfo，优先使用
            if (conv.lastMessage?.groupInfo != null) {
              displayName = conv.lastMessage!.groupInfo!.groupName;
            }
          } catch (e) {
            // 尝试从最后一条消息的groupInfo获取
            if (conv.lastMessage?.groupInfo != null) {
              displayName = conv.lastMessage!.groupInfo!.groupName;
            } else {
              displayName = '群组 ${conv.targetId}';
            }
          }
        } else {
          // 优先从最后一条消息的senderInfo获取（新方案）
          if (conv.lastMessage?.senderInfo != null) {
            final lastMsgSenderInfo = conv.lastMessage!.senderInfo!;
            displayName = lastMsgSenderInfo.nickname.isNotEmpty 
                ? lastMsgSenderInfo.nickname 
                : '用户${conv.targetId}';
            displayAvatar = lastMsgSenderInfo.avatar.isNotEmpty 
                ? lastMsgSenderInfo.avatar 
                : null;
          } else {
            // fallback到本地缓存（原有方案）
            final contactInfo = _contactInfoCache[conv.targetId];
            displayName = DisplayNameHelper.getDisplayNameOrDefault(contactInfo, conv.targetId);
            displayAvatar = DisplayNameHelper.getDisplayAvatar(contactInfo);
          }
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
          dbId: conv.id,
          targetId: conv.targetId,
          name: displayName,
          avatar: displayAvatar,
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
    // ✅ 立即清空旧消息，避免切换会话时短暂显示上一个会话的消息
    _messages = [];
    _isLoading = true;
    notifyListeners();

    try {
      final targetId = int.tryParse(conversationId) ?? 0;
      final isGroup = _currentConversation?.isGroup ?? false;

      debugPrint('📍[ChatProvider] 📥 开始加载历史消息, conversationId=$conversationId, targetId=$targetId, isGroup=$isGroup');
      
      // ✅ 自动分页加载：循环查询直到获取所有消息
      List<sdk.Message> allMessages = [];
      int currentPage = 1;
      const pageSize = 100; // SDK最大允许值
      bool hasMore = true;
      
      while (hasMore) {
        // targetId 是当前会话的目标ID（私聊=对方userId / 群聊=群组ID）
        // SDK 按会话类型提供不同的查询方法
        final pageMessages = isGroup
            ? await _sdkManager.client.getGroupHistoryMessages(
                groupId: targetId,
                page: currentPage,
                size: pageSize,
              )
            : await _sdkManager.client.getHistoryMessages(
                targetId: targetId,
                page: currentPage,
                size: pageSize,
              );
        
        if (pageMessages.isEmpty) {
          hasMore = false;
        } else {
          allMessages.addAll(pageMessages);
          debugPrint('📍[ChatProvider] 📄 第${currentPage}页加载了 ${pageMessages.length} 条, 累计 ${allMessages.length} 条');
          
          if (pageMessages.length < pageSize) {
            hasMore = false; // 这一页没满，说明没有更多数据了
          } else {
            currentPage++;
          }
        }
      }
      
      final sdkMessages = allMessages;
      
      debugPrint('📍[ChatProvider] ✅ 历史消息全部加载完成，共 ${sdkMessages.length} 条');
      
      debugPrint('📍[ChatProvider] 📥 加载消息完成，共 ${sdkMessages.length} 条');
      debugPrint('📍[ChatProvider] 🔍 SDK返回的原始顺序（前10条）：');
      for (var i = 0; i < (sdkMessages.length < 10 ? sdkMessages.length : 10); i++) {
        final msg = sdkMessages[i];
        debugPrint('  [$i] id=${msg.id}, from=${msg.fromId}, to=${msg.toId}, timestamp=${msg.timestamp}, content="${msg.content.toString().substring(0, msg.content.toString().length > 20 ? 20 : msg.content.toString().length)}"');
      }
      
      _messages = sdkMessages
          .map((msg) => _convertSdkMessageToModel(msg))
          .toList();

      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      debugPrint('📍[ChatProvider] ✅ 排序后的顺序（前10条）：');
      for (var i = 0; i < (_messages.length < 10 ? _messages.length : 10); i++) {
        final msg = _messages[i];
        debugPrint('  [$i] id=${msg.id}, from=${msg.senderId}, timestamp=${msg.timestamp.millisecondsSinceEpoch}, content="${msg.content.substring(0, msg.content.length > 20 ? 20 : msg.content.length)}"');
      }
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
    debugPrint('📤[ChatProvider] sendMessage 被调用: content=$content, type=$type');
    debugPrint('📤[ChatProvider] 当前 _currentConversation: ${_currentConversation?.id ?? "null"}');

    if (_currentConversation == null) {
      debugPrint('❌[ChatProvider] sendMessage 失败: _currentConversation 为空');
      debugPrint('❌[ChatProvider] 调用栈: ${StackTrace.current}');
      return;
    }

    final currentUserId = _sdkManager.client.currentUserId;
    final currentUserInfo = await _getCurrentUserInfo();

    final tempMessage = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: _currentConversation!.id,
      senderId: currentUserId?.toString() ?? '',
      receiverId: '',
      type: type == 'image' ? MessageType.image : MessageType.text,
      content: content,
      timestamp: DateTime.now(),
      isSending: true,
      isSent: true,
      status: MessageStatus.sending,
      senderInfo: currentUserInfo,
    );

    debugPrint('📤[ChatProvider] 发送消息(本地) senderInfo=${tempMessage.senderInfo?.toJson()}');

    _messages.add(tempMessage);
    notifyListeners();

    try {
      final targetId = _currentConversation!.targetId;
      final isGroup = _currentConversation!.isGroup;

      debugPrint('📍[ChatProvider] 发送消息: conversationId=${_currentConversation!.id}, targetId=$targetId, isGroup=$isGroup, currentUserId=$currentUserId');
      
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

  Future<SenderInfoModel?> _getCurrentUserInfo() async {
    try {
      final currentUserId = _sdkManager.client.currentUserId;
      if (currentUserId == null) return null;

      // 先从本地缓存获取
      final contactInfo = _contactInfoCache[currentUserId];
      if (contactInfo != null) {
        return SenderInfoModel(
          userId: contactInfo.id,
          nickname: contactInfo.nickname,
          avatar: contactInfo.avatar,
        );
      }

      // 缓存未命中，从数据库查询
      final contactService = ContactDatabaseService();
      await contactService.init(userId: currentUserId);
      final contactsMap = await contactService.getContactsByIds([currentUserId]);
      final info = contactsMap[currentUserId];

      if (info != null) {
        _contactInfoCache[currentUserId] = info;
        return SenderInfoModel(
          userId: info.id,
          nickname: info.nickname,
          avatar: info.avatar,
        );
      }

      // 都没有，返回基本信息
      return SenderInfoModel(
        userId: currentUserId,
        nickname: '我',
        avatar: '',
      );
    } catch (e) {
      debugPrint('⚠️[ChatProvider] 获取当前用户信息失败: $e');
      return null;
    }
  }

  Future<void> retrySendMessage(MessageModel message) async {
    if (_currentConversation == null) return;

    final retryIndex = _messages.indexWhere((m) => m.id == message.id);
    if (retryIndex != -1) {
      _messages[retryIndex] = _messages[retryIndex].copyWith(
        isSending: true,
        isSent: true,
        status: MessageStatus.sending,
      );
      notifyListeners();
    }

    try {
      final targetId = _currentConversation!.targetId;
      final isGroup = _currentConversation!.isGroup;

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
    int? dbId,
  }) async {
    try {
      // 如果外部没传 dbId，从已加载的会话列表中查找
      final resolvedDbId = dbId ?? _findDbIdByTargetId(targetId);
      debugPrint('📍[ChatProvider] 标记会话已读: targetId=$targetId, 传入dbId=$dbId, 解析dbId=$resolvedDbId, isGroup=$isGroup');

      // 使用数据库主键作为 conversationId（这才是 SDK 需要的）
      final conversationId = (resolvedDbId != null && resolvedDbId > 0) ? resolvedDbId : targetId;
      await _sdkManager.client.markConversationAsRead(conversationId);

      final convIndex = _conversations.indexWhere(
        (c) => c.id.contains(targetId.toString()),
      );

      if (convIndex != -1 && _conversations[convIndex].unreadCount > 0) {
        final updatedConv = _conversations[convIndex].copyWith(
          unreadCount: 0,
        );
        _conversations[convIndex] = updatedConv;
        debugPrint('✅[ChatProvider] 会话已读标记成功, 未读数已清零 (conversationId=$conversationId)');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌[ChatProvider] 标记会话已读失败: $e');
    }
  }

  /// 根据 targetId 从已加载的会话列表中查找数据库主键 dbId
  int? _findDbIdByTargetId(int targetId) {
    final match = _conversations.where(
      (c) => c.targetId == targetId || c.id.contains(targetId.toString()),
    ).firstOrNull;
    if (match?.dbId != null && match!.dbId! > 0) {
      debugPrint('📍[ChatProvider] 从会话列表中查找到 dbId: ${match.dbId} (targetId=$targetId)');
      return match.dbId;
    }
    debugPrint('⚠️[ChatProvider] 会话列表中未找到 targetId=$targetId 对应的 dbId');
    return null;
  }

  Future<void> deleteConversation(String conversationId) async {
    try {
      final conversation = _conversations.where((c) => c.id == conversationId).firstOrNull;

      if (conversation?.dbId != null && conversation!.dbId! > 0) {
        debugPrint('🗑️[ChatProvider] 开始删除会话: $conversationId (dbId=${conversation.dbId})');
        await _sdkManager.client.deleteConversation(conversation.dbId!);
        debugPrint('✅[ChatProvider] 会话删除成功: $conversationId (dbId=${conversation.dbId})');
      } else {
        debugPrint('⚠️[ChatProvider] 会话 dbId 为空，只从内存移除: $conversationId');
      }

      _conversations.removeWhere((c) => c.id == conversationId);
      notifyListeners();
      debugPrint('✅[ChatProvider] 会话已从列表移除: $conversationId');
    } catch (e, stackTrace) {
      debugPrint('❌[ChatProvider] 删除会话失败: $e');
      debugPrint('❌[ChatProvider] 堆栈: $stackTrace');
      rethrow;
    }
  }

  Future<void> clearAllChatData() async {
    debugPrint('🗑️[ChatProvider] 开始清空所有聊天数据（物理删除）...');

    try {
      for (final conv in _conversations) {
        final targetId = conv.targetId;
        if (targetId > 0) {
          try {
            await _sdkManager.client.deleteConversation(targetId);
            debugPrint('✅[ChatProvider] 已物理删除会话: ${conv.name} ($targetId)');
          } catch (e) {
            debugPrint('⚠️[ChatProvider] 删除会话失败 $targetId: $e');
          }
        }
      }

      _conversations.clear();
      _messages.clear();
      _currentConversation = null;

      debugPrint('✅[ChatProvider] 所有聊天数据已清空');
    } catch (e, stackTrace) {
      debugPrint('❌[ChatProvider] 清空聊天数据失败: $e');
      debugPrint('❌[ChatProvider] 堆栈: $stackTrace');
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  void clearCurrentConversation() {
    debugPrint('🗑️[ChatProvider] clearCurrentConversation 被调用，清空前: ${_currentConversation?.id ?? "null"}');
    _currentConversation = null;
    _messages = [];
    // ✅ 清除通知服务的当前聊天状态
    NotificationService().currentChatTargetId = null;
    notifyListeners();
  }

  /// ✅ 初始化消息通知服务
  Future<void> _initNotificationService() async {
    try {
      final notificationService = NotificationService();
      await notificationService.initialize();

      // 请求通知权限（Android 13+ 需要）
      await notificationService.requestPermission();
      debugPrint('✅[ChatProvider] 消息通知服务初始化完成');
    } catch (e) {
      debugPrint('⚠️[ChatProvider] 消息通知服务初始化失败: $e');
    }
  }

  /// ✅ 触发消息通知
  /// 当收到新消息且用户不在该会话的聊天界面时调用
  void _triggerMessageNotification(sdk.Message message) {
    try {
      final currentUserId = _sdkManager.client.currentUserId;

      // 忽略自己发送的消息（只对收到的消息显示通知）
      if (currentUserId != null && message.fromId == currentUserId) {
        return;
      }

      // 获取发送者信息
      String nickname = '用户${message.fromId}';
      String? avatarUrl;

      if (message.senderInfo != null) {
        nickname = message.senderInfo!.nickname.isNotEmpty
            ? message.senderInfo!.nickname
            : '用户${message.fromId}';
        avatarUrl = message.senderInfo!.avatar.isNotEmpty
            ? message.senderInfo!.avatar
            : null;
      } else {
        // 尝试从缓存获取联系人信息
        final contactInfo = _contactInfoCache[message.fromId];
        if (contactInfo != null) {
          nickname = contactInfo.nickname.isNotEmpty
              ? contactInfo.nickname
              : '用户${message.fromId}';
          avatarUrl = contactInfo.avatar.isNotEmpty
              ? contactInfo.avatar
              : null;
        }
      }

      // 确定目标ID和是否为群聊
      final targetId = message.groupId ?? message.toId;
      final isGroup = message.groupId != null && message.groupId! > 0;

      final notificationData = NotificationData(
        senderId: message.fromId,
        nickname: isGroup ? '$nickname(群)' : nickname,
        avatarUrl: avatarUrl,
        content: message.content,
        time: DateTime.fromMillisecondsSinceEpoch(message.timestamp),
        targetId: targetId,
        isGroup: isGroup,
      );

      // 通过通知服务统一分发通知
      NotificationService().showMessageNotification(notificationData);
    } catch (e) {
      debugPrint('⚠️[ChatProvider] 触发消息通知失败: $e');
    }
  }

  Future<ContactInfo?> _getContactInfo(int targetId) async {
    debugPrint('📍[ChatProvider] 查询联系人信息: targetId=$targetId');

    try {
      // 优先从本地缓存获取
      if (_contactInfoCache.containsKey(targetId)) {
        final cached = _contactInfoCache[targetId]!;
        debugPrint('📍[ChatProvider] 💾 联系人信息缓存命中: targetId=$targetId, nickname=${cached.nickname}');
        return cached;
      }

      // 缓存未命中，查询数据库
      final contactService = ContactDatabaseService();
      await contactService.init(userId: _sdkManager.client.currentUserId ?? 0);
      final contactMap = await contactService.getContactsByIds([targetId]);
      final contactInfo = contactMap[targetId];

      if (contactInfo != null) {
        // 查询成功后加入缓存
        _contactInfoCache[targetId] = contactInfo;
        debugPrint('📍[ChatProvider] 📥 联系人信息已缓存: targetId=$targetId, nickname=${contactInfo.nickname}');
      }

      return contactInfo;
    } catch (e) {
      debugPrint('⚠️[ChatProvider] 查询联系人信息失败: targetId=$targetId, error=$e');
      return null;
    }
  }

  /// 公共方法：根据ID获取联系人信息（供UI层调用）
  Future<ContactInfo?> getContactInfoById(int targetId) async {
    return _getContactInfo(targetId);
  }

  /// 清空联系人信息缓存（在联系人变更时调用）
  void _clearContactInfoCache() {
    final count = _contactInfoCache.length;
    _contactInfoCache.clear();
    debugPrint('📍[ChatProvider] 🗑️ 已清空联系人信息缓存，共移除 $count 条记录');
  }

  MessageModel _convertSdkMessageToModel(sdk.Message msg) {
    final currentUserId = _sdkManager.client.currentUserId;
    final isFromMe = currentUserId != null && msg.fromId == currentUserId;

    SenderInfoModel? senderInfo;
    if (msg.senderInfo != null) {
      senderInfo = SenderInfoModel(
        userId: msg.senderInfo!.userId,
        nickname: msg.senderInfo!.nickname,
        avatar: msg.senderInfo!.avatar,
        groupNickname: msg.senderInfo!.groupNickname,
      );
    }

    GroupInfoModel? groupInfo;
    if (msg.groupInfo != null) {
      groupInfo = GroupInfoModel(
        groupId: msg.groupInfo!.groupId,
        groupName: msg.groupInfo!.groupName,
        groupAvatar: msg.groupInfo!.groupAvatar,
      );
    }

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
      senderInfo: senderInfo,
      groupInfo: groupInfo,
    );
  }
}

class _ChatMessageListener implements sdk.MessageListener {
  final ChatProvider _provider;
  _ChatMessageListener(this._provider);

  /// 判断消息是否属于当前正在查看的会话
  bool _isMessageBelongsToCurrentConversation(sdk.Message message) {
    final currentConv = _provider._currentConversation;
    if (currentConv == null) return false;

    final targetId = currentConv.targetId;

    // 群聊消息：检查 groupId 是否匹配当前会话 targetId
    if (message.groupId != null && message.groupId! > 0) {
      return message.groupId == targetId;
    }

    // 私聊消息：检查 fromId 或 toId 是否匹配当前会话 targetId
    // （fromId 是发送者，toId 是接收者，targetId 是聊天对象的ID）
    return message.fromId == targetId || message.toId == targetId;
  }

  @override
  void onMessageReceived(sdk.Message message) {
    final currentUserId = _provider._sdkManager.client.currentUserId;

    SenderInfoModel? senderInfo;
    if (message.senderInfo != null) {
      senderInfo = SenderInfoModel(
        userId: message.senderInfo!.userId,
        nickname: message.senderInfo!.nickname,
        avatar: message.senderInfo!.avatar,
        groupNickname: message.senderInfo!.groupNickname,
      );
    } else {
      // 如果消息中没有senderInfo，尝试从缓存获取
      final fromId = message.fromId;
      final contactInfo = _provider._contactInfoCache[fromId];
      if (contactInfo != null) {
        senderInfo = SenderInfoModel(
          userId: contactInfo.id,
          nickname: contactInfo.nickname,
          avatar: contactInfo.avatar,
        );
      }
    }

    GroupInfoModel? groupInfo;
    if (message.groupInfo != null) {
      groupInfo = GroupInfoModel(
        groupId: message.groupInfo!.groupId,
        groupName: message.groupInfo!.groupName,
        groupAvatar: message.groupInfo!.groupAvatar,
      );
    }

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
      senderInfo: senderInfo,
      groupInfo: groupInfo,
    );

    debugPrint('📥[ChatProvider] 收到消息 fromId=${message.fromId} senderInfo=${senderInfo?.toJson()} groupInfo=${groupInfo?.toJson()}');

    // ✅ 只有当消息属于当前正在查看的会话时，才添加到消息列表
    // 否则由 EventBus 的 MessageReceivedEvent 处理器统一管理（刷新会话列表 + 触发通知）
    if (_isMessageBelongsToCurrentConversation(message)) {
      _provider.receiveMessage(model);
    } else {
      debugPrint('📥[ChatProvider] 消息不属于当前会话，不加载到当前聊天页面（由EventBus处理）');
    }
  }

  @override
  void onMessageSent(sdk.Message message) {}

  @override
  void onMessageRecalled(sdk.Message message) {}
}
