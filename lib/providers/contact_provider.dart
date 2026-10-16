import 'package:flutter/material.dart';
import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart' as sdk;
import 'package:cao_im_sdk_flutter/event/event_bus.dart';
import 'package:cao_im_sdk_flutter/event/im_event.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../models/contact_info_model.dart';
import '../providers/layout_provider.dart';
import '../router/app_router.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/contact_database_service.dart';

class ContactProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final ContactDatabaseService _dbService = ContactDatabaseService();
  final sdk.IMClient _imClient = sdk.IMClient.instance;
  final EventBus _eventBus = EventBus();
  List<UserModel> _contacts = [];
  List<UserModel> _searchResults = [];
  List<Map<String, dynamic>> _friendRequests = [];
  int _unreadFriendRequestCount = 0;
  final Set<String> _seenFriendRequestIds = {};
  bool _isLoading = false;
  bool _isListening = false;
  _ContactFriendRequestListener? _friendRequestListener;

  /// 点击「查看」时切到通讯录。由首页注入。
  VoidCallback? onOpenContacts;

  final Map<int, ContactInfo> _contactCache = {};
  bool _isCacheInitialized = false;

  List<UserModel> get contacts => _contacts;
  List<UserModel> get searchResults => _searchResults;
  List<Map<String, dynamic>> get friendRequests => _friendRequests;
  int get unreadFriendRequestCount => _unreadFriendRequestCount;
  bool get isLoading => _isLoading;

  Map<int, ContactInfo> get contactCache => Map.unmodifiable(_contactCache);

  /// 固定的索引顺序：# + A~Z
  static final List<String> _indexLetters = ['#', ...List.generate(26, (i) => String.fromCharCode(65 + i))];

  Map<String, List<UserModel>> get groupedContacts {
    final Map<String, List<UserModel>> grouped = {};
    // 初始化所有索引项
    for (final letter in _indexLetters) {
      grouped[letter] = [];
    }
    for (final contact in _contacts) {
      final initial = _getPinyinInitial(contact.displayName);
      grouped[initial]!.add(contact);
    }
    // 移除空的索引项（保留 # 即使为空也显示）
    grouped.removeWhere((key, value) => value.isEmpty && key != '#');
    return grouped;
  }

  String _getPinyinInitial(String name) {
    if (name.isEmpty) return '#';

    final firstChar = name[0];
    final codeUnit = firstChar.codeUnitAt(0);

    if (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) {
      // 中文 → 转拼音取首字母大写
      final shortPinyin = PinyinHelper.getShortPinyin(name);
      // 取第一个拼音首字母（去除非字母字符）
      for (final char in shortPinyin.split('')) {
        if (RegExp(r'[a-zA-Z]').hasMatch(char)) {
          return char.toUpperCase();
        }
      }
      return '#';
    } else if (codeUnit >= 0x41 && codeUnit <= 0x5A) {
      return firstChar; // 大写英文直接用
    } else if (codeUnit >= 0x61 && codeUnit <= 0x7A) {
      return firstChar.toUpperCase(); // 小写英文转大写
    } else {
      return '#'; // 数字/符号归入 #
    }
  }

  Future<void> loadContacts() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _initDatabaseIfNeeded();

      final localContacts = await loadContactsFromLocal();
      if (localContacts.isNotEmpty) {
        _contacts = localContacts;
        debugPrint('📱 从本地数据库加载了 ${_contacts.length} 个联系人');
        notifyListeners();
      }

      syncContactsFromServer().then((_) {
        debugPrint('🔄 后台同步完成');
      }).catchError((e) {
        debugPrint('⚠️ 后台同步失败（使用本地数据）: $e');
      });
    } catch (e) {
      debugPrint('加载联系人失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _initDatabaseIfNeeded() async {
    try {
      final imUserIdStr = await StorageService.getImUserId();
      if (imUserIdStr == null) return;

      final userId = int.tryParse(imUserIdStr);
      if (userId == null || userId <= 0) return;

      await _dbService.init(userId: userId);
      debugPrint('✅ 数据库初始化完成 (userId=$userId)');
    } catch (e) {
      debugPrint('⚠️ 数据库初始化失败: $e');
    }
  }

  Future<void> syncContactsFromServer() async {
    try {
      final imUserIdStr = await StorageService.getImUserId();
      if (imUserIdStr == null) return;

      final userId = int.tryParse(imUserIdStr);
      if (userId == null) return;

      final data = await _apiService.getFriendList(userId);
      final serverContacts = data
          .map((json) => _convertFriendToUserModel(json as Map<String, dynamic>))
          .toList();

      if (serverContacts.isNotEmpty) {
        await _dbService.upsertContacts(serverContacts);
        debugPrint('🔄 已从服务器同步 ${serverContacts.length} 个联系人到本地数据库');

        // 本地库暂无 isTop/isMute 列，内存列表保留服务端标记，并写回私聊会话
        final localContacts = await loadContactsFromLocal();
        final flagById = {
          for (final c in serverContacts)
            (int.tryParse(c.imUserId ?? c.id) ?? 0): c,
        };
        _contacts = localContacts.map((local) {
          final id = int.tryParse(local.imUserId ?? local.id) ?? 0;
          final server = flagById[id];
          if (server == null) return local;
          return local.copyWith(
            remark: server.remark,
            isTop: server.isTop,
            isMute: server.isMute,
          );
        }).toList();

        await _syncPrivateConversationFlags(serverContacts);

        clearCache();
        final allContactIds = _contacts.map((c) => int.tryParse(c.id) ?? 0).where((id) => id > 0).toList();
        if (allContactIds.isNotEmpty) {
          await batchLoadContactsToCache(allContactIds);
        }

        // 触发联系人变更事件（同步完成）
        _eventBus.fire(ContactDataChangedEvent(
          changeType: 'synced',
        ));
        debugPrint('📍[ContactProvider] 📢 已触发 ContactDataChangedEvent (synced), 同步了 ${serverContacts.length} 个联系人');

        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ 从服务器同步联系人失败: $e');
      rethrow;
    }
  }

  /// 进入用户主页时拉取服务器上的最新昵称和头像，并写回本地联系人。
  Future<UserModel?> refreshContactFromServer(int imUserId) async {
    if (imUserId <= 0) return null;
    try {
      final data = await _apiService.getImUser(imUserId);
      if (data == null) return null;
      final user = UserModel(
        id: imUserId.toString(),
        username: data['username']?.toString() ?? '',
        nickname: data['nickname']?.toString() ?? '',
        avatar: data['avatar']?.toString(),
        phone: data['phone']?.toString(),
        email: data['email']?.toString(),
        imUserId: imUserId.toString(),
      );

      await _initDatabaseIfNeeded();
      final existing = await _dbService.getContactByUserId(imUserId);
      if (existing != null) {
        await _dbService.updateContactProfile(
          imUserId,
          nickname: user.nickname,
          avatar: user.avatar ?? '',
        );
      } else {
        await _dbService.upsertContacts([user]);
      }

      final index = _contacts.indexWhere(
        (c) => c.imUserId == user.imUserId || c.id == user.id,
      );
      if (index != -1) {
        final previous = _contacts[index];
        _contacts[index] = user.copyWith(
          id: previous.id,
          phone: user.phone ?? previous.phone,
          email: user.email ?? previous.email,
          remark: previous.remark,
          isTop: previous.isTop,
          isMute: previous.isMute,
        );
      }
      updateCache(ContactInfo(
        id: 0,
        userId: imUserId,
        username: user.username,
        nickname: user.nickname,
        avatar: user.avatar ?? '',
        remark: index != -1 ? _contacts[index].remark : '',
        isTop: index != -1 ? _contacts[index].isTop : false,
        isMute: index != -1 ? _contacts[index].isMute : false,
      ));
      _eventBus.fire(ContactDataChangedEvent(
        contactId: imUserId,
        changeType: 'updated',
      ));
      notifyListeners();
      return index != -1 ? _contacts[index] : user;
    } catch (e) {
      debugPrint('❌ 刷新用户资料失败: userId=$imUserId, error=$e');
      return null;
    }
  }

  Future<List<UserModel>> loadContactsFromLocal() async {
    try {
      final contacts = await _dbService.getAllContacts();
      debugPrint('📖 从本地数据库读取 ${contacts.length} 个联系人');
      return contacts;
    } catch (e) {
      debugPrint('❌ 从本地数据库加载联系人失败: $e');
      return [];
    }
  }

  Future<void> addContactToLocal(UserModel contact) async {
    try {
      await _dbService.upsertContacts([contact]);
      debugPrint('➕ 联系人已添加到本地: ${contact.nickname} (${contact.id})');

      final existingIndex = _contacts.indexWhere((c) => c.id == contact.id);
      if (existingIndex != -1) {
        _contacts[existingIndex] = contact;
      } else {
        _contacts.add(contact);
      }

      // 业务键必须是 IM 用户 ID（优先 imUserId，避免误用联系人表主键）
      final userId = int.tryParse(contact.imUserId ?? '') ?? int.tryParse(contact.id) ?? 0;
      if (userId > 0) {
        final contactInfo = ContactInfo(
          id: 0,  // 本地自增ID，此处无法获取，由数据库填充
          userId: userId,
          username: contact.username,
          nickname: contact.nickname,
          avatar: contact.avatar ?? '',
          remark: '',
        );
        updateCache(contactInfo);

        // 触发联系人变更事件
        _eventBus.fire(ContactDataChangedEvent(
          contactId: userId,
          changeType: 'added',
        ));
        debugPrint('📍[ContactProvider] 📢 已触发 ContactDataChangedEvent (added), userId=$userId');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ 添加联系人到本地数据库失败: $e');
      rethrow;
    }
  }

  Future<void> deleteContactFromLocal(String contactId) async {
    try {
      await _dbService.deleteContact(contactId);
      debugPrint('🗑️ 已从本地数据库删除联系人: $contactId');

      _contacts.removeWhere((c) => c.id == contactId);

      final userId = int.tryParse(contactId);
      if (userId != null && userId > 0) {
        removeFromCache(userId);

        // 触发联系人变更事件
        _eventBus.fire(ContactDataChangedEvent(
          contactId: userId,
          changeType: 'deleted',
        ));
        debugPrint('📍[ContactProvider] 📢 已触发 ContactDataChangedEvent (deleted), userId=$userId');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ 从本地数据库删除联系人失败: $e');
      rethrow;
    }
  }

  Future<void> deleteFriend(String contactId) async {
    try {
      final imUserIdStr = await StorageService.getImUserId();
      if (imUserIdStr == null) return;

      final userId = int.tryParse(imUserIdStr);
      if (userId == null) return;

      final friendIdInt = int.tryParse(contactId);
      if (friendIdInt == null) return;

      await _apiService.deleteFriend(userId, friendIdInt);
      debugPrint('🗑️ 已从服务器删除好友: $contactId');

      await deleteContactFromLocal(contactId);
    } catch (e) {
      debugPrint('❌ 删除好友失败: $e');
      rethrow;
    }
  }

  Future<void> searchUsers(String keyword) async {
    if (keyword.isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    try {
      final userIdStr = await StorageService.getUserId();
      if (userIdStr == null) return;

      final data = await _apiService.searchUsers(keyword);
      final allResults = data
          .map((json) => UserModel.fromJson(json as Map<String, dynamic>))
          .toList();
      _searchResults = allResults;
      debugPrint('🔍 搜索关键词:$keyword | 返回${allResults.length}条结果 | 用户列表:[${allResults.map((u) => 'id:${u.id},username:${u.username},status:${u.friendStatus}').join('; ')}] | 最终结果数:${_searchResults.length}');
    } catch (e) {
      debugPrint('搜索用户失败: $e');
      _searchResults = [];
    } finally {
      notifyListeners();
    }
  }

  void updateSearchResultFriendStatus(String friendId, int status) {
    final index = _searchResults.indexWhere((u) => u.id == friendId);
    if (index != -1) {
      _searchResults[index] = _searchResults[index].copyWith(friendStatus: status);
      notifyListeners();
    }
  }

  Future<void> sendFriendRequest(int friendId, {int source = 0}) async {
    try {
      final imUserIdStr = await StorageService.getImUserId();
      if (imUserIdStr == null) return;

      final userId = int.tryParse(imUserIdStr);
      if (userId == null) return;

      await _apiService.sendFriendRequest(userId, friendId, source: source);
    } catch (e) {
      debugPrint('发送好友请求失败: $e');
      rethrow;
    }
  }

  Future<void> sendFriendRequestWithString(String friendId) async {
    try {
      final imUserIdStr = await StorageService.getImUserId();
      if (imUserIdStr == null) return;

      await _apiService.sendFriendRequestWithString(imUserIdStr, friendId);
    } catch (e) {
      debugPrint('发送好友请求失败（字符串ID）: $e');
      rethrow;
    }
  }

  UserModel _convertFriendToUserModel(Map<String, dynamic> json) {
    // contactUserId / friendId 才是对方 IM 用户 ID；id 多为联系人表主键，不能当业务键
    final imUserId = json['contactUserId']?.toString() ??
        json['friendId']?.toString() ??
        json['id']?.toString() ??
        '';
    return UserModel(
      id: imUserId,
      username: json['username']?.toString() ??
          json['friendUsername']?.toString() ?? '',
      nickname: json['nickname']?.toString() ??
          json['friendNickname']?.toString() ?? '',
      avatar: json['avatar'] ?? json['friendAvatar'],
      email: json['email'],
      phone: json['phone'],
      imUserId: imUserId,
      remark: json['remark']?.toString() ?? '',
      isTop: json['isTop'] == true || json['isTop'] == 1,
      isMute: json['isMute'] == true || json['isMute'] == 1,
    );
  }

  /// 更新好友备注，并写回本地缓存
  Future<UserModel?> updateRemark(int contactUserId, String remark) async {
    final imUserIdStr = await StorageService.getImUserId();
    final userId = int.tryParse(imUserIdStr ?? '');
    if (userId == null || contactUserId <= 0) return null;

    await _apiService.updateContactRemark(userId, contactUserId, remark);
    await _initDatabaseIfNeeded();
    await _dbService.updateContactRemark(contactUserId, remark);

    final updated = _patchContact(contactUserId, (c) => c.copyWith(remark: remark));
    if (updated != null) {
      _contactCache[contactUserId] = ContactInfo(
        id: _contactCache[contactUserId]?.id ?? 0,
        userId: contactUserId,
        username: updated.username,
        nickname: updated.nickname,
        avatar: updated.avatar ?? '',
        remark: remark,
        isTop: updated.isTop,
        isMute: updated.isMute,
      );
      _eventBus.fire(ContactDataChangedEvent(changeType: 'remark'));
      notifyListeners();
    }
    return updated;
  }

  /// 设置联系人置顶（同步服务端）
  Future<UserModel?> setContactTop(int contactUserId, bool isTop) async {
    final imUserIdStr = await StorageService.getImUserId();
    final userId = int.tryParse(imUserIdStr ?? '');
    if (userId == null || contactUserId <= 0) return null;

    await _apiService.setContactTop(userId, contactUserId, isTop);
    final updated = _patchContact(contactUserId, (c) => c.copyWith(isTop: isTop));
    notifyListeners();
    return updated;
  }

  /// 设置联系人免打扰（同步服务端）
  Future<UserModel?> setContactMute(int contactUserId, bool isMute) async {
    final imUserIdStr = await StorageService.getImUserId();
    final userId = int.tryParse(imUserIdStr ?? '');
    if (userId == null || contactUserId <= 0) return null;

    await _apiService.setContactMute(userId, contactUserId, isMute);
    final updated = _patchContact(contactUserId, (c) => c.copyWith(isMute: isMute));
    notifyListeners();
    return updated;
  }

  /// 把会话或内存联系人里的置顶、免打扰、备注补到资料对象上。
  /// 传入的会话标记优先，避免资料页用空的 UserModel 把开关显示成关闭。
  UserModel mergeRelationState(
    UserModel user, {
    bool? isTop,
    bool? isMute,
  }) {
    final id = int.tryParse(user.imUserId ?? user.id) ?? 0;
    UserModel? known;
    for (final contact in _contacts) {
      final contactId = int.tryParse(contact.imUserId ?? contact.id) ?? 0;
      if (contactId == id && id > 0) {
        known = contact;
        break;
      }
    }
    return user.copyWith(
      remark: user.remark.isNotEmpty ? user.remark : (known?.remark ?? ''),
      isTop: isTop ?? known?.isTop ?? user.isTop,
      isMute: isMute ?? known?.isMute ?? user.isMute,
    );
  }

  UserModel? _patchContact(int contactUserId, UserModel Function(UserModel) patch) {
    final index = _contacts.indexWhere(
      (c) => c.imUserId == contactUserId.toString() || c.id == contactUserId.toString(),
    );
    if (index == -1) return null;
    final updated = patch(_contacts[index]);
    _contacts[index] = updated;
    return updated;
  }

  /// 拉黑用户
  Future<void> blockUser(int targetUserId) async {
    final imUserIdStr = await StorageService.getImUserId();
    final userId = int.tryParse(imUserIdStr ?? '');
    if (userId == null || targetUserId <= 0) return;
    await _apiService.blockUser(userId, targetUserId);
    notifyListeners();
  }

  /// 解除拉黑
  Future<void> unblockUser(int targetUserId) async {
    final imUserIdStr = await StorageService.getImUserId();
    final userId = int.tryParse(imUserIdStr ?? '');
    if (userId == null || targetUserId <= 0) return;
    await _apiService.unblockUser(userId, targetUserId);
    notifyListeners();
  }

  /// 是否已拉黑
  Future<bool> isBlocked(int targetUserId) async {
    final imUserIdStr = await StorageService.getImUserId();
    final userId = int.tryParse(imUserIdStr ?? '');
    if (userId == null || targetUserId <= 0) return false;
    return _apiService.isBlocked(userId, targetUserId);
  }

  /// 将联系人置顶/免打扰同步到对应私聊会话
  Future<void> _syncPrivateConversationFlags(List<UserModel> contacts) async {
    try {
      for (final contact in contacts) {
        final targetId = int.tryParse(contact.imUserId ?? contact.id) ?? 0;
        if (targetId <= 0) continue;
        final conv = await _imClient.getOrCreateConversation(
          targetType: sdk.TargetType.private.value,
          targetId: targetId,
        );
        if (conv.id == null || conv.id! <= 0) continue;
        if (conv.isTop != contact.isTop) {
          await _imClient.setConversationTop(conv.id!, contact.isTop);
        }
        if (conv.isMute != contact.isMute) {
          await _imClient.setConversationMute(conv.id!, contact.isMute);
        }
      }
    } catch (e) {
      debugPrint('⚠️ 同步私聊会话置顶/免打扰失败: $e');
    }
  }

  void clearSearchResults() {
    _searchResults = [];
    notifyListeners();
  }

  Future<void> loadFriendRequests() async {
    try {
      final imUserIdStr = await StorageService.getImUserId();
      if (imUserIdStr == null) return;

      final userId = int.tryParse(imUserIdStr);
      if (userId == null) return;

      final data = await _apiService.getFriendRequests(userId);
      _friendRequests = data
          .map((json) => json as Map<String, dynamic>)
          .toList();
      _calculateUnreadCount(userId);
    } catch (e) {
      debugPrint('加载好友请求失败: $e');
    } finally {
      notifyListeners();
    }
  }

  void _calculateUnreadCount(int currentUserId) {
    int count = 0;

    for (final request in _friendRequests) {
      if (!_isIncomingPending(request, currentUserId)) continue;
      if (_seenFriendRequestIds.contains(_friendRequestKey(request))) continue;
      count++;
    }

    if (_unreadFriendRequestCount != count) {
      _unreadFriendRequestCount = count;
      notifyListeners();
    }
  }

  bool _isIncomingPending(Map<String, dynamic> request, int currentUserId) {
    final status = request['status']?.toString() ?? '0';
    final toUserId = int.tryParse(request['toUserId']?.toString() ?? '');
    return status == '0' && toUserId == currentUserId;
  }

  String _friendRequestKey(Map<String, dynamic> request) {
    final id = request['id']?.toString();
    if (id != null && id.isNotEmpty) return id;
    return '${request['fromUserId']}_${request['createTime']}';
  }

  String _requesterName(int fromId) {
    for (final request in _friendRequests) {
      if (request['fromUserId']?.toString() != fromId.toString()) continue;
      final nickname = request['fromNickname']?.toString() ?? '';
      if (nickname.isNotEmpty) return nickname;
      final username = request['fromUsername']?.toString() ?? '';
      if (username.isNotEmpty) return username;
    }
    return '用户$fromId';
  }

  /// 实时收到好友申请：刷新列表、点亮未读，并弹出可点击的提示。
  Future<void> handleIncomingFriendRequest(int fromId) async {
    await loadFriendRequests();

    var matched = false;
    for (final request in _friendRequests) {
      if (request['fromUserId']?.toString() != fromId.toString()) continue;
      if ((request['status']?.toString() ?? '0') != '0') continue;
      _seenFriendRequestIds.remove(_friendRequestKey(request));
      matched = true;
    }

    final currentUserId = int.tryParse(await StorageService.getImUserId() ?? '');
    if (currentUserId != null) {
      _calculateUnreadCount(currentUserId);
    }
    if (!matched) {
      _unreadFriendRequestCount += 1;
      notifyListeners();
    }

    _presentFriendRequestNotice(_requesterName(fromId));
  }

  void _presentFriendRequestNotice(String name) {
    final context = AppRouter.navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name 请求添加你为好友'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: '查看',
            onPressed: () {
              onOpenContacts?.call();
              context.read<LayoutProvider>().selectNavigation(1);
            },
          ),
        ),
      );
    }

    NotificationService().showMessageNotification(
      NotificationData(
        senderId: 0,
        nickname: name,
        content: '请求添加你为好友',
        time: DateTime.now(),
        targetId: -1,
      ),
    );
  }

  void markFriendRequestsAsRead() {
    for (final request in _friendRequests) {
      final status = request['status']?.toString() ?? '0';
      if (status == '0') {
        _seenFriendRequestIds.add(_friendRequestKey(request));
      }
    }
    if (_unreadFriendRequestCount > 0) {
      _unreadFriendRequestCount = 0;
      notifyListeners();
    }
  }

  Future<void> acceptFriendRequest(int friendId) async {
    try {
      final imUserIdStr = await StorageService.getImUserId();
      if (imUserIdStr == null) return;

      final userId = int.tryParse(imUserIdStr);
      if (userId == null) return;

      await _apiService.acceptFriendRequest(userId, friendId);
      await _finalizeAcceptedFriend(friendId.toString());
    } catch (e) {
      debugPrint('接受好友请求失败: $e');
      rethrow;
    }
  }

  Future<void> acceptFriendRequestWithString(String friendId) async {
    try {
      final imUserIdStr = await StorageService.getImUserId();
      if (imUserIdStr == null) return;

      await _apiService.acceptFriendRequestWithString(imUserIdStr, friendId);
      await _finalizeAcceptedFriend(friendId);
    } catch (e) {
      debugPrint('接受好友请求失败（字符串ID）: $e');
      rethrow;
    }
  }

  /// 同意后：落本地联系人 + 本端创建会话（对端靠 friend_accepted 推送创建）
  Future<void> _finalizeAcceptedFriend(String friendId) async {
    final newContact = await _fetchAndConvertFriend(friendId);
    if (newContact != null) {
      await addContactToLocal(newContact);
    } else {
      await syncContactsFromServer();
    }

    final peerId = int.tryParse(friendId);
    if (peerId != null && peerId > 0) {
      await _imClient.createAcceptedFriendConversation(peerId);
    }

    await loadFriendRequests();
  }

  /// 申请方收到「对方已同意」：同步联系人，补全会话昵称
  Future<void> handlePeerAcceptedFriendship(int friendId) async {
    try {
      final newContact = await _fetchAndConvertFriend(friendId.toString());
      if (newContact != null) {
        await addContactToLocal(newContact);
      } else {
        await syncContactsFromServer();
      }
      await loadFriendRequests();
    } catch (e) {
      debugPrint('⚠️ 处理好友同意通知失败: $e');
      loadContacts();
      loadFriendRequests();
    }
  }

  Future<UserModel?> _fetchAndConvertFriend(String friendId) async {
    try {
      final imUserIdStr = await StorageService.getImUserId();
      if (imUserIdStr == null) return null;

      final userId = int.tryParse(imUserIdStr);
      if (userId == null) return null;

      final data = await _apiService.getFriendList(userId);
      for (final json in data) {
        if (json is! Map) continue;
        final jsonMap = Map<String, dynamic>.from(json);
        final peerId = jsonMap['contactUserId']?.toString() ??
            jsonMap['friendId']?.toString() ??
            '';
        if (peerId == friendId) {
          return _convertFriendToUserModel(jsonMap);
        }
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ 获取新好友信息失败: $e');
      return null;
    }
  }

  Future<void> rejectFriendRequest(int friendId) async {
    try {
      final imUserIdStr = await StorageService.getImUserId();
      if (imUserIdStr == null) return;

      final userId = int.tryParse(imUserIdStr);
      if (userId == null) return;

      await _apiService.rejectFriendRequest(userId, friendId);
      await loadFriendRequests();
    } catch (e) {
      debugPrint('拒绝好友请求失败: $e');
      rethrow;
    }
  }

  Future<void> rejectFriendRequestWithString(String friendId) async {
    try {
      final imUserIdStr = await StorageService.getImUserId();
      if (imUserIdStr == null) return;

      await _apiService.rejectFriendRequestWithString(imUserIdStr, friendId);
      await loadFriendRequests();
    } catch (e) {
      debugPrint('拒绝好友请求失败（字符串ID）: $e');
      rethrow;
    }
  }

  Future<int> checkFriendStatus(int targetUserId) async {
    final imUserIdStr = await StorageService.getImUserId();
    if (imUserIdStr == null) return 0;

    final userId = int.tryParse(imUserIdStr);
    if (userId == null) return 0;

    return _apiService.checkFriendStatus(userId, targetUserId);
  }

  void startListening() {
    if (_isListening) return;
    _friendRequestListener = _ContactFriendRequestListener(this);
    _imClient.addFriendRequestListener(_friendRequestListener!);
    _isListening = true;
  }

  void stopListening() {
    final listener = _friendRequestListener;
    if (listener != null) {
      _imClient.removeFriendRequestListener(listener);
    }
    _friendRequestListener = null;
    _isListening = false;
  }

  ContactInfo? getContactFromCache(int id) {
    final contact = _contactCache[id];
    if (contact != null) {
      debugPrint('💾 缓存命中: id=$id, nickname=${contact.nickname}');
    } else {
      debugPrint('💾 缓存未命中: id=$id');
    }
    return contact;
  }

  Future<void> batchLoadContactsToCache(List<int> ids) async {
    if (ids.isEmpty) {
      debugPrint('💾 batchLoadContactsToCache: 传入空列表');
      return;
    }

    final uncachedIds = ids.where((id) => !_contactCache.containsKey(id)).toList();
    if (uncachedIds.isEmpty) {
      debugPrint('💾 batchLoadContactsToCache: 全部命中缓存 (${ids.length}/${ids.length})，无需查询数据库');
      return;
    }

    final hitCount = ids.length - uncachedIds.length;
    debugPrint('💾 batchLoadContactsToCache: 缓存命中率 ${hitCount}/${ids.length} (${(hitCount / ids.length * 100).toStringAsFixed(1)}%)');

    try {
      final contactsFromDb = await _dbService.getContactsByIds(uncachedIds);
      for (final entry in contactsFromDb.entries) {
        _contactCache[entry.key] = entry.value;
      }

      if (!_isCacheInitialized && _contactCache.isNotEmpty) {
        _isCacheInitialized = true;
      }

      debugPrint('💾 batchLoadContactsToCache: 从数据库加载 ${contactsFromDb.length} 个联系人到缓存，当前缓存总数: ${_contactCache.length}');
    } catch (e) {
      debugPrint('❌ batchLoadContactsToCache: 批量加载失败 - $e');
      rethrow;
    }
  }

  Future<ContactInfo?> getContactWithCache(int id) async {
    final cachedContact = getContactFromCache(id);
    if (cachedContact != null) {
      return cachedContact;
    }

    try {
      final contactsFromDb = await _dbService.getContactsByIds([id]);
      if (contactsFromDb.containsKey(id)) {
        final contact = contactsFromDb[id]!;
        _contactCache[id] = contact;

        if (!_isCacheInitialized) {
          _isCacheInitialized = true;
        }

        debugPrint('💾 getContactWithCache: 从数据库加载并缓存联系人 id=$id, 当前缓存总数: ${_contactCache.length}');
        return contact;
      }

      debugPrint('⚠️ getContactWithCache: 数据库中未找到联系人 id=$id');
      return null;
    } catch (e) {
      debugPrint('❌ getContactWithCache: 查询失败 - $e');
      rethrow;
    }
  }

  void updateCache(ContactInfo contact) {
    _contactCache[contact.userId] = contact;
    debugPrint('💾 updateCache: 已更新缓存 userId=${contact.userId}, nickname=${contact.nickname}, 当前缓存总数: ${_contactCache.length}');
  }

  void removeFromCache(int id) {
    final removed = _contactCache.remove(id);
    if (removed != null) {
      debugPrint('💾 removeFromCache: 已从缓存移除 id=$id, nickname=${removed.nickname}, 剩余缓存数: ${_contactCache.length}');
    } else {
      debugPrint('⚠️ removeFromCache: 缓存中未找到 id=$id');
    }
  }

  void clearCache() {
    final count = _contactCache.length;
    _contactCache.clear();
    _isCacheInitialized = false;
    debugPrint('💾 clearCache: 已清空缓存，共移除 $count 个联系人');
  }

  /// 重置所有状态（用于登出/切换账号时调用）
  Future<void> resetState() async {
    _contacts = [];
    _searchResults = [];
    _friendRequests = [];
    _unreadFriendRequestCount = 0;
    _seenFriendRequestIds.clear();
    clearCache();
    await _dbService.reset();
    debugPrint('📍[ContactProvider] ✓ 状态已重置（通讯录、搜索结果、好友请求、缓存、数据库）');
  }
}

class _ContactFriendRequestListener implements sdk.FriendRequestListener {
  final ContactProvider _provider;

  _ContactFriendRequestListener(this._provider);

  @override
  void onFriendRequestReceived(int fromId, int toId) {
    debugPrint('🔔 收到好友请求通知: fromId=$fromId, toId=$toId');
    _provider.handleIncomingFriendRequest(fromId);
  }

  @override
  void onFriendAccepted(int fromId, int toId) {
    debugPrint('✅ 收到好友接受通知: fromId=$fromId (同意者), toId=$toId (你)');
    // fromId=同意者，对申请方来说就是新好友；同步联系人以便会话显示真实昵称
    _provider.handlePeerAcceptedFriendship(fromId);
  }

  @override
  void onFriendRejected(int fromId, int toId) {
    debugPrint('❌ 收到好友拒绝通知: fromId=$fromId (拒绝者), toId=$toId (你)');
    _provider.loadFriendRequests();
  }
}
