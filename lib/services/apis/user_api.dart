import '../base_api.dart';

/// 用户资料相关 API 接口
///
/// 管理用户个人资料的查询和修改
/// 所有接口对接 App Server (应用服务器)
class UserApi extends BaseApi {
  UserApi();

  // ==================== 公开方法 ====================

  /// 获取当前登录用户的个人资料
  ///
  /// 返回用户信息（id、username、nickname、avatar 等）
  Future<Map<String, dynamic>> getUserProfile() async {
    return getApp('/user/info');
  }

  /// 修改个人资料
  ///
  /// [data] 要更新的字段，支持：
  /// - nickname: 昵称
  /// - avatar: 头像
  /// - signature: 个性签名
  ///
  /// 返回更新后的完整用户数据
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    return putApp('/user/profile', data: data);
  }
}
