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
          final imRefreshToken = data['imRefreshToken'] as String?;
          
          if (imToken != null) {
            await StorageService.saveImToken(imToken);
            debugPrint('✅[AuthProvider] 保存 IM Token');
          }
          
          if (imRefreshToken != null) {
            await StorageService.saveImRefreshToken(imRefreshToken);
            debugPrint('✅[AuthProvider] 保存 IM RefreshToken');
          }
          
          final user = UserModel.fromJson(userData);
          _user = user;
          await StorageService.saveUserId(user.id);
          await StorageService.saveUsername(user.username);
          await StorageService.saveNickname(user.nickname);
          
          if (user.imUserId != null) {
            await StorageService.saveImUserId(user.imUserId!);
            debugPrint('✅[AuthProvider] 存储 imUserId: ${user.imUserId}');
          }

          final connectionProvider =
              context.read<ConnectionProvider>();
          if (connectionProvider.isInitialized) {
            final connectToken = imToken ?? token;
            final imUid = int.tryParse(user.imUserId ?? user.id) ?? 0;
            debugPrint('📍[AuthProvider] 使用 imUid=$imUid 连接 IM (含RefreshToken)');
            await connectionProvider.connect(
              connectToken,
              userId: imUid,
              refreshToken: imRefreshToken,
            );
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
          final imRefreshToken = data['imRefreshToken'] as String?;
          
          if (imToken != null) {
            await StorageService.saveImToken(imToken);
            debugPrint('✅[AuthProvider] 注册时保存 IM Token');
          }
          
          if (imRefreshToken != null) {
            await StorageService.saveImRefreshToken(imRefreshToken);
            debugPrint('✅[AuthProvider] 注册时保存 IM RefreshToken');
          }
          
          final user = UserModel.fromJson(userData);
          _user = user;
          await StorageService.saveUserId(user.id);
          await StorageService.saveUsername(user.username);
          await StorageService.saveNickname(user.nickname);
          
          if (user.imUserId != null) {
            await StorageService.saveImUserId(user.imUserId!);
            debugPrint('✅[AuthProvider] 注册时存储 imUserId: ${user.imUserId}');
          }
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
    final imRefreshToken = await StorageService.getImRefreshToken();
    
    debugPrint('📍[AuthProvider] token: ${token != null ? "有" : "无"}');
    debugPrint('📍[AuthProvider] imToken: ${imToken != null ? "有" : "无"}');
    debugPrint('📍[AuthProvider] imRefreshToken: ${imRefreshToken != null ? "有" : "无"}');

    if (token != null && token.isNotEmpty) {
      final userId = await StorageService.getUserId();
      final imUserIdStr = await StorageService.getImUserId();
      debugPrint('📍[AuthProvider] userId: $userId, imUserId: $imUserIdStr');

      if (userId != null) {
        try {
          final connectionProvider =
              context.read<ConnectionProvider>();
          debugPrint('📍[AuthProvider] isInitialized=${connectionProvider.isInitialized}, isConnected=${connectionProvider.isConnected}');

          if (connectionProvider.isInitialized && !connectionProvider.isConnected) {
            final connectToken = imToken ?? token;
            final uid = int.tryParse(imUserIdStr ?? userId) ?? 0;
            debugPrint('📍[AuthProvider] 准备连接IM (SDK会自动处理Token刷新)...');
            await connectionProvider.connect(
              connectToken,
              userId: uid,
              refreshToken: imRefreshToken,
            );
            debugPrint('✅[AuthProvider] connect() 返回');
          }

          debugPrint('ℹ️[AuthProvider] SDK已接管用户信息获取和Token管理');
          
          // 优先从服务端获取最新用户资料
          try {
            final profileResponse = await _apiService.getUserProfile();
            final profileCode = profileResponse['code'];
            if (profileCode == 200) {
              final userData = profileResponse['data'];
              if (userData != null) {
                _user = UserModel.fromJson(userData);
                // 同步更新本地存储
                await StorageService.saveNickname(_user!.nickname);
                debugPrint('✅[AuthProvider] 从服务端获取到最新用户资料, nickname=${_user!.nickname}');
              }
            } else {
              debugPrint('⚠️[AuthProvider] 服务端返回非200: ${profileResponse['message']}');
              throw Exception('服务端返回异常');
            }
          } catch (e) {
            debugPrint('⚠️[AuthProvider] 从服务端获取用户资料失败($e)，降级使用本地缓存');
            final username = await StorageService.getUsername();
            final nickname = await StorageService.getNickname();
            _user = UserModel(
              id: userId,
              username: username ?? userId,
              nickname: nickname ?? username ?? '用户',
              imUserId: imUserIdStr,
            );
          }
          
          notifyListeners();
        } catch (e, stack) {
          debugPrint('❌[AuthProvider] 加载失败: $e');
          debugPrint('❌[AuthProvider] stackTrace: $stack');
          
          if (e.toString().contains('401') || e.toString().contains('Token无效')) {
            debugPrint('⚠️[AuthProvider] Token无效，执行登出');
            await logout(context);
          } else {
            debugPrint('⚠️[AuthProvider] 使用本地存储的基本信息作为降级方案');
            final username = await StorageService.getUsername();
            final nickname = await StorageService.getNickname();
            _user = UserModel(
              id: userId,
              username: username ?? userId,
              nickname: nickname ?? username ?? '用户',
              imUserId: imUserIdStr,
            );
            notifyListeners();
          }
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

  Future<bool> updateNickname(String newNickname) async {
    _setLoading(true);
    _clearError();

    try {
      final response = await _apiService.updateProfile({'nickname': newNickname});
      final code = response['code'];

      if (code == 200) {
        // 从服务端返回的完整用户数据更新本地状态
        final userData = response['data'];
        if (userData != null && _user != null) {
          _user = UserModel.fromJson(userData);
        } else if (_user != null) {
          // 降级：直接用传入值更新
          _user = _user!.copyWith(nickname: newNickname);
        }
        // 同步持久化昵称到本地存储
        await StorageService.saveNickname(_user!.nickname);
        notifyListeners();
        return true;
      }
      _setError(response['message'] ?? '修改昵称失败');
      return false;
    } catch (e) {
      _setError(e.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 通用个人资料更新方法，支持昵称、头像、签名等多个字段
  Future<bool> updateProfile(Map<String, dynamic> data) async {
    _setLoading(true);
    _clearError();

    try {
      final response = await _apiService.updateProfile(data);
      final code = response['code'];

      if (code == 200) {
        final userData = response['data'];
        if (userData != null && _user != null) {
          _user = UserModel.fromJson(userData);
          // 同步持久化到本地存储
          await StorageService.saveNickname(_user!.nickname);
        }
        notifyListeners();
        return true;
      }
      _setError(response['message'] ?? '修改个人资料失败');
      return false;
    } catch (e) {
      _setError(e.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      _setLoading(false);
    }
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
