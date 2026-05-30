import 'package:flutter/foundation.dart';
import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart' as sdk;
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/contact_database_service.dart';

class ContactProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final ContactDatabaseService _dbService = ContactDatabaseService();
  final sdk.IMClient _imClient = sdk.IMClient.instance;
  List<UserModel> _contacts = [];
  List<UserModel> _searchResults = [];
  List<Map<String, dynamic>> _friendRequests = [];
  int _unreadFriendRequestCount = 0;
  bool _isLoading = false;
  bool _isListening = false;

  List<UserModel> get contacts => _contacts;
  List<UserModel> get searchResults => _searchResults;
  List<Map<String, dynamic>> get friendRequests => _friendRequests;
  int get unreadFriendRequestCount => _unreadFriendRequestCount;
  bool get isLoading => _isLoading;

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
      id: json['friendId']?.toString() ?? json['id']?.toString() ?? '',
      username: json['username']?.toString() ??
          json['friendUsername']?.toString() ?? '',
      nickname: json['nickname']?.toString() ??
          json['friendNickname']?.toString() ?? '',
      avatar: json['avatar'] ?? json['friendAvatar'],
      email: json['email'],
      phone: json['phone'],
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
