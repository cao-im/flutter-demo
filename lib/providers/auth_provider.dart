import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../router/app_router.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import 'connection_provider.dart';
import 'contact_provider.dart';

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
          await _rememberProfile(user);
          
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
          await _rememberProfile(user);
          
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
    debugPrint('📍[AuthProvider] ====== loadUserFromStorage() 开始 ======');

    final token = await StorageService.getToken();
    final imToken = await StorageService.getImToken();
    final imRefreshToken = await StorageService.getImRefreshToken();

    debugPrint(
        '📍[AuthProvider] token:${token != null ? "有" : "无"}, imToken:${imToken != null ? "有" : "无"}, imRefreshToken:${imRefreshToken != null ? "有" : "无"}');

    if (token != null && token.isNotEmpty) {
      final userId = await StorageService.getUserId();
      final imUserIdStr = await StorageService.getImUserId();
      debugPrint('📍[AuthProvider] userId: $userId, imUserId: $imUserIdStr');

      if (userId != null) {
        try {
          final connectionProvider = context.read<ConnectionProvider>();
          debugPrint(
              '📍[AuthProvider] isInitialized=${connectionProvider.isInitialized}, isConnected=${connectionProvider.isConnected}');

          if (connectionProvider.isInitialized &&
              !connectionProvider.isConnected) {
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

          // 优先从服务端获取最新用户资料；401/403 视为登录失效，禁止降级本地缓存
          try {
            final profileResponse = await _apiService.getUserProfile();
            final profileCode = profileResponse['code'];
            if (profileCode == 200) {
              final userData = profileResponse['data'];
              if (userData != null) {
                _user = UserModel.fromJson(userData);
                await _rememberProfile(_user!);
                debugPrint(
                    '✅[AuthProvider] 从服务端获取到最新用户资料, nickname=${_user!.nickname}');
              }
            } else if (_isAuthFailureCode(profileCode) ||
                _isAuthFailureMessage(profileResponse['message']?.toString())) {
              debugPrint(
                  '🔐[AuthProvider] 用户资料认证失败 code=$profileCode，清理登录态');
              await _clearLocalSession(context);
              return;
            } else {
              debugPrint(
                  '⚠️[AuthProvider] 服务端返回非200: ${profileResponse['message']}');
              throw Exception('服务端返回异常');
            }
          } catch (e) {
            if (e is IMException && e.code == ErrorCode.authFailed) {
              rethrow;
            }
            if (_isAuthHttpFailure(e)) {
              debugPrint('🔐[AuthProvider] 用户资料请求认证失败($e)，清理登录态');
              await _clearLocalSession(context);
              return;
            }
            debugPrint('⚠️[AuthProvider] 从服务端获取用户资料失败($e)，降级使用本地缓存');
            final username = await StorageService.getUsername();
            final nickname = await StorageService.getNickname();
            final avatar = await StorageService.getAvatar();
            _user = UserModel(
              id: userId,
              username: username ?? userId,
              nickname: nickname ?? username ?? '用户',
              avatar: avatar,
              imUserId: imUserIdStr,
            );
          }

          notifyListeners();
        } on IMException catch (e) {
          debugPrint('❌[AuthProvider] IM认证失败: $e');
          if (e.code == ErrorCode.authFailed) {
            await _clearLocalSession(context);
          }
        } catch (e, stack) {
          debugPrint('❌[AuthProvider] 加载失败: $e | stackTrace: $stack');

          if (_isAuthHttpFailure(e) ||
              e.toString().contains('Token无效') ||
              e.toString().contains('请重新登录')) {
            debugPrint('⚠️[AuthProvider] Token无效，执行登出');
            await _clearLocalSession(context);
          } else {
            debugPrint('⚠️[AuthProvider] 使用本地存储的基本信息作为降级方案');
            final username = await StorageService.getUsername();
            final nickname = await StorageService.getNickname();
            final avatar = await StorageService.getAvatar();
            _user = UserModel(
              id: userId,
              username: username ?? userId,
              nickname: nickname ?? username ?? '用户',
              avatar: avatar,
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
  }

  /// SDK 报告认证永久失效（如 RefreshToken 无效）时调用
  Future<void> handleAuthExpired(String reason) async {
    debugPrint('🔐[AuthProvider] handleAuthExpired: $reason');
    await _clearLocalSession(null);
    final nav = AppRouter.navigatorKey.currentState;
    if (nav != null) {
      nav.pushNamedAndRemoveUntil(AppRouter.login, (route) => false);
    }
  }

  Future<void> _clearLocalSession(BuildContext? context) async {
    try {
      if (context != null && context.mounted) {
        final connectionProvider = context.read<ConnectionProvider>();
        if (connectionProvider.isConnected ||
            connectionProvider.state == ImConnectionState.reconnecting ||
            connectionProvider.state == ImConnectionState.connecting) {
          await connectionProvider.disconnect();
        }
        final contactProvider = context.read<ContactProvider>();
        await contactProvider.resetState();
      } else {
        // 无 context：仅断开 IM，避免无限重连
        // ConnectionProvider 由 Provider 树持有，通过 navigator context 取
        final navContext = AppRouter.navigatorKey.currentContext;
        if (navContext != null) {
          final connectionProvider = navContext.read<ConnectionProvider>();
          await connectionProvider.disconnect();
          try {
            await navContext.read<ContactProvider>().resetState();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('⚠️[AuthProvider] _clearLocalSession disconnect 异常: $e');
    }

    await StorageService.clearAll();
    _user = null;
    notifyListeners();
  }

  bool _isAuthFailureCode(dynamic code) {
    return code == 401 || code == 403 || code == 1002 || code == 1005;
  }

  bool _isAuthFailureMessage(String? message) {
    if (message == null) return false;
    return message.contains('未认证') ||
        message.contains('Token无效') ||
        message.contains('无效的Refresh') ||
        message.contains('请先登录') ||
        message.contains('请重新登录');
  }

  bool _isAuthHttpFailure(Object e) {
    final s = e.toString();
    return s.contains('401') ||
        s.contains('403') ||
        s.contains('status code of 401') ||
        s.contains('status code of 403') ||
        _isAuthFailureMessage(s);
  }

  Future<void> logout(BuildContext context) async {
    final connectionProvider = context.read<ConnectionProvider>();
    if (connectionProvider.isConnected) {
      await connectionProvider.disconnect();
    }

    // 重置通讯录状态（清空内存缓存 + 关闭数据库连接）
    final contactProvider = context.read<ContactProvider>();
    await contactProvider.resetState();

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
        await _rememberProfile(_user!);
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
          await _rememberProfile(_user!);
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

  Future<void> _rememberProfile(UserModel user) async {
    await StorageService.saveNickname(user.nickname);
    final avatar = user.avatar;
    if (avatar != null && avatar.isNotEmpty) {
      await StorageService.saveAvatar(avatar);
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
