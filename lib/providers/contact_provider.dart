import 'package:flutter/foundation.dart';
import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart' as sdk;
import 'package:cao_im_sdk_flutter/event/event_bus.dart';
import 'package:cao_im_sdk_flutter/event/im_event.dart';
import '../models/user_model.dart';
import '../models/contact_info_model.dart';
import '../services/api_service.dart';
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
  bool _isLoading = false;
  bool _isListening = false;

  final Map<int, ContactInfo> _contactCache = {};
  bool _isCacheInitialized = false;

  List<UserModel> get contacts => _contacts;
  List<UserModel> get searchResults => _searchResults;
  List<Map<String, dynamic>> get friendRequests => _friendRequests;
  int get unreadFriendRequestCount => _unreadFriendRequestCount;
  bool get isLoading => _isLoading;

  Map<int, ContactInfo> get contactCache => Map.unmodifiable(_contactCache);

  Map<String, List<UserModel>> get groupedContacts {
    final Map<String, List<UserModel>> grouped = {};
    for (final contact in _contacts) {
      final initial = _getPinyinInitial(contact.nickname.isNotEmpty ? contact.nickname : contact.username);
      if (!grouped.containsKey(initial)) {
        grouped[initial] = [];
      }
      grouped[initial]!.add(contact);
    }

    final sortedKeys = grouped.keys.toList()..sort();
    return Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, grouped[key]!)),
    );
  }

  String _getPinyinInitial(String name) {
    if (name.isEmpty) return '#';

    final firstChar = name[0];
    final codeUnit = firstChar.codeUnitAt(0);

    if (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) {
      return firstChar.toUpperCase();
    } else if (codeUnit >= 0x41 && codeUnit <= 0x5A) {
      return firstChar;
    } else if (codeUnit >= 0x61 && codeUnit <= 0x7A) {
        return firstChar.toUpperCase();
    } else {
      return '#';
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

        _contacts = await loadContactsFromLocal();

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

      final contactId = int.tryParse(contact.id);
      if (contactId != null && contactId > 0) {
        final contactInfo = ContactInfo(
          id: contactId,
          username: contact.username,
          nickname: contact.nickname,
          avatar: contact.avatar ?? '',
          remark: '',
        );
        updateCache(contactInfo);

        // 触发联系人变更事件
        _eventBus.fire(ContactDataChangedEvent(
          contactId: contactId,
          changeType: 'added',
        ));
        debugPrint('📍[ContactProvider] 📢 已触发 ContactDataChangedEvent (added), contactId=$contactId');
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

      final id = int.tryParse(contactId);
      if (id != null && id > 0) {
        removeFromCache(id);

        // 触发联系人变更事件
        _eventBus.fire(ContactDataChangedEvent(
          contactId: id,
          changeType: 'deleted',
        ));
        debugPrint('📍[ContactProvider] 📢 已触发 ContactDataChangedEvent (deleted), contactId=$id');
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
      debugPrint('🔍 搜索关键词: $keyword');
      debugPrint('🔍 服务端返回 ${allResults.length} 条结果');
      for (final u in allResults) {
        debugPrint('🔍   用户: id=${u.id}, username=${u.username}, friendStatus=${u.friendStatus}');
      }
      _searchResults = allResults;
      debugPrint('🔍 最终结果数: ${_searchResults.length}');
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

  Future<void> sendFriendRequest(int friendId) async {
    try {
      final imUserIdStr = await StorageService.getImUserId();
      if (imUserIdStr == null) return;

      final userId = int.tryParse(imUserIdStr);
      if (userId == null) return;

      await _apiService.sendFriendRequest(userId, friendId);
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
    return UserModel(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ??
          json['friendUsername']?.toString() ?? '',
      nickname: json['nickname']?.toString() ??
          json['friendNickname']?.toString() ?? '',
      avatar: json['avatar'] ?? json['friendAvatar'],
      email: json['email'],
      phone: json['phone'],
      imUserId: json['contactUserId']?.toString() ?? json['friendId']?.toString(),
    );
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
      _calculateUnreadCount();
    } catch (e) {
      debugPrint('加载好友请求失败: $e');
    } finally {
      notifyListeners();
    }
  }

  void _calculateUnreadCount() async {
    final imUserIdStr = await StorageService.getImUserId();
    if (imUserIdStr == null) return;

    final currentUserId = int.tryParse(imUserIdStr) ?? 0;
    int count = 0;

    for (final request in _friendRequests) {
      final status = request['status']?.toString() ?? '0';
      final userId = request['userId'];

      if (status == '0' && userId != currentUserId) {
        count++;
      }
    }

    if (_unreadFriendRequestCount != count) {
      _unreadFriendRequestCount = count;
      notifyListeners();
    }
  }

  void markFriendRequestsAsRead() {
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

      await _apiService.acceptFriendRequest(friendId, userId);

      final newContact = await _fetchAndConvertFriend(friendId.toString());
      if (newContact != null) {
        await addContactToLocal(newContact);
      }

      await loadFriendRequests();
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

      final newContact = await _fetchAndConvertFriend(friendId);
      if (newContact != null) {
        await addContactToLocal(newContact);
      }

      await loadFriendRequests();
    } catch (e) {
      debugPrint('接受好友请求失败（字符串ID）: $e');
      rethrow;
    }
  }

  Future<UserModel?> _fetchAndConvertFriend(String friendId) async {
    try {
      final imUserIdStr = await StorageService.getImUserId();
      if (imUserIdStr == null) return null;

      final userId = int.tryParse(imUserIdStr);
      if (userId == null) return null;

      final data = await _apiService.getFriendList(userId);
      final friendData = data.firstWhere(
        (json) {
          final jsonMap = json as Map<String, dynamic>;
          return jsonMap['friendId']?.toString() == friendId ||
              jsonMap['id']?.toString() == friendId;
        },
        orElse: () => null,
      );

      if (friendData != null) {
        return _convertFriendToUserModel(friendData as Map<String, dynamic>);
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

      await _apiService.rejectFriendRequest(friendId, userId);
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
    _imClient.addFriendRequestListener(_ContactFriendRequestListener(this));
    _isListening = true;
  }

  void stopListening() {
    _imClient.removeFriendRequestListener(_ContactFriendRequestListener(this));
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
    _contactCache[contact.id] = contact;
    debugPrint('💾 updateCache: 已更新缓存 id=${contact.id}, nickname=${contact.nickname}, 当前缓存总数: ${_contactCache.length}');
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
}

class _ContactFriendRequestListener implements sdk.FriendRequestListener {
  final ContactProvider _provider;

  _ContactFriendRequestListener(this._provider);

  @override
  void onFriendRequestReceived(int fromId, int toId) {
    debugPrint('🔔 收到好友请求通知: fromId=$fromId, toId=$toId');
    _provider._unreadFriendRequestCount++;
    _provider.loadFriendRequests();
  }

  @override
  void onFriendAccepted(int fromId, int toId) {
    debugPrint('✅ 收到好友接受通知: fromId=$fromId (同意者), toId=$toId (你)');
    _provider.loadContacts();
    _provider.loadFriendRequests();
  }

  @override
  void onFriendRejected(int fromId, int toId) {
    debugPrint('❌ 收到好友拒绝通知: fromId=$fromId (拒绝者), toId=$toId (你)');
    _provider.loadFriendRequests();
  }
}
