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
          final imToken = data['imToken'] as String?;
          if (imToken != null) {
            await StorageService.saveImToken(imToken);
          }
          final user = UserModel.fromJson(userData);
          _user = user;
          await StorageService.saveUserId(user.id);
          await StorageService.saveUsername(user.username);

          final connectionProvider =
              context.read<ConnectionProvider>();
          if (connectionProvider.isInitialized) {
            final connectToken = imToken ?? token;
            await connectionProvider.connect(connectToken, userId: int.tryParse(user.id) ?? 0);
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
          final imToken = data['imToken'] as String?;
          if (imToken != null) {
            await StorageService.saveImToken(imToken);
          }
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
    debugPrint('');
    debugPrint('📍[AuthProvider] ====== loadUserFromStorage() 开始 ======');

    final token = await StorageService.getToken();
    final imToken = await StorageService.getImToken();
    debugPrint('📍[AuthProvider] token: ${token != null ? "有 (长度=${token.length})" : "无"}');
    debugPrint('📍[AuthProvider] imToken: ${imToken != null ? "有 (长度=${imToken.length})" : "无"}');

    if (token != null && token.isNotEmpty) {
      final userId = await StorageService.getUserId();
      debugPrint('📍[AuthProvider] userId: $userId');

      if (userId != null) {
        try {
          debugPrint('📍[AuthProvider] 调用 getUserInfo($userId)...');
          final user = await _apiService.getUserInfo(userId);
          _user = user;
          debugPrint('✅[AuthProvider] 用户信息获取成功: ${user.username}');

          final connectionProvider =
              context.read<ConnectionProvider>();
          debugPrint('📍[AuthProvider] isInitialized=${connectionProvider.isInitialized}, isConnected=${connectionProvider.isConnected}');

          if (connectionProvider.isInitialized && !connectionProvider.isConnected) {
            final connectToken = imToken ?? token;
            final uid = int.tryParse(userId) ?? 0;
            debugPrint('📍[AuthProvider] 准备调用 connectionProvider.connect(imToken, userId=$uid)...');
            await connectionProvider.connect(connectToken, userId: uid);
            debugPrint('✅[AuthProvider] connect() 返回');
          } else if (connectionProvider.isConnected) {
            debugPrint('⚠️[AuthProvider] 已连接，跳过 connect()');
          } else {
            debugPrint('⚠️[AuthProvider] SDK 未初始化，跳过 connect()');
          }

          notifyListeners();
        } catch (e, stack) {
          debugPrint('❌[AuthProvider] 加载用户信息失败: $e');
          debugPrint('❌[AuthProvider] stackTrace: $stack');
          await logout(context);
        }
      } else {
        debugPrint('⚠️[AuthProvider] userId 为空');
      }
    } else {
      debugPrint('⚠️[AuthProvider] token 为空或未登录');
    }

    debugPrint('📍[AuthProvider] ====== loadUserFromStorage() 结束 ======');
    debugPrint('');
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
