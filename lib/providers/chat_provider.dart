import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart' as sdk;
import 'package:cao_im_sdk_flutter/event/event_bus.dart';
import 'package:cao_im_sdk_flutter/event/im_event.dart';
import '../models/chat_file_item.dart';
import '../models/chat_model.dart';
import '../models/chat_search_hit.dart';
import '../models/message_model.dart';
import '../models/voice_content.dart';
import '../models/file_content.dart';
import '../models/video_content.dart';
import '../services/video_inspect.dart';
import '../models/contact_info_model.dart';
import '../models/sender_info_model.dart';
import '../providers/contact_provider.dart';
import '../providers/layout_provider.dart';
import '../router/app_router.dart';
import '../services/apis/file_api.dart';
import '../services/media_store.dart';
import '../services/keep_alive_service.dart';
import '../widgets/adaptive_layout.dart';
import '../services/apis/message_api.dart';
import '../services/contact_database_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../utils/display_name_helper.dart';
import '../sdk/im_sdk_manager.dart';

class ChatProvider with ChangeNotifier {
  static const int maxTextBytes = 60 * 1024;

  final IMSdkManager _sdkManager = IMSdkManager();
  final EventBus _eventBus = EventBus();

  ConversationModel? _currentConversation;
  List<MessageModel> _messages = [];
  String? _focusMessageKey;
  bool _focusReady = false;
  final List<_RemoteMedia> _cacheQueue = [];
  final Set<String> _cacheKeys = {};
  int _cacheRunning = 0;
  MessageModel? _replyingTo;
  final List<int> _pendingMentions = [];
  final Map<int, String> _mentionLabels = {};
  final Map<int, String> _mentionJumpKeys = {};
  bool _mentionsReady = false;
  int _mentionScanToken = 0;
  List<ConversationModel> _conversations = [];
  bool _isLoading = false;
  bool _isListening = false;
  bool _isEventListening = false;

  // 联系人信息本地缓存（避免重复查询数据库）
  final Map<int, ContactInfo> _contactInfoCache = {};

  ConversationModel? get currentConversation => _currentConversation;
  String? get focusMessageKey => _focusReady ? _focusMessageKey : null;
  List<MessageModel> get messages => _messages;
  List<ConversationModel> get conversations => _conversations;
  MessageModel? get replyingTo => _replyingTo;
  bool get isLoading => _isLoading;

  void setReplyingTo(MessageModel? message) {
    if (message != null && message.status == MessageStatus.recalled) return;
    _replyingTo = message;
    notifyListeners();
  }

  void clearReply() {
    if (_replyingTo == null) return;
    _replyingTo = null;
    notifyListeners();
  }

  void addMention(int userId, String name) {
    if (userId <= 0 || name.isEmpty) return;
    _mentionLabels[userId] = name;
    if (!_pendingMentions.contains(userId)) {
      _pendingMentions.add(userId);
    }
  }

  String? _consumeAtUserIds(String content) {
    final kept = _pendingMentions.where((id) {
      final name = _mentionLabels[id];
      return name != null && content.contains('@$name');
    }).toList();
    _pendingMentions.clear();
    if (kept.isEmpty) return null;
    return kept.join(',');
  }

  Future<void> _ensureMentionsLoaded() async {
    if (_mentionsReady) return;
    _mentionJumpKeys.addAll(await StorageService.loadGroupMentions());
    _mentionsReady = true;
  }

  /// 内存里已有的 @ 跳转位置。打开聊天前先拿走，避免随后清未读时丢掉。
  String? mentionKeyNow(int groupId) {
    final key = _mentionJumpKeys[groupId];
    if (key == null || key.isEmpty) return null;
    return key;
  }

  /// 打开群聊前读取未读 @ 的跳转位置。
  Future<String?> peekMention(int groupId) async {
    await _ensureMentionsLoaded();
    return mentionKeyNow(groupId);
  }

  void dismissMention(int groupId) => _clearMention(groupId);

  void _rememberMention(int groupId, String key) {
    if (groupId <= 0 || key.isEmpty || _mentionJumpKeys.containsKey(groupId)) return;
    if (_isViewingTarget(groupId, true)) return;
    _mentionJumpKeys[groupId] = key;
    StorageService.saveGroupMentions(_mentionJumpKeys);
  }

  void _clearMention(int groupId) {
    if (_mentionJumpKeys.remove(groupId) == null) return;
    StorageService.saveGroupMentions(_mentionJumpKeys);
  }

  bool _mentionsMe(String? atUserIds) {
    final me = _sdkManager.client.currentUserId;
    if (me == null || me <= 0 || atUserIds == null || atUserIds.isEmpty) return false;
    return atUserIds.split(',').any((item) => int.tryParse(item.trim()) == me);
  }

  String? _messageJumpKey(sdk.Message message) {
    final raw = message.midKey?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    final mid = message.mid;
    if (mid == null || mid <= 0) return null;
    return mid.toString();
  }

  void _noteIncomingMention(sdk.Message message) {
    final groupId = message.groupId;
    if (groupId == null || groupId <= 0) return;
    final me = _sdkManager.client.currentUserId;
    if (me == null || message.fromId == me) return;
    if (!_mentionsMe(message.atUserIds)) return;
    if (_isViewingTarget(groupId, true)) return;
    final key = _messageJumpKey(message);
    if (key == null) return;
    _rememberMention(groupId, key);
  }

  String? _mentionKeyFor(sdk.Conversation conv, int unreadCount) {
    if (!conv.isGroup) return null;
    if (unreadCount <= 0 || _isViewingTarget(conv.targetId, true)) {
      return null;
    }
    final remembered = _mentionJumpKeys[conv.targetId];
    if (remembered != null && remembered.isNotEmpty) return remembered;
    final last = conv.lastMessage;
    final me = _sdkManager.client.currentUserId;
    if (last != null && me != null && last.fromId != me && _mentionsMe(last.atUserIds)) {
      final key = _messageJumpKey(last);
      if (key != null) {
        _rememberMention(conv.targetId, key);
        return key;
      }
    }
    return null;
  }

  void _scheduleMentionScan() {
    final token = ++_mentionScanToken;
    _scanUnreadMentions(token);
  }

  Future<void> _scanUnreadMentions(int token) async {
    final me = _sdkManager.client.currentUserId;
    if (me == null || me <= 0) return;
    final pending = _conversations.where((item) =>
        item.isGroup &&
        item.unreadCount > 0 &&
        (item.mentionMessageKey == null || item.mentionMessageKey!.isEmpty));
    var changed = false;
    for (final conversation in pending) {
      if (token != _mentionScanToken) return;
      if (_mentionJumpKeys.containsKey(conversation.targetId)) continue;
      try {
        final hit = await _sdkManager.client.findRecentGroupMention(
          groupId: conversation.targetId,
          userId: me,
          recentLimit: conversation.unreadCount.clamp(1, 200),
        );
        final key = hit == null ? null : _messageJumpKey(hit);
        if (key == null) continue;
        _rememberMention(conversation.targetId, key);
        changed = true;
      } catch (e) {
        debugPrint('查找未读@失败: $e');
      }
    }
    if (!changed || token != _mentionScanToken) return;
    for (var index = 0; index < _conversations.length; index++) {
      final conversation = _conversations[index];
      if (!conversation.isGroup || conversation.unreadCount <= 0) continue;
      final key = _mentionJumpKeys[conversation.targetId];
      if (key == null || key == conversation.mentionMessageKey) continue;
      _conversations[index] = conversation.copyWith(mentionMessageKey: key);
    }
    notifyListeners();
  }

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
    NotificationService().onOpen = null;
    KeepAliveService.stop();

