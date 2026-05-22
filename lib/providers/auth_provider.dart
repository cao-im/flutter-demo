import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import 'connection_provider.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  UserModel? _user;
  bool _isLoading = false;
  String? _errorMessage;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  String? get errorMessage => _errorMessage;

  Future<bool> login(String username, String password, BuildContext context) async {
    _setLoading(true);
    _clearError();

    try {
      final response = await _apiService.login(username, password);
      final code = response['code'];
      final data = response['data'] as Map<String, dynamic>?;

      if (code == 200 && data != null) {
        final token = data['token'] as String?;
        final userData = data['user'] as Map<String, dynamic>?;

        if (token != null && userData != null) {
          await StorageService.saveToken(token);
          final user = UserModel.fromJson(userData);
          _user = user;
          await StorageService.saveUserId(user.id);
          await StorageService.saveUsername(user.username);

          final connectionProvider =
              context.read<ConnectionProvider>();
          if (connectionProvider.isInitialized) {
            await connectionProvider.connect(token);
          }

          notifyListeners();
          return true;
        }
      }
      _setError(response['message'] ?? '登录响应格式错误');
      return false;
    } catch (e) {
      _setError(e.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> register(
      String username, String password, String nickname) async {
    _setLoading(true);
    _clearError();

    try {
      final response =
          await _apiService.register(username, password, nickname);
      final code = response['code'];
      final data = response['data'] as Map<String, dynamic>?;

      if (code == 200 && data != null) {
        final token = data['token'] as String?;
        final userData = data['user'] as Map<String, dynamic>?;

        if (token != null && userData != null) {
          await StorageService.saveToken(token);
          final user = UserModel.fromJson(userData);
          _user = user;
          await StorageService.saveUserId(user.id);
          await StorageService.saveUsername(user.username);
        }

        notifyListeners();
        return true;
      }
      _setError(response['message'] ?? '注册失败');
      return false;
    } catch (e) {
      _setError(e.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadUserFromStorage(BuildContext context) async {
    final token = await StorageService.getToken();
    if (token != null && token.isNotEmpty) {
      final userId = await StorageService.getUserId();
      if (userId != null) {
        try {
          final user = await _apiService.getUserInfo(userId);
          _user = user;

          final connectionProvider =
              context.read<ConnectionProvider>();
          if (connectionProvider.isInitialized && !connectionProvider.isConnected) {
            await connectionProvider.connect(token);
          }

          notifyListeners();
        } catch (e) {
          debugPrint('加载用户信息失败: $e');
          await logout(context);
        }
      }
    }
  }

  Future<void> logout(BuildContext context) async {
    final connectionProvider =
        context.read<ConnectionProvider>();
    if (connectionProvider.isConnected) {
      await connectionProvider.disconnect();
    }

    await StorageService.clearAll();
    _user = null;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }
}
