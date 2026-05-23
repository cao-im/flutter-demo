import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class ContactProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  List<UserModel> _contacts = [];
  List<UserModel> _searchResults = [];
  List<Map<String, dynamic>> _friendRequests = [];
  bool _isLoading = false;

  List<UserModel> get contacts => _contacts;
  List<UserModel> get searchResults => _searchResults;
  List<Map<String, dynamic>> get friendRequests => _friendRequests;
  bool get isLoading => _isLoading;

  Future<void> loadContacts() async {
    _isLoading = true;
    notifyListeners();

    try {
      final userIdStr = await StorageService.getUserId();
      if (userIdStr == null) return;

      final userId = int.tryParse(userIdStr);
      if (userId == null) return;

      final data = await _apiService.getFriendList(userId);
      _contacts = data
          .map((json) => _convertFriendToUserModel(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('加载联系人失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
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
        debugPrint('🔍   用户: id=${u.id}, username=${u.username}');
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

  Future<void> sendFriendRequest(int friendId) async {
    try {
      final userIdStr = await StorageService.getUserId();
      if (userIdStr == null) return;

      final userId = int.tryParse(userIdStr);
      if (userId == null) return;

      await _apiService.sendFriendRequest(userId, friendId);
    } catch (e) {
      debugPrint('发送好友请求失败: $e');
      rethrow;
    }
  }

  UserModel _convertFriendToUserModel(Map<String, dynamic> json) {
    return UserModel(
      id: json['friendId']?.toString() ?? json['id']?.toString() ?? '',
      username: json['friendUsername']?.toString() ?? json['username']?.toString() ?? '',
      nickname: json['friendNickname']?.toString() ?? json['nickname']?.toString() ?? '',
      avatar: json['avatar'],
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
      final userIdStr = await StorageService.getUserId();
      if (userIdStr == null) return;

      final userId = int.tryParse(userIdStr);
      if (userId == null) return;

      final data = await _apiService.getFriendRequests(userId);
      _friendRequests = data
          .map((json) => json as Map<String, dynamic>)
          .toList();
    } catch (e) {
      debugPrint('加载好友请求失败: $e');
    } finally {
      notifyListeners();
    }
  }

  Future<void> acceptFriendRequest(int friendId) async {
    try {
      final userIdStr = await StorageService.getUserId();
      if (userIdStr == null) return;

      final userId = int.tryParse(userIdStr);
      if (userId == null) return;

      await _apiService.acceptFriendRequest(userId, friendId);
      await loadFriendRequests();
      await loadContacts();
    } catch (e) {
      debugPrint('接受好友请求失败: $e');
      rethrow;
    }
  }

  Future<void> rejectFriendRequest(int friendId) async {
    try {
      final userIdStr = await StorageService.getUserId();
      if (userIdStr == null) return;

      final userId = int.tryParse(userIdStr);
      if (userId == null) return;

      await _apiService.rejectFriendRequest(userId, friendId);
      await loadFriendRequests();
    } catch (e) {
      debugPrint('拒绝好友请求失败: $e');
      rethrow;
    }
  }
}
