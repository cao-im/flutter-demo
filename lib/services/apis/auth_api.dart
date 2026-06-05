import '../base_api.dart';

/// 认证相关 API 接口
///
/// 管理用户登录、注册等认证相关的 HTTP 请求
/// 所有接口对接 App Server (应用服务器)
class AuthApi extends BaseApi {
  AuthApi();

  // ==================== 公开方法 ====================

  /// 用户登录
  ///
  /// [username] 用户名
  /// [password] 密码
  ///
  /// 返回服务端响应，包含 token、user、imToken、imRefreshToken 等字段
  Future<Map<String, dynamic>> login(String username, String password) async {
    return postApp(
      '/client/login',
      data: {
        'username': username,
        'password': password,
      },
      removeAuth: true, // 登录接口不需要 Token
    );
  }

  /// 用户注册
  ///
  /// [username] 用户名
  /// [password] 密码
  /// [nickname] 昵称
  ///
  /// 返回服务端响应，包含 token、user 等字段
  Future<Map<String, dynamic>> register(
    String username,
    String password,
    String nickname,
  ) async {
    return postApp(
      '/client/register',
      data: {
        'username': username,
        'password': password,
        'nickname': nickname,
      },
      removeAuth: true, // 注册接口不需要 Token
    );
  }
}