    // ✅ 停止监听事件总线
    stopEventListening();
  }

  /// ✅ 开始监听 EventBus 事件（自动刷新会话列表）
  void startEventListening() {
    if (_isEventListening) return;
    _isEventListening = true;

    // 监听消息发送成功/状态更新 → 同步气泡状态并刷新会话列表
    _eventBus.on<MessageSentEvent>().listen((event) {
      debugPrint('📍[ChatProvider] 📢 收到 MessageSentEvent, status=${event.message.status.name}');
      _syncLocalMessageStatus(event.message);
      loadConversations();
    });

    // 服务端拒绝发送（消息过长等）→ 标记失败并提示用户
    _eventBus.on<MessageSendFailedEvent>().listen((event) {
      debugPrint('❌[ChatProvider] 📢 收到 MessageSendFailedEvent: ${event.reason}, mid=${event.mid}');
      _markLocalMessageFailed(event.mid);
      _showSendErrorTip(event.reason);
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
        _noteIncomingMention(event.message);
        loadConversations();
        if (event.message.msgType != sdk.MessageType.system) {
          _triggerMessageNotification(event.message);
        }
      } else {
        // 在当前会话时：消息已由 receiveMessage() 增量添加到列表，
        // 只需刷新会话列表以更新 lastMessage/unreadCount
        _loadConversationsAndClearUnread();
      }
    });

    // 监听会话更新 → 刷新会话列表。正在看的会话刚被加上未读时，立刻再标成已读。
    _eventBus.on<ConversationUpdatedEvent>().listen((event) {
      debugPrint('📍[ChatProvider] 📢 收到 ConversationUpdatedEvent, 自动刷新会话列表');
      final conv = event.conversation;
      if (_isViewingTarget(conv.targetId, conv.isGroup) &&
          conv.unreadCount > 0 &&
          (conv.id ?? 0) > 0) {
        _sdkManager.client.markConversationAsRead(conv.id!);
      }
      loadConversations();
    });

    // 监听消息撤回 → 刷新相关数据
    _eventBus.on<sdk.MessagesReadEvent>().listen((event) {
      if (event.readCounts.isEmpty) return;
      var changed = false;
      for (var index = 0; index < _messages.length; index++) {
        final mid = _messages[index].mid;
        final count = mid == null ? null : event.readCounts[mid];
        if (count == null || _messages[index].readCount == count) continue;
        _messages[index] = _messages[index].copyWith(readCount: count);
        changed = true;
      }
      if (changed) notifyListeners();
    });

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

  /// 当前打开的就是这个会话。用 targetId 判断，避免列表刷新后未读数又冒出来。
  bool _isViewingTarget(int targetId, bool isGroup) {
    final current = _currentConversation;
    if (current == null || targetId <= 0 || current.isGroup != isGroup) return false;
    if (current.targetId > 0) return current.targetId == targetId;
    return current.id == '$targetId';
  }

  void setCurrentConversation(ConversationModel conversation) {
    debugPrint('🔧[ChatProvider] setCurrentConversation 被调用: id=${conversation.id}, name=${conversation.name}');
    debugPrint('🔧[ChatProvider] 设置前 _currentConversation: ${_currentConversation?.id ?? "null"}');
    if (_currentConversation?.id != conversation.id) {
      _replyingTo = null;
    }
    _currentConversation = conversation;
    debugPrint('🔧[ChatProvider] 设置后 _currentConversation: ${_currentConversation?.id ?? "null"}');

    // ✅ 同步当前聊天会话到通知服务（用于判断是否需要显示通知）
    NotificationService().currentChatTargetId = conversation.targetId;
    NotificationService().cancelForTarget(conversation.targetId);

    // 延迟通知，避免在 initState 等 build 期间调用 notifyListeners 导致报错
    Future.microtask(() => notifyListeners());
  }

  /// 打开会话后滚到这条消息。加载完成前不会当成“找不到”。
  void focusMessage(String key) {
    final value = key.trim();
    if (value.isEmpty) return;
    _focusMessageKey = value;
    _focusReady = false;
    notifyListeners();
  }

  void markFocusReady() {
    if (_focusMessageKey == null || _focusReady) return;
    _focusReady = true;
    notifyListeners();
  }

  void clearFocusMessage() {
    _focusMessageKey = null;
    _focusReady = false;
  }

  Future<void> rememberMediaPath(String midKey, String path) async {
    final key = midKey.trim();
    final value = path.trim();
    if (key.isEmpty || value.isEmpty) return;
    final index = _messages.indexWhere((item) => item.midKey == key || item.id == key);
    if (index != -1 && _messages[index].localPath != value) {
      _messages[index] = _messages[index].copyWith(localPath: value);
      notifyListeners();
    }
    await _remember(key, value);
  }

  Future<void> loadConversations() async {
    await _ensureMentionsLoaded();
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
          displayName = _groupDisplayName(conv);
        } else {
          final resolved = _resolvePrivatePeerDisplay(conv);
          displayName = resolved.$1;
          displayAvatar = resolved.$2;
        }

        if (conv.lastMessage != null) {
          lastActiveTime = DateTime.fromMillisecondsSinceEpoch(conv.lastMessage!.timestamp);
        } else if (conv.updateTime != null) {
          lastActiveTime = DateTime.fromMillisecondsSinceEpoch(conv.updateTime);
        }

        final unreadCount = _isViewingTarget(conv.targetId, conv.isGroup) ? 0 : conv.unreadCount;

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
          isTop: conv.isTop,
          isMute: conv.isMute,
          mentionMessageKey: _mentionKeyFor(conv, unreadCount),
        ));
      }

      conversationModels.sort((a, b) {
        if (a.isTop != b.isTop) return a.isTop ? -1 : 1;
        final at = a.lastActiveTime?.millisecondsSinceEpoch ?? 0;
        final bt = b.lastActiveTime?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });

      _conversations = conversationModels;
      _scheduleMentionScan();

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

  /// 私聊会话显示名：本地联系人优先；否则用对方发来的消息里的 senderInfo/nickname
  (String, String?) _resolvePrivatePeerDisplay(sdk.Conversation conv) {
    final contactInfo = _contactInfoCache[conv.targetId];
    final fromContact = DisplayNameHelper.getDisplayName(contactInfo);
    if (fromContact != null && fromContact.isNotEmpty) {
      return (fromContact, DisplayNameHelper.getDisplayAvatar(contactInfo));
    }

    final last = conv.lastMessage;
    if (last != null && last.fromId == conv.targetId) {
      final nick = last.senderInfo?.nickname.isNotEmpty == true
          ? last.senderInfo!.nickname
          : (last.senderNickname ?? '');
      final avatar = last.senderInfo?.avatar.isNotEmpty == true
          ? last.senderInfo!.avatar
          : last.senderAvatar;
      if (nick.isNotEmpty) {
        _seedContactCache(
          userId: conv.targetId,
          nickname: nick,
          avatar: avatar ?? '',
        );
        return (nick, (avatar != null && avatar.isNotEmpty) ? avatar : null);
      }
    }

    return ('用户${conv.targetId}', null);
  }

  /// 群名以本地缓存为准。改名和群提示消息都会刷新这份缓存，避免会话列表停在旧名称。
  String _groupDisplayName(sdk.Conversation conv) {
    final cached = _sdkManager.client.groupService.getFromCache(conv.targetId);
    if (cached != null && cached.name.isNotEmpty) {
      return cached.name;
    }
    final snapshot = conv.lastMessage?.groupInfo;
    if (snapshot != null && snapshot.groupName.isNotEmpty) {
      _sdkManager.client.groupService.cacheGroupFromInfo(snapshot);
      return snapshot.groupName;
    }
    _refreshGroupInfoInBackground(conv.targetId);
    return '群组 ${conv.targetId}';
  }

  void renameGroup(int groupId, String name) {
    final trimmed = name.trim();
    if (groupId <= 0 || trimmed.isEmpty) return;
    final cached = _sdkManager.client.groupService.getFromCache(groupId);
    var changed = cached == null || cached.name != trimmed;
    if (changed) {
      _sdkManager.client.groupService.cacheGroupFromInfo(sdk.GroupInfo(
        groupId: groupId,
        groupName: trimmed,
        groupAvatar: cached?.avatar,
      ));
    }
    final next = <ConversationModel>[];
    for (final conversation in _conversations) {
      if (conversation.isGroup && conversation.targetId == groupId && conversation.name != trimmed) {
        next.add(conversation.copyWith(name: trimmed));
        changed = true;
      } else {
        next.add(conversation);
      }
    }
    _conversations = next;
    if (_currentConversation != null &&
        _currentConversation!.isGroup &&
        _currentConversation!.targetId == groupId &&
        _currentConversation!.name != trimmed) {
      _currentConversation = _currentConversation!.copyWith(name: trimmed);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// 自己的资料变更后覆盖缓存，后续发出的消息带上新昵称和头像。
  void applySelfProfile({
    required int userId,
    required String nickname,
    String avatar = '',
  }) {
    if (userId <= 0 || nickname.isEmpty) return;
    final existing = _contactInfoCache[userId];
    _contactInfoCache[userId] = ContactInfo(
      id: existing?.id ?? userId,
      userId: userId,
      username: existing?.username ?? '',
      nickname: nickname,
      avatar: avatar.isNotEmpty ? avatar : (existing?.avatar ?? ''),
      remark: existing?.remark ?? '',
    );
  }

  void _seedContactCache({
    required int userId,
    required String nickname,
    String avatar = '',
    String username = '',
  }) {
    if (userId <= 0 || nickname.isEmpty) return;
    final existing = _contactInfoCache[userId];
    if (existing != null && existing.nickname.isNotEmpty) return;
    _contactInfoCache[userId] = ContactInfo(
      id: existing?.id ?? 0,
      userId: userId,
      username: username.isNotEmpty ? username : (existing?.username ?? ''),
      nickname: nickname,
      avatar: avatar.isNotEmpty ? avatar : (existing?.avatar ?? ''),
      remark: existing?.remark ?? '',
    );
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
      await _ensureMentionsLoaded();
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
          displayName = _groupDisplayName(conv);
        } else {
          final resolved = _resolvePrivatePeerDisplay(conv);
          displayName = resolved.$1;
          displayAvatar = resolved.$2;
        }

        if (conv.lastMessage != null) {
          lastActiveTime = DateTime.fromMillisecondsSinceEpoch(conv.lastMessage!.timestamp);
        } else if (conv.updateTime != null) {
          lastActiveTime = DateTime.fromMillisecondsSinceEpoch(conv.updateTime);
        }

        final unreadCount = _isViewingTarget(conv.targetId, conv.isGroup) ? 0 : conv.unreadCount;

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
          isTop: conv.isTop,
          isMute: conv.isMute,
          mentionMessageKey: _mentionKeyFor(conv, unreadCount),
        ));
      }

      conversationModels.sort((a, b) {
        if (a.isTop != b.isTop) return a.isTop ? -1 : 1;
        final at = a.lastActiveTime?.millisecondsSinceEpoch ?? 0;
        final bt = b.lastActiveTime?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });

      _conversations = conversationModels;
      _scheduleMentionScan();
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
      
      _messages = [];
      for (final msg in sdkMessages.map(_convertSdkMessageToModel)) {
        if (_messages.any((item) => _sameMessage(item, msg))) continue;
        _messages.add(msg);
      }

      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (targetId > 0) {
        if (isGroup) {
          await _fillGroupReadCounts(targetId);
        } else {
          await _fillPrivateReadCounts(targetId);
        }
      }
      
      debugPrint('📍[ChatProvider] ✅ 排序后的顺序（前10条）：');
      for (var i = 0; i < (_messages.length < 10 ? _messages.length : 10); i++) {
        final msg = _messages[i];
        debugPrint('  [$i] id=${msg.id}, from=${msg.senderId}, timestamp=${msg.timestamp.millisecondsSinceEpoch}, content="${msg.content.substring(0, msg.content.length > 20 ? 20 : msg.content.length)}"');
      }
      _enqueueMedia(_messages);
    } catch (e) {
      debugPrint('加载消息失败: $e');
    } finally {
      _isLoading = false;
      if (_focusMessageKey != null) {
        _focusReady = true;
      }
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
          .where((msg) => !_messages.any((item) => _sameMessage(item, msg)))
          .toList();
      _messages.insertAll(0, newMessages);
      notifyListeners();
      return newMessages;
    } catch (e) {
      debugPrint('加载更多消息失败: $e');
      return null;
    }
  }

  Future<List<ChatSearchHit>> searchMessages(String keyword) async {
    final text = keyword.trim();
    if (text.isEmpty) return [];
    final local = await _sdkManager.client.searchLocalMessages(text);
    List<sdk.Message> remote = const [];
    try {
      remote = await _sdkManager.client.searchServerMessages(text);
    } catch (e) {
      debugPrint('服务端消息搜索失败: $e');
    }
    final merged = <String, sdk.Message>{};
    for (final message in [...local, ...remote]) {
      final mid = message.mid;
      final key = mid != null && mid > 0
          ? 'm$mid'
          : 't${message.timestamp}-${message.fromId}-${message.groupId ?? message.toId}';
      merged.putIfAbsent(key, () => message);
    }
    final me = _sdkManager.client.currentUserId ?? 0;
    final hits = merged.values.map((message) {
      final groupId = message.groupId ?? 0;
      final isGroup = groupId > 0;
      final peer = message.fromId == me ? message.toId : message.fromId;
      return ChatSearchHit(
        message: _convertSdkMessageToModel(message),
        isGroup: isGroup,
        targetId: isGroup ? groupId : peer,
      );
    }).where((hit) => hit.targetId > 0).toList();
    hits.sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));
    return hits;
  }

  Future<void> sendImage(Uint8List bytes, String filename) async {
    final saved = await _storeOutgoing(bytes, filename);
    final url = await FileApi().uploadBytes(bytes, filename);
    await sendMessage(url, type: 'image', localPath: saved);
  }

  /// 先在列表里放一条本地文件，上传成功后再按文件类型发出。
  Future<void> sendFile({
    required String name,
    required int size,
    String? path,
    Uint8List? bytes,
  }) async {
    if (_currentConversation == null) {
      throw StateError('请先选择会话');
    }
    final filename = name.trim();
    if (filename.isEmpty) {
      throw StateError('文件名为空');
    }
    if (!FileContent.isAllowed(filename)) {
      throw StateError('不支持的文件类型');
    }
    if (size > FileContent.maxBytes || (bytes != null && bytes.length > FileContent.maxBytes)) {
      throw StateError('文件不能超过 10MB');
    }
    final localRef = (path ?? '').trim();
    final currentUserId = _sdkManager.client.currentUserId;
    final currentUserInfo = await _getCurrentUserInfo();
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final pending = FileContent.encode(localRef, filename, size);
    _messages.add(MessageModel(
      id: tempId,
      conversationId: _currentConversation!.id,
      senderId: currentUserId?.toString() ?? '',
      receiverId: '',
      type: MessageType.file,
      content: pending,
      mediaUrl: localRef.isEmpty ? null : localRef,
      timestamp: DateTime.now(),
      isSending: true,
      isSent: true,
      status: MessageStatus.sending,
      readCount: 0,
      senderInfo: currentUserInfo,
      canRecall: true,
    ));
    notifyListeners();

    try {
      final data = bytes ?? await _readLocalFile(localRef);
      if (data.length > FileContent.maxBytes) {
        throw StateError('文件不能超过 10MB');
      }
      final saved = await _storeOutgoing(data, filename);
      if (saved.isNotEmpty) {
        _replaceMessage(tempId, (m) => m.copyWith(localPath: saved));
      }
      final url = await FileApi().uploadBytes(data, filename);
      final content = FileContent.encode(url, filename, data.length);
      _replaceMessage(tempId, (m) => m.copyWith(content: content, mediaUrl: url));

      final targetId = _currentConversation!.targetId;
      if (targetId <= 0) {
        throw StateError('会话无效，无法发送');
      }
      final sentMessage = _currentConversation!.isGroup
          ? await _sdkManager.client.sendGroupMessage(
              groupId: targetId,
              content: content,
              msgType: sdk.MessageType.file.value,
              senderNickname: currentUserInfo?.nickname,
              senderAvatar: currentUserInfo?.avatar,
            )
          : await _sdkManager.client.sendMessage(
              toId: targetId,
              content: content,
              msgType: sdk.MessageType.file.value,
              senderNickname: currentUserInfo?.nickname,
              senderAvatar: currentUserInfo?.avatar,
            );
      _replaceMessage(tempId, (m) => m.copyWith(
        mid: sentMessage.mid,
        midKey: sentMessage.midKey,
        localPath: saved.isEmpty ? m.localPath : saved,
      ));
      await _remember(sentMessage.midKey, saved);
      loadConversations();
    } catch (e) {
      debugPrint('发送文件失败: $e');
      await _keepFailedOutgoing(
        tempId: tempId,
        content: pending,
        msgType: sdk.MessageType.file.value,
        localPath: localRef.isEmpty ? null : localRef,
        nickname: currentUserInfo?.nickname,
        avatar: currentUserInfo?.avatar,
      );
      rethrow;
    }
  }

  /// 先展示本地封面和时长，上传成功后再按视频类型发出。
  Future<void> sendVideo({
    required String name,
    required int size,
    String? path,
    Uint8List? bytes,
  }) async {
    if (_currentConversation == null) {
      throw StateError('请先选择会话');
    }
    final localRef = _localMediaPath(path);
    var filename = name.trim();
    if (filename.isEmpty) filename = 'video.mp4';
    if (!VideoContent.isAllowed(filename) && VideoContent.isAllowed(localRef)) {
      filename = localRef.replaceAll('\\', '/').split('/').last;
    }
    if (!VideoContent.isAllowed(filename)) {
      throw StateError('只支持 mp4、mov、avi');
    }
    final declared = size > 0 ? size : (bytes?.length ?? 0);
    if (declared > VideoContent.maxBytes) {
      throw StateError('视频不能超过 50MB');
    }

    var duration = 0;
    var coverPath = '';
    if (localRef.isNotEmpty) {
      final inspected = await VideoInspect.inspect(localRef);
      duration = inspected.durationSeconds;
      coverPath = inspected.coverPath;
      if (duration > VideoContent.maxSeconds) {
        throw StateError('视频不能超过 5 分钟');
      }
    }

    final currentUserId = _sdkManager.client.currentUserId;
    final currentUserInfo = await _getCurrentUserInfo();
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final pending = VideoContent.encode(
      url: localRef,
      name: filename,
      size: declared,
      duration: duration,
      cover: coverPath,
    );
    _messages.add(MessageModel(
      id: tempId,
      conversationId: _currentConversation!.id,
      senderId: currentUserId?.toString() ?? '',
      receiverId: '',
      type: MessageType.video,
      content: pending,
      mediaUrl: localRef.isEmpty ? null : localRef,
      timestamp: DateTime.now(),
      isSending: true,
      isSent: true,
      status: MessageStatus.sending,
      readCount: 0,
      senderInfo: currentUserInfo,
      canRecall: true,
    ));
    notifyListeners();

    try {
      final data = bytes ?? await _readLocalFile(localRef);
      if (data.length > VideoContent.maxBytes) {
        throw StateError('视频不能超过 50MB');
      }
      final saved = await _storeOutgoing(data, filename);
      if (saved.isNotEmpty) {
        _replaceMessage(tempId, (m) => m.copyWith(localPath: saved));
      }
      final url = await FileApi().uploadBytes(data, filename);
      var coverUrl = '';
      if (coverPath.isNotEmpty) {
        try {
          final coverBytes = await _readLocalFile(coverPath);
          coverUrl = await FileApi().uploadBytes(coverBytes, 'cover.jpg');
        } catch (e) {
          debugPrint('封面上传失败: $e');
        }
      }
      final content = VideoContent.encode(
        url: url,
        name: filename,
        size: data.length,
        duration: duration,
        cover: coverUrl,
      );
      _replaceMessage(tempId, (m) => m.copyWith(content: content, mediaUrl: url));

      final targetId = _currentConversation!.targetId;
      if (targetId <= 0) {
        throw StateError('会话无效，无法发送');
      }
      final sentMessage = _currentConversation!.isGroup
          ? await _sdkManager.client.sendGroupMessage(
              groupId: targetId,
              content: content,
              msgType: sdk.MessageType.video.value,
              senderNickname: currentUserInfo?.nickname,
              senderAvatar: currentUserInfo?.avatar,
            )
          : await _sdkManager.client.sendMessage(
              toId: targetId,
              content: content,
              msgType: sdk.MessageType.video.value,
              senderNickname: currentUserInfo?.nickname,
              senderAvatar: currentUserInfo?.avatar,
            );
      _replaceMessage(tempId, (m) => m.copyWith(
        mid: sentMessage.mid,
        midKey: sentMessage.midKey,
        localPath: saved.isEmpty ? m.localPath : saved,
      ));
      await _remember(sentMessage.midKey, saved);
      loadConversations();
    } catch (e) {
      debugPrint('发送视频失败: $e');
      await _keepFailedOutgoing(
        tempId: tempId,
        content: pending,
        msgType: sdk.MessageType.video.value,
        localPath: localRef.isEmpty ? null : localRef,
        nickname: currentUserInfo?.nickname,
        avatar: currentUserInfo?.avatar,
      );
      rethrow;
    }
  }

  void cacheStoredFiles(List<ChatFileItem> items) {
    _enqueueRemote(items.map((item) => _RemoteMedia(
          key: item.key,
          url: item.url,
          name: item.name,
          localPath: item.localPath,
        )));
  }

  void _enqueueMedia(List<MessageModel> messages) {
    final targets = <_RemoteMedia>[];
    for (final message in messages) {
      final target = _remoteMedia(message);
      if (target != null) targets.add(target);
    }
    _enqueueRemote(targets);
  }

  void _enqueueRemote(Iterable<_RemoteMedia> targets) {
    if (kIsWeb) return;
    for (final target in targets) {
      final key = target.key.trim();
      final url = target.url.trim();
      if (key.isEmpty || !(url.startsWith('http://') || url.startsWith('https://'))) continue;
      if (target.localPath.trim().isNotEmpty) continue;
      if (!_cacheKeys.add(key)) continue;
      _cacheQueue.add(target);
    }
    _pumpMediaCache();
  }

  void _pumpMediaCache() {
    while (_cacheRunning < 2 && _cacheQueue.isNotEmpty) {
      final target = _cacheQueue.removeAt(0);
      _cacheRunning++;
      _downloadMedia(target).whenComplete(() {
        _cacheRunning--;
        _cacheKeys.remove(target.key);
        _pumpMediaCache();
      });
    }
  }

  Future<void> _downloadMedia(_RemoteMedia target) async {
    try {
      if (await MediaStore.exists(target.localPath)) return;
      final saved = await MediaStore.ensure(
        knownPath: target.localPath,
        remoteUrl: target.url,
        name: target.name,
      );
      if (saved.path.isEmpty) return;
      await rememberMediaPath(target.key, saved.path);
    } catch (error) {
      debugPrint('自动保存附件失败: $error');
    }
  }

  _RemoteMedia? _remoteMedia(MessageModel message) {
    if (message.status == MessageStatus.recalled) return null;
    final key = message.midKey ?? message.id;
    switch (message.type) {
      case MessageType.image:
        final url = (message.mediaUrl ?? message.content).trim();
        final name = Uri.tryParse(url)?.path.split('/').last;
        return _RemoteMedia(
          key: key,
          url: url,
          name: name == null || name.isEmpty ? 'image.jpg' : name,
          localPath: message.localPath ?? '',
        );
      case MessageType.file:
        final file = FileContent.tryParse(message.content);
        final url = (file?.url ?? message.mediaUrl ?? '').trim();
        final name = file?.name.trim().isNotEmpty == true ? file!.name.trim() : '文件';
        return _RemoteMedia(key: key, url: url, name: name, localPath: message.localPath ?? '');
      case MessageType.video:
        final video = VideoContent.tryParse(message.content);
        final url = (video?.url ?? message.mediaUrl ?? '').trim();
        final name = video?.name.trim().isNotEmpty == true ? video!.name.trim() : 'video.mp4';
        return _RemoteMedia(key: key, url: url, name: name, localPath: message.localPath ?? '');
      case MessageType.text:
      case MessageType.audio:
      case MessageType.notice:
        return null;
    }
  }

  Future<String> _storeOutgoing(List<int> bytes, String name) async {
    try {
      return await MediaStore.keepBytes(bytes, name);
    } catch (error) {
      debugPrint('保存本地副本失败: $error');
      return '';
    }
  }

  Future<void> _remember(String? midKey, String path) async {
    final key = midKey?.trim() ?? '';
    final value = path.trim();
    if (key.isEmpty || value.isEmpty) return;
    try {
      await _sdkManager.client.rememberLocalPath(midKey: key, path: value);
    } catch (error) {
      debugPrint('记录本地路径失败: $error');
    }
  }

  String _localMediaPath(String? path) {
    final value = (path ?? '').trim();
    if (kIsWeb || value.isEmpty) return '';
    if (value.startsWith('blob:') || value.startsWith('http://') || value.startsWith('https://')) {
      return '';
    }
    return value;
  }

  Future<Uint8List> _readLocalFile(String path) async {
    if (kIsWeb || path.isEmpty) {
      throw StateError('文件不存在，无法发送');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('文件不存在，无法发送');
    }
    return file.readAsBytes();
  }

  /// 先在列表里放一条本地语音，上传成功后再按语音类型发出。
  Future<void> sendVoiceFile(String path, int durationSeconds) async {
    if (_currentConversation == null) {
      throw StateError('请先选择会话');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('录音文件不存在');
    }
    final seconds = durationSeconds.clamp(1, 60);
    final currentUserId = _sdkManager.client.currentUserId;
    final currentUserInfo = await _getCurrentUserInfo();
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    _messages.add(MessageModel(
      id: tempId,
      conversationId: _currentConversation!.id,
      senderId: currentUserId?.toString() ?? '',
      receiverId: '',
      type: MessageType.audio,
      content: VoiceContent.encode(path, seconds),
      mediaUrl: path,
      timestamp: DateTime.now(),
      isSending: true,
      isSent: true,
      status: MessageStatus.sending,
      readCount: 0,
      senderInfo: currentUserInfo,
      canRecall: true,
    ));
    notifyListeners();

    try {
      final content = await _uploadVoice(path, seconds);
      final remote = VoiceContent.tryParse(content);
      _replaceMessage(tempId, (m) => m.copyWith(
        content: content,
        mediaUrl: remote?.url ?? m.mediaUrl,
      ));

      final targetId = _currentConversation!.targetId;
      if (targetId <= 0) {
        throw StateError('会话无效，无法发送');
      }
      final sentMessage = _currentConversation!.isGroup
          ? await _sdkManager.client.sendGroupMessage(
              groupId: targetId,
              content: content,
              msgType: sdk.MessageType.voice.value,
              senderNickname: currentUserInfo?.nickname,
              senderAvatar: currentUserInfo?.avatar,
            )
          : await _sdkManager.client.sendMessage(
              toId: targetId,
              content: content,
              msgType: sdk.MessageType.voice.value,
              senderNickname: currentUserInfo?.nickname,
              senderAvatar: currentUserInfo?.avatar,
            );
      _replaceMessage(tempId, (m) => m.copyWith(mid: sentMessage.mid));
      loadConversations();
    } catch (e) {
      debugPrint('发送语音失败: $e');
      await _keepFailedOutgoing(
        tempId: tempId,
        content: VoiceContent.encode(path, seconds),
        msgType: sdk.MessageType.voice.value,
        localPath: path,
        nickname: currentUserInfo?.nickname,
        avatar: currentUserInfo?.avatar,
      );
      rethrow;
    }
  }

  Future<void> sendMessage(String content, {String type = 'text', String? localPath}) async {
    debugPrint('📤[ChatProvider] sendMessage 被调用: bytes=${utf8.encode(content).length}, type=$type');
    if (type == 'text' && utf8.encode(content).length > maxTextBytes) {
      throw StateError('消息过长，单条最多 60KB');
    }
    debugPrint('📤[ChatProvider] 当前 _currentConversation: ${_currentConversation?.id ?? "null"}');

    if (_currentConversation == null) {
      debugPrint('❌[ChatProvider] sendMessage 失败: _currentConversation 为空');
      debugPrint('❌[ChatProvider] 调用栈: ${StackTrace.current}');
      return;
    }

    final currentUserId = _sdkManager.client.currentUserId;
    final currentUserInfo = await _getCurrentUserInfo();
    final reply = _replyingTo;
    _replyingTo = null;
    final isGroup = _currentConversation!.isGroup;
    final atUserIds = isGroup && type == 'text' ? _consumeAtUserIds(content) : null;

    final tempMessage = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: _currentConversation!.id,
      senderId: currentUserId?.toString() ?? '',
      receiverId: '',
      type: _uiTypeFromWire(type),
      content: content,
      mediaUrl: type == 'image'
          ? content
          : type == 'voice'
              ? VoiceContent.tryParse(content)?.url
              : type == 'file'
                  ? FileContent.tryParse(content)?.url
                  : type == 'video'
                      ? VideoContent.tryParse(content)?.url
                      : null,
      timestamp: DateTime.now(),
      isSending: true,
      isSent: true,
      status: MessageStatus.sending,
      readCount: 0,
      senderInfo: currentUserInfo,
      canRecall: true,
      replyMsgId: reply?.mid,
      replyPreview: reply?.quoteText,
      replySenderName: reply?.senderDisplayName,
      localPath: localPath,
      atUserIds: atUserIds,
    );

    debugPrint('📤[ChatProvider] 发送消息(本地) senderInfo=${tempMessage.senderInfo?.toJson()}');

    _messages.add(tempMessage);
    notifyListeners();

    try {
      final targetId = _currentConversation!.targetId;

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
          msgType: _sdkTypeFromWire(type),
          senderNickname: currentUserInfo?.nickname,
          senderAvatar: currentUserInfo?.avatar,
          replyMsgId: reply?.mid,
          replyPreview: reply?.quoteText,
          replySenderName: reply?.senderDisplayName,
          atUserIds: atUserIds,
        );
      } else {
        sentMessage = await _sdkManager.client.sendMessage(
          toId: targetId,
          content: content,
          msgType: _sdkTypeFromWire(type),
          senderNickname: currentUserInfo?.nickname,
          senderAvatar: currentUserInfo?.avatar,
          replyMsgId: reply?.mid,
          replyPreview: reply?.quoteText,
          replySenderName: reply?.senderDisplayName,
        );
      }

      final index = _messages.indexWhere((m) => m.id == tempMessage.id);
      if (index != -1) {
        // 使用 SDK 返回的消息信息更新本地消息
        _messages[index] = _messages[index].copyWith(
          mid: sentMessage.mid,
          midKey: sentMessage.midKey,
          localPath: (localPath == null || localPath.isEmpty) ? _messages[index].localPath : localPath,
        );
        notifyListeners();
      }
      await _remember(sentMessage.midKey, localPath ?? '');
      
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

  Future<void> forwardMessage(MessageModel source, ConversationModel target) async {
    if (source.status == MessageStatus.recalled || source.content.isEmpty) {
      throw StateError('这条消息不能转发');
    }
    if (target.targetId <= 0) {
      throw StateError('会话无效');
    }
    final current = _currentConversation;
    final toCurrent = current != null &&
        current.isGroup == target.isGroup &&
        current.targetId == target.targetId;
    if (toCurrent) {
      _replyingTo = null;
      final wire = switch (source.type) {
        MessageType.image => 'image',
        MessageType.audio => 'voice',
        MessageType.file => 'file',
        MessageType.video => 'video',
        MessageType.text => 'text',
        MessageType.notice => 'text',
      };
      await sendMessage(source.content, type: wire);
      return;
    }

    final currentUserInfo = await _getCurrentUserInfo();
    if (target.isGroup) {
      await _sdkManager.client.sendGroupMessage(
        groupId: target.targetId,
        content: source.content,
        msgType: _sdkTypeFromModel(source),
        senderNickname: currentUserInfo?.nickname,
        senderAvatar: currentUserInfo?.avatar,
      );
    } else {
      await _sdkManager.client.sendMessage(
        toId: target.targetId,
        content: source.content,
        msgType: _sdkTypeFromModel(source),
        senderNickname: currentUserInfo?.nickname,
        senderAvatar: currentUserInfo?.avatar,
      );
    }
    loadConversations();
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

      // 从 StorageService 获取登录时保存的用户信息
      final nickname = await StorageService.getNickname();
      if (nickname != null && nickname.isNotEmpty) {
        final avatar = await StorageService.getAvatar();
        return SenderInfoModel(
          userId: currentUserId,
          nickname: nickname,
          avatar: avatar ?? '',
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
        nickname: '用户$currentUserId',
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

      var content = message.content;
      if (message.type == MessageType.audio) {
        content = await _uploadVoiceIfNeeded(message);
        final voice = VoiceContent.tryParse(content);
        _replaceMessage(message.id, (m) => m.copyWith(
          content: content,
          mediaUrl: voice?.url ?? m.mediaUrl,
        ));
      } else if (message.type == MessageType.file) {
        content = await _uploadFileIfNeeded(message);
        final file = FileContent.tryParse(content);
        _replaceMessage(message.id, (m) => m.copyWith(
          content: content,
          mediaUrl: file?.url ?? m.mediaUrl,
        ));
      } else if (message.type == MessageType.video) {
        content = await _uploadVideoIfNeeded(message);
        final video = VideoContent.tryParse(content);
        _replaceMessage(message.id, (m) => m.copyWith(
          content: content,
          mediaUrl: video?.url ?? m.mediaUrl,
        ));
      }

      final sdk.Message sentMessage;
      final savedMid = message.mid;
      if (savedMid != null && savedMid > 0) {
        sentMessage = await _sdkManager.client.resendSavedMessage(
          mid: savedMid,
          content: content,
        );
      } else if (isGroup) {
        sentMessage = await _sdkManager.client.sendGroupMessage(
          groupId: targetId,
          content: content,
          msgType: _sdkTypeFromModel(message),
        );
      } else {
        sentMessage = await _sdkManager.client.sendMessage(
          toId: targetId,
          content: content,
          msgType: _sdkTypeFromModel(message),
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

  bool _sameMessage(MessageModel a, MessageModel b) {
    final aKey = a.midKey;
    final bKey = b.midKey;
    final aHasKey = aKey != null && aKey.isNotEmpty && aKey != '0';
    final bHasKey = bKey != null && bKey.isNotEmpty && bKey != '0';
    if (aHasKey && bHasKey && aKey == bKey) return true;
    final aMid = a.mid ?? 0;
    final bMid = b.mid ?? 0;
    if (aMid <= 0 || aMid != bMid) return false;
    // 旧记录只有舍入后的数字，新记录带完整雪花原文。数字相同且至少一边没有独立原文时，视为同一条。
    final aIsLegacy = !aHasKey || aKey == '$aMid';
    final bIsLegacy = !bHasKey || bKey == '$bMid';
    return aIsLegacy || bIsLegacy;
  }

  void receiveMessage(MessageModel message) {
    if (_messages.any((item) => _sameMessage(item, message))) return;
    _messages.add(message);
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    notifyListeners();
    final conversation = _currentConversation;
    final mid = message.mid ?? 0;
    final me = _sdkManager.client.currentUserId;
    if (conversation != null &&
        mid > 0 &&
        me != null &&
        message.senderId != '$me') {
      _sdkManager.client.sendReadReceipt(
        mid,
        groupId: conversation.isGroup ? conversation.targetId : null,
      );
    }
  }

  Future<void> _fillPrivateReadCounts(int peerId) async {
    final me = _sdkManager.client.currentUserId?.toString();
    if (me == null || me.isEmpty) return;
    final ownIndexes = <int>[];
    final mids = <int>[];
    for (var index = 0; index < _messages.length; index++) {
      final message = _messages[index];
      final mid = message.mid ?? 0;
      if (message.senderId != me ||
          mid <= 0 ||
          message.type == MessageType.notice ||
          message.status == MessageStatus.recalled) {
        continue;
      }
      ownIndexes.add(index);
      mids.add(mid);
    }
    if (mids.isEmpty) return;
    try {
      final api = MessageApi();
      final counts = <int, int>{};
      for (var start = 0; start < mids.length; start += 50) {
        final end = start + 50 < mids.length ? start + 50 : mids.length;
        counts.addAll(await api.privateReadCounts(peerId, mids.sublist(start, end)));
      }
      for (final index in ownIndexes) {
        final mid = _messages[index].mid!;
        _messages[index] = _messages[index].copyWith(readCount: counts[mid] ?? 0);
      }
    } catch (e) {
      debugPrint('⚠️[ChatProvider] 拉取私聊已读状态失败: $e');
      for (final index in ownIndexes) {
        final alreadyRead = _messages[index].status == MessageStatus.read;
        _messages[index] = _messages[index].copyWith(
          readCount: _messages[index].readCount ?? (alreadyRead ? 1 : 0),
        );
      }
    }
  }

  Future<void> _fillGroupReadCounts(int groupId) async {
    final me = _sdkManager.client.currentUserId?.toString();
    if (me == null || me.isEmpty) return;
    final ownIndexes = <int>[];
    final mids = <int>[];
    for (var index = 0; index < _messages.length; index++) {
      final message = _messages[index];
      final mid = message.mid ?? 0;
      if (message.senderId != me ||
          mid <= 0 ||
          message.type == MessageType.notice ||
          message.status == MessageStatus.recalled) {
        continue;
      }
      ownIndexes.add(index);
      mids.add(mid);
    }
    if (mids.isEmpty) return;
    try {
      final api = MessageApi();
      final counts = <int, int>{};
      for (var start = 0; start < mids.length; start += 50) {
        final end = start + 50 < mids.length ? start + 50 : mids.length;
        counts.addAll(await api.groupReadCounts(groupId, mids.sublist(start, end)));
      }
      for (final index in ownIndexes) {
        final mid = _messages[index].mid!;
        _messages[index] = _messages[index].copyWith(readCount: counts[mid] ?? 0);
      }
    } catch (e) {
      debugPrint('⚠️[ChatProvider] 拉取群已读人数失败: $e');
      for (final index in ownIndexes) {
        _messages[index] = _messages[index].copyWith(readCount: _messages[index].readCount ?? 0);
      }
    }
  }

  /// 仅从本机删除这条消息，不影响对方。
  Future<void> deleteMessage(MessageModel message) async {
    final mid = message.mid;
    final localId = int.tryParse(message.id);
    _messages.removeWhere((item) {
      if (item.id == message.id) return true;
      if (mid != null && mid > 0 && item.mid == mid) return true;
      return false;
    });
    notifyListeners();

    try {
      await _sdkManager.client.deleteLocalMessage(
        id: localId,
        mid: (mid != null && mid > 0) ? mid : null,
      );
      loadConversations();
    } catch (e) {
      debugPrint('❌[ChatProvider] 删除本地消息失败: $e');
    }
  }

  /// 撤回消息
  Future<void> recallMessage(MessageModel message) async {
    try {
      debugPrint('🗑️[ChatProvider] 撤回消息: messageId=${message.id}, mid=${message.mid}');

      // 优先使用 SDK 的 mid（雪花算法生成的全局唯一ID）
      final messageMid = message.mid ?? int.tryParse(message.id);
      if (messageMid == null) {
        debugPrint('❌[ChatProvider] 消息ID无效，无法撤回');
        return;
      }

      await _sdkManager.client.recallMessage(messageMid);

      // 更新本地消息状态
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          status: MessageStatus.recalled,
          content: '[消息已撤回]',
        );
        notifyListeners();
      }

      debugPrint('✅[ChatProvider] 消息撤回成功: messageId=${message.id}');
    } catch (e) {
      debugPrint('❌[ChatProvider] 撤回消息失败: $e');
      rethrow;
    }
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
      if (isGroup) _clearMention(targetId);

      final convIndex = _conversations.indexWhere(
        (c) => c.id.contains(targetId.toString()),
      );

      if (convIndex != -1 &&
          (_conversations[convIndex].unreadCount > 0 ||
              _conversations[convIndex].mentionMessageKey != null)) {
        final updatedConv = _conversations[convIndex].copyWith(
          unreadCount: 0,
          clearMention: true,
        );
        _conversations[convIndex] = updatedConv;
        debugPrint('✅[ChatProvider] 会话已读标记成功, 未读数已清零 (conversationId=$conversationId)');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌[ChatProvider] 标记会话已读失败: $e');
    }
  }

  /// 已加载的私聊会话。置顶、免打扰以这里的状态为准。
  ConversationModel? privateConversation(int targetId) {
    if (targetId <= 0) return null;
    return _conversations
        .where((c) => !c.isGroup && c.targetId == targetId)
        .firstOrNull;
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

  /// 会话置顶；私聊时同步联系人服务端标记
  Future<void> setConversationTop(
    ConversationModel conversation,
    bool isTop, {
    Future<void> Function(int contactUserId, bool isTop)? syncContact,
  }) async {
    final dbId = conversation.dbId ?? _findDbIdByTargetId(conversation.targetId);
    if (dbId == null || dbId <= 0) {
      throw StateError('会话尚未落库，无法置顶');
    }
    await _sdkManager.client.setConversationTop(dbId, isTop);
    if (!conversation.isGroup && syncContact != null) {
      await syncContact(conversation.targetId, isTop);
    }
    final index = _conversations.indexWhere((c) => c.id == conversation.id);
    if (index != -1) {
      _conversations[index] = _conversations[index].copyWith(isTop: isTop);
      _conversations.sort((a, b) {
        if (a.isTop != b.isTop) return a.isTop ? -1 : 1;
        final at = a.lastActiveTime?.millisecondsSinceEpoch ?? 0;
        final bt = b.lastActiveTime?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
      notifyListeners();
    } else {
      await loadConversations();
    }
  }

  /// 会话免打扰；私聊时同步联系人服务端标记
  Future<void> setConversationMute(
    ConversationModel conversation,
    bool isMute, {
    Future<void> Function(int contactUserId, bool isMute)? syncContact,
  }) async {
    final dbId = conversation.dbId ?? _findDbIdByTargetId(conversation.targetId);
    if (dbId == null || dbId <= 0) {
      throw StateError('会话尚未落库，无法设置免打扰');
    }
    await _sdkManager.client.setConversationMute(dbId, isMute);
    if (!conversation.isGroup && syncContact != null) {
      await syncContact(conversation.targetId, isMute);
    }
    final index = _conversations.indexWhere((c) => c.id == conversation.id);
    if (index != -1) {
      _conversations[index] = _conversations[index].copyWith(isMute: isMute);
      notifyListeners();
    } else {
      await loadConversations();
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

  void _syncLocalMessageStatus(sdk.Message sdkMessage) {
    final mid = sdkMessage.mid;
    if (mid == null) return;

    final index = _messages.indexWhere((m) => m.mid == mid);
    if (index == -1) return;

    final mapped = _mapSdkStatus(sdkMessage.status);
    _messages[index] = _messages[index].copyWith(
      isSending: mapped == MessageStatus.sending,
      status: mapped,
    );
    notifyListeners();
  }

  void _markLocalMessageFailed(int? mid) {
    var index = -1;
    if (mid != null) {
      index = _messages.indexWhere((m) => m.mid == mid);
    }
    if (index == -1) {
      index = _messages.lastIndexWhere(
        (m) => m.isSending || m.status == MessageStatus.sending,
      );
    }
    if (index == -1) return;

    _messages[index] = _messages[index].copyWith(
      isSending: false,
      status: MessageStatus.failed,
    );
    notifyListeners();
  }

  MessageStatus _mapSdkStatus(sdk.MessageStatus status) {
    switch (status) {
      case sdk.MessageStatus.sending:
        return MessageStatus.sending;
      case sdk.MessageStatus.sent:
        return MessageStatus.sent;
      case sdk.MessageStatus.delivered:
        return MessageStatus.delivered;
      case sdk.MessageStatus.read:
        return MessageStatus.read;
      case sdk.MessageStatus.failed:
        return MessageStatus.failed;
      case sdk.MessageStatus.recalled:
        return MessageStatus.recalled;
    }
  }

  void _showSendErrorTip(String reason) {
    final context = AppRouter.navigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(reason),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void clearCurrentConversation() {
    if (_currentConversation == null && _messages.isEmpty) {
      return;
    }
    debugPrint('🗑️[ChatProvider] clearCurrentConversation 被调用，清空前: ${_currentConversation?.id ?? "null"}');
    _currentConversation = null;
    _messages = [];
    _focusMessageKey = null;
    _focusReady = false;
    // ✅ 清除通知服务的当前聊天状态
    NotificationService().currentChatTargetId = null;
    notifyListeners();
  }

  /// ✅ 初始化消息通知服务
  Future<void> _initNotificationService() async {
    try {
      final notificationService = NotificationService();
      await notificationService.initialize();
      notificationService.onOpen = _openFromNotification;
      await notificationService.handleLaunchNotification();

      // 请求通知权限（Android 13+ 需要）
      await notificationService.requestPermission();
      await KeepAliveService.start();
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
      final targetId = message.groupId ?? (message.fromId);
      final isGroup = message.groupId != null && message.groupId! > 0;

      // 免打扰会话不弹通知；有人 @ 我时仍然提醒
      final mentioned = isGroup && _mentionsMe(message.atUserIds);
      final muted = _conversations.any(
        (c) => c.isMute && c.targetId == (isGroup ? message.groupId : message.fromId),
      );
      if (muted && !mentioned) {
        debugPrint('🔕[ChatProvider] 免打扰会话，跳过通知: targetId=$targetId');
        return;
      }

      final preview = _notificationPreview(message);
      var title = nickname;
      var body = preview;
      if (isGroup) {
        for (final conversation in _conversations) {
          if (conversation.isGroup && conversation.targetId == message.groupId) {
            title = conversation.name;
            break;
          }
        }
        if (title == nickname) title = '群聊';
        body = mentioned ? '$nickname @了你' : '$nickname: $preview';
      }

      final notificationData = NotificationData(
        senderId: message.fromId,
        nickname: title,
        avatarUrl: avatarUrl,
        content: body,
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

  String _notificationPreview(sdk.Message message) {
    switch (message.msgType) {
      case sdk.MessageType.image:
        return '[图片]';
      case sdk.MessageType.voice:
        return '[语音]';
      case sdk.MessageType.video:
        return '[视频]';
      case sdk.MessageType.file:
        final name = FileContent.tryParse(message.content)?.name ?? '';
        return name.isEmpty ? '[文件]' : '[文件] $name';
      case sdk.MessageType.system:
        return '';
      case sdk.MessageType.text:
        final text = message.content.replaceAll('\n', ' ').trim();
        if (text.length <= 40) return text;
        return '${text.substring(0, 40)}…';
    }
  }

  void _openFromNotification(NotificationData data) {
    final context = AppRouter.navigatorKey.currentContext;
    final navigator = AppRouter.navigatorKey.currentState;
    if (context == null || navigator == null) return;
    if (data.targetId < 0) {
      context.read<ContactProvider>().onOpenContacts?.call();
      context.read<LayoutProvider>().selectNavigation(1);
      return;
    }
    if (data.targetId <= 0) return;
    if (_currentConversation?.targetId == data.targetId &&
        _currentConversation?.isGroup == data.isGroup) {
      return;
    }
    final id = '${data.targetId}';
    if (AdaptiveLayout.isDesktopPlatform) {
      final layout = context.read<LayoutProvider>();
      if (layout.currentConversationId != id) {
        layout.selectConversation(id, data.nickname, data.isGroup);
      }
      return;
    }
    navigator.pushNamed(
      AppRouter.chat,
      arguments: {
        'conversationId': id,
        'conversationName': data.nickname,
        'isGroup': data.isGroup,
        'targetId': data.targetId,
      },
    );
  }

  /// 后台异步刷新群组信息（不阻塞 UI，成功后触发会话列表更新）
  void _refreshGroupInfoInBackground(int groupId) {
    _sdkManager.client.getGroup(groupId).then((group) {
      if (group.name.isNotEmpty) {
        debugPrint('✅[ChatProvider] 后台获取群组信息成功: groupId=$groupId, name=${group.name}');
        loadConversations();
      }
    }).catchError((e) {
      // 静默忽略：服务端 group_get 接口暂未实现，失败是预期行为
    });
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

  Future<void> _keepFailedOutgoing({
    required String tempId,
    required String content,
    required int msgType,
    String? localPath,
    String? nickname,
    String? avatar,
  }) async {
    final conversation = _currentConversation;
    if (conversation == null || conversation.targetId <= 0) {
      _replaceMessage(tempId, (m) => m.copyWith(
        isSending: false,
        status: MessageStatus.failed,
      ));
      return;
    }
    try {
      final saved = await _sdkManager.client.saveLocalOutgoing(
        toId: conversation.targetId,
        groupId: conversation.isGroup ? conversation.targetId : null,
        content: content,
        msgType: msgType,
        status: sdk.MessageStatus.failed,
        localPath: localPath,
        senderNickname: nickname,
        senderAvatar: avatar,
      );
      _replaceMessage(tempId, (m) => m.copyWith(
        id: saved.id?.toString() ?? tempId,
        mid: saved.mid,
        isSending: false,
        status: MessageStatus.failed,
      ));
      loadConversations();
    } catch (e) {
      debugPrint('保存失败消息到本地失败: $e');
      _replaceMessage(tempId, (m) => m.copyWith(
        isSending: false,
        status: MessageStatus.failed,
      ));
    }
  }

  void _replaceMessage(String id, MessageModel Function(MessageModel) update) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index == -1) return;
    _messages[index] = update(_messages[index]);
    notifyListeners();
  }

  MessageType _uiTypeFromWire(String type) {
    switch (type) {
      case 'image':
        return MessageType.image;
      case 'voice':
        return MessageType.audio;
      case 'file':
        return MessageType.file;
      case 'video':
        return MessageType.video;
      default:
        return MessageType.text;
    }
  }

  int _sdkTypeFromWire(String type) {
    switch (type) {
      case 'image':
        return sdk.MessageType.image.value;
      case 'voice':
        return sdk.MessageType.voice.value;
      case 'file':
        return sdk.MessageType.file.value;
      case 'video':
        return sdk.MessageType.video.value;
      default:
        return sdk.MessageType.text.value;
    }
  }

  int _sdkTypeFromModel(MessageModel message) {
    switch (message.type) {
      case MessageType.image:
        return sdk.MessageType.image.value;
      case MessageType.audio:
        return sdk.MessageType.voice.value;
      case MessageType.file:
        return sdk.MessageType.file.value;
      case MessageType.video:
        return sdk.MessageType.video.value;
      case MessageType.text:
      case MessageType.notice:
        return sdk.MessageType.text.value;
    }
  }

  MessageType _uiTypeFromSdk(sdk.MessageType type) {
    switch (type) {
      case sdk.MessageType.image:
        return MessageType.image;
      case sdk.MessageType.voice:
        return MessageType.audio;
      case sdk.MessageType.file:
        return MessageType.file;
      case sdk.MessageType.video:
        return MessageType.video;
      case sdk.MessageType.text:
        return MessageType.text;
      case sdk.MessageType.system:
        return MessageType.notice;
    }
  }

  String? _mediaUrlFromSdk(sdk.Message msg) {
    switch (msg.msgType) {
      case sdk.MessageType.image:
        return msg.localPath ?? msg.content;
      case sdk.MessageType.voice:
        final remote = VoiceContent.tryParse(msg.content)?.url;
        if (remote != null &&
            (remote.startsWith('http://') || remote.startsWith('https://'))) {
          return remote;
        }
        return msg.localPath ?? remote;
      case sdk.MessageType.file:
        final file = FileContent.tryParse(msg.content);
        final remote = file?.url ?? '';
        if (remote.startsWith('http://') || remote.startsWith('https://')) {
          return remote;
        }
        return msg.localPath ?? (remote.isEmpty ? null : remote);
      case sdk.MessageType.video:
        final video = VideoContent.tryParse(msg.content);
        final videoUrl = video?.url ?? '';
        if (videoUrl.startsWith('http://') || videoUrl.startsWith('https://')) {
          return videoUrl;
        }
        return msg.localPath ?? (videoUrl.isEmpty ? null : videoUrl);
      case sdk.MessageType.text:
      case sdk.MessageType.system:
        return null;
    }
  }

  Future<String> _uploadVoice(String path, int seconds) async {
    final filename = path.replaceAll('\\', '/').split('/').last;
    final bytes = await File(path).readAsBytes();
    final url = await FileApi().uploadBytes(bytes, filename);
    return VoiceContent.encode(url, seconds);
  }

  Future<String> _uploadVoiceIfNeeded(MessageModel message) async {
    final parsed = VoiceContent.tryParse(message.content);
    final raw = (parsed?.url ?? message.mediaUrl ?? '').trim();
    final seconds = (parsed?.duration ?? message.voiceDuration).clamp(1, 60);
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return VoiceContent.encode(raw, seconds);
    }
    if (raw.isEmpty || !await File(raw).exists()) {
      throw StateError('语音文件不存在，无法重发');
    }
    return _uploadVoice(raw, seconds);
  }

  Future<String> _uploadFileIfNeeded(MessageModel message) async {
    final parsed = FileContent.tryParse(message.content);
    final raw = (parsed?.url ?? message.mediaUrl ?? '').trim();
    final name = parsed?.name.isNotEmpty == true ? parsed!.name : '文件';
    final size = parsed?.size ?? 0;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return FileContent.encode(raw, name, size);
    }
    final bytes = await _readLocalFile(raw);
    if (bytes.length > FileContent.maxBytes) {
      throw StateError('文件不能超过 10MB');
    }
    final url = await FileApi().uploadBytes(bytes, name);
    return FileContent.encode(url, name, bytes.length);
  }

  Future<String> _uploadVideoIfNeeded(MessageModel message) async {
    final parsed = VideoContent.tryParse(message.content);
    var raw = (parsed?.url ?? message.mediaUrl ?? '').trim();
    var cover = parsed?.cover ?? '';
    final name = parsed?.name.isNotEmpty == true ? parsed!.name : 'video.mp4';
    final duration = parsed?.duration ?? 0;
    if (!VideoContent.isRemote(raw)) {
      final bytes = await _readLocalFile(raw);
      if (bytes.length > VideoContent.maxBytes) {
        throw StateError('视频不能超过 50MB');
      }
      raw = await FileApi().uploadBytes(bytes, name);
    }
    if (cover.isNotEmpty && !VideoContent.isRemote(cover)) {
      try {
        final coverBytes = await _readLocalFile(cover);
        cover = await FileApi().uploadBytes(coverBytes, 'cover.jpg');
      } catch (e) {
        debugPrint('重发时封面上传失败: $e');
        cover = '';
      }
    }
    return VideoContent.encode(
      url: raw,
      name: name,
      size: parsed?.size ?? 0,
      duration: duration,
      cover: cover,
    );
  }

  MessageModel _convertSdkMessageToModel(sdk.Message msg) {
    final currentUserId = _sdkManager.client.currentUserId;
    final isFromMe = currentUserId != null && msg.fromId == currentUserId;

    // 判断是否可以撤回：自己发的消息 + 2分钟内
    bool canRecall = false;
    if (isFromMe) {
      final msgTime = DateTime.fromMillisecondsSinceEpoch(msg.timestamp);
      final now = DateTime.now();
      final diff = now.difference(msgTime);
      canRecall = diff.inMinutes < 2;
    }

    // 优先使用消息中存储的发送者信息（已持久化到数据库）
    SenderInfoModel? senderInfo;
    if (msg.senderNickname != null || msg.senderAvatar != null) {
      senderInfo = SenderInfoModel(
        userId: msg.fromId,
        nickname: msg.senderNickname ?? '用户${msg.fromId}',
        avatar: msg.senderAvatar ?? '',
      );
    } else if (msg.senderInfo != null) {
      // 兼容旧消息（没有存储发送者信息的情况）
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
      type: _uiTypeFromSdk(msg.msgType),
      content: msg.content,
      mediaUrl: _mediaUrlFromSdk(msg),
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.timestamp),
      isSent: isFromMe,
      status: _convertSdkStatus(msg.status),
      senderInfo: senderInfo,
      groupInfo: groupInfo,
      canRecall: canRecall,
      mid: msg.mid,
      midKey: msg.midKey,
      replyMsgId: msg.replyMsgId,
      replyPreview: msg.replyPreview,
      replySenderName: msg.replySenderName,
      localPath: msg.localPath,
      atUserIds: msg.atUserIds,
    );
  }

  void applySendConfirmation(sdk.Message message) {
    final mid = message.mid;
    if (mid == null) return;
    final index = _messages.indexWhere((item) => item.mid == mid);
    if (index == -1) return;
    final trackRead = _currentConversation != null;
    _messages[index] = _messages[index].copyWith(
      isSending: false,
      isSent: true,
      status: _convertSdkStatus(message.status),
      mediaUrl: _mediaUrlFromSdk(message) ?? _messages[index].mediaUrl,
      readCount: trackRead ? (_messages[index].readCount ?? 0) : _messages[index].readCount,
    );
    notifyListeners();
  }

  MessageStatus _convertSdkStatus(sdk.MessageStatus sdkStatus) {
    switch (sdkStatus) {
      case sdk.MessageStatus.sending:
        return MessageStatus.sending;
      case sdk.MessageStatus.sent:
        return MessageStatus.sent;
      case sdk.MessageStatus.delivered:
        return MessageStatus.delivered;
      case sdk.MessageStatus.read:
        return MessageStatus.read;
      case sdk.MessageStatus.failed:
        return MessageStatus.failed;
      case sdk.MessageStatus.recalled:
        return MessageStatus.recalled;
      default:
        return MessageStatus.delivered;
    }
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

    // 用消息里的发送者信息补全联系人缓存，避免会话列表一直显示「用户XX」
    final incomingNick = message.senderInfo?.nickname.isNotEmpty == true
        ? message.senderInfo!.nickname
        : message.senderNickname;
    final incomingAvatar = message.senderInfo?.avatar.isNotEmpty == true
        ? message.senderInfo!.avatar
        : message.senderAvatar;
    if (incomingNick != null && incomingNick.isNotEmpty) {
      _provider._seedContactCache(
        userId: message.fromId,
        nickname: incomingNick,
        avatar: incomingAvatar ?? '',
      );
    }

    // 优先使用消息中存储的发送者信息
    SenderInfoModel? senderInfo;
    if (message.senderNickname != null || message.senderAvatar != null) {
      senderInfo = SenderInfoModel(
        userId: message.fromId,
        nickname: message.senderNickname ?? '用户${message.fromId}',
        avatar: message.senderAvatar ?? '',
      );
    } else if (message.senderInfo != null) {
      senderInfo = SenderInfoModel(
        userId: message.senderInfo!.userId,
        nickname: message.senderInfo!.nickname,
        avatar: message.senderInfo!.avatar,
        groupNickname: message.senderInfo!.groupNickname,
      );
    } else {
      // 尝试从缓存获取
      final contactInfo = _provider._contactInfoCache[message.fromId];
      if (contactInfo != null) {
        senderInfo = SenderInfoModel(
          userId: contactInfo.userId,
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
      type: _provider._uiTypeFromSdk(message.msgType),
      content: message.content,
      mediaUrl: _provider._mediaUrlFromSdk(message),
      timestamp: DateTime.fromMillisecondsSinceEpoch(message.timestamp),
      status: MessageStatus.delivered,
      senderInfo: senderInfo,
      groupInfo: groupInfo,
      mid: message.mid,
      midKey: message.midKey,
      replyMsgId: message.replyMsgId,
      replyPreview: message.replyPreview,
      replySenderName: message.replySenderName,
      localPath: message.localPath,
      atUserIds: message.atUserIds,
    );

    _provider._noteIncomingMention(message);

    debugPrint('📥[ChatProvider] 收到消息 fromId=${message.fromId} senderInfo=${senderInfo?.toJson()} groupInfo=${groupInfo?.toJson()}');

    // ✅ 只有当消息属于当前正在查看的会话时，才添加到消息列表
    // 否则由 EventBus 的 MessageReceivedEvent 处理器统一管理（刷新会话列表 + 触发通知）
    _provider._enqueueMedia([model]);
    if (_isMessageBelongsToCurrentConversation(message)) {
      _provider.receiveMessage(model);
    } else {
      debugPrint('📥[ChatProvider] 消息不属于当前会话，不加载到当前聊天页面（由EventBus处理）');
    }
  }

  @override
  void onMessageSent(sdk.Message message) {
    _provider.applySendConfirmation(message);
  }

  @override
  void onMessageRecalled(sdk.Message message) {}
}

class _RemoteMedia {
  final String key;
  final String url;
  final String name;
  final String localPath;

  const _RemoteMedia({
    required this.key,
    required this.url,
    required this.name,
    this.localPath = '',
  });
}
