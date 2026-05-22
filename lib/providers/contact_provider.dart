import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';

class ContactProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  List<UserModel> _contacts = [];
  List<UserModel> _searchResults = [];
  bool _isLoading = false;

  List<UserModel> get contacts => _contacts;
  List<UserModel> get searchResults => _searchResults;
  bool get isLoading => _isLoading;

  Future<void> loadContacts() async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _apiService.getContacts();
      _contacts = data.map((json) => UserModel.fromJson(json)).toList();
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

    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.searchUsers(keyword);
      final usersData = response['users'] as List<dynamic>? ?? [];
      _searchResults =
          usersData.map((json) => UserModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint('搜索用户失败: $e');
      _searchResults = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearSearchResults() {
    _searchResults = [];
    notifyListeners();
  }
}
